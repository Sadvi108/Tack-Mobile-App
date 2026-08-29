-- reap_stuck_jobs never reaped anything.
--
--   set status = case when s.attempts >= s.max_attempts then 'dead' else 'pending' end
--
-- Both branches are unknown-typed literals, so the CASE resolves to text, and
-- text does not assign to a queue_status column. A plain `set status = 'dead'`
-- works — the literal is coerced to the column's type — which is why every
-- other statement in 0042 was fine and this one was not.
--
-- It failed at runtime, not at migration time: plpgsql does not resolve types
-- inside a function body until the body runs. Same class of mistake as 0039,
-- where a renamed enum value left two function bodies referring to a label the
-- type no longer had. The lesson is the one 0039 already taught — a migration
-- applying cleanly says nothing about whether its functions execute.

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
     set status = case
                    when s.attempts >= s.max_attempts then 'dead'::queue_status
                    else 'pending'::queue_status
                  end,
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

-- The same shape appears nowhere else in this schema, but it is worth proving
-- rather than asserting: this exercises both branches on throwaway rows and
-- refuses the migration if either one still fails to assign.
do $$
declare
  v_retry uuid;
  v_dead  uuid;
  v_reaped int;
begin
  insert into public.jobs_queue (type, payload, status, attempts, max_attempts, locked_at, locked_by)
    values ('__reap_selftest', '{}'::jsonb, 'running', 1, 3, now() - interval '1 hour', 'selftest')
    returning id into v_retry;
  insert into public.jobs_queue (type, payload, status, attempts, max_attempts, locked_at, locked_by)
    values ('__reap_selftest', '{}'::jsonb, 'running', 3, 3, now() - interval '1 hour', 'selftest')
    returning id into v_dead;

  v_reaped := public.reap_stuck_jobs();
  if v_reaped < 2 then
    raise exception 'reap_stuck_jobs returned %, expected at least 2', v_reaped;
  end if;

  if (select status from public.jobs_queue where id = v_retry) <> 'pending' then
    raise exception 'a job with attempts left was not handed back';
  end if;
  if (select status from public.jobs_queue where id = v_dead) <> 'dead' then
    raise exception 'a job out of attempts was not dead-lettered';
  end if;

  delete from public.jobs_queue where type = '__reap_selftest';
end $$;
