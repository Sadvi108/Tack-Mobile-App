-- Anyone who finished onboarding before the stage step existed has no stage.
--
-- Their mode still resolves, because stage_to_mode falls through to the year
-- when the stage is null, but the profile screen has nothing to show and their
-- profile reads as incomplete for a question they were never asked.
--
-- A student who answered a year of study was at university by definition, so
-- that much can be inferred. Anyone who did not is left null rather than
-- guessed at, and will be asked.

update public.profiles
   set education_stage = 'bachelors'
 where education_stage is null
   and onboarding_completed_at is not null
   and year_of_study is not null;

-- Their education record should say the same thing.
update public.education e
   set stage = 'bachelors'
  from public.profiles p
 where p.id = e.user_id
   and e.stage is null
   and e.deleted_at is null
   and p.education_stage = 'bachelors';

-- And the institution name column added later should carry what was already
-- stored under the old column.
update public.education
   set institution_name = university_name
 where institution_name is null
   and university_name is not null;
