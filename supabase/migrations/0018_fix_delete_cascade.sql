-- Deleting an account cascades through profiles into every owned table. Each
-- of those deletes fired the recompute trigger, which tried to insert a
-- jobs_queue row for a user that no longer exists — so the delete always
-- failed with a foreign key violation and no account could be removed.
-- Enqueue only when the profile is still there.
create or replace function public.enqueue_readiness_recompute()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  rec jsonb := to_jsonb(coalesce(new, old));
  uid uuid;
begin
  if tg_table_name = 'profiles' then
    uid := (rec->>'id')::uuid;
  else
    uid := (rec->>'user_id')::uuid;
  end if;
  if uid is null then return null; end if;

  -- The profile is already gone during a cascading account delete.
  if not exists (select 1 from public.profiles where id = uid) then
    return null;
  end if;

  insert into public.jobs_queue (user_id, type, payload, idempotency_key, run_after)
    values (uid, 'recompute_readiness',
            jsonb_build_object('user_id', uid, 'source', tg_table_name),
            'readiness:' || uid || ':' || to_char(now(), 'YYYYMMDDHH24MI'),
            now() + interval '20 seconds')
  on conflict (idempotency_key) do nothing;

  return null;
end $$;

-- The recompute trigger on profiles must not fire while the row is being
-- deleted either; restrict it to insert and update.
drop trigger if exists profiles_readiness_recompute on public.profiles;
create trigger profiles_readiness_recompute
  after insert or update on public.profiles
  for each row execute function public.enqueue_readiness_recompute();
