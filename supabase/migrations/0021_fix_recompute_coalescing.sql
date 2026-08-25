-- The recompute trigger keyed its idempotency on the current minute:
--   'readiness:' || user_id || ':' || to_char(now(), 'YYYYMMDDHH24MI')
--
-- That silently dropped work. Once a minute's job had run, every further
-- change inside that same minute conflicted with the finished row and
-- enqueued nothing, so the score went stale until the student happened to
-- change something in a later minute. Adding eight skills straight after
-- onboarding moved the score by zero.
--
-- What was actually wanted is coalescing: at most one *pending* recompute per
-- student, and a new one whenever none is waiting. A partial unique index says
-- exactly that, and enforces it under concurrency rather than trusting the
-- trigger to look first.

create unique index if not exists jobs_queue_one_pending_recompute
  on public.jobs_queue (user_id, type)
  where status = 'pending' and type = 'recompute_readiness';

create or replace function public.enqueue_readiness_recompute()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  rec jsonb := to_jsonb(coalesce(new, old));
  uid uuid;
begin
  if tg_table_name = 'profiles' then
    uid := (rec->>'id')::uuid;
  else
    uid := (rec->>'user_id')::uuid;
  end if;
  if uid is null then return null; end if;

  -- The profile is already gone during a cascading account delete.
  if not exists (select 1 from public.profiles where id = uid) then
    return null;
  end if;

  -- The partial unique index collapses a burst of changes into one pending
  -- job; once that job runs, the next change queues a fresh one.
  insert into public.jobs_queue (user_id, type, payload, run_after)
    values (uid, 'recompute_readiness',
            jsonb_build_object('user_id', uid, 'source', tg_table_name),
            now() + interval '10 seconds')
  on conflict do nothing;

  return null;
end $$;
