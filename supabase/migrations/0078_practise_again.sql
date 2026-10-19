-- Practise again: spaced repetition for interview answers.
--
-- A student answers a question once, reads the feedback, and never sees that
-- question again. The feedback is the most useful thing interview practice
-- produces and it is read exactly once.
--
-- This brings answered questions back on a schedule, the way AnkiDroid brings
-- back a flashcard (github.com/ankidroid/Anki-Android, `Reviewer`, review
-- reminders): the student reads the question, says the answer out loud, opens
-- their own notes, and grades themselves Again / Hard / Good / Easy. The grade
-- decides when it comes back. A question they nail drifts out to weeks; one
-- they keep missing comes back tomorrow.
--
-- Self-graded on purpose. Re-scoring every repeat with the model would spend
-- the shared daily AI allowance on rehearsal, which is the opposite of what a
-- free practice loop should cost. The schedule is arithmetic (SM-2, the
-- algorithm Anki grew from) and lives here so every client gets the same one.
--
-- Rows are written only by the trigger and by review_interview_question();
-- the student can read theirs and nothing else.

create table if not exists public.interview_reviews (
  question_id   uuid primary key
                  references public.interview_questions(id) on delete cascade,
  user_id       uuid not null references public.profiles(id) on delete cascade,
  due_on        date not null,
  interval_days int not null default 1 check (interval_days between 1 and 180),
  ease          numeric(4,2) not null default 2.50 check (ease between 1.30 and 3.50),
  reps          int not null default 0 check (reps >= 0),
  lapses        int not null default 0 check (lapses >= 0),
  last_grade    text check (last_grade in ('again', 'hard', 'good', 'easy')),
  reviewed_at   timestamptz,
  created_at    timestamptz not null default now()
);

create index if not exists interview_reviews_due_idx
  on public.interview_reviews(user_id, due_on);

alter table public.interview_reviews enable row level security;
alter table public.interview_reviews force row level security;

drop policy if exists interview_reviews_own on public.interview_reviews;
create policy interview_reviews_own on public.interview_reviews
  for select to authenticated
  using (user_id = (select auth.uid()));

comment on table public.interview_reviews is
  'When each answered interview question comes back for practice. Written by '
  'a trigger and by review_interview_question(); read-only to the student.';


-- -------------------------------------------------------------- the schedule
--
-- Pure: the next interval, ease, reps and lapses for one grade. Kept apart
-- from the write so the checks at the bottom can run it on fixed inputs.
create or replace function public.tack_next_review(
  p_interval int,
  p_ease     numeric,
  p_reps     int,
  p_lapses   int,
  p_grade    text,
  out interval_days int,
  out ease          numeric,
  out reps          int,
  out lapses        int
)
language plpgsql
immutable
set search_path = public
as $$
begin
  ease   := p_ease;
  reps   := p_reps + 1;
  lapses := p_lapses;

  case p_grade
    when 'again' then
      interval_days := 1;
      ease   := greatest(1.30, p_ease - 0.20);
      reps   := 0;
      lapses := p_lapses + 1;
    when 'hard' then
      interval_days := greatest(1, round(p_interval * 1.2));
      ease := greatest(1.30, p_ease - 0.15);
    when 'good' then
      interval_days := case p_reps
                         when 0 then 3
                         when 1 then 7
                         else round(p_interval * p_ease)
                       end;
    when 'easy' then
      interval_days := case p_reps
                         when 0 then 5
                         else round(p_interval * p_ease * 1.3)
                       end;
      ease := least(3.50, p_ease + 0.15);
    else
      raise exception 'unknown grade %', p_grade using errcode = '22023';
  end case;

  interval_days := least(180, interval_days);
end $$;

revoke all on function public.tack_next_review(int, numeric, int, int, text)
  from public, anon, authenticated;


-- --------------------------------------------------------------- the queue
--
-- An answered question joins the queue for tomorrow. A skipped one does not:
-- there is nothing of the student's own to practise against.
create or replace function public.queue_interview_review()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if nullif(btrim(coalesce(new.answer_text, '')), '') is not null
     and not coalesce(new.skipped, false) then
    insert into public.interview_reviews (question_id, user_id, due_on)
    values (new.id, new.user_id, public.tack_today() + 1)
    on conflict (question_id) do nothing;
  end if;
  return null;
end $$;

revoke all on function public.queue_interview_review() from public, anon, authenticated;

drop trigger if exists interview_questions_queue_review on public.interview_questions;
create trigger interview_questions_queue_review
  after insert or update of answer_text on public.interview_questions
  for each row execute function public.queue_interview_review();

-- Everything already answered is due today, so the feature has something in
-- it the first time a student opens it.
insert into public.interview_reviews (question_id, user_id, due_on)
select q.id, q.user_id, public.tack_today()
  from public.interview_questions q
  join public.interview_sessions s on s.id = q.session_id and s.deleted_at is null
 where nullif(btrim(coalesce(q.answer_text, '')), '') is not null
   and not coalesce(q.skipped, false)
on conflict (question_id) do nothing;


-- -------------------------------------------------------------- client API

-- Today's questions, oldest due first, at most ten. Dhaka days, like the
-- dashboard, so the list never changes with the phone's clock.
create or replace function public.interview_due()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(item order by due_on, reps), '[]'::jsonb)
    from (
      select jsonb_build_object(
               'question_id',   r.question_id,
               'due_on',        r.due_on,
               'interval_days', r.interval_days,
               'reps',          r.reps,
               'role',          s.role,
               'question',      q.question,
               'answer_text',   q.answer_text,
               'score',         f.score,
               'to_improve',    f.to_improve,
               'model_answer',  f.model_answer
             ) as item,
             r.due_on,
             r.reps
        from public.interview_reviews r
        join public.interview_questions q on q.id = r.question_id
        join public.interview_sessions s
          on s.id = q.session_id and s.deleted_at is null
        left join public.interview_feedback f on f.question_id = q.id
       where r.user_id = (select auth.uid())
         and r.due_on <= public.tack_today()
       order by r.due_on, r.reps
       limit 10
    ) due
$$;

revoke all on function public.interview_due() from public, anon;
grant execute on function public.interview_due() to authenticated;

-- One self-grade. Returns when the question comes back.
create or replace function public.review_interview_question(
  p_question_id uuid,
  p_grade       text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := (select auth.uid());
  v_row  public.interview_reviews;
  v_next record;
begin
  if v_uid is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;

  select * into v_row
    from public.interview_reviews
   where question_id = p_question_id and user_id = v_uid
   for update;

  if not found then
    raise exception 'that question is not in your practice list'
      using errcode = 'P0002';
  end if;

  select * into v_next
    from public.tack_next_review(v_row.interval_days, v_row.ease,
                                 v_row.reps, v_row.lapses, p_grade);

  update public.interview_reviews
     set interval_days = v_next.interval_days,
         ease          = v_next.ease,
         reps          = v_next.reps,
         lapses        = v_next.lapses,
         last_grade    = p_grade,
         reviewed_at   = now(),
         due_on        = public.tack_today() + v_next.interval_days
   where question_id = p_question_id;

  return jsonb_build_object(
    'due_on',        public.tack_today() + v_next.interval_days,
    'interval_days', v_next.interval_days
  );
end $$;

revoke all on function public.review_interview_question(uuid, text) from public, anon;
grant execute on function public.review_interview_question(uuid, text) to authenticated;


-- ------------------------------------------------------------------ checked
do $$
declare
  n record;
begin
  -- A new card graded Good comes back in three days, then a week, then
  -- interval × ease.
  select * into n from public.tack_next_review(1, 2.50, 0, 0, 'good');
  if n.interval_days <> 3 or n.reps <> 1 then
    raise exception 'tack_next_review: first Good should be 3 days, got %', n.interval_days;
  end if;
  select * into n from public.tack_next_review(3, 2.50, 1, 0, 'good');
  if n.interval_days <> 7 then
    raise exception 'tack_next_review: second Good should be 7 days, got %', n.interval_days;
  end if;
  select * into n from public.tack_next_review(7, 2.50, 2, 0, 'good');
  if n.interval_days <> 18 then
    raise exception 'tack_next_review: third Good should be 18 days, got %', n.interval_days;
  end if;

  -- Again starts over, counts the lapse and lowers the ease, never below 1.3.
  select * into n from public.tack_next_review(18, 1.40, 3, 0, 'again');
  if n.interval_days <> 1 or n.reps <> 0 or n.lapses <> 1 or n.ease <> 1.30 then
    raise exception 'tack_next_review: Again should reset to tomorrow';
  end if;

  -- Hard is always sooner than Good, and Easy always later.
  if (public.tack_next_review(3, 2.50, 1, 0, 'hard')).interval_days
     >= (public.tack_next_review(3, 2.50, 1, 0, 'good')).interval_days
  or (public.tack_next_review(3, 2.50, 1, 0, 'easy')).interval_days
     <= (public.tack_next_review(3, 2.50, 1, 0, 'good')).interval_days then
    raise exception 'tack_next_review: Hard < Good < Easy does not hold';
  end if;

  -- Nothing waits longer than half a year.
  if (public.tack_next_review(170, 3.50, 9, 0, 'easy')).interval_days <> 180 then
    raise exception 'tack_next_review: the interval must cap at 180 days';
  end if;

  if not has_function_privilege('authenticated', 'public.interview_due()', 'EXECUTE')
  or not has_function_privilege('authenticated',
           'public.review_interview_question(uuid, text)', 'EXECUTE') then
    raise exception 'a student cannot reach their practice list';
  end if;
  if has_function_privilege('authenticated',
       'public.tack_next_review(int, numeric, int, int, text)', 'EXECUTE')
  or has_function_privilege('authenticated', 'public.queue_interview_review()', 'EXECUTE') then
    raise exception 'an internal practice helper is callable by a student';
  end if;
  -- RLS with only a select policy is what keeps the schedule honest.
  if exists (select 1 from pg_policies
              where schemaname = 'public' and tablename = 'interview_reviews'
                and cmd <> 'SELECT') then
    raise exception 'a student can write their own schedule';
  end if;
end $$;
