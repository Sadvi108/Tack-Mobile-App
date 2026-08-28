-- Writes a finished draft into the real tables, in one transaction.
--
-- Nothing touches the real tables until the student finishes, so an abandoned
-- flow leaves no half-built profile for the readiness score to grade. This is
-- the moment that changes, and it either all lands or none of it does.
--
-- Idempotent by construction: every write is an upsert keyed on the user, and
-- the child collections are cleared before reinsert. Double-tapping Finish
-- must not produce two of anything.
--
-- SECURITY INVOKER on purpose. It runs as the student, so Row Level Security
-- applies to every statement inside it and the function cannot be used to
-- write somebody else's rows.
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
    intended_field      = nullif(p_answers->>'intended_field', ''),
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
        where slug = nullif(p_answers->>'intended_field_slug', '')),
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
