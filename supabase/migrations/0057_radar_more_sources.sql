-- Four more boards, and the enum that has to know about them first.
--
-- The providers were added in TypeScript and the upsert was rejected by
-- Postgres on every row: `invalid input value for enum radar_source:
-- "remotive"`. The function answered 200 with a cached feed, so from the
-- outside it looked like the new boards simply had nothing to offer.
--
-- Why these four:
--   remotive   every listing is remote, which for a student in Dhaka is the
--              category that is actually reachable. Carries a description.
--   arbeitnow  the only free board with both an employment type and a full
--              description, and where internships appear in any number.
--   themuse    publishes an explicit level, so "Internship" is stated rather
--              than guessed at from a job title.
--   jobicy     remote, reserved here so adding it later is not another
--              migration.
--
-- None of them need an API key.
alter type radar_source add value if not exists 'remotive';
alter type radar_source add value if not exists 'arbeitnow';
alter type radar_source add value if not exists 'themuse';
alter type radar_source add value if not exists 'jobicy';
