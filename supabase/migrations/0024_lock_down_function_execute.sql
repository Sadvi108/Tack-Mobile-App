-- Close a real hole: every function added after migration 0010 was callable
-- by anyone holding the anon key.
--
-- 0010 ran `revoke all on all functions in schema public from anon`, which
-- only affects functions that exist at that moment. Everything created in
-- 0011 onward got PostgreSQL's default of EXECUTE TO PUBLIC. Verified
-- exploitable with the anon key alone, which ships inside every copy of the
-- app:
--
--   readiness_ratios(<victim>)    -> returned their full score breakdown
--   consume_quota(<victim>, ...)  -> burned their daily AI quota
--   recompute_readiness(<victim>) -> wrote a score snapshot as them
--   nightly_maintenance()         -> ran deletes
--   claim_jobs()                  -> reached into the job queue
--
-- These take a user id as an argument and are SECURITY DEFINER, so Row Level
-- Security never applied. RLS protects tables; it does not protect a function
-- that was handed the caller's choice of user id.
--
-- The rule from here: functions are private unless a client genuinely needs
-- them, and a function a client may call must either be SECURITY INVOKER or
-- derive the user from auth.uid() rather than from an argument.

do $$
declare fn record;
begin
  for fn in
    select p.oid::regprocedure as sig
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        -- Leave extension-owned functions alone: pg_trgm's operator support
        -- is used by index scans and is not ours to re-permission.
        and not exists (
          select 1 from pg_depend d
          where d.objid = p.oid and d.deptype = 'e'
        )
  loop
    execute format('revoke all on function %s from public, anon, authenticated', fn.sig);
  end loop;
end $$;

-- The short list a signed-in student legitimately calls. Each one either runs
-- as the caller so RLS applies, or takes no user id at all.
grant execute on function public.set_default_cv(uuid)            to authenticated; -- security invoker
grant execute on function public.current_readiness()             to authenticated; -- reads auth.uid()
grant execute on function public.upsert_company(text)            to authenticated; -- creates a shared company row only
grant execute on function public.is_valid_status_transition(application_status, application_status) to authenticated; -- pure
grant execute on function public.normalise_company_name(text)    to authenticated; -- pure
grant execute on function public.year_to_mode(int, int)          to authenticated; -- pure

-- Anon signs in and nothing else.
-- Everything else — quota, scoring, the queue, maintenance — is reachable
-- only by the service role, which Edge Functions and cron use.

-- Stop this regressing: functions added by later migrations start private.
alter default privileges in schema public revoke execute on functions from public;
alter default privileges for role postgres in schema public revoke execute on functions from public;

-- The same oversight on tables. RLS was already denying these, since neither
-- table has a policy for anon, but a grant that does nothing is a grant
-- waiting to matter.
revoke all on public.analytics_events from anon;
revoke all on public.error_reports    from anon;
revoke all on public.score_weights    from anon;
