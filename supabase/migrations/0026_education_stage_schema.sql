-- Onboarding now branches on where a student is in their education, so the
-- profile has to carry that, and the questions that follow differ enough to
-- need somewhere to live.

-- ------------------------------------------------------------- countries
-- The app was Bangladesh-only, with the +880 prefix hard-coded in the form.
-- Country comes first now and the dial code follows from it, so a student
-- abroad is not asked to lie about their phone number.
create table public.countries (
  id         uuid primary key default gen_random_uuid(),
  iso2       text not null unique,
  name       text not null unique,
  dial_code  text not null,
  -- Bangladesh sorts first because that is who the app is for; the rest are
  -- there so nobody is turned away by a form.
  sort_order int not null default 100
);
alter table public.countries enable row level security;
alter table public.countries force row level security;
create policy countries_select_all on public.countries
  for select to authenticated using (true);

insert into public.countries (iso2, name, dial_code, sort_order) values
  ('BD','Bangladesh','+880',1),
  ('IN','India','+91',2),
  ('PK','Pakistan','+92',3),
  ('NP','Nepal','+977',4),
  ('LK','Sri Lanka','+94',5),
  ('BT','Bhutan','+975',6),
  ('MV','Maldives','+960',7),
  ('MY','Malaysia','+60',10),
  ('SG','Singapore','+65',11),
  ('AE','United Arab Emirates','+971',12),
  ('SA','Saudi Arabia','+966',13),
  ('QA','Qatar','+974',14),
  ('GB','United Kingdom','+44',20),
  ('US','United States','+1',21),
  ('CA','Canada','+1',22),
  ('AU','Australia','+61',23),
  ('DE','Germany','+49',24),
  ('JP','Japan','+81',25),
  ('KR','South Korea','+82',26),
  ('CN','China','+86',27),
  ('TR','Türkiye','+90',28),
  ('EG','Egypt','+20',29),
  ('Other','Other','+',999)
on conflict (iso2) do nothing;

alter table public.cities add column if not exists country_id uuid references public.countries(id) on delete set null;
create index if not exists cities_country_idx on public.cities(country_id);

-- Every city already seeded is Bangladeshi.
update public.cities set country_id = (select id from public.countries where iso2 = 'BD')
  where country_id is null;

-- --------------------------------------------------------------- profile
alter table public.profiles add column if not exists country_id uuid references public.countries(id) on delete set null;
alter table public.profiles add column if not exists education_stage education_stage;
-- What a school student wants to study next, and why they care. Both are the
-- student's own words, so both are free text.
alter table public.profiles add column if not exists intended_field text;
alter table public.profiles add column if not exists passion text;
create index if not exists profiles_country_idx on public.profiles(country_id);

-- The mode now follows the stage first and the year only within a degree.
create or replace function public.stage_to_mode(
  p_stage education_stage,
  p_year int,
  p_years_total int
)
returns year_mode
language sql
immutable
as $$
  select case
    -- Primary students are told plainly that Tack is not for them yet, so
    -- this only exists so the column is never null.
    when p_stage in ('primary', 'high_school') then 'school'::year_mode
    when p_stage = 'graduated' then 'graduate'::year_mode
    else public.year_to_mode(p_year, p_years_total)
  end
$$;

-- The generated column has to be rebuilt to use it, and the cohort view sits
-- on top of it, so both come down and go back up.
drop view if exists public.cohort_benchmarks;
drop materialized view if exists public.cohort_averages;

alter table public.profiles drop column mode;
alter table public.profiles add column mode year_mode
  generated always as (public.stage_to_mode(education_stage, year_of_study, years_total)) stored;

create materialized view public.cohort_averages as
  select p.year_of_study,
         p.mode,
         round(avg(r.total))::int as avg_total,
         count(*)::int            as cohort_size
  from public.profiles p
  join lateral (
    select total from public.readiness_scores
      where user_id = p.id order by computed_at desc limit 1
  ) r on true
  where p.deleted_at is null and p.mode is not null
  group by p.year_of_study, p.mode;
create unique index cohort_averages_key on public.cohort_averages(year_of_study, mode);

create view public.cohort_benchmarks
  with (security_invoker = false) as
  select year_of_study, mode, avg_total, cohort_size
    from public.cohort_averages
    where cohort_size >= 5;
grant select on public.cohort_benchmarks to authenticated;
revoke all on public.cohort_averages from anon, authenticated;

-- ------------------------------------------------------------- education
-- The same table now holds a school as well as a university.
alter table public.education add column if not exists stage education_stage;
alter table public.education add column if not exists institution_name text;
-- "Class 10", "HSC first year" — a label rather than a number, because the
-- naming differs between boards and countries.
alter table public.education add column if not exists class_level text;
-- "4.75 of 5", "A", "82%". Grading differs enough that a number would lie.
alter table public.education add column if not exists current_grade text;

-- ------------------------------------------------- subjects, courses, hobbies
-- One table rather than two. A school student's favourite subject and an
-- undergraduate's favourite course are the same shape, and keeping them
-- together means the profile screen and the score read one place.
create table public.student_interests (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  kind       interest_kind not null,
  label      text not null,
  -- Set when the student's answer matched something in the skill vocabulary,
  -- so a favourite subject can feed skills without being one.
  skill_id   uuid references public.skills(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (user_id, kind, label)
);
create index student_interests_user_idx on public.student_interests(user_id, kind);
create index student_interests_skill_idx on public.student_interests(skill_id);

alter table public.student_interests enable row level security;
alter table public.student_interests force row level security;

create policy student_interests_select_own on public.student_interests
  for select to authenticated using (user_id = (select auth.uid()));
create policy student_interests_insert_own on public.student_interests
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy student_interests_update_own on public.student_interests
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy student_interests_delete_own on public.student_interests
  for delete to authenticated using (user_id = (select auth.uid()));

create trigger student_interests_readiness_recompute
  after insert or update or delete on public.student_interests
  for each row execute function public.enqueue_readiness_recompute();
