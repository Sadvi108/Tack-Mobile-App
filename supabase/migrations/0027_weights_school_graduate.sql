-- Weights for the two new modes.
--
-- The eleven components are the same; what changes is what they are worth,
-- because a score that measured a sixteen-year-old against a final-year
-- student would be both wrong and discouraging.
--
-- school: nothing about applying, no CV, no interviews. A school student is
--   choosing what to study, so what counts is doing well at school, trying
--   things, and having interests they can name. Academic is the largest
--   single weight here and applications are worth nothing at all.
--
-- graduate: the mirror image. No more coursework to improve, so academic
--   drops to almost nothing and applications, CV quality and interview
--   practice carry the score — those are the only things that still move.

insert into public.score_weights (mode, component, weight) values
  ('school','profile_completeness',16), ('school','academic',24), ('school','skills',14),
  ('school','projects',8),  ('school','activities',20), ('school','experience',0),
  ('school','cv_quality',0), ('school','certifications',6), ('school','interview_practice',0),
  ('school','application_activity',0), ('school','roadmap_progress',12),

  ('graduate','profile_completeness',8), ('graduate','academic',4), ('graduate','skills',12),
  ('graduate','projects',10), ('graduate','activities',3), ('graduate','experience',12),
  ('graduate','cv_quality',14), ('graduate','certifications',6), ('graduate','interview_practice',10),
  ('graduate','application_activity',16), ('graduate','roadmap_progress',5)
on conflict (mode, component) do update set weight = excluded.weight;

-- A school student's favourite subjects and interests are the equivalent of a
-- university student's skills, so they count toward the same component rather
-- than leaving the score stuck at zero for a year.
create or replace function public.readiness_ratios(p_user_id uuid)
returns table (component text, ratio numeric)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  p record;
  v_cgpa numeric := 0;
  v_courses int; v_skills int; v_skill_avg numeric; v_projects int;
  v_activities int; v_exp_months numeric; v_certs int;
  v_cv_quality numeric; v_has_cv boolean;
  v_sessions int; v_session_avg numeric;
  v_apps int; v_interviews int;
  v_tasks int; v_tasks_done int;
  v_profile_filled int;
  v_interests int; v_favourites int;
  v_is_school boolean;
begin
  select * into p from public.profiles where id = p_user_id;
  if not found then return; end if;

  v_is_school := p.mode = 'school';

  -- Seven fields for a university student. A school student is not asked for
  -- a target role, so theirs is what they want to study instead.
  v_profile_filled :=
      (p.full_name is not null)::int
    + (p.city_id is not null)::int
    + (p.phone is not null)::int
    + (p.country_id is not null)::int
    + (p.education_stage is not null)::int
    + (case when v_is_school then (p.intended_field is not null)::int
            else (p.year_of_study is not null)::int end)
    + (case when v_is_school then (p.passion is not null)::int
            else (p.target_role is not null)::int end)
    + (exists (select 1 from public.education e where e.user_id = p_user_id and e.deleted_at is null))::int;

  select coalesce(max(case when e.cgpa is not null and e.cgpa_scale > 0
                           then least(e.cgpa / e.cgpa_scale, 1) end), 0)
    into v_cgpa
    from public.education e where e.user_id = p_user_id and e.deleted_at is null;

  select count(*) into v_courses from public.courses where user_id = p_user_id and deleted_at is null;

  select count(*), coalesce(avg(proficiency), 0) into v_skills, v_skill_avg
    from public.user_skills where user_id = p_user_id;

  select count(*) filter (where kind in ('interest','hobby')),
         count(*) filter (where kind in ('favourite_subject','favourite_course'))
    into v_interests, v_favourites
    from public.student_interests where user_id = p_user_id;

  select count(*) into v_projects from public.projects where user_id = p_user_id and deleted_at is null;
  select count(*) into v_activities from public.activities where user_id = p_user_id and deleted_at is null;
  select count(*) into v_certs from public.certifications where user_id = p_user_id and deleted_at is null;

  select coalesce(sum(
      greatest(0, extract(epoch from (coalesce(end_date, current_date)::timestamp
                                      - coalesce(start_date, current_date)::timestamp)) / 2629800.0)
    ), 0) into v_exp_months
    from public.experiences where user_id = p_user_id and deleted_at is null;

  select exists (select 1 from public.documents
    where user_id = p_user_id and type = 'cv' and status = 'ready' and deleted_at is null)
    into v_has_cv;

  select coalesce(max(r.quality_score), 0) / 100.0 into v_cv_quality
    from public.cv_parse_results r
    join public.documents d on d.id = r.document_id and d.deleted_at is null
    where r.user_id = p_user_id;

  select count(*), coalesce(avg(overall_score), 0) into v_sessions, v_session_avg
    from public.interview_sessions
    where user_id = p_user_id and completed_at is not null and deleted_at is null;

  select count(*) into v_apps from public.job_applications
    where user_id = p_user_id and deleted_at is null and status <> 'saved';
  select count(distinct application_id) into v_interviews from public.application_status_history
    where user_id = p_user_id and to_status in ('interview','offer');

  select count(*), count(*) filter (where is_done)
    into v_tasks, v_tasks_done
    from public.roadmap_tasks where user_id = p_user_id and deleted_at is null;

  return query values
    ('profile_completeness', round(v_profile_filled / 8.0, 4)),
    -- A school student is graded on their results and the subjects they have
    -- named, not on a university course list they do not have.
    ('academic',             round(case when v_is_school
                                        then 0.6 * least(v_cgpa / 0.9, 1) + 0.4 * least(v_favourites / 4.0, 1)
                                        else 0.6 * least(v_cgpa / 0.9, 1) + 0.4 * least(v_courses / 8.0, 1) end, 4)),
    ('skills',               round(case when v_is_school
                                        then 0.5 * least(v_skills / 6.0, 1) + 0.5 * least(v_interests / 4.0, 1)
                                        else 0.7 * least(v_skills / 12.0, 1) + 0.3 * (v_skill_avg / 5.0) end, 4)),
    ('projects',             round(least(v_projects / 3.0, 1), 4)),
    ('activities',           round(least(v_activities / 3.0, 1), 4)),
    ('experience',           round(least(v_exp_months / 12.0, 1), 4)),
    ('cv_quality',           round(case when v_cv_quality > 0 then v_cv_quality
                                        when v_has_cv then 0.35 else 0 end, 4)),
    ('certifications',       round(least(v_certs / 3.0, 1), 4)),
    ('interview_practice',   round(0.6 * least(v_sessions / 4.0, 1) + 0.4 * (v_session_avg / 10.0), 4)),
    ('application_activity', round(0.6 * least(v_apps / 10.0, 1) + 0.4 * least(v_interviews / 2.0, 1), 4)),
    ('roadmap_progress',     round(case when v_tasks = 0 then 0 else v_tasks_done::numeric / v_tasks end, 4));
end $$;

revoke all on function public.readiness_ratios(uuid) from public, anon, authenticated;
