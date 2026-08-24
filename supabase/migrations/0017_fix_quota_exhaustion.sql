-- The previous version froze count at the limit on conflict, so the call that
-- exhausted the quota and every call after it both returned 0 — the caller
-- could not tell "you just used your last one" from "you have none left".
-- Now the counter always increments, and an over-limit call is clamped back
-- and reported as -1.
create or replace function public.consume_quota(p_user_id uuid, p_bucket text, p_limit int)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  today date := (now() at time zone 'utc')::date;
  n int;
begin
  insert into public.rate_limits(user_id, bucket, window_start, count)
    values (p_user_id, p_bucket, today, 1)
  on conflict (user_id, bucket, window_start) do update
    set count = public.rate_limits.count + 1
  returning count into n;

  if n > p_limit then
    update public.rate_limits set count = p_limit
      where user_id = p_user_id and bucket = p_bucket and window_start = today;
    return -1;
  end if;

  return p_limit - n;
end $$;
