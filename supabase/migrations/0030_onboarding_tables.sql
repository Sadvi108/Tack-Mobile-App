-- Stage-typed education tables, rather than one JSONB blob.
--
-- "All students graduating in 2027" and "everyone whose favourite subject is
-- physics" are queries this product will run. Real columns keep them fast and
-- typed, and the flexible-schema argument does not apply because these fields
-- are known.

-- ------------------------------------------------------- profile additions
alter table public.profiles add column if not exists dial_code text;
alter table public.profiles add column if not exists birth_year int
  check (birth_year between 1940 and extract(year from now())::int);
alter table public.profiles add column if not exists age_band age_band;

-- ------------------------------------------------------ education_profiles
-- What every stage has in common.
create table public.education_profiles (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null unique references public.profiles(id) on delete cascade,
  stage             education_stage not null,
  institution_name  text,
  institution_id    uuid references public.universities(id) on delete set null,
  country_id        uuid references public.countries(id) on delete set null,
  start_year        int check (start_year between 1950 and 2100),
  expected_end_year int check (expected_end_year between 1950 and 2100),
  gpa               numeric(4,2) check (gpa >= 0),
  gpa_scale         numeric(4,2) not null default 4.00 check (gpa_scale > 0),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz
);
create index education_profiles_stage_idx on public.education_profiles(stage);
create index education_profiles_end_year_idx on public.education_profiles(expected_end_year);
create trigger education_profiles_updated_at before update on public.education_profiles
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------- high_school_profiles
create table public.high_school_profiles (
  id                   uuid primary key default gen_random_uuid(),
  education_profile_id uuid not null unique references public.education_profiles(id) on delete cascade,
  user_id              uuid not null unique references public.profiles(id) on delete cascade,
  -- A label, not a number: boards and countries name these differently.
  current_class        text,
  curriculum           curriculum,
  intended_field_id    uuid,
  -- "Not sure yet" is a first-class answer here, not a null.
  field_confidence     field_confidence not null default 'unsure',
  ten_year_note        text check (char_length(ten_year_note) <= 200),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);
create trigger high_school_profiles_updated_at before update on public.high_school_profiles
  for each row execute function public.set_updated_at();

-- ----------------------------------------------------- university_profiles
create table public.university_profiles (
  id                   uuid primary key default gen_random_uuid(),
  education_profile_id uuid not null unique references public.education_profiles(id) on delete cascade,
  user_id              uuid not null unique references public.profiles(id) on delete cascade,
  degree               text,
  major                text,
  -- The single most important field in the flow: it drives the app's mode.
  year_of_study        int check (year_of_study between 1 and 8),
  years_total          int check (years_total between 2 and 8),
  graduation_month     int check (graduation_month between 1 and 12),
  graduation_year      int check (graduation_year between 1950 and 2100),
  current_status       current_status,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);
create index university_profiles_graduation_idx
  on public.university_profiles(graduation_year, graduation_month);
create trigger university_profiles_updated_at before update on public.university_profiles
  for each row execute function public.set_updated_at();

-- ------------------------------------------------------- career_preferences
create table public.career_preferences (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null unique references public.profiles(id) on delete cascade,
  target_role     text,
  target_industry text[] not null default '{}',
  -- Mirrors field_confidence: not knowing is an answer.
  confidence      field_confidence not null default 'unsure',
  -- Ranked, most important first: money, stability, creativity, and so on.
  values_ranked   text[] not null default '{}',
  ten_year_note   text check (char_length(ten_year_note) <= 200),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create trigger career_preferences_updated_at before update on public.career_preferences
  for each row execute function public.set_updated_at();
