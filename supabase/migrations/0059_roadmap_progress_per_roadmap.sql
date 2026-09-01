-- Following a second career path should not cost you points.
--
-- roadmap_progress pooled every task the student owned into one done/total,
-- across every roadmap they had ever made, ignoring roadmaps.deleted_at. Two
-- consequences, both of them the app punishing a student for using it:
--
--   Following a second path instantly dropped the ratio, because the new
--   roadmap arrives with 0 of ~29 done. A student curious about a second
--   career was charged readiness points for the curiosity.
--
--   Unfollowing a path never gave them back. PathRepository.unfollow only
--   soft-deletes the user_career_paths row; the roadmap and its ~29 unfinished
--   tasks survived and dragged the ratio down permanently, with no way for the
--   student to find out why their score had fallen.
--
-- The fix is to score the roadmap the student is actually working on: the best
-- progressed of their live roadmaps. One roadmap behaves exactly as before.
-- A second one can only ever help, never hurt — which is the only version of
-- this rule a student would agree with if it were explained to them.
--
-- Note what was considered and rejected: averaging the per-roadmap ratios has
-- the same defect as pooling, because the second roadmap still averages in at
-- zero. The problem was never the arithmetic, it was counting work the student
-- has not started as work they have failed to do.

create or replace function public.roadmap_progress_ratio(p_user_id uuid)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(max(ratio), 0)
    from (
      select case when count(t.id) = 0 then 0
                  else count(t.id) filter (where t.is_done)::numeric / count(t.id)
             end as ratio
        from public.roadmaps r
        join public.roadmap_milestones m on m.roadmap_id = r.id
        join public.roadmap_tasks t on t.milestone_id = m.id and t.deleted_at is null
       where r.user_id = p_user_id
         and r.deleted_at is null
       group by r.id
    ) per_roadmap
$$;

revoke all on function public.roadmap_progress_ratio(uuid) from public, anon, authenticated;


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
  v_roadmap numeric;
  v_profile_filled int;
  v_interests int; v_favourites int;
  v_is_school boolean;
begin
  select * into p from public.profiles where id = p_user_id;
  if not found then return; end if;

  v_is_school := p.mode = 'discover';

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
    + (exists (select 1 from public.education_profiles e
                where e.user_id = p_user_id and e.deleted_at is null))::int;

  select coalesce(max(case when e.gpa is not null and e.gpa_scale > 0
                           then least(e.gpa / e.gpa_scale, 1) end), 0)
    into v_cgpa
    from public.education_profiles e
    where e.user_id = p_user_id and e.deleted_at is null;

  select count(*) into v_courses from public.courses where user_id = p_user_id and deleted_at is null;

  select count(*), coalesce(avg(proficiency), 0) into v_skills, v_skill_avg
    from public.user_skills where user_id = p_user_id;

  -- Subjects and interests are a school student's equivalent of skills, so
  -- they are not stuck at zero for two years waiting to have any.
  select count(*) into v_interests from public.user_interests where user_id = p_user_id;
  select count(*) into v_favourites from public.user_subjects
    where user_id = p_user_id and sentiment = 'loves';

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

  -- The roadmap they are actually working on, not every roadmap they have
  -- ever opened. See the note at the top of this migration.
  v_roadmap := public.roadmap_progress_ratio(p_user_id);

  return query values
    ('profile_completeness', round(v_profile_filled / 8.0, 4)),
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
    ('roadmap_progress',     round(v_roadmap, 4));
end $$;

revoke all on function public.readiness_ratios(uuid) from public, anon, authenticated;


-- Unfollowing a path retires its roadmap.
--
-- The client only ever soft-deleted the user_career_paths row, so the roadmap
-- outlived the decision to stop following it. Doing this in the database means
-- it holds however the row is retired — from the app, from a support script,
-- or from a future screen nobody has written yet.
create or replace function public.retire_roadmap_on_unfollow()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.deleted_at is not null and old.deleted_at is null then
    update public.roadmaps
       set deleted_at = now()
     where user_id = new.user_id
       and path_id = new.path_id
       and deleted_at is null;
  -- Re-following inside the same session should not orphan the work already
  -- done on it.
  elsif new.deleted_at is null and old.deleted_at is not null then
    update public.roadmaps
       set deleted_at = null
     where user_id = new.user_id
       and path_id = new.path_id
       and deleted_at is not null;
  end if;
  return null;
end $$;

drop trigger if exists user_career_paths_retire_roadmap on public.user_career_paths;
create trigger user_career_paths_retire_roadmap
  after update of deleted_at on public.user_career_paths
  for each row execute function public.retire_roadmap_on_unfollow();


-- Retire the roadmaps already orphaned by an unfollow that happened before
-- this trigger existed.
update public.roadmaps r
   set deleted_at = now()
 where r.deleted_at is null
   and exists (
     select 1 from public.user_career_paths u
      where u.user_id = r.user_id and u.path_id = r.path_id
        and u.deleted_at is not null
   )
   and not exists (
     select 1 from public.user_career_paths u
      where u.user_id = r.user_id and u.path_id = r.path_id
        and u.deleted_at is null
   );
