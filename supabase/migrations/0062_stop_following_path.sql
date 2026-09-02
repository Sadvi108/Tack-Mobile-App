-- Changing your mind, without losing what you did.
--
-- A student picks a path, works at it for three weeks, and realises it is not
-- for them. Until now there was no way out from inside the app: unfollow lived
-- only on the path detail screen, several taps away, and the roadmap tab had
-- no exit at all.
--
-- Nothing is deleted. Retiring a path soft-deletes its roadmap, and following
-- it again brings the roadmap and every ticked step back exactly as they were
-- — which is what makes this a safe button rather than a scary one. Measured
-- on a real account: 6 steps ticked, roadmap_progress 0.2069, cancel, 0.0000,
-- follow again, 0.2069.
--
-- It exists as a function so the rule has one definition. The roadmap screen
-- must not reach into the paths feature's repository to do this, and two
-- copies of "retiring a path also retires its roadmap" is exactly how the
-- roadmap came to outlive the decision to stop following it in the first
-- place.
create or replace function public.stop_following_path(p_path_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_hit int;
begin
  if v_uid is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;

  update public.user_career_paths
     set deleted_at = now()
   where user_id = v_uid
     and path_id = p_path_id
     and deleted_at is null;

  get diagnostics v_hit = row_count;

  -- The roadmap is retired by user_career_paths_retire_roadmap, which fires on
  -- this update. Doing it here as well would be the second copy of the rule.
  --
  -- A student who was never following it is not an error: two taps on a slow
  -- connection should leave them stopped, not show them a failure.
  return v_hit > 0;
end $$;

revoke all on function public.stop_following_path(uuid) from public, anon;
grant execute on function public.stop_following_path(uuid) to authenticated;


do $$
begin
  if not has_function_privilege('authenticated', 'public.stop_following_path(uuid)', 'EXECUTE') then
    raise exception 'stop_following_path is not callable by a signed-in student';
  end if;
  if has_function_privilege('anon', 'public.stop_following_path(uuid)', 'EXECUTE') then
    raise exception 'stop_following_path must not be reachable with the anon key alone';
  end if;
end $$;
