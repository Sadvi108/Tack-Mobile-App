-- Adding an application has never worked from the app.
--
-- job_applications carries an after-insert trigger that writes the first row
-- of the status timeline into application_status_history. That table is a
-- server-written audit trail, so it has a select policy and nothing else —
-- correct, because a student must not be able to forge their own history.
--
-- But record_application_status was SECURITY INVOKER, so the trigger's insert
-- ran as the student and was refused by the very policy that is meant to stop
-- them writing it by hand:
--
--   POST /rest/v1/job_applications
--   -> 403 42501 new row violates row-level security policy
--      for table "application_status_history"
--
-- Which the app renders as "You do not have access to that." The same trigger
-- fires on a status change, so moving an application along was broken too.
--
-- This was invisible because the live suites create applications with the
-- service role, which bypasses row level security and therefore never takes
-- the path a student takes. verify_db.js now does it as the student.
--
-- The fix is to let the trigger write the history the client is forbidden to
-- write, which is what the trigger is for. Ownership is not weakened: the row
-- is built from the application's own user_id, and the table still has no
-- insert policy, so a direct write is refused exactly as before.
create or replace function public.record_application_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.application_status_history(application_id, user_id, from_status, to_status)
      values (new.id, new.user_id, null, new.status);
    if new.status <> 'saved' and new.applied_at is null then
      update public.job_applications set applied_at = now() where id = new.id;
    end if;
  elsif new.status is distinct from old.status then
    if not public.is_valid_status_transition(old.status, new.status) then
      raise exception 'cannot move an application from % to %', old.status, new.status
        using errcode = 'check_violation';
    end if;
    insert into public.application_status_history(application_id, user_id, from_status, to_status)
      values (new.id, new.user_id, old.status, new.status);
  end if;
  return null;
end $$;

-- A trigger function is called by the trigger, never by a client, so nobody
-- needs EXECUTE on it.
revoke all on function public.record_application_status() from public, anon, authenticated;
