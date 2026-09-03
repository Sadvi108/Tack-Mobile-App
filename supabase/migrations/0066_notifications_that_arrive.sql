-- Notifications that actually reach somebody.
--
-- `public.notifications` has existed since 0009 and the app has a screen that
-- reads it, a repository, an unread badge and a route for each type. Nothing
-- has ever written a row into it. The inbox is not quiet — it is empty, and
-- always has been.
--
-- This makes it work, and puts push on the same rail so the two can never
-- disagree. Everything goes through one function: `notify()` writes the in-app
-- row *and* enqueues the push in the same transaction. A caller that wrote the
-- row directly would produce a notification the phone never announced; a
-- caller that sent a push directly would announce something the inbox cannot
-- show when the student opens the app.
--
-- No new scheduling machinery. jobs_queue already has `run_after` and a unique
-- `idempotency_key`, and the worker already drains it every two minutes, so a
-- digest that must arrive at a civil hour is an ordinary job with a later
-- run_after — and one that must arrive once a day is an idempotency key with
-- the date in it.

-- ------------------------------------------------------------ device tokens
--
-- Keyed on the token, not on (user, token). A token identifies one install of
-- the app on one phone, and it outlives the account: reinstalling, or logging
-- in as somebody else on a shared handset, hands the same token to a different
-- student. Making the token the primary key means the newest owner wins on
-- conflict, which is exactly right — the alternative sends the new student's
-- reminders to the previous one's notification tray.
create table if not exists public.device_tokens (
  token        text primary key,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  platform     text not null check (platform in ('android', 'ios')),
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

create index if not exists device_tokens_user_idx
  on public.device_tokens(user_id);

alter table public.device_tokens enable row level security;
alter table public.device_tokens force row level security;

drop policy if exists device_tokens_own on public.device_tokens;
create policy device_tokens_own on public.device_tokens
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

comment on table public.device_tokens is
  'One row per install. The token is the key because it moves between accounts '
  'when a phone is shared or the app reinstalled; the newest owner wins.';

-- --------------------------------------------------------------- notify()
--
-- The only way a notification is created. Internal: never granted to
-- authenticated, because a student who could call it could put a message in
-- somebody else's inbox.
--
-- p_dedupe_key makes the whole thing idempotent. Passing one twice writes one
-- notification and enqueues one push, which is what stops a retried job or a
-- re-run of the nightly sweep from telling somebody the same thing twice.
create or replace function public.notify(
  p_user_id    uuid,
  p_type       text,
  p_title      text,
  p_body       text default null,
  p_payload    jsonb default '{}'::jsonb,
  p_dedupe_key text default null,
  p_send_after timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id  uuid;
  v_key text := coalesce(p_dedupe_key,
                         p_type || ':' || p_user_id || ':' || gen_random_uuid());
begin
  -- The queue's unique idempotency_key is the lock. Claim it first: if this
  -- conflicts, the notification has already been made and there is nothing to
  -- do. Doing it in this order means the in-app row and the push are decided
  -- together rather than one slipping through on a retry.
  insert into public.jobs_queue (user_id, type, payload, idempotency_key, run_after)
  values (
    p_user_id,
    'send_push',
    jsonb_build_object('title', p_title, 'body', p_body, 'type', p_type)
      || coalesce(p_payload, '{}'::jsonb),
    'push:' || v_key,
    greatest(p_send_after, now())
  )
  on conflict (idempotency_key) do nothing;

  if not found then
    return null;
  end if;

  insert into public.notifications (user_id, type, title, body, payload)
  values (p_user_id, p_type, p_title, p_body, coalesce(p_payload, '{}'::jsonb))
  returning id into v_id;

  return v_id;
end $$;

comment on function public.notify(uuid, text, text, text, jsonb, text, timestamptz) is
  'The one way a notification is made: writes the in-app row and enqueues the '
  'push together, deduplicated on p_dedupe_key.';

-- ------------------------------------------------------------- the digest
--
-- One notification a day, at a civil hour, or none at all.
--
-- Deliberately not one per event. A careers app that pings a student for every
-- opening and every due step is uninstalled in week one, and the thing being
-- tested in a beta is whether the reminders help — which cannot be measured
-- through the noise of too many of them.
--
-- Says nothing when there is nothing to say. A digest that arrives every day
-- regardless teaches people to ignore it.
create or replace function public.enqueue_daily_digest()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  r         record;
  v_today   date := public.tack_today();
  v_sent    int := 0;
  v_title   text;
  v_body    text;
  -- 09:00 in Dhaka, the morning after this runs. The nightly sweep fires at
  -- 00:20 Dhaka; nobody wants a careers reminder then.
  v_when    timestamptz := (v_today + 1)::timestamp
                           at time zone 'Asia/Dhaka' + interval '9 hours';
begin
  for r in
    select p.id as user_id,
           -- Steps that are late, and steps due in the next two days. Two
           -- rather than one so a digest is not the first the student hears
           -- of a deadline that is already tomorrow morning.
           count(*) filter (
             where t.due_date < v_today) as overdue,
           count(*) filter (
             where t.due_date between v_today and v_today + 1) as due_soon
      from public.profiles p
      join public.roadmap_tasks t on t.user_id = p.id
      join public.roadmap_milestones m on m.id = t.milestone_id
      join public.roadmaps rm on rm.id = m.roadmap_id and rm.deleted_at is null
     where p.onboarding_completed_at is not null
       and t.deleted_at is null
       and not t.is_done
       and t.due_date is not null
       and t.due_date <= v_today + 1
     group by p.id
  loop
    if r.overdue = 0 and r.due_soon = 0 then
      continue;
    end if;

    if r.overdue > 0 and r.due_soon > 0 then
      v_title := r.overdue || ' late, ' || r.due_soon || ' coming up';
      v_body  := 'Open your roadmap and move a date, or tick one off — '
                 || 'either is fine.';
    elsif r.overdue > 0 then
      v_title := case when r.overdue = 1
                      then 'One step is late'
                      else r.overdue || ' steps are late' end;
      v_body  := 'Nothing is lost. Move the date or tick it off.';
    else
      v_title := case when r.due_soon = 1
                      then 'One step is due soon'
                      else r.due_soon || ' steps are due soon' end;
      v_body  := 'A good day to get one out of the way.';
    end if;

    -- The date in the key is the cap: one digest per student per day, whatever
    -- else runs or retries.
    perform public.notify(
      r.user_id,
      'step_due',
      v_title,
      v_body,
      jsonb_build_object('overdue', r.overdue, 'due_soon', r.due_soon),
      'digest:' || r.user_id || ':' || v_today,
      v_when
    );
    v_sent := v_sent + 1;
  end loop;

  return v_sent;
end $$;

comment on function public.enqueue_daily_digest() is
  'At most one roadmap digest per student per day, delivered 09:00 Dhaka. '
  'Returns how many were enqueued.';

-- --------------------------------------------------- hang it off the nightly
--
-- nightly_maintenance already runs at 00:20 Dhaka and is where the recurring
-- work lives. Appending rather than adding a fourth cron job keeps one place
-- to look when something scheduled did not happen.
create or replace function public.nightly_maintenance()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.documents
    where deleted_at is not null and purge_after is not null and purge_after < now();

  delete from public.jobs_queue
    where status in ('done', 'dead') and updated_at < now() - interval '7 days';

  delete from public.analytics_events where occurred_at < now() - interval '90 days';
  delete from public.error_reports    where occurred_at < now() - interval '90 days';

  -- A token the app has not refreshed in two months belongs to an install that
  -- is gone. Pushing to it wastes a job and, on FCM, earns an UNREGISTERED.
  delete from public.device_tokens where last_seen_at < now() - interval '60 days';

  perform public.reap_stuck_jobs();
  perform public.sweep_stuck_documents();
  perform public.enqueue_daily_digest();
end $$;

-- --------------------------------------------------------------- registration
--
-- The one thing the client does call. Upsert on the token so a reinstall or a
-- second account on the same phone reassigns it rather than leaving the old
-- owner receiving somebody else's reminders.
create or replace function public.register_device(p_token text, p_platform text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;
  if coalesce(trim(p_token), '') = '' then
    raise exception 'a device token is required' using errcode = 'check_violation';
  end if;
  if p_platform not in ('android', 'ios') then
    raise exception 'unknown platform %', p_platform using errcode = 'check_violation';
  end if;

  insert into public.device_tokens (token, user_id, platform, last_seen_at)
  values (trim(p_token), v_uid, p_platform, now())
  on conflict (token) do update
    set user_id      = excluded.user_id,
        platform     = excluded.platform,
        last_seen_at = now();
end $$;

comment on function public.register_device(text, text) is
  'Client-callable. Records this install against the signed-in student.';

grant execute on function public.register_device(text, text) to authenticated;

-- notify(), enqueue_daily_digest() and nightly_maintenance() are deliberately
-- not granted: 0065's event trigger has already taken PUBLIC and anon off
-- them, and a student must not be able to put a message in another inbox.

-- ------------------------------------------------------------------- checked
do $$
declare
  v_user uuid;
  v_a uuid;
  v_b uuid;
begin
  select id into v_user from public.profiles limit 1;
  if v_user is null then
    raise notice 'no profiles yet; skipping the dedupe check';
    return;
  end if;

  v_a := public.notify(v_user, 'general', 'probe', null, '{}'::jsonb, 'probe:0066');
  v_b := public.notify(v_user, 'general', 'probe', null, '{}'::jsonb, 'probe:0066');

  if v_a is null then
    raise exception 'notify() did not create the first notification';
  end if;
  if v_b is not null then
    raise exception 'notify() is not idempotent: the same dedupe key wrote twice';
  end if;

  delete from public.notifications where id = v_a;
  delete from public.jobs_queue where idempotency_key = 'push:probe:0066';
end $$;
