-- Scoring must not depend on an Edge Function being deployed.
--
-- Readiness recompute is pure SQL: the triggers enqueue it and the HTTP worker
-- was calling `recompute_readiness` straight back into Postgres. That is a
-- round trip out of the database and back for work that never had to leave,
-- and it meant the app's central number stayed at zero until the functions
-- shipped. Postgres drains those jobs itself now.
--
-- The HTTP worker still owns everything that genuinely needs the outside
-- world — the model calls — and will simply find no recompute jobs waiting.

create or replace function public.drain_local_jobs(p_limit int default 50)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job record;
  v_done int := 0;
begin
  for v_job in
    select id, user_id, payload
      from public.jobs_queue
      where status = 'pending'
        and type = 'recompute_readiness'
        and run_after <= now()
      order by run_after
      limit p_limit
      for update skip locked
  loop
    begin
      perform public.recompute_readiness(
        coalesce((v_job.payload->>'user_id')::uuid, v_job.user_id),
        coalesce(v_job.payload->>'source', 'cron')
      );

      update public.jobs_queue
        set status = 'done', result = jsonb_build_object('recomputed', true)
        where id = v_job.id;

      v_done := v_done + 1;
    exception when others then
      -- One bad row must not stop the rest of the batch.
      perform public.fail_job(v_job.id, sqlerrm);
    end;
  end loop;

  return v_done;
end $$;

revoke all on function public.drain_local_jobs(int) from anon, authenticated;

select cron.unschedule('tack-score-drain') where exists (
  select 1 from cron.job where jobname = 'tack-score-drain'
);

-- Every minute. A student who ticks a task sees their score move on the next
-- pull-to-refresh rather than whenever a deploy happens.
select cron.schedule('tack-score-drain', '* * * * *', $$select public.drain_local_jobs()$$);
