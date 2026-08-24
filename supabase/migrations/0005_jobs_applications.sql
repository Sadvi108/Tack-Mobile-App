-- Companies are shared reference data; normalised_name collapses
-- "bKash Ltd." / "bkash limited" onto one row.
create table public.companies (
  id              uuid primary key default gen_random_uuid(),
  name            text not null,
  normalised_name text not null unique,
  website         text,
  location        text,
  created_at      timestamptz not null default now()
);
create index companies_name_trgm on public.companies using gin (name gin_trgm_ops);

create or replace function public.normalise_company_name(raw text)
returns text
language sql
immutable
as $$
  select nullif(
    regexp_replace(
      regexp_replace(lower(trim(raw)), '\s*(ltd\.?|limited|inc\.?|llc|plc|pvt\.?|private|company|co\.?)\s*$', '', 'g'),
      '[^a-z0-9]+', '', 'g'),
    '')
$$;

create or replace function public.upsert_company(raw_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  n text := public.normalise_company_name(raw_name);
  cid uuid;
begin
  if n is null then return null; end if;
  select id into cid from public.companies where normalised_name = n;
  if cid is null then
    insert into public.companies(name, normalised_name)
      values (trim(raw_name), n)
      on conflict (normalised_name) do update set name = public.companies.name
      returning id into cid;
  end if;
  return cid;
end $$;

-- A job row is created by the student (pasted or typed). is_public rows are
-- curated listings shown in the year-3 "live internships" panel.
create table public.jobs (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid references public.profiles(id) on delete cascade,
  company_id      uuid references public.companies(id) on delete set null,
  company_name    text,
  title           text not null,
  location        text,
  employment_type text,
  description     text,
  source_url      text,
  posted_at       date,
  closes_at       date,
  salary_min_bdt  int,
  salary_max_bdt  int,
  is_public       boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  constraint jobs_owner_or_public check (user_id is not null or is_public)
);
create index jobs_user_idx on public.jobs(user_id) where deleted_at is null;
create index jobs_public_closes_idx on public.jobs(closes_at) where is_public and deleted_at is null;
create trigger jobs_updated_at before update on public.jobs
  for each row execute function public.set_updated_at();

create table public.job_applications (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references public.profiles(id) on delete cascade,
  job_id           uuid not null references public.jobs(id) on delete cascade,
  status           application_status not null default 'saved',
  applied_at       timestamptz,
  next_action      text,
  next_action_date date,
  cv_document_id   uuid,
  notes            text,
  source           text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  unique (user_id, job_id)
);
create index job_applications_user_status_idx on public.job_applications(user_id, status) where deleted_at is null;
create index job_applications_next_action_idx on public.job_applications(user_id, next_action_date)
  where deleted_at is null and next_action_date is not null;
create trigger job_applications_updated_at before update on public.job_applications
  for each row execute function public.set_updated_at();

create table public.application_status_history (
  id             uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.job_applications(id) on delete cascade,
  user_id        uuid not null references public.profiles(id) on delete cascade,
  from_status    application_status,
  to_status      application_status not null,
  note           text,
  changed_at     timestamptz not null default now()
);
create index application_status_history_app_idx on public.application_status_history(application_id, changed_at desc);

-- The state machine. 'rejected' is reachable from anywhere; the rest move forward,
-- with one step back allowed so a mistyped status can be corrected.
create or replace function public.is_valid_status_transition(from_s application_status, to_s application_status)
returns boolean
language sql
immutable
as $$
  select case
    when from_s is null then to_s in ('saved','applied')
    when from_s = to_s then true
    when to_s = 'rejected' then true
    when from_s = 'saved'      then to_s in ('applied')
    when from_s = 'applied'    then to_s in ('assessment','interview','offer','saved')
    when from_s = 'assessment' then to_s in ('interview','offer','applied')
    when from_s = 'interview'  then to_s in ('offer','assessment')
    when from_s = 'offer'      then to_s in ('interview')
    when from_s = 'rejected'   then to_s in ('saved','applied','assessment','interview','offer')
    else false
  end
$$;

create or replace function public.record_application_status()
returns trigger
language plpgsql
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

create trigger job_applications_status_history
  after insert or update of status on public.job_applications
  for each row execute function public.record_application_status();
