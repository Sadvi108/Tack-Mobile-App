-- ------------------------------------------------------- reference tables
create table public.subjects (
  id         uuid primary key default gen_random_uuid(),
  slug       text not null unique,
  name       text not null,
  category   text not null default 'general',
  sort_order int not null default 100,
  is_active  boolean not null default true
);
create index subjects_category_idx on public.subjects(category) where is_active;

create table public.interests (
  id         uuid primary key default gen_random_uuid(),
  slug       text not null unique,
  name       text not null,
  category   text not null default 'general',
  sort_order int not null default 100,
  is_active  boolean not null default true
);

create table public.career_fields (
  id         uuid primary key default gen_random_uuid(),
  slug       text not null unique,
  name       text not null,
  -- Which school subjects usually lead here, so a student who likes physics
  -- can be shown fields that follow from it.
  subjects   text[] not null default '{}',
  sort_order int not null default 100,
  is_active  boolean not null default true
);

alter table public.high_school_profiles
  add constraint high_school_profiles_field_fk
  foreign key (intended_field_id) references public.career_fields(id) on delete set null;

-- ------------------------------------------------ what a student likes
create table public.user_subjects (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete cascade,
  -- Subjects a student finds hard are as useful as the ones they love; they
  -- are what a gap analysis reads later.
  sentiment  subject_sentiment not null default 'loves',
  created_at timestamptz not null default now(),
  unique (user_id, subject_id, sentiment)
);
create index user_subjects_user_idx on public.user_subjects(user_id, sentiment);
create index user_subjects_subject_idx on public.user_subjects(subject_id);

create table public.user_interests (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  interest_id uuid references public.interests(id) on delete cascade,
  -- Anything typed rather than picked, so the escape hatch is never lossy.
  label       text,
  source      entry_source not null default 'preset',
  created_at  timestamptz not null default now(),
  constraint user_interests_has_value check (interest_id is not null or label is not null)
);
create index user_interests_user_idx on public.user_interests(user_id);
create index user_interests_interest_idx on public.user_interests(interest_id);
create unique index user_interests_unique_preset
  on public.user_interests(user_id, interest_id) where interest_id is not null;
create unique index user_interests_unique_custom
  on public.user_interests(user_id, label) where label is not null;

-- ------------------------------------------------------------- drafts
-- Answers live here until the student finishes.
--
-- Partial answers never touch the real tables, so somebody who abandons at
-- step three leaves no half-built profile for the readiness score to grade.
-- Resuming is then trivial, and the drop-off point is visible.
create table public.onboarding_drafts (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null unique references public.profiles(id) on delete cascade,
  current_step text not null default 'basics',
  branch       onboarding_branch,
  answers      jsonb not null default '{}'::jsonb,
  started_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  completed_at timestamptz
);
create index onboarding_drafts_step_idx on public.onboarding_drafts(current_step)
  where completed_at is null;
create trigger onboarding_drafts_updated_at before update on public.onboarding_drafts
  for each row execute function public.set_updated_at();

-- ------------------------------------------------------------ waitlist
-- Primary school students create no account at all.
--
-- Honest product behaviour, and it avoids holding personal data on children
-- who cannot meaningfully consent to it. An email and nothing else.
create table public.waitlist (
  id              uuid primary key default gen_random_uuid(),
  email           text not null unique,
  stage_requested education_stage,
  country_id      uuid references public.countries(id) on delete set null,
  created_at      timestamptz not null default now()
);

-- ---------------------------------------------------------------- RLS
alter table public.subjects enable row level security;
alter table public.interests enable row level security;
alter table public.career_fields enable row level security;
alter table public.education_profiles enable row level security;
alter table public.high_school_profiles enable row level security;
alter table public.university_profiles enable row level security;
alter table public.career_preferences enable row level security;
alter table public.user_subjects enable row level security;
alter table public.user_interests enable row level security;
alter table public.onboarding_drafts enable row level security;
alter table public.waitlist enable row level security;

alter table public.subjects force row level security;
alter table public.interests force row level security;
alter table public.career_fields force row level security;
alter table public.education_profiles force row level security;
alter table public.high_school_profiles force row level security;
alter table public.university_profiles force row level security;
alter table public.career_preferences force row level security;
alter table public.user_subjects force row level security;
alter table public.user_interests force row level security;
alter table public.onboarding_drafts force row level security;
alter table public.waitlist force row level security;

do $$
declare t text;
begin
  foreach t in array array['subjects', 'interests', 'career_fields'] loop
    execute format(
      'create policy %I on public.%I for select to authenticated using (true)',
      t || '_select_all', t);
  end loop;

  foreach t in array array[
    'education_profiles', 'high_school_profiles', 'university_profiles',
    'career_preferences', 'user_subjects', 'user_interests', 'onboarding_drafts'
  ] loop
    execute format($f$create policy %I on public.%I for select to authenticated
      using (user_id = (select auth.uid()))$f$, t || '_select_own', t);
    execute format($f$create policy %I on public.%I for insert to authenticated
      with check (user_id = (select auth.uid()))$f$, t || '_insert_own', t);
    execute format($f$create policy %I on public.%I for update to authenticated
      using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))$f$,
      t || '_update_own', t);
    execute format($f$create policy %I on public.%I for delete to authenticated
      using (user_id = (select auth.uid()))$f$, t || '_delete_own', t);
  end loop;
end $$;

-- The waitlist is the one thing a signed-out visitor may write, and only
-- write: nobody may read the list back.
create policy waitlist_insert_anon on public.waitlist
  for insert to anon, authenticated with check (true);
grant insert on public.waitlist to anon, authenticated;
