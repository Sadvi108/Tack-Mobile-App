-- Enums for the rebuilt onboarding intake, alone in their own migration
-- because Postgres will not let the same transaction use a value it just
-- added to an existing type.

-- The architecture doc names the school mode "discover", which says what the
-- student is doing rather than where they are.
alter type year_mode rename value 'school' to 'discover';

do $$ begin
  create type age_band as enum ('under_13', '13_15', '16_18', '19_22', '23_26', '27_plus');
exception when duplicate_object then null; end $$;

do $$ begin
  create type curriculum as enum (
    'national', 'english_medium', 'o_a_level', 'ib', 'madrasah', 'other'
  );
exception when duplicate_object then null; end $$;

-- How settled a student is on a direction. "Unsure" is a real answer, not a
-- missing one, and the app is built to say so.
do $$ begin
  create type field_confidence as enum ('sure', 'leaning', 'unsure');
exception when duplicate_object then null; end $$;

do $$ begin
  create type current_status as enum (
    'job_hunting', 'employed', 'freelancing', 'studying_further'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type subject_sentiment as enum ('loves', 'finds_hard');
exception when duplicate_object then null; end $$;

do $$ begin
  create type entry_source as enum ('preset', 'custom');
exception when duplicate_object then null; end $$;

do $$ begin
  create type experience_type as enum ('internship', 'job', 'freelance', 'volunteer');
exception when duplicate_object then null; end $$;

do $$ begin
  create type onboarding_branch as enum ('primary', 'high_school', 'bachelors', 'graduated');
exception when duplicate_object then null; end $$;
