-- Give an action back when the model never answered.
--
-- consume_quota counts before the provider is called, which is the right order
-- — counting afterwards lets a student fire twenty requests in parallel and
-- pay for three. But it means a provider timeout charges somebody for a reply
-- they never received, and with an allowance of three a day that is a third of
-- their coaching gone to a network error.
--
-- Never drops below zero, and never refunds a day that has already rolled
-- over: a failure at 23:59 does not hand out a free action tomorrow.
create or replace function public.refund_quota(p_user_id uuid, p_bucket text)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  today date := (now() at time zone 'utc')::date;
  n int;
begin
  update public.rate_limits
     set count = greatest(0, count - 1)
   where user_id = p_user_id
     and bucket = p_bucket
     and window_start = today
  returning count into n;

  return coalesce(n, 0);
end $$;

-- Service role only. A student who could call this would have no limit at all.
revoke all on function public.refund_quota(uuid, text) from public, anon, authenticated;
