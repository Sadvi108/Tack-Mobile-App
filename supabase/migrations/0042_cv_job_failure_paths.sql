-- Closing the ways a CV can get stuck.
--
-- DocumentRepository.upload sets a CV to 'processing' and, until this slice,
-- nothing in the system ever moved it out of that state: there was no parse_cv
-- handler at all. Every CV uploaded so far is still spinning. Shipping the
-- handler fixes the happy path; this file makes a stuck document impossible by
-- construction rather than by the handler always working.
--
-- Three guards, each for a different way it goes wrong:
--   a job that dies       -> the document says so, with a sentence to act on
--   a worker that dies    -> the job is handed back rather than lost
--   a document with no job at all -> swept up nightly

-- ------------------------------------------------------------ a job that dies
create or replace function public.fail_document_on_dead_job()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_doc uuid;
begin
  if new.type <> 'parse_cv' then return null; end if;

  v_doc := nullif(new.payload->>'document_id', '')::uuid;
  if v_doc is null then return null; end if;

  -- The worker sets a specific reason for the failures it can explain — an
  -- unreadable scan, a password-protected PDF. Only a document still waiting
  -- is touched here, so that better sentence is never overwritten by this
  -- fallback.
  update public.documents
     set status = 'failed',
         failure_reason = coalesce(
           failure_reason,
           'Tack could not read that CV. Upload it again, or export it as a PDF first.')
   where id = v_doc
     and status in ('pending', 'processing')
     and deleted_at is null;

  insert into public.audit_log (user_id, action, entity, entity_id, meta)
    values (new.user_id, 'cv_parse_dead', 'documents', v_doc,
            jsonb_build_object('job_id', new.id, 'attempts', new.attempts));

  return null;
end $$;

revoke all on function public.fail_document_on_dead_job() from public, anon, authenticated;

create trigger jobs_queue_dead_fails_document
  after update of status on public.jobs_queue
  for each row
  when (new.status = 'dead' and old.status is distinct from 'dead')
  execute function public.fail_document_on_dead_job();

-- --------------------------------------------------------- a worker that dies
-- claim_jobs only ever picks up 'pending', so a job whose worker was killed
-- mid-run stays 'running' forever and is never retried. That was survivable
-- while the longest job was a job-description analysis; CV parsing is the
-- slowest thing in the system and the most likely to be caught by a restart.
create or replace function public.reap_stuck_jobs(p_older interval default interval '10 minutes')
returns int
language plpgsql
security definer
set search_path = public
as $$
declare v_count int;
begin
  with stuck as (
    select id, attempts, max_attempts
      from public.jobs_queue
     where status = 'running'
       and locked_at is not null
       and locked_at < now() - p_older
     for update skip locked
  )
  update public.jobs_queue q
     set status = case when s.attempts >= s.max_attempts then 'dead' else 'pending' end,
         last_error = 'worker did not finish',
         locked_at = null,
         locked_by = null,
         run_after = now()
    from stuck s
   where q.id = s.id;

  get diagnostics v_count = row_count;
  return v_count;
end $$;

revoke all on function public.reap_stuck_jobs(interval) from public, anon, authenticated;

-- ------------------------------------------------- a document with no job left
-- The backstop for anything the two guards above cannot see: a CV that has sat
-- in 'processing' with nothing queued for it and nothing parsed. This is what
-- clears the documents that were stuck before any of this existed.
create or replace function public.sweep_stuck_documents(p_older interval default interval '1 hour')
returns int
language plpgsql
security definer
set search_path = public
as $$
declare v_count int;
begin
  update public.documents d
     set status = 'failed',
         failure_reason = coalesce(
           failure_reason,
           'Reading that CV did not finish. Upload it again and Tack will try once more.')
   where d.type = 'cv'
     and d.status = 'processing'
     and d.deleted_at is null
     and d.updated_at < now() - p_older
     and not exists (
       select 1 from public.jobs_queue j
        where j.type = 'parse_cv'
          and j.status in ('pending', 'running')
          and nullif(j.payload->>'document_id', '')::uuid = d.id)
     and not exists (
       select 1 from public.cv_parse_results r where r.document_id = d.id);

  get diagnostics v_count = row_count;
  return v_count;
end $$;

revoke all on function public.sweep_stuck_documents(interval) from public, anon, authenticated;

-- Both join the nightly run. The reaper is also called by the worker at the
-- top of every drain, because ten minutes is a long time to leave a student
-- watching a spinner.
create or replace function public.nightly_maintenance()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  refresh materialized view concurrently public.cohort_averages;

  delete from public.documents
    where deleted_at is not null and purge_after is not null and purge_after < now();

  delete from public.jobs_queue
    where status in ('done', 'dead') and updated_at < now() - interval '7 days';

  delete from public.analytics_events where occurred_at < now() - interval '90 days';
  delete from public.error_reports    where occurred_at < now() - interval '90 days';

  perform public.reap_stuck_jobs();
  perform public.sweep_stuck_documents();
end $$;

revoke all on function public.nightly_maintenance() from anon, authenticated;

-- Finding the job for a document is now a real access path, not a rarity.
create index if not exists jobs_queue_parse_cv_document_idx
  on public.jobs_queue ((payload->>'document_id'))
  where type = 'parse_cv';
