-- An application checklist, and the plumbing for the interview prep brief.
--
-- Borrowed from the insurance intake team in awesome-llm-apps
-- (voice_ai_agents/insurance_claim_live_agent_team/policies.py): plain rules
-- produce findings with a fixed id and an action, a fixed precedence picks the
-- one message to lead with, and the model is never allowed to claim evidence
-- it was not given. Here the rules are about an application, the precedence is
-- DATE > PRACTICE > PREP > CV > JD > FOLLOW, and the evidence rule lives in
-- the prep brief's gate (supabase/functions/_shared/prep/evidence.ts).
--
-- Also admits the three AI job types this round adds — interview_prep,
-- cv_first_read and coach_cited — so enqueue_student_job is redefined once.

-- --------------------------------------------------------- the text hash
--
-- hashText() in supabase/functions/_shared/ai/gateway.ts, in SQL: trim, lower
-- case, runs of whitespace to one space, SHA-256. job_analyses is keyed by it,
-- so "has this student checked this job's description?" can be answered here,
-- even when the analysis came from the shared cache and was never linked to
-- the job. tool/verify_application_checklist.js holds the two equal.
create or replace function public.tack_text_hash(p_text text)
returns text
language sql
immutable
set search_path = public
as $$
  select encode(sha256(convert_to(
           btrim(regexp_replace(lower(p_text), '\s+', ' ', 'g'), ' '),
           'UTF8')), 'hex');
$$;

revoke all on function public.tack_text_hash(text) from public, anon, authenticated;

-- ------------------------------------------------------ prep brief storage
create table if not exists public.interview_prep_briefs (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references public.profiles(id) on delete cascade,
  application_id uuid not null references public.job_applications(id) on delete cascade,
  -- What the brief was built from. A changed CV, skill list or description
  -- makes a new brief; the same inputs are never charged for twice.
  input_hash     text not null,
  brief          jsonb not null,
  job_id         uuid references public.jobs_queue(id) on delete set null,
  created_at     timestamptz not null default now(),
  unique (application_id, input_hash)
);

create index if not exists interview_prep_briefs_user_idx
  on public.interview_prep_briefs(user_id, created_at desc);

alter table public.interview_prep_briefs enable row level security;
alter table public.interview_prep_briefs force row level security;

drop policy if exists interview_prep_briefs_own on public.interview_prep_briefs;
create policy interview_prep_briefs_own on public.interview_prep_briefs
  for select to authenticated
  using (user_id = (select auth.uid()));

-- Written only by the worker, with the service role.
revoke insert, update, delete on public.interview_prep_briefs from anon, authenticated;

-- ------------------------------------------------------------ the checklist
create or replace function public.application_checklist(p_application uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid    uuid := (select auth.uid());
  v_today  date := public.tack_today();
  v_items  jsonb := '[]'::jsonb;
  v_since  timestamptz;
  a        record;
begin
  if v_uid is null then
    raise exception 'sign_in_required' using errcode = '42501';
  end if;

  select ap.id, ap.status, ap.cv_document_id, ap.applied_at, ap.created_at,
         j.closes_at, j.description
    into a
    from public.job_applications ap
    join public.jobs j on j.id = ap.job_id
   where ap.id = p_application
     and ap.user_id = v_uid
     and ap.deleted_at is null;

  if not found then
    raise exception 'application_not_owned' using errcode = '42501';
  end if;

  -- An offer or a rejection asks nothing more of the checklist.
  if a.status not in ('saved', 'applied', 'assessment', 'interview') then
    return jsonb_build_object('items', '[]'::jsonb, 'next_step', null);
  end if;

  -- Appended in precedence order, so the first item is the next step.

  if a.status = 'saved' and a.closes_at between v_today and v_today + 3 then
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'id', 'APP-DATE', 'severity', 'required', 'action', 'open_job',
      'title', 'Closes ' || to_char(a.closes_at, 'Dy DD Mon')
               || '. Send it, or let it go.'));
  end if;

  if a.status = 'interview' and not exists (
       select 1
         from public.interview_questions q
         join public.interview_sessions s on s.id = q.session_id
        where q.user_id = v_uid
          and s.deleted_at is null
          and q.answered_at >= now() - interval '7 days') then
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'id', 'APP-PRACTICE', 'severity', 'required', 'action', 'practise',
      'title', 'Practise a few questions for this role this week'));
  end if;

  if a.status = 'interview' and not exists (
       select 1 from public.interview_prep_briefs b
        where b.application_id = a.id) then
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'id', 'APP-PREP', 'severity', 'recommended', 'action', 'prep',
      'title', 'Get your interview prep brief'));
  end if;

  if a.cv_document_id is null then
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'id', 'APP-CV', 'severity', 'recommended', 'action', 'attach_cv',
      'title', case when a.status = 'saved'
                    then 'Attach the CV you will send'
                    else 'Attach the CV you sent' end));
  end if;

  if nullif(btrim(a.description), '') is not null and not exists (
       select 1
         from public.job_match_scores m
         join public.job_analyses ja on ja.id = m.analysis_id
        where m.user_id = v_uid
          and ja.raw_text_hash = public.tack_text_hash(a.description)) then
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'id', 'APP-JD', 'severity', 'recommended', 'action', 'analyse',
      'title', 'Check the job description against your skills'));
  end if;

  if a.status = 'applied' then
    select max(h.changed_at) into v_since
      from public.application_status_history h
     where h.application_id = a.id;
    if coalesce(v_since, a.applied_at, a.created_at) < now() - interval '21 days' then
      v_items := v_items || jsonb_build_array(jsonb_build_object(
        'id', 'APP-FOLLOW', 'severity', 'recommended', 'action', 'follow_up',
        'title', 'No reply in three weeks. Follow up, or move it on.'));
    end if;
  end if;

  return jsonb_build_object(
    'items', v_items,
    'next_step', case when jsonb_array_length(v_items) > 0
                      then v_items -> 0 else null end);
end $$;

revoke all on function public.application_checklist(uuid) from public, anon;
grant execute on function public.application_checklist(uuid) to authenticated;

-- ---------------------------------------------------- three new job types
--
-- 0072's enqueue_student_job, with interview_prep, cv_first_read and
-- coach_cited admitted and checked for ownership. Everything else unchanged.
create or replace function public.enqueue_student_job(
  p_user_id uuid, p_type text, p_payload jsonb, p_key text
)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare
  v_job public.jobs_queue;
  v_paid boolean := p_type <> 'check_cv';
  v_remaining int;
  v_doc uuid;
  v_thread uuid;
  v_status public.application_status;
begin
  if p_user_id is null or p_type not in (
    'analyse_jd', 'parse_cv', 'check_cv', 'coach_reply',
    'interview_questions', 'interview_evaluate',
    'interview_prep', 'cv_first_read', 'coach_cited'
  ) or p_type is null or p_key is null or length(p_key) not between 1 and 240
    or p_payload is null or jsonb_typeof(p_payload) <> 'object'
    or octet_length(p_payload::text) > 65536 then
    raise exception 'invalid_job_request';
  end if;

  -- Serialize submissions for one account, including duplicate free checks.
  perform pg_advisory_xact_lock(hashtextextended('tack:ai:' || p_user_id::text, 0));

  if p_type in ('parse_cv', 'check_cv', 'cv_first_read') then
    v_doc := (p_payload->>'document_id')::uuid;
    if not exists(select 1 from public.documents
      where id = v_doc and user_id = p_user_id and type = 'cv' and deleted_at is null) then
      raise exception 'document_not_owned';
    end if;
  elsif p_type = 'analyse_jd' and p_payload->>'jobId' is not null then
    if not exists(select 1 from public.jobs
      where id = (p_payload->>'jobId')::uuid and user_id = p_user_id) then
      raise exception 'job_not_owned';
    end if;
  elsif p_type in ('coach_reply', 'coach_cited') and p_payload->>'thread_id' is not null then
    if not exists(select 1 from public.chat_threads
      where id = (p_payload->>'thread_id')::uuid and user_id = p_user_id) then
      raise exception 'thread_not_owned';
    end if;
  elsif p_type = 'interview_evaluate' then
    if not exists(select 1 from public.interview_questions
      where id = (p_payload->>'question_id')::uuid and user_id = p_user_id) then
      raise exception 'question_not_owned';
    end if;
  elsif p_type = 'interview_prep' then
    select status into v_status from public.job_applications
     where id = (p_payload->>'application_id')::uuid
       and user_id = p_user_id and deleted_at is null;
    if not found then
      raise exception 'application_not_owned';
    end if;
    -- A brief before the interview stage would spend an action on a guess.
    if v_status <> 'interview' then
      raise exception 'application_not_interview';
    end if;
  end if;

  select * into v_job from public.jobs_queue
   where idempotency_key = p_key for update;
  if found and (v_job.user_id is distinct from p_user_id or v_job.type <> p_type) then
    raise exception 'operation_not_owned';
  end if;

  if v_job.id is not null and v_job.status in ('pending', 'running', 'done') then
    return jsonb_build_object('jobId', v_job.id, 'duplicate', true,
      'status', v_job.status, 'threadId', v_job.payload->>'thread_id',
      'remaining', public.quota_remaining(p_user_id, 'ai', null));
  end if;

  if (select count(*) from public.jobs_queue where user_id = p_user_id
       and type in ('analyse_jd', 'parse_cv', 'check_cv', 'coach_reply',
                    'interview_questions', 'interview_evaluate',
                    'interview_prep', 'cv_first_read', 'coach_cited')
       and status in ('pending', 'running')) >= 5 then
    raise exception 'queue_busy';
  end if;

  v_remaining := public.quota_remaining(p_user_id, 'ai', null);
  if v_paid then
    v_remaining := public.consume_quota(p_user_id, 'ai', null);
    if v_remaining < 0 then raise exception 'quota_exhausted'; end if;
  end if;

  if p_type in ('coach_reply', 'coach_cited') and p_payload->>'thread_id' is null then
    insert into public.chat_threads(user_id, title)
      values(p_user_id, left(p_payload->>'question', 60)) returning id into v_thread;
    p_payload := p_payload || jsonb_build_object('thread_id', v_thread);
  end if;

  if v_job.id is null then
    insert into public.jobs_queue(user_id, type, payload, idempotency_key)
      values(p_user_id, p_type, p_payload, p_key) returning * into v_job;
  else
    -- Re-submitting a failed operation is an explicit retry. The old failure
    -- refunded its charge; this attempt reserves a fresh action atomically.
    update public.jobs_queue set status = 'pending', attempts = 0,
      payload = p_payload, result = null, last_error = null,
      locked_at = null, locked_by = null, run_after = now()
     where id = v_job.id returning * into v_job;
  end if;

  if p_type in ('coach_reply', 'coach_cited') then
    insert into public.chat_messages(job_id, thread_id, user_id, role, body)
      values(v_job.id, (p_payload->>'thread_id')::uuid, p_user_id, 'student', p_payload->>'question')
      on conflict(job_id, role) do nothing;
  end if;

  if p_type = 'parse_cv' then
    update public.documents set status = 'processing', failure_reason = null
      where id = v_doc and user_id = p_user_id;
  end if;

  if v_paid then
    insert into public.ai_job_charges(job_id, user_id, window_start)
      values(v_job.id, p_user_id, (now() at time zone 'Asia/Dhaka')::date)
    on conflict(job_id) do update set window_start = excluded.window_start,
      refunded_at = null;
  end if;
  return jsonb_build_object('jobId', v_job.id, 'duplicate', false,
    'status', v_job.status, 'threadId', v_job.payload->>'thread_id', 'remaining', v_remaining);
end $$;

revoke all on function public.enqueue_student_job(uuid,text,jsonb,text) from public, anon, authenticated;
