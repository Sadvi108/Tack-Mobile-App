-- Reference tables for onboarding selects.
create table public.cities (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  division    text,
  sort_order  int not null default 100
);

create table public.universities (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  short_name  text,
  city_id     uuid references public.cities(id) on delete set null,
  is_active   boolean not null default true
);
create index universities_name_trgm on public.universities using gin (name gin_trgm_ops);

-- One row per authenticated user. id mirrors auth.users.id.
create table public.profiles (
  id                     uuid primary key references auth.users(id) on delete cascade,
  full_name              text,
  city_id                uuid references public.cities(id) on delete set null,
  phone                  text,
  avatar_url             text,
  year_of_study          int check (year_of_study between 1 and 8),
  years_total            int check (years_total between 2 and 8),
  expected_graduation    date,
  -- Derived, never set by the client. Drives which dashboard the app renders.
  mode                   year_mode generated always as (public.year_to_mode(year_of_study, years_total)) stored,
  target_role            text,
  target_industry        text[] not null default '{}',
  onboarding_step        int not null default 0,
  onboarding_completed_at timestamptz,
  locale                 text not null default 'en',
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  deleted_at             timestamptz
);
create trigger profiles_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();

create table public.education (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles(id) on delete cascade,
  university_id   uuid references public.universities(id) on delete set null,
  university_name text,
  degree          text,
  field_of_study  text,
  start_year      int,
  graduation_year int,
  cgpa            numeric(4,2) check (cgpa >= 0),
  cgpa_scale      numeric(4,2) not null default 4.00,
  is_current      boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz
);
create index education_user_idx on public.education(user_id) where deleted_at is null;
create trigger education_updated_at before update on public.education
  for each row execute function public.set_updated_at();

create table public.courses (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,
  semester     text not null,
  semester_order int not null default 0,
  code         text,
  title        text not null,
  grade        text,
  grade_points numeric(4,2),
  credits      numeric(4,2),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);
create index courses_user_semester_idx on public.courses(user_id, semester_order) where deleted_at is null;
create trigger courses_updated_at before update on public.courses
  for each row execute function public.set_updated_at();

create table public.activities (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,
  category     activity_category not null default 'other',
  title        text not null,
  organisation text,
  role         text,
  start_date   date,
  end_date     date,
  description  text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);
create index activities_user_idx on public.activities(user_id, category) where deleted_at is null;
create trigger activities_updated_at before update on public.activities
  for each row execute function public.set_updated_at();

-- Work / internship history, feeds the "experience" score component.
create table public.experiences (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,
  company_name text not null,
  title        text not null,
  employment_type text,
  location     text,
  start_date   date,
  end_date     date,
  is_current   boolean not null default false,
  description  text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);
create index experiences_user_idx on public.experiences(user_id) where deleted_at is null;
create trigger experiences_updated_at before update on public.experiences
  for each row execute function public.set_updated_at();

create table public.projects (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,
  title        text not null,
  summary      text,
  url          text,
  repo_url     text,
  started_on   date,
  completed_on date,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);
create index projects_user_idx on public.projects(user_id) where deleted_at is null;
create trigger projects_updated_at before update on public.projects
  for each row execute function public.set_updated_at();

create table public.certifications (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles(id) on delete cascade,
  title         text not null,
  issuer        text,
  issued_on     date,
  expires_on    date,
  credential_id text,
  credential_url text,
  document_id   uuid,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);
create index certifications_user_idx on public.certifications(user_id) where deleted_at is null;
create trigger certifications_updated_at before update on public.certifications
  for each row execute function public.set_updated_at();

create table public.portfolio_links (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  kind       text not null,
  url        text not null,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, kind)
);
