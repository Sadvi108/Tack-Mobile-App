-- One definition of the daily allowance, and a bigger one.
--
-- The number 3 was written in four places that all had to agree:
--
--   _shared/ai/gateway.ts   DAILY_AI_QUOTA = 3   (passed in as p_limit)
--   coach_allowance()       'limit', 3           (hardcoded)
--   coach_screen.dart:176   'of 3 coach questions left today'
--   coach_screen.dart:185   'of 3'
--
-- Two of those fail silently when they drift. The SQL would report an
-- allowance the server does not enforce, and the app would print a number that
-- is simply wrong — neither raises anything, they just disagree, and the
-- student is the one who finds out.
--
-- So the limit moves into the database and the callers stop carrying it.
-- `consume_quota` and `quota_remaining` keep their p_limit argument for the
-- moment — the deployed functions still pass it — but it is now *ignored* in
-- favour of ai_daily_limit(), which means the server cannot disagree with the
-- database even before the TypeScript is redeployed.
--
-- Raised from 3 to 10. Most of what those three were being spent on is
-- arithmetic that is about to stop costing anything: a CV check, a job
-- description match and interview answer feedback all become free and
-- unlimited. What is left that genuinely needs language is roughly six calls
-- on a heavy day — one CV read, one job description, a couple of coach
-- questions, a couple of answers read properly. Ten is headroom rather than a
-- new ceiling.

create or replace function public.ai_daily_limit()
returns int
language sql
immutable
set search_path = public
as $$
  select 10;
$$;

comment on function public.ai_daily_limit() is
  'The only definition of the daily AI allowance. Everything else reads it: '
  'consume_quota, quota_remaining, coach_allowance, and the app through '
  'coach_allowance. Change it here and nowhere else.';

grant execute on function public.ai_daily_limit() to authenticated;

-- ---------------------------------------------------------------- enforcement
--
-- p_limit stays in the signature so the currently deployed Edge Functions keep
-- working unchanged, and is deliberately ignored. A caller that passes the
-- wrong number can no longer grant itself a different allowance.
create or replace function public.consume_quota(p_user_id uuid, p_bucket text, p_limit int)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  today date := (now() at time zone 'utc')::date;
  v_limit int := public.ai_daily_limit();
  n int;
begin
  insert into public.rate_limits(user_id, bucket, window_start, count)
    values (p_user_id, p_bucket, today, 1)
  on conflict (user_id, bucket, window_start) do update
    set count = public.rate_limits.count + 1
  returning count into n;

  if n > v_limit then
    update public.rate_limits set count = v_limit
      where user_id = p_user_id and bucket = p_bucket and window_start = today;
    return -1;
  end if;

  -- Returns what is LEFT, not what was used. Reading it the other way made the
  -- coach counter climb instead of fall; see 0054.
  return v_limit - n;
end $$;

create or replace function public.quota_remaining(p_user_id uuid, p_bucket text, p_limit int)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select greatest(0, public.ai_daily_limit() - coalesce(
    (select count from public.rate_limits
      where user_id = p_user_id and bucket = p_bucket
        and window_start = (now() at time zone 'utc')::date), 0))
$$;

-- ------------------------------------------------------------- what is shown
--
-- Renamed in spirit rather than in name: the allowance was never the coach's,
-- it is shared with CV scoring, job-description analysis and interview
-- feedback. The app reads `limit` from here now instead of printing 3.
create or replace function public.coach_allowance()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'used', coalesce((
      select count from public.rate_limits
       where user_id = (select auth.uid()) and bucket = 'ai'
         and window_start = (now() at time zone 'utc')::date
    ), 0),
    'limit', public.ai_daily_limit()
  )
$$;

-- ------------------------------------------------------------------- checked
do $$
declare
  v_user  uuid;
  v_limit int := public.ai_daily_limit();
  v_left  int;
  v_shown int;
begin
  if v_limit <> 10 then
    raise exception 'ai_daily_limit() should be 10, got %', v_limit;
  end if;

  select id into v_user from public.profiles limit 1;
  if v_user is null then
    raise notice 'no profiles yet; skipping the enforcement check';
    return;
  end if;

  -- A caller passing the old 3 must not be able to hold the allowance down.
  -- This is the whole point of ignoring p_limit.
  delete from public.rate_limits
   where user_id = v_user and bucket = 'probe0070';

  v_left := public.consume_quota(v_user, 'probe0070', 3);
  if v_left <> v_limit - 1 then
    raise exception
      'consume_quota honoured the caller''s limit instead of the database: got %',
      v_left;
  end if;

  v_shown := public.quota_remaining(v_user, 'probe0070', 3);
  if v_shown <> v_limit - 1 then
    raise exception 'quota_remaining disagrees with consume_quota: % vs %',
      v_shown, v_left;
  end if;

  delete from public.rate_limits
   where user_id = v_user and bucket = 'probe0070';
end $$;
