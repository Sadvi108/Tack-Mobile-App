-- Making deny-by-default actually true.
--
-- 0063 claimed that `alter default privileges in schema public revoke execute
-- on functions from public` would stop the problem coming back. It does not,
-- and the very next migration proved it: 0064 added two helper functions and
-- tool/verify_rpc_surface.js immediately failed with both of them executable
-- by anon.
--
-- Measured rather than assumed. Creating a function after 0063 and reading its
-- ACL back gives:
--
--   {=X/postgres, postgres=X/postgres, anon=X/postgres,
--    authenticated=X/postgres, service_role=X/postgres}
--
-- Two separate grants are in there and 0063 addressed neither properly:
--
--   * `=X/postgres` is PUBLIC. Postgres applies EXECUTE-to-PUBLIC to every new
--     function from its own built-in default, and ALTER DEFAULT PRIVILEGES
--     cannot suppress it — re-running the revoke in the same session and
--     creating another function produced the identical ACL. A default-ACL row
--     records grants to add, not the built-in to take away.
--   * `anon=X` and `authenticated=X` come from Supabase's own pre-configured
--     default privileges (visible in pg_default_acl for both the postgres and
--     supabase_admin roles). Those *can* be revoked, and are, below.
--
-- So a sweep alone can never hold: it is correct only until the next CREATE
-- FUNCTION. What holds is an event trigger, which fires as each function is
-- created and takes PUBLIC and anon straight back off it. Event triggers turn
-- out to be permitted on this project, which makes this a real fix rather than
-- a convention nobody remembers.
--
-- The check that caught this stays the backstop: tool/verify_rpc_surface.js
-- asserts the invariant from outside, over HTTP as well as in the catalogue.

-- ------------------------------------------------- 1. the two 0064 left open
revoke execute on function public.onboarding_intended_field_slug(jsonb) from public, anon;
revoke execute on function public.onboarding_intended_field(jsonb) from public, anon;

-- ------------------------------------ 2. Supabase's default grants, removed
-- These two do work, unlike the PUBLIC revoke, so a new function no longer
-- arrives pre-granted to the client roles. A migration that wants a function
-- reachable from the app now has to say so.
alter default privileges in schema public revoke execute on functions from anon;
alter default privileges in schema public revoke execute on functions from authenticated;

-- ------------------------------------------------ 3. the part that persists
create or replace function public.revoke_public_execute()
returns event_trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
begin
  for r in
    select objid, object_identity
      from pg_event_trigger_ddl_commands()
     where command_tag = 'CREATE FUNCTION'
       and schema_name = 'public'
  loop
    -- An extension owns its own functions; pg_trgm's operators are not ours to
    -- re-permission and the trigram indexes depend on them.
    if exists (select 1 from pg_depend d
                where d.objid = r.objid and d.deptype = 'e') then
      continue;
    end if;

    begin
      execute format('revoke execute on function %s from public', r.objid::regprocedure);
      execute format('revoke execute on function %s from anon', r.objid::regprocedure);
    exception when others then
      -- Never let a permissions tidy-up abort somebody's migration. The
      -- verify script is what turns a miss into a visible failure.
      raise warning 'could not revoke public execute on %: %',
        r.object_identity, sqlerrm;
    end;
  end loop;
end $$;

comment on function public.revoke_public_execute() is
  'Event trigger body: strips the PUBLIC and anon EXECUTE that Postgres and '
  'Supabase put on every new function in public. See 0065.';

-- The guard cannot guard its own creation: it is created before the trigger
-- that would have stripped it, so it arrives with PUBLIC EXECUTE like anything
-- else. Caught by this migration's own closing check on the first dry run.
revoke execute on function public.revoke_public_execute() from public, anon, authenticated;

drop event trigger if exists tack_revoke_public_execute;
create event trigger tack_revoke_public_execute
  on ddl_command_end
  when tag in ('CREATE FUNCTION')
  execute function public.revoke_public_execute();

-- ------------------------------------------------------------ 4. proved live
-- A throwaway function, created and inspected through the trigger, then
-- dropped. If the guard is not working this migration fails and rolls back
-- rather than leaving a claim in a comment that nothing tests.
do $$
declare
  v_anon boolean;
  v_auth boolean;
begin
  execute 'create function public.tack_guard_probe() returns int language sql as ''select 1''';

  select has_function_privilege('anon', 'public.tack_guard_probe()', 'EXECUTE'),
         has_function_privilege('authenticated', 'public.tack_guard_probe()', 'EXECUTE')
    into v_anon, v_auth;

  execute 'drop function public.tack_guard_probe()';

  if v_anon then
    raise exception 'a newly created function is still executable by anon';
  end if;
  if v_auth then
    raise exception 'a newly created function is still executable by authenticated';
  end if;
end $$;

-- ------------------------------------------------------- 5. and still closed
do $$
declare
  v_open text;
begin
  select string_agg(p.oid::regprocedure::text, ', ')
    into v_open
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.prokind = 'f'
     and not exists (
           select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
     and has_function_privilege('anon', p.oid, 'EXECUTE');

  if v_open is not null then
    raise exception 'still executable by anon: %', v_open;
  end if;
end $$;
