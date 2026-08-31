-- The coach: a conversation, grounded in what Tack already knows.
--
-- The daily allowance stays at three, which is a real constraint for something
-- shaped like a chat. It works because most of what a student asks a career
-- coach is not a question for a model at all — "what should I do next", "what
-- is my weakest area", "how far through my roadmap am I" are all already
-- computed, deterministically, from their own data. Those are answered here
-- for nothing.
--
-- The allowance is spent only on questions that genuinely need language: "how
-- do I explain a gap year in an interview", "is this project good enough to
-- put on a CV". That is the difference between three messages and three
-- conversations.

create table public.chat_threads (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  title      text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index chat_threads_user_idx on public.chat_threads(user_id, updated_at desc)
  where deleted_at is null;

create table public.chat_messages (
  id        uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.chat_threads(id) on delete cascade,
  user_id   uuid not null references public.profiles(id) on delete cascade,
  role      text not null check (role in ('student', 'coach')),
  body      text not null,

  -- 'data' when Tack answered from its own numbers and no model was called,
  -- 'model' when the allowance was spent. Stored so the screen can say which,
  -- and so nobody has to guess later why a day's usage looks the way it does.
  answered_by text check (answered_by in ('data', 'model')),

  created_at timestamptz not null default now()
);
create index chat_messages_thread_idx on public.chat_messages(thread_id, created_at);

alter table public.chat_threads enable row level security;
alter table public.chat_threads force row level security;
alter table public.chat_messages enable row level security;
alter table public.chat_messages force row level security;

create policy chat_threads_own on public.chat_threads
  for all to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy chat_messages_own on public.chat_messages
  for all to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));


-- Everything the coach is allowed to know, in one compact object.
--
-- Deliberately not the whole dashboard feed. Every field here is one a student
-- would expect a careers adviser to have read, and nothing else is sent: no
-- CV text, no application notes, no document contents, no contact details.
-- What leaves this function is what reaches Google, so the boundary is drawn
-- here rather than in the prompt, where it would be a matter of wording.
create or replace function public.coach_context()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_p   record;
  v_s   record;
begin
  if v_uid is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;

  select p.mode, p.year_of_study, p.years_total, p.target_role,
         p.education_stage, p.expected_graduation
    into v_p
    from public.profiles p
   where p.id = v_uid and p.deleted_at is null;
  if not found then return null; end if;

  select r.total, r.components into v_s
    from public.readiness_scores r
   where r.user_id = v_uid order by r.computed_at desc limit 1;

  return jsonb_build_object(
    'mode',                v_p.mode,
    'year_of_study',       v_p.year_of_study,
    'years_total',         v_p.years_total,
    'stage',               v_p.education_stage,
    'target_role',         v_p.target_role,
    'expected_graduation', v_p.expected_graduation,

    'score', jsonb_build_object(
      'total', coalesce(v_s.total, 0),
      -- Named components with what is still available, so the model can talk
      -- about the biggest win without being told the arithmetic.
      'components', coalesce(v_s.components, '{}'::jsonb)
    ),

    'target_path', (
      select jsonb_build_object('title', cp.title, 'slug', cp.slug)
        from public.user_career_paths ucp
        join public.career_paths cp on cp.id = ucp.path_id
       where ucp.user_id = v_uid and ucp.deleted_at is null and ucp.is_primary
       limit 1
    ),

    'skills_held', coalesce((
      select jsonb_agg(s.name order by s.name)
        from public.user_skills us join public.skills s on s.id = us.skill_id
       where us.user_id = v_uid
    ), '[]'::jsonb),

    'skill_gap', coalesce((
      select jsonb_agg(s.name order by s.name)
        from public.career_path_skills cps
        join public.skills s on s.id = cps.skill_id
        join public.user_career_paths ucp
          on ucp.path_id = cps.path_id and ucp.user_id = v_uid
         and ucp.deleted_at is null and ucp.is_primary
       where cps.importance = 'core'
         and not exists (select 1 from public.user_skills us
                          where us.user_id = v_uid and us.skill_id = cps.skill_id)
    ), '[]'::jsonb),

    'roadmap', (
      select jsonb_build_object(
        'done', count(*) filter (where t.is_done),
        'total', count(*),
        'next', (select nt.title from public.roadmap_tasks nt
                   join public.roadmap_milestones nm on nm.id = nt.milestone_id
                  where nt.user_id = v_uid and not nt.is_done and nt.deleted_at is null
                    and nm.state = 'active'
                  order by nt.due_date nulls last, nt.order_index limit 1))
        from public.roadmap_tasks t
       where t.user_id = v_uid and t.deleted_at is null
    ),

    'applications', (
      select coalesce(jsonb_object_agg(status, n), '{}'::jsonb)
        from (select a.status::text status, count(*)::int n
                from public.job_applications a
               where a.user_id = v_uid and a.deleted_at is null
               group by a.status) x
    ),

    'has_cv', exists (select 1 from public.documents
                       where user_id = v_uid and type = 'cv'
                         and status <> 'failed' and deleted_at is null),

    'streak', (
      select count(distinct day)::int from public.tack_activity(v_uid)
       where day > public.tack_today() - 14
    )
  );
end $$;

revoke all on function public.coach_context() from public, anon;
grant execute on function public.coach_context() to authenticated;


-- How much of today's allowance is left, without spending any of it.
create or replace function public.coach_allowance()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'used', coalesce((
      select count from public.rate_limits
       where user_id = (select auth.uid()) and bucket = 'ai'
         and window_start = (now() at time zone 'utc')::date
    ), 0),
    'limit', 3
  )
$$;

revoke all on function public.coach_allowance() from public, anon;
grant execute on function public.coach_allowance() to authenticated;

do $$
begin
  if not has_function_privilege('authenticated', 'public.coach_context()', 'EXECUTE')
  or not has_function_privilege('authenticated', 'public.coach_allowance()', 'EXECUTE') then
    raise exception 'the coach is not callable by a signed-in student';
  end if;
  if has_function_privilege('anon', 'public.coach_context()', 'EXECUTE') then
    raise exception 'coach_context must not be reachable with the anon key alone';
  end if;
end $$;
