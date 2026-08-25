-- Runs the queue worker every two minutes.
--
-- The bearer secret is NOT in this file. It lives in Supabase Vault under the
-- name 'tack_cron_secret' and is read at call time, so this migration can be
-- committed and the secret never can. Set it once with:
--
--   select vault.create_secret('<value>', 'tack_cron_secret');
--
-- and rotate it by updating that secret; nothing here changes.

create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

create or replace function public.dispatch_worker()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_secret text;
  v_url text;
begin
  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'tack_cron_secret';

  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'tack_functions_url';

  if v_secret is null or v_url is null then
    -- Nothing to do until the secrets are set. Silent rather than noisy:
    -- this runs every two minutes and a missing secret is a setup step,
    -- not a recurring incident.
    return;
  end if;

  perform net.http_post(
    url := v_url || '/worker',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_secret
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
end $$;

revoke all on function public.dispatch_worker() from anon, authenticated;

-- Re-scheduling is idempotent, so the migration can be re-run safely.
select cron.unschedule('tack-worker') where exists (
  select 1 from cron.job where jobname = 'tack-worker'
);

select cron.schedule('tack-worker', '*/2 * * * *', $$select public.dispatch_worker()$$);

-- Nightly: refresh the cohort benchmark the dashboards compare against, and
-- purge documents whose 30-day recovery window has passed.
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

  -- Queue rows are useful for a week and noise after that.
  delete from public.jobs_queue
    where status in ('done', 'dead') and updated_at < now() - interval '7 days';
end $$;

revoke all on function public.nightly_maintenance() from anon, authenticated;

select cron.unschedule('tack-nightly') where exists (
  select 1 from cron.job where jobname = 'tack-nightly'
);

select cron.schedule('tack-nightly', '20 18 * * *', $$select public.nightly_maintenance()$$);
