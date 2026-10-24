-- Review fixes for the cited coach (0085, 0086).
--
-- 1. Two catalog edits at once both rebuilt the chunk index, and the second
--    one's insert collided with the first's: an admin edit rolled back for no
--    reason a person could see. The rebuild now takes a transaction lock.
-- 2. A coach question could be queued into a deleted conversation, charged,
--    and answered where the student would never see it. enqueue_student_job
--    (0082) now requires a live thread; nothing else in it changes.

-- ------------------------------------------------------------------------ 1
create or replace function public.rebuild_career_catalog_chunks()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('tack:career_catalog_chunks', 0));

  delete from public.career_catalog_chunks;

  insert into public.career_catalog_chunks
    (chunk_id, path_id, path_slug, path_title, kind, text, tsv)
  select c.chunk_id, c.path_id, c.slug, c.title, c.kind, c.text,
         setweight(to_tsvector('english', c.title), 'A')
           || to_tsvector('english', c.text)
    from (
      select p.id as path_id, p.slug, p.title,
             p.slug || ':summary:1' as chunk_id, 'summary' as kind,
             p.summary as text
        from public.career_paths p
       where p.is_active
      union all
      select p.id, p.slug, p.title,
             p.slug || ':day:' || d.n, 'day_to_day',
             'Day to day: ' || d.item
        from public.career_paths p,
             unnest(p.day_to_day) with ordinality as d(item, n)
       where p.is_active
      union all
      select p.id, p.slug, p.title,
             p.slug || ':fit:' || f.n, 'good_fit',
             'A good fit if: ' || f.item
        from public.career_paths p,
             unnest(p.good_fit_if) with ordinality as f(item, n)
       where p.is_active
      union all
      select p.id, p.slug, p.title,
             p.slug || ':salary:1', 'salary',
             'Salary: a starting ' || lower(p.title) || ' usually earns '
               || to_char(p.salary_min_bdt, 'FM999,999,999') || ' to '
               || to_char(coalesce(p.salary_max_bdt, p.salary_min_bdt), 'FM999,999,999')
               || ' taka a month.'
        from public.career_paths p
       where p.is_active and p.salary_min_bdt is not null
      union all
      select p.id, p.slug, p.title,
             p.slug || ':demand:1', 'demand',
             'Demand: hiring for this role in Bangladesh is ' || p.demand_level || '.'
        from public.career_paths p
       where p.is_active and p.demand_level is not null
      union all
      select p.id, p.slug, p.title,
             p.slug || ':ready:1', 'time_to_ready',
             'Time to job-ready: about ' || p.months_to_job_ready
               || ' months of steady work.'
        from public.career_paths p
       where p.is_active and p.months_to_job_ready is not null
      union all
      select p.id, p.slug, p.title,
             p.slug || ':step:' || (m.order_index + 1), 'step',
             'Step ' || (m.order_index + 1) || ': '
               || concat_ws(' ', m.title || '.', m.description, m.unlock_text)
        from public.career_paths p
        join public.career_path_milestones m on m.path_id = p.id
       where p.is_active
    ) c
   where nullif(btrim(c.text), '') is not null;
end $$;

revoke all on function public.rebuild_career_catalog_chunks() from public, anon, authenticated;

-- ------------------------------------------------------------------------ 2
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
    -- A deleted conversation cannot be continued: the reply would land in a
    -- thread the student can no longer see, and they would pay for it.
    if not exists(select 1 from public.chat_threads
      where id = (p_payload->>'thread_id')::uuid and user_id = p_user_id
        and deleted_at is null) then
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
