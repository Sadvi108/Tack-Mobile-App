-- Product analytics and crash reports, kept inside the same project as
-- everything else.
--
-- Tack previously sent events to PostHog and was configured for Sentry. Both
-- are gone: no student data leaves this database now. That costs the query
-- tooling a hosted product gives you, and buys one place to look, one
-- jurisdiction, and one thing to delete when a student closes their account.

create table public.analytics_events (
  id         bigserial primary key,
  user_id    uuid references public.profiles(id) on delete cascade,
  name       text not null,
  -- Never contains a name, email, phone, CV text or job description. The
  -- client is written to send counts and identifiers only.
  properties jsonb not null default '{}'::jsonb,
  session_id text,
  app_version text,
  platform   text,
  occurred_at timestamptz not null default now()
);
create index analytics_events_user_time_idx on public.analytics_events(user_id, occurred_at desc);
create index analytics_events_name_time_idx on public.analytics_events(name, occurred_at desc);

create table public.error_reports (
  id          bigserial primary key,
  user_id     uuid references public.profiles(id) on delete set null,
  message     text not null,
  stack       text,
  context     jsonb not null default '{}'::jsonb,
  app_version text,
  platform    text,
  occurred_at timestamptz not null default now()
);
create index error_reports_time_idx on public.error_reports(occurred_at desc);

alter table public.analytics_events enable row level security;
alter table public.analytics_events force row level security;
alter table public.error_reports enable row level security;
alter table public.error_reports force row level security;

-- A student may add their own events and read their own history back. Nobody
-- can read anyone else's, and nothing here is updatable or deletable by a
-- client — an event log you can edit is not a log.
create policy analytics_events_insert_own on public.analytics_events
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy analytics_events_select_own on public.analytics_events
  for select to authenticated using (user_id = (select auth.uid()));

create policy error_reports_insert_own on public.error_reports
  for insert to authenticated with check (user_id = (select auth.uid()) or user_id is null);

-- Ninety days is long enough to answer a product question and short enough
-- that this table never becomes the biggest thing in the database.
create or replace function public.nightly_maintenance()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  refresh materialized view concurrently public.cohort_averages;

  delete from public.documents
    where deleted_at is not null and purge_after is not null and purge_after < now();

  delete from public.jobs_queue
    where status in ('done', 'dead') and updated_at < now() - interval '7 days';

  delete from public.analytics_events where occurred_at < now() - interval '90 days';
  delete from public.error_reports    where occurred_at < now() - interval '90 days';
end $$;

revoke all on function public.nightly_maintenance() from anon, authenticated;
