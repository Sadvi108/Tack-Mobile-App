-- Reading a student, and suggesting where they could go.
--
-- Onboarding asks eight screens of questions and then almost nothing reads
-- the answers. The paths screen ranks by user_skills alone, which is empty for
-- most students on the day they finish signing up, so the one moment a
-- suggestion would be most useful is the moment it has least to say.
--
-- Meanwhile the account this was built against carries: a Computer Science
-- major, a stated target of Backend developer, four target industries, a
-- course called "Data Structures and Algorithm", and a recorded confidence of
-- "unsure". Every one of those is a signal, and none of them were being used.
--
-- Deterministic throughout. AGENTS.md is explicit that matching is arithmetic
-- and never a model, and a suggestion a student cannot get twice is one they
-- cannot plan around. Every point a path scores here comes with a sentence
-- saying where it came from, so the ranking can be argued with rather than
-- taken on faith.

-- Which field a student belongs to, from whatever they actually gave us.
--
-- In order of how much the student meant it: the field they picked outright,
-- then the field their stated target role sits in, then their degree subject
-- read against the field vocabulary. Null when there is genuinely nothing —
-- a guess presented as a fact is worse than no guess.
create or replace function public.derive_career_field(p_user_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_field uuid;
  v_major text;
begin
  -- 1. They chose one. Nothing beats being asked.
  select h.intended_field_id into v_field
    from public.high_school_profiles h
   where h.user_id = p_user_id and h.intended_field_id is not null;
  if v_field is not null then return v_field; end if;

  -- 2. The role they said they want belongs to a field.
  select cp.field_id into v_field
    from public.profiles p
    join public.career_paths cp
      on lower(cp.title) = lower(p.target_role) and cp.is_active
   where p.id = p_user_id and cp.field_id is not null;
  if v_field is not null then return v_field; end if;

  -- 3. Their degree subject, matched against the field vocabulary. Loose on
  --    purpose: students write "CSE", "Computer Science and Engineering" and
  --    "Computer Science" for the same degree.
  select lower(concat_ws(' ', u.major, u.degree)) into v_major
    from public.university_profiles u where u.user_id = p_user_id;

  if v_major is not null and v_major <> '' then
    select cf.id into v_field
      from public.career_fields cf
     where cf.is_active
       and (
         v_major like '%' || lower(split_part(cf.name, ' and ', 1)) || '%'
         or lower(cf.name) like '%' || v_major || '%'
       )
     order by
       -- Prefer a field that actually has paths behind it; suggesting a field
       -- with nothing to follow is a dead end.
       (select count(*) from public.career_paths cp
         where cp.field_id = cf.id and cp.is_active) desc,
       length(cf.name)
     limit 1;
  end if;

  return v_field;
end $$;

revoke all on function public.derive_career_field(uuid) from public, anon, authenticated;


-- The suggestions, ranked, each carrying its reasons.
create or replace function public.path_suggestions(p_limit int default 6)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid    uuid := (select auth.uid());
  v_field  uuid;
  v_unsure boolean;
  v_result jsonb;
begin
  if v_uid is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;

  v_field := public.derive_career_field(v_uid);

  -- A student who told us they are unsure is asking for options, not for one
  -- answer. It widens the list rather than narrowing it.
  --
  -- SELECT INTO leaves the variable null when no row matches, so a student
  -- with no preferences row at all came back null rather than the intended
  -- default. Somebody who has told us nothing about their confidence is, if
  -- anything, less sure than somebody who said so.
  select cp.confidence::text = 'unsure' into v_unsure
    from public.career_preferences cp where cp.user_id = v_uid;
  v_unsure := coalesce(v_unsure, true);

  with me as (
    select p.target_role, p.target_industry, p.mode
      from public.profiles p where p.id = v_uid
  ),
  my_skills as (
    select skill_id from public.user_skills where user_id = v_uid
  ),
  my_subjects as (
    select s.name from public.user_subjects us
      join public.subjects s on s.id = us.subject_id
     where us.user_id = v_uid and us.sentiment = 'loves'
  ),
  scored as (
    select
      cp.id, cp.slug, cp.title, cp.summary, cp.field_id,
      cp.salary_min_bdt, cp.salary_max_bdt, cp.months_to_job_ready,
      cp.demand_level,

      -- The role they named. The strongest thing a student ever tells us.
      (case when lower(cp.title) = lower((select target_role from me))
            then 45 else 0 end) as s_target,

      -- Same field as the one they belong to.
      (case when v_field is not null and cp.field_id = v_field
            then 25 else 0 end) as s_field,

      -- What they can already do, weighted the way the paths screen weights
      -- it: core counts for three, important two, nice one.
      (select coalesce(round(
                30.0 * sum(case cps.importance
                             when 'core' then 3 when 'important' then 2 else 1 end)
                     filter (where cps.skill_id in (select skill_id from my_skills))
                / nullif(sum(case cps.importance
                             when 'core' then 3 when 'important' then 2 else 1 end), 0)
              ), 0)::int
         from public.career_path_skills cps where cps.path_id = cp.id) as s_skills,

      -- A subject they love that leads into this path's field.
      (select least(count(*) * 8, 16)::int
         from public.career_fields cf
         cross join lateral unnest(cf.subjects) as subj
        where cf.id = cp.field_id
          and subj in (select name from my_subjects)) as s_subjects,

      -- One of the industries they said they want to work in.
      (case when exists (
              select 1 from unnest(coalesce((select target_industry from me), '{}')) as ind
               where lower(ind) like '%' || lower(cp.category) || '%'
                  or lower(cp.category) like '%' || lower(split_part(ind, ' and ', 1)) || '%'
            ) then 10 else 0 end) as s_industry,

      -- A student who is job hunting now needs something reachable, so a path
      -- that takes a year to become hireable in is worth slightly less than
      -- one that takes four months.
      (case when (select mode from me) in ('launch', 'graduate')
                 and cp.months_to_job_ready is not null
            then greatest(0, 8 - cp.months_to_job_ready) else 0 end) as s_speed

      from public.career_paths cp
     where cp.is_active
  ),
  totalled as (
    select *,
           -- Everything that ties this path to this student. Speed is
           -- deliberately not in here: being quick to become hireable in is a
           -- tiebreak between paths that already fit, never a reason to
           -- suggest one. Without the split, a job-hunting graduate was shown
           -- Content writer and HR executive with no reasons attached at all,
           -- purely because they are fast — which is a list, not advice.
           s_target + s_field + s_skills + s_subjects + s_industry as connection,
           s_target + s_field + s_skills + s_subjects + s_industry + s_speed as score
      from scored
  )
  select coalesce(jsonb_agg(item order by ord), '[]'::jsonb) into v_result
    from (
      select jsonb_build_object(
               'id', t.id,
               'slug', t.slug,
               'title', t.title,
               'summary', t.summary,
               'score', t.score,
               'salary_min', t.salary_min_bdt,
               'salary_max', t.salary_max_bdt,
               'months', t.months_to_job_ready,
               'demand', t.demand_level,
               'is_target', t.s_target > 0,
               -- Already following it, so the screen can say so rather than
               -- suggesting something they have.
               'followed', exists (
                 select 1 from public.user_career_paths u
                  where u.user_id = v_uid and u.path_id = t.id and u.deleted_at is null
               ),
               -- Why this one. Ordered strongest first, and only reasons that
               -- actually contributed — a suggestion that cannot say why it is
               -- there is one a student has no reason to trust.
               'reasons', (
                 select coalesce(jsonb_agg(r order by w desc), '[]'::jsonb)
                   from (
                     select 'You said this is what you are aiming at' as r, 5 as w
                      where t.s_target > 0
                     union all
                     select 'Your subject leads here', 4 where t.s_field > 0 and t.s_target = 0
                     union all
                     select 'You already have some of the skills it asks for', 3
                      where t.s_skills > 0
                     union all
                     select 'A subject you enjoy leads here', 2 where t.s_subjects > 0
                     union all
                     select 'It is in an industry you picked', 1 where t.s_industry > 0
                   ) reasons
               )
             ) as item,
             row_number() over (order by t.score desc, t.title) as ord
        from totalled t
       -- A path with no connection to the student is not a suggestion.
       where t.connection > 0
       order by t.score desc, t.title
       limit greatest(1, least(coalesce(p_limit, 6) + (case when v_unsure then 2 else 0 end), 10))
    ) page;

  return jsonb_build_object(
    'field', (select cf.name from public.career_fields cf where cf.id = v_field),
    'unsure', v_unsure,
    'suggestions', v_result
  );
end $$;

revoke all on function public.path_suggestions(int) from public, anon;
grant execute on function public.path_suggestions(int) to authenticated;

do $$
begin
  if not has_function_privilege('authenticated', 'public.path_suggestions(int)', 'EXECUTE') then
    raise exception 'path_suggestions is not callable by a signed-in student';
  end if;
  if has_function_privilege('anon', 'public.path_suggestions(int)', 'EXECUTE') then
    raise exception 'path_suggestions must not be reachable with the anon key alone';
  end if;
end $$;
