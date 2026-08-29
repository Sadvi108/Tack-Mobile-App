-- Every child table has been unwritable by students since migration 0024.
--
-- 0024 closed a real hole: functions added after 0010 were callable by anyone
-- holding the anon key, so it revoked EXECUTE on everything and granted back a
-- short list. But seven of the revoked functions are not called by clients at
-- all — they are called by row level security policies, on the caller's
-- behalf, while the caller's own statement runs:
--
--   roadmap_milestones  insert/update -> owns_roadmap
--   roadmap_tasks       insert/update -> owns_milestone
--   interview_questions insert/update -> owns_question, owns_session
--   course_skills       insert/select -> owns_course
--
-- A policy that calls a function the caller may not execute does not fall
-- back to false. It raises:
--
--   POST /rest/v1/roadmap_milestones
--   -> 403 42501 permission denied for function owns_roadmap
--
-- So picking a career path created an empty roadmap, ticking a task failed,
-- and a practice session could not store its questions. The dashboard read
-- the roadmap as `.value ?? const []`, so all of that surfaced as a card
-- saying "0 of 0 steps done".
--
-- Granting these back does not undo 0024. Each is SECURITY DEFINER and each
-- answers exactly one question — "does this row belong to me?" — resolved
-- against auth.uid() and nobody else's id. The caller cannot learn anything
-- they did not already know, which is the opposite of the functions 0024 was
-- written to lock down: those took a user id as an argument and would answer
-- about a stranger.
grant execute on function public.owns_roadmap(uuid)     to authenticated;
grant execute on function public.owns_milestone(uuid)   to authenticated;
grant execute on function public.owns_application(uuid) to authenticated;
grant execute on function public.owns_document(uuid)    to authenticated;
grant execute on function public.owns_session(uuid)     to authenticated;
grant execute on function public.owns_question(uuid)    to authenticated;
grant execute on function public.owns_course(uuid)      to authenticated;

-- Prove it, rather than assert it: every policy that names one of these
-- helpers must have an executable helper behind it, or the table it guards is
-- silently read-only for the people it was written for.
do $$
declare
  r record;
  v_missing text[] := '{}';
begin
  for r in
    select p.oid::regprocedure as sig, p.proname
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname like 'owns\_%'
  loop
    if not has_function_privilege('authenticated', r.sig, 'EXECUTE') then
      v_missing := v_missing || r.proname;
    end if;
  end loop;

  if array_length(v_missing, 1) > 0 then
    raise exception 'ownership helpers still unusable by a student: %', v_missing;
  end if;
end $$;
