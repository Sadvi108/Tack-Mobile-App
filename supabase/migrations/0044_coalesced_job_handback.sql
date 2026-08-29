-- Handing a coalesced job back could not work, and took the whole reaper with it.
--
-- Migration 0021 added a partial unique index so that at most one recompute is
-- pending per student. 0041 added the same index for score_cv. Both are right:
-- coalescing is what stopped a burst of skill inserts queuing forty identical
-- recomputes.
--
-- But two functions move a job *back* to pending, and neither knew about it:
--
--   fail_job        retries a job after a failure
--   reap_stuck_jobs hands back a job whose worker died
--
-- If another pending job of that type already exists for the student, the move
-- violates the index. Reproduced against the live database:
--
--   reap_stuck_jobs -> 23505 duplicate key ... jobs_queue_one_pending_cv_score
--   fail_job        -> 23505 duplicate key ... jobs_queue_one_pending_cv_score
--
-- The consequences differ and the second is the bad one. fail_job throws, the
-- worker's rpc call returns an error nobody reads, and the job stays 'running'
-- forever. reap_stuck_jobs throws mid-statement, so *nothing* is reaped — one
-- poisoned row stops the reaper for every student on the platform.
--
-- The fix follows from what coalescing means. If a pending job of the same
-- type is already waiting for this student, it will do exactly the work the
-- stuck one was going to do. So the stuck job is not resurrected, it is
-- retired as superseded.

-- The types with a partial unique index on (user_id, type) where pending.
-- This list must track those indexes: adding another coalesced type without
-- adding it here reintroduces the bug.
create or replace function public.is_coalesced_job(p_type text)
returns boolean
language sql
immutable
as $$
  select p_type in ('recompute_readiness', 'score_cv')
$$;

revoke all on function public.is_coalesced_job(text) from public, anon, authenticated;

create or replace function public.superseded_by_pending(p_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.jobs_queue mine
      join public.jobs_queue other
        on other.user_id is not distinct from mine.user_id
       and other.type = mine.type
       and other.id <> mine.id
       and other.status = 'pending'
     where mine.id = p_id
       and public.is_coalesced_job(mine.type)
  )
$$;

revoke all on function public.superseded_by_pending(uuid) from public, anon, authenticated;

-- Backoff: 30s, 2m, 8m. After max_attempts the job is dead-lettered, never
-- retried. A coalesced job with a newer one already waiting is retired instead
-- of retried, because retrying it would do the same work twice at best and
-- violate the coalescing index at worst.
create or replace function public.fail_job(p_id uuid, p_error text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare a int; m int;
begin
  select attempts, max_attempts into a, m from public.jobs_queue where id = p_id;
  if a is null then return; end if;

  if a >= m then
    update public.jobs_queue
      set status = 'dead', last_error = p_error, locked_at = null, locked_by = null
      where id = p_id;
  elsif public.superseded_by_pending(p_id) then
    update public.jobs_queue
      set status = 'done',
          last_error = p_error,
          result = jsonb_build_object('superseded', true),
          locked_at = null, locked_by = null
      where id = p_id;
  else
    update public.jobs_queue
      set status = 'pending', last_error = p_error, locked_at = null, locked_by = null,
          run_after = now() + (interval '30 seconds' * power(4, a))
      where id = p_id;
  end if;
end $$;

revoke all on function public.fail_job(uuid, text) from public, anon, authenticated;

-- Reaping is row by row rather than one set-based update: a single statement
-- that violates a constraint on one row rolls back every other row with it,
-- which is exactly how one stuck job came to block the whole sweep.
create or replace function public.reap_stuck_jobs(p_older interval default interval '10 minutes')
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_count int := 0;
begin
  for r in
    select id, attempts, max_attempts
      from public.jobs_queue
     where status = 'running'
       and locked_at is not null
       and locked_at < now() - p_older
     for update skip locked
  loop
    begin
      if r.attempts >= r.max_attempts then
        update public.jobs_queue
           set status = 'dead'::queue_status,
               last_error = 'worker did not finish',
               locked_at = null, locked_by = null
         where id = r.id;
      elsif public.superseded_by_pending(r.id) then
        update public.jobs_queue
           set status = 'done'::queue_status,
               last_error = 'worker did not finish',
               result = jsonb_build_object('superseded', true),
               locked_at = null, locked_by = null
         where id = r.id;
      else
        update public.jobs_queue
           set status = 'pending'::queue_status,
               last_error = 'worker did not finish',
               locked_at = null, locked_by = null,
               run_after = now()
         where id = r.id;
      end if;
      v_count := v_count + 1;
    exception when unique_violation then
      -- Belt and braces. A job that cannot be handed back for any reason must
      -- not stop the rest of the sweep.
      update public.jobs_queue
         set status = 'done'::queue_status,
             last_error = 'worker did not finish; superseded',
             result = jsonb_build_object('superseded', true),
             locked_at = null, locked_by = null
       where id = r.id;
      v_count := v_count + 1;
    end;
  end loop;

  return v_count;
end $$;

revoke all on function public.reap_stuck_jobs(interval) from public, anon, authenticated;

-- Prove both paths against real rows, so this cannot regress silently the way
-- it was introduced.
do $$
declare
  v_user uuid;
  v_pending uuid; v_stuck uuid; v_lonely uuid; v_failing uuid;
begin
  select id into v_user from public.profiles limit 1;
  if v_user is null then
    raise notice 'no profile to self-test against, skipping';
    return;
  end if;

  insert into public.jobs_queue (user_id, type, payload, status)
    values (v_user, 'score_cv', '{"selftest":1}'::jsonb, 'pending')
    returning id into v_pending;
  insert into public.jobs_queue (user_id, type, payload, status, attempts, max_attempts, locked_at, locked_by)
    values (v_user, 'score_cv', '{"selftest":1}'::jsonb, 'running', 1, 3, now() - interval '1 hour', 'selftest')
    returning id into v_stuck;
  insert into public.jobs_queue (user_id, type, payload, status, attempts, max_attempts, locked_at, locked_by)
    values (v_user, '__selftest_lonely', '{"selftest":1}'::jsonb, 'running', 1, 3, now() - interval '1 hour', 'selftest')
    returning id into v_lonely;

  perform public.reap_stuck_jobs();

  if (select status from public.jobs_queue where id = v_stuck) <> 'done' then
    raise exception 'a superseded coalesced job was not retired: %',
      (select status from public.jobs_queue where id = v_stuck);
  end if;
  if (select status from public.jobs_queue where id = v_lonely) <> 'pending' then
    raise exception 'an ordinary stuck job was not handed back: %',
      (select status from public.jobs_queue where id = v_lonely);
  end if;

  -- And the same for fail_job, which is where a live worker would hit it.
  insert into public.jobs_queue (user_id, type, payload, status, attempts, max_attempts)
    values (v_user, 'score_cv', '{"selftest":2}'::jsonb, 'running', 1, 3)
    returning id into v_failing;
  perform public.fail_job(v_failing, 'selftest');
  if (select status from public.jobs_queue where id = v_failing) <> 'done' then
    raise exception 'fail_job did not retire a superseded coalesced job: %',
      (select status from public.jobs_queue where id = v_failing);
  end if;

  delete from public.jobs_queue where payload->>'selftest' is not null;
end $$;
