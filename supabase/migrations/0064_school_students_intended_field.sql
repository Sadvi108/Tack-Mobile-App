-- Every school student was losing their intended field, and a score point with it.
--
-- Two defects, one cause: write_onboarding was written against a shape the
-- onboarding flow does not produce.
--
--   1. `intended_field_slug` is a multiChip — a JSON *array*
--      (flow_config.dart:302). The function read it with `->>`, which on an
--      array yields the literal text `["engineering"]`. No career_fields.slug
--      is ever equal to that, so high_school_profiles.intended_field_id was
--      NULL for every school student who ever finished onboarding.
--
--   2. profiles.intended_field was written from a key called `intended_field`,
--      which no onboarding step sends and nothing else writes. So it was
--      always NULL — and readiness_ratios (0059:81) awards a profile
--      completeness point for `p.intended_field is not null`, but only to
--      school students. Every one of them silently lost one of eight points,
--      a penalty applied to exactly the segment that cannot understand why.
--
-- The second is the more expensive bug, because it is invisible: the field is
-- not shown anywhere, so nobody could see the thing whose absence was costing
-- them the point.
--
-- Both are fixed by resolving the answer once, in one place, rather than at
-- each site that happens to need it. The two helpers below take the answers
-- object and cope with either shape — an array from the current flow, or a
-- bare string from an older draft that a student may still have saved.
--
-- write_onboarding is otherwise reproduced unchanged from 0036. It is long,
-- and the two lines that differ were substituted mechanically and diffed
-- rather than retyped.

-- Accepts ["engineering"] or "engineering", and answers with the slug.
create or replace function public.onboarding_intended_field_slug(p_answers jsonb)
returns text
language sql
immutable
set search_path = public
as $$
  select nullif(
    case jsonb_typeof(p_answers->'intended_field_slug')
      when 'array'  then p_answers->'intended_field_slug'->>0
      when 'string' then p_answers->>'intended_field_slug'
      else null
    end, '');
$$;

comment on function public.onboarding_intended_field_slug(jsonb) is
  'The first chosen field slug, whether the answer is an array or a string.';

-- The field's display name, which is what profiles.intended_field holds and
-- what readiness_ratios tests for. Resolved through career_fields rather than
-- stored raw, so a renamed field does not leave stale text behind.
create or replace function public.onboarding_intended_field(p_answers jsonb)
returns text
language sql
stable
set search_path = public
as $$
  select coalesce(
    (select f.name from public.career_fields f
      where f.slug = public.onboarding_intended_field_slug(p_answers)),
    -- An older draft may carry the name directly.
    nullif(p_answers->>'intended_field', ''));
$$;

comment on function public.onboarding_intended_field(jsonb) is
  'The display name of the field a school student intends to study.';

create or replace function public.write_onboarding(p_answers jsonb)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_uid          uuid := auth.uid();
  v_stage        education_stage;
  v_education_id uuid;
  v_country_id   uuid;
  v_city_id      uuid;
  v_item         jsonb;
  v_label        text;
begin
  if v_uid is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;

  v_stage := (p_answers->>'stage')::education_stage;
  if v_stage is null then
    raise exception 'onboarding cannot finish without a stage'
      using errcode = 'check_violation';
  end if;

  -- A primary student never reaches this function; they go to the waitlist
  -- and no account is created at all.
  if v_stage = 'primary' then
    raise exception 'primary students do not create a profile'
      using errcode = 'check_violation';
  end if;

  v_country_id := nullif(p_answers->>'country_id', '')::uuid;
  v_city_id    := nullif(p_answers->>'city_id', '')::uuid;

  -- ------------------------------------------------------------ profile
  update public.profiles set
    full_name           = coalesce(nullif(p_answers->>'full_name', ''), full_name),
    country_id          = coalesce(v_country_id, country_id),
    city_id             = coalesce(v_city_id, city_id),
    phone               = nullif(p_answers->>'phone', ''),
    dial_code           = nullif(p_answers->>'dial_code', ''),
    birth_year          = nullif(p_answers->>'birth_year', '')::int,
    age_band            = nullif(p_answers->>'age_band', '')::age_band,
    education_stage     = v_stage,
    year_of_study       = nullif(p_answers->>'year_of_study', '')::int,
    years_total         = nullif(p_answers->>'years_total', '')::int,
    target_role         = nullif(p_answers->>'target_role', ''),
    intended_field      = public.onboarding_intended_field(p_answers),
    passion             = nullif(p_answers->>'ten_year_note', ''),
    target_industry     = coalesce(
      (select array_agg(value::text) from jsonb_array_elements_text(
        coalesce(p_answers->'target_industry', '[]'::jsonb)) as value), '{}'),
    expected_graduation = case
      when nullif(p_answers->>'graduation_year', '') is null then null
      else make_date(
        (p_answers->>'graduation_year')::int,
        coalesce(nullif(p_answers->>'graduation_month', '')::int, 6), 1)
    end,
    onboarding_step        = 99,
    onboarding_completed_at = coalesce(onboarding_completed_at, now())
  where id = v_uid;

  -- -------------------------------------------------- education profile
  insert into public.education_profiles (
    user_id, stage, institution_name, institution_id, country_id,
    start_year, expected_end_year, gpa, gpa_scale
  ) values (
    v_uid, v_stage,
    nullif(p_answers->>'institution_name', ''),
    nullif(p_answers->>'institution_id', '')::uuid,
    v_country_id,
    nullif(p_answers->>'start_year', '')::int,
    coalesce(
      nullif(p_answers->>'expected_end_year', '')::int,
      nullif(p_answers->>'graduation_year', '')::int
    ),
    nullif(p_answers->>'gpa', '')::numeric,
    coalesce(nullif(p_answers->>'gpa_scale', '')::numeric, 4.0)
  )
  on conflict (user_id) do update set
    stage             = excluded.stage,
    institution_name  = excluded.institution_name,
    institution_id    = excluded.institution_id,
    country_id        = excluded.country_id,
    start_year        = excluded.start_year,
    expected_end_year = excluded.expected_end_year,
    gpa               = excluded.gpa,
    gpa_scale         = excluded.gpa_scale
  returning id into v_education_id;

  -- ------------------------------------------------------ stage detail
  if v_stage = 'high_school' then
    insert into public.high_school_profiles (
      education_profile_id, user_id, current_class, curriculum,
      intended_field_id, field_confidence, ten_year_note
    ) values (
      v_education_id, v_uid,
      nullif(p_answers->>'current_class', ''),
      nullif(p_answers->>'curriculum', '')::curriculum,
      (select id from public.career_fields
        where slug = public.onboarding_intended_field_slug(p_answers)),
      coalesce(nullif(p_answers->>'field_confidence', '')::field_confidence, 'unsure'),
      nullif(p_answers->>'ten_year_note', '')
    )
    on conflict (user_id) do update set
      education_profile_id = excluded.education_profile_id,
      current_class        = excluded.current_class,
      curriculum           = excluded.curriculum,
      intended_field_id    = excluded.intended_field_id,
      field_confidence     = excluded.field_confidence,
      ten_year_note        = excluded.ten_year_note;

    delete from public.university_profiles where user_id = v_uid;
  else
    insert into public.university_profiles (
      education_profile_id, user_id, degree, major, year_of_study,
      years_total, graduation_month, graduation_year, current_status
    ) values (
      v_education_id, v_uid,
      nullif(p_answers->>'degree', ''),
      nullif(p_answers->>'major', ''),
      nullif(p_answers->>'year_of_study', '')::int,
      nullif(p_answers->>'years_total', '')::int,
      nullif(p_answers->>'graduation_month', '')::int,
      nullif(p_answers->>'graduation_year', '')::int,
      nullif(p_answers->>'current_status', '')::current_status
    )
    on conflict (user_id) do update set
      education_profile_id = excluded.education_profile_id,
      degree               = excluded.degree,
      major                = excluded.major,
      year_of_study        = excluded.year_of_study,
      years_total          = excluded.years_total,
      graduation_month     = excluded.graduation_month,
      graduation_year      = excluded.graduation_year,
      current_status       = excluded.current_status;

    delete from public.high_school_profiles where user_id = v_uid;
  end if;

  -- -------------------------------------------------- career preferences
  insert into public.career_preferences (
    user_id, target_role, target_industry, confidence, values_ranked, ten_year_note
  ) values (
    v_uid,
    nullif(p_answers->>'target_role', ''),
    coalesce((select array_agg(value::text) from jsonb_array_elements_text(
      coalesce(p_answers->'target_industry', '[]'::jsonb)) as value), '{}'),
    coalesce(nullif(p_answers->>'field_confidence', '')::field_confidence, 'unsure'),
    coalesce((select array_agg(value::text) from jsonb_array_elements_text(
      coalesce(p_answers->'career_values', '[]'::jsonb)) as value), '{}'),
    nullif(p_answers->>'ten_year_note', '')
  )
  on conflict (user_id) do update set
    target_role     = excluded.target_role,
    target_industry = excluded.target_industry,
    confidence      = excluded.confidence,
    values_ranked   = excluded.values_ranked,
    ten_year_note   = excluded.ten_year_note;

  -- ------------------------------- collections: cleared, then rewritten
  -- Clearing first is what makes a second submit produce the same rows
  -- rather than twice as many.
  delete from public.user_subjects where user_id = v_uid;
  for v_item in select * from jsonb_array_elements(coalesce(p_answers->'favourite_subjects', '[]'::jsonb))
  loop
    insert into public.user_subjects (user_id, subject_id, sentiment)
      select v_uid, s.id, 'loves' from public.subjects s
      where s.slug = trim(both '"' from v_item::text)
      on conflict do nothing;
  end loop;
  for v_item in select * from jsonb_array_elements(coalesce(p_answers->'hard_subjects', '[]'::jsonb))
  loop
    insert into public.user_subjects (user_id, subject_id, sentiment)
      select v_uid, s.id, 'finds_hard' from public.subjects s
      where s.slug = trim(both '"' from v_item::text)
      on conflict do nothing;
  end loop;

  delete from public.user_interests where user_id = v_uid;
  for v_item in select * from jsonb_array_elements(coalesce(p_answers->'interests', '[]'::jsonb))
  loop
    insert into public.user_interests (user_id, interest_id, source)
      select v_uid, i.id, 'preset' from public.interests i
      where i.slug = trim(both '"' from v_item::text)
      on conflict do nothing;
  end loop;
  for v_item in select * from jsonb_array_elements(coalesce(p_answers->'custom_interests', '[]'::jsonb))
  loop
    v_label := trim(both '"' from v_item::text);
    if v_label <> '' then
      insert into public.user_interests (user_id, label, source)
        values (v_uid, v_label, 'custom')
        on conflict do nothing;
    end if;
  end loop;

  delete from public.user_skills where user_id = v_uid and source = 'self';
  for v_item in select * from jsonb_array_elements(coalesce(p_answers->'skills', '[]'::jsonb))
  loop
    insert into public.user_skills (user_id, skill_id, proficiency, source)
      select v_uid, s.id, 2, 'self' from public.skills s
      where s.id = (trim(both '"' from v_item::text))::uuid
      on conflict (user_id, skill_id) do nothing;
  end loop;

  delete from public.courses where user_id = v_uid;
  for v_item in select * from jsonb_array_elements(coalesce(p_answers->'courses', '[]'::jsonb))
  loop
    insert into public.courses (user_id, semester, code, title, credits)
      values (
        v_uid,
        coalesce(nullif(v_item->>'semester', ''), 'Current'),
        nullif(v_item->>'code', ''),
        coalesce(nullif(v_item->>'title', ''), 'Untitled course'),
        nullif(v_item->>'credits', '')::numeric
      );
  end loop;

  delete from public.activities where user_id = v_uid;
  for v_item in select * from jsonb_array_elements(coalesce(p_answers->'activities', '[]'::jsonb))
  loop
    v_label := trim(both '"' from v_item::text);
    if v_label <> '' and v_label <> 'none' then
      insert into public.activities (user_id, category, title)
        values (v_uid, v_label::activity_category, initcap(replace(v_label, '_', ' ')));
    end if;
  end loop;

  delete from public.experiences where user_id = v_uid;
  for v_item in select * from jsonb_array_elements(coalesce(p_answers->'experiences', '[]'::jsonb))
  loop
    insert into public.experiences (user_id, company_name, title, employment_type, description)
      values (
        v_uid,
        coalesce(nullif(v_item->>'organisation', ''), 'Not given'),
        coalesce(nullif(v_item->>'role', ''), 'Not given'),
        nullif(v_item->>'type', ''),
        nullif(v_item->>'description', '')
      );
  end loop;

  -- ------------------------------------------------------------- finish
  update public.onboarding_drafts
     set completed_at = coalesce(completed_at, now()),
         answers = p_answers
   where user_id = v_uid;

end $$;

grant execute on function public.write_onboarding(jsonb) to authenticated;

-- The helpers are called from inside write_onboarding, which runs as the
-- student, so authenticated needs them. They read nothing but their argument
-- and the public career_fields reference table.
grant execute on function public.onboarding_intended_field_slug(jsonb) to authenticated;
grant execute on function public.onboarding_intended_field(jsonb) to authenticated;

-- ------------------------------------------------------------------ backfill
--
-- Nobody is affected today — there are no school students in the database yet
-- — but this is written for the beta, when there will be, and for the local
-- and staging copies where there already are. It repairs from the saved draft,
-- which is the only surviving record of what the student actually answered.
do $$
declare
  r record;
  v_fixed int := 0;
begin
  for r in
    select p.id, d.answers
      from public.profiles p
      join public.onboarding_drafts d on d.user_id = p.id
     where p.education_stage = 'high_school'
       and d.answers is not null
       and (p.intended_field is null
            or exists (select 1 from public.high_school_profiles h
                        where h.user_id = p.id and h.intended_field_id is null))
  loop
    update public.profiles
       set intended_field = public.onboarding_intended_field(r.answers)
     where id = r.id
       and intended_field is null;

    update public.high_school_profiles
       set intended_field_id = (
             select f.id from public.career_fields f
              where f.slug = public.onboarding_intended_field_slug(r.answers))
     where user_id = r.id
       and intended_field_id is null;

    -- The score was computed with the point missing; it has to be asked again
    -- rather than left to correct itself the next time the student happens to
    -- touch the app.
    perform public.recompute_readiness(r.id, 'backfill_intended_field');
    v_fixed := v_fixed + 1;
  end loop;

  raise notice 'intended field repaired for % school student(s)', v_fixed;
end $$;

-- ------------------------------------------------------------------- checked
do $$
begin
  -- The array shape is the one the app actually sends, and the one that broke.
  if public.onboarding_intended_field_slug('{"intended_field_slug":["engineering"]}'::jsonb)
     is distinct from 'engineering' then
    raise exception 'array-shaped intended_field_slug still does not resolve';
  end if;

  if public.onboarding_intended_field_slug('{"intended_field_slug":"engineering"}'::jsonb)
     is distinct from 'engineering' then
    raise exception 'string-shaped intended_field_slug does not resolve';
  end if;

  if public.onboarding_intended_field_slug('{}'::jsonb) is not null then
    raise exception 'a missing answer should resolve to null, not a value';
  end if;
end $$;

-- ---------------------------------------------------------- reviewed, not fixed
--
-- Supabase's advisor flags cohort_benchmarks as a SECURITY DEFINER view at
-- ERROR level. It was reviewed and deliberately kept: it exposes only
-- year_of_study, mode, avg_total and cohort_size, and only where cohort_size
-- >= 5. That threshold is what makes it safe — it lets a student see how their
-- cohort is doing without reading a single other student's score, which is
-- precisely why it must not run as the caller.
comment on view public.cohort_benchmarks is
  'SECURITY DEFINER on purpose: aggregates only, k-anonymised at cohort_size '
  '>= 5, so a student can see their cohort average without reading anyone''s '
  'row. Reviewed against advisor lint 0010 in migration 0064.';
