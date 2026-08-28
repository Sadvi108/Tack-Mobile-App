-- New enum values, alone in their own migration.
--
-- Postgres will add a value to an enum inside a transaction but will not let
-- the same transaction use it, so anything that references 'school' or
-- 'graduate' has to wait for the next file.

-- Where a student is in their education, which is now the first thing the app
-- asks and the thing that decides what it asks next.
do $$ begin
  create type education_stage as enum ('primary', 'high_school', 'bachelors', 'graduated');
exception when duplicate_object then null; end $$;

-- Two modes beyond the four university years:
--   school    — still at school, choosing what to study rather than where to work
--   graduate  — finished, and looking for the first job now
alter type year_mode add value if not exists 'school' before 'explore';
alter type year_mode add value if not exists 'graduate' after 'launch';

do $$ begin
  create type interest_kind as enum (
    'favourite_subject', 'hobby', 'interest', 'course', 'favourite_course'
  );
exception when duplicate_object then null; end $$;
