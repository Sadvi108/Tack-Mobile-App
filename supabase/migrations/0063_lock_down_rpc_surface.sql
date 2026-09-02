-- Closing the RPC surface to callers who are not signed in.
--
-- Supabase's security advisor found six SECURITY DEFINER functions callable by
-- `anon` — that is, by anybody holding the publishable key, which is in every
-- copy of the app. Three of them are *trigger* functions that nothing should
-- ever call by name: ensure_one_primary_path, promote_next_primary_path,
-- retire_roadmap_on_unfollow. The others were enqueue_cv_rescore,
-- recompute_my_cv_score and recompute_my_readiness.
--
-- The cause is not six mistakes. Postgres grants EXECUTE on a new function to
-- PUBLIC by default, and PUBLIC includes anon. Every migration that added a
-- function without an explicit revoke left it open. Naming the six and
-- revoking them would leave the seventh open the day somebody writes it.
--
-- A dry run showed the second half of the problem. Revoking PUBLIC and anon
-- alone dropped anon from 13 functions to 0 but left `authenticated` on 38,
-- because an early migration also ran a blanket grant to `authenticated` — so
-- every signed-in student could still call the five trigger functions and the
-- radar indexing helper by name. The sweep therefore revokes `authenticated`
-- too, and the allowlist below is the only thing that gives it back.
--
-- So the default becomes deny, in three parts:
--
--   1. ALTER DEFAULT PRIVILEGES, so functions written after this one are not
--      granted to PUBLIC in the first place. This is the part that stops the
--      problem coming back.
--   2. A sweep that revokes PUBLIC and anon from every function already in the
--      schema.
--   3. An explicit allowlist granted back to `authenticated`, which is the
--      client API documented in docs/API.md and nothing else.
--
-- Two things are deliberately left alone. Extension-owned functions (pg_trgm's
-- similarity operators and GiST/GIN support) are skipped via pg_depend: they
-- are not ours to re-permission, and the trigram indexes on skills, companies
-- and universities depend on them. And `service_role`/`postgres` keep every
-- grant they hold — checked against the live database first, because the
-- worker, the nightly sweep and the quota primitives all run as service_role,
-- and a blanket revoke that caught them would silently stop the job queue
-- draining. They hold explicit grants, not PUBLIC's, so this does not touch
-- them.

-- 1 ---------------------------------------------------------------- the future
alter default privileges in schema public revoke execute on functions from public;

-- 2 ----------------------------------------------------------------- the sweep
do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.prokind = 'f'
       -- Not ours: installed by an extension.
       and not exists (
             select 1 from pg_depend d
              where d.objid = p.oid and d.deptype = 'e')
  loop
    execute format('revoke execute on function %s from public', r.sig);
    execute format('revoke execute on function %s from anon', r.sig);
    execute format('revoke execute on function %s from authenticated', r.sig);
  end loop;
end $$;

-- 3 ------------------------------------------------------------- the allowlist
--
-- Everything a signed-in student may call, and why it is here.
--
-- The seven owns_* helpers are not a client API: row policies call them, and a
-- policy runs as the caller, so they must be executable by `authenticated` for
-- RLS to work at all. Revoking them would lock every student out of their own
-- rows.
do $$
declare
  -- The client API. Anything absent from this list is now unreachable from the
  -- app, which for a trigger function or a worker primitive is the point.
  allowed constant text[] := array[
    -- dashboard
    'dashboard_feed', 'tack_today',
    -- roadmap and paths
    'generate_roadmap', 'path_suggestions', 'stop_following_path',
    'set_primary_path',
    -- radar (radar_feed is called by the radar Edge Function as the *user*,
    -- so that the fit score is computed against their skills and nobody else's)
    'radar_feed', 'radar_kinds', 'save_listing',
    -- coach (coach_context likewise runs as the user)
    'coach_allowance', 'coach_context',
    -- onboarding, profile and scoring
    'submit_onboarding', 'write_onboarding',
    'recompute_my_readiness', 'current_readiness',
    'recompute_my_cv_score', 'current_cv_score', 'set_default_cv',
    -- applications
    'upsert_company', 'normalise_company_name', 'is_valid_status_transition',
    -- pure converters, safe anywhere
    'year_to_mode', 'stage_to_mode', 'derive_mode', 'classify_employment',
    -- RLS policy helpers
    'owns_application', 'owns_course', 'owns_document', 'owns_milestone',
    'owns_question', 'owns_roadmap', 'owns_session'
  ];
  r record;
  v_granted int := 0;
begin
  for r in
    select p.oid::regprocedure as sig
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = any(allowed)
  loop
    execute format('grant execute on function %s to authenticated', r.sig);
    v_granted := v_granted + 1;
  end loop;

  -- A name that no longer resolves means a function was renamed and this list
  -- was not, which would quietly remove it from the client API.
  if v_granted <> array_length(allowed, 1) then
    raise exception
      'allowlist has % names but % functions matched — a name is stale',
      array_length(allowed, 1), v_granted;
  end if;
end $$;

-- 4 ------------------------------------------------------------ prove it stuck
--
-- The migration checks its own work. If anything of ours is still reachable
-- without signing in, this fails and rolls back rather than reporting success.
do $$
declare
  v_open text;
begin
  -- Nothing of ours may be reachable without signing in.
  select string_agg(p.oid::regprocedure::text, ', ')
    into v_open
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.prokind = 'f'
     and not exists (
           select 1 from pg_depend d
            where d.objid = p.oid and d.deptype = 'e')
     and has_function_privilege('anon', p.oid, 'EXECUTE');

  if v_open is not null then
    raise exception 'still executable by anon: %', v_open;
  end if;

  -- And no trigger function may be callable by name at all. This is the
  -- invariant rather than a count, so it still holds after the next migration
  -- adds a function — a trigger body reached through PostgREST runs with every
  -- TG_ variable null, which is a crash at best and a bypassed check at worst.
  select string_agg(p.proname, ', ')
    into v_open
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.prorettype = 'trigger'::regtype
     and (has_function_privilege('anon', p.oid, 'EXECUTE')
       or has_function_privilege('authenticated', p.oid, 'EXECUTE'));

  if v_open is not null then
    raise exception 'trigger functions still callable by a client: %', v_open;
  end if;
end $$;

comment on schema public is
  'EXECUTE is deny-by-default here. A new function is reachable from the app '
  'only once it is granted to authenticated by name — see 0063 and docs/API.md.';
