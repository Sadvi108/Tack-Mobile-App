-- An AI action and its durable job are one transaction. Clients cannot invoke
-- these service-only primitives or choose the daily allowance.
create or replace function public.ai_daily_limit()
returns int language sql immutable set search_path = public
as $$ select 3 $$;

create or replace function public.consume_quota(p_user_id uuid, p_bucket text, p_limit int)
returns int language plpgsql security definer set search_path = public
as $$
declare
  v_today date := (now() at time zone 'Asia/Dhaka')::date;
  v_count int;
  v_limit int := public.ai_daily_limit();
begin
  if p_user_id is null then raise exception 'user_required'; end if;
  insert into public.rate_limits(user_id, bucket, window_start, count)
    values(p_user_id, p_bucket, v_today, 1)
  on conflict(user_id, bucket, window_start) do update
    set count = public.rate_limits.count + 1
    where public.rate_limits.count < v_limit
  returning count into v_count;
  if v_count is null then return -1; end if;
  return v_limit - v_count;
end $$;

create or replace function public.quota_remaining(p_user_id uuid, p_bucket text, p_limit int)
returns int language sql stable security definer set search_path = public
as $$
  select greatest(0, public.ai_daily_limit() - coalesce((
    select count from public.rate_limits
     where user_id = p_user_id and bucket = p_bucket
       and window_start = (now() at time zone 'Asia/Dhaka')::date
  ), 0))
$$;

create or replace function public.coach_allowance()
returns jsonb language sql stable security definer set search_path = public
as $$
  select jsonb_build_object(
    'used', public.ai_daily_limit() - public.quota_remaining(auth.uid(), 'ai', 3),
    'limit', public.ai_daily_limit(), 'timezone', 'Asia/Dhaka')
$$;

-- Retained for older deployed endpoints during the migration. Durable jobs use
-- refund_job_quota, which is idempotent and refunds the original charge date.
create or replace function public.refund_quota(p_user_id uuid, p_bucket text)
returns int language plpgsql security definer set search_path = public
as $$
declare v_count int;
begin
  update public.rate_limits set count = greatest(0, count - 1)
   where user_id = p_user_id and bucket = p_bucket
     and window_start = (now() at time zone 'Asia/Dhaka')::date
   returning count into v_count;
  return coalesce(v_count, 0);
end
$$;

create table public.ai_job_charges (
  job_id uuid primary key references public.jobs_queue(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  window_start date not null,
  refunded_at timestamptz
);
alter table public.ai_job_charges enable row level security;
alter table public.ai_job_charges force row level security;
revoke all on public.ai_job_charges from anon, authenticated;
grant all on public.ai_job_charges to service_role;
create index ai_job_charges_user_idx on public.ai_job_charges(user_id);

create or replace function public.refund_job_quota(p_job_id uuid)
returns boolean language plpgsql security definer set search_path = public
as $$
declare v_charge public.ai_job_charges;
begin
  update public.ai_job_charges set refunded_at = now()
   where job_id = p_job_id and refunded_at is null
   returning * into v_charge;
  if not found then return false; end if;
  update public.rate_limits set count = greatest(0, count - 1)
   where user_id = v_charge.user_id and bucket = 'ai'
     and window_start = v_charge.window_start;
  return true;
end $$;

alter table public.chat_messages add column job_id uuid references public.jobs_queue(id) on delete set null;
alter table public.chat_messages add constraint chat_messages_job_role_unique unique(job_id, role);
alter table public.interview_feedback add column job_id uuid references public.jobs_queue(id) on delete set null;

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
begin
  if p_user_id is null or p_type not in (
    'analyse_jd', 'parse_cv', 'check_cv', 'coach_reply',
    'interview_questions', 'interview_evaluate'
  ) or p_type is null or p_key is null or length(p_key) not between 1 and 240
    or p_payload is null or jsonb_typeof(p_payload) <> 'object'
    or octet_length(p_payload::text) > 65536 then
    raise exception 'invalid_job_request';
  end if;

  -- Serialize submissions for one account, including duplicate free checks.
  perform pg_advisory_xact_lock(hashtextextended('tack:ai:' || p_user_id::text, 0));

  if p_type in ('parse_cv', 'check_cv') then
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
  elsif p_type = 'coach_reply' and p_payload->>'thread_id' is not null then
    if not exists(select 1 from public.chat_threads
      where id = (p_payload->>'thread_id')::uuid and user_id = p_user_id) then
      raise exception 'thread_not_owned';
    end if;
  elsif p_type = 'interview_evaluate' then
    if not exists(select 1 from public.interview_questions
      where id = (p_payload->>'question_id')::uuid and user_id = p_user_id) then
      raise exception 'question_not_owned';
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
      'remaining', public.quota_remaining(p_user_id, 'ai', 3));
  end if;

  if (select count(*) from public.jobs_queue where user_id = p_user_id
       and type in ('analyse_jd', 'parse_cv', 'check_cv', 'coach_reply',
                    'interview_questions', 'interview_evaluate')
       and status in ('pending', 'running')) >= 5 then
    raise exception 'queue_busy';
  end if;

  v_remaining := public.quota_remaining(p_user_id, 'ai', 3);
  if v_paid then
    v_remaining := public.consume_quota(p_user_id, 'ai', 3);
    if v_remaining < 0 then raise exception 'quota_exhausted'; end if;
  end if;

  if p_type = 'coach_reply' and p_payload->>'thread_id' is null then
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

  if p_type = 'coach_reply' then
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

create or replace function public.refund_unsuccessful_job()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if new.status = 'dead' or (new.status = 'done' and (
    new.result->>'unreadable' = 'true' or new.result->>'cached' = 'true'
    or new.result ? 'skipped' or new.result->>'superseded' = 'true'
  )) then
    perform public.refund_job_quota(new.id);
  end if;
  return null;
end $$;
create trigger refund_unsuccessful_job
  after update of status on public.jobs_queue
  for each row execute function public.refund_unsuccessful_job();

revoke all on function public.enqueue_student_job(uuid,text,jsonb,text) from public, anon, authenticated;
revoke all on function public.refund_job_quota(uuid) from public, anon, authenticated;
revoke all on function public.refund_unsuccessful_job() from public, anon, authenticated;
revoke all on function public.consume_quota(uuid,text,int) from public, anon, authenticated;
revoke all on function public.quota_remaining(uuid,text,int) from public, anon, authenticated;
revoke all on function public.refund_quota(uuid,text) from public, anon, authenticated;
grant execute on function public.enqueue_student_job(uuid,text,jsonb,text),
  public.refund_job_quota(uuid), public.consume_quota(uuid,text,int),
  public.quota_remaining(uuid,text,int), public.refund_quota(uuid,text) to service_role;
grant execute on function public.ai_daily_limit(), public.coach_allowance() to authenticated;

alter table public.score_weights force row level security;
alter table public.schema_migrations force row level security;

-- Feedback and its answer become visible together. A stale evaluation cannot
-- overwrite a newer submitted answer.
create or replace function public.save_interview_feedback(p_job_id uuid, p_feedback jsonb)
returns void language plpgsql security definer set search_path = public
as $$
declare v_job public.jobs_queue;
begin
  select * into strict v_job from public.jobs_queue where id = p_job_id and type = 'interview_evaluate';
  perform pg_advisory_xact_lock(hashtextextended('tack:answer:' || (v_job.payload->>'question_id'), 0));
  if exists(select 1 from public.jobs_queue where user_id = v_job.user_id
    and type = v_job.type and payload->>'question_id' = v_job.payload->>'question_id'
    and created_at > v_job.created_at) then return; end if;
  update public.interview_questions set answer_text = v_job.payload->>'answer', answered_at = now()
    where id = (v_job.payload->>'question_id')::uuid and user_id = v_job.user_id;
  if not found then raise exception 'question_not_owned'; end if;
  insert into public.interview_feedback(question_id, user_id, job_id, score, went_well, to_improve, model_answer)
    values((v_job.payload->>'question_id')::uuid, v_job.user_id, v_job.id,
      (p_feedback->>'score')::numeric,
      p_feedback->'went_well',
      p_feedback->'to_improve',
      p_feedback->>'model_answer')
    on conflict(question_id) do update set job_id = excluded.job_id,
      score = excluded.score, went_well = excluded.went_well,
      to_improve = excluded.to_improve, model_answer = excluded.model_answer;
end $$;
revoke all on function public.save_interview_feedback(uuid,jsonb) from public, anon, authenticated;
grant execute on function public.save_interview_feedback(uuid,jsonb) to service_role;

-- A client cannot attach a forged message or feedback to a worker receipt.
revoke insert, update on public.chat_messages from authenticated;
grant insert(thread_id,user_id,role,body,answered_by), update(body) on public.chat_messages to authenticated;
revoke insert, update, delete on public.interview_feedback from authenticated, anon;

alter table public.cv_checks add column job_id uuid references public.jobs_queue(id) on delete set null unique;
