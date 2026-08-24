-- profiles keys on id, not user_id; the generic extractor missed it.
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

  insert into public.jobs_queue (user_id, type, payload, idempotency_key, run_after)
    values (uid, 'recompute_readiness',
            jsonb_build_object('user_id', uid, 'source', tg_table_name),
            'readiness:' || uid || ':' || to_char(now(), 'YYYYMMDDHH24MI'),
            now() + interval '20 seconds')
  on conflict (idempotency_key) do nothing;

  return null;
end $$;
