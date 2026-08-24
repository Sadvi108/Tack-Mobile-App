-- The readiness score. Eleven components, each producing a 0..1 ratio, each
-- weighted by the student's year mode. Entirely deterministic — no model call
-- is involved anywhere in this file, by design.
--
-- Weights sum to exactly 100 in every mode. Application activity is worth 14
-- in launch and 0 in explore: a first-year is not behind for having applied to
-- nothing, and the score must not tell them otherwise.

create table public.score_weights (
  mode      year_mode not null,
  component text      not null,
  weight    int       not null check (weight >= 0),
  primary key (mode, component)
);
alter table public.score_weights enable row level security;
create policy score_weights_select_all on public.score_weights for select to authenticated using (true);

insert into public.score_weights (mode, component, weight) values
  ('explore','profile_completeness',14), ('explore','academic',14), ('explore','skills',16),
  ('explore','projects',8),  ('explore','activities',14), ('explore','experience',2),
  ('explore','cv_quality',6), ('explore','certifications',6), ('explore','interview_practice',2),
  ('explore','application_activity',0), ('explore','roadmap_progress',18),

  ('build','profile_completeness',12), ('build','academic',12), ('build','skills',16),
  ('build','projects',14), ('build','activities',12), ('build','experience',5),
  ('build','cv_quality',8), ('build','certifications',7), ('build','interview_practice',4),
  ('build','application_activity',0), ('build','roadmap_progress',10),

  ('prove','profile_completeness',10), ('prove','academic',9), ('prove','skills',14),
  ('prove','projects',14), ('prove','activities',8), ('prove','experience',10),
  ('prove','cv_quality',10), ('prove','certifications',7), ('prove','interview_practice',6),
  ('prove','application_activity',4), ('prove','roadmap_progress',8),

  ('launch','profile_completeness',8), ('launch','academic',6), ('launch','skills',12),
  ('launch','projects',10), ('launch','activities',4), ('launch','experience',10),
  ('launch','cv_quality',13), ('launch','certifications',6), ('launch','interview_practice',9),
  ('launch','application_activity',14), ('launch','roadmap_progress',8);

-- Returns one row per component: the raw 0..1 ratio for this user.
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
begin
  select * into p from public.profiles where id = p_user_id;
  if not found then return; end if;

  -- profile completeness: seven fields a student can actually answer
  v_profile_filled :=
      (p.full_name is not null)::int
    + (p.city_id is not null)::int
    + (p.phone is not null)::int
    + (p.year_of_study is not null)::int
    + (p.expected_graduation is not null)::int
    + (p.target_role is not null)::int
    + (exists (select 1 from public.education e where e.user_id = p_user_id and e.deleted_at is null))::int;

  select coalesce(max(case when e.cgpa is not null and e.cgpa_scale > 0
                           then least(e.cgpa / e.cgpa_scale, 1) end), 0)
    into v_cgpa
    from public.education e where e.user_id = p_user_id and e.deleted_at is null;

  select count(*) into v_courses from public.courses where user_id = p_user_id and deleted_at is null;

  select count(*), coalesce(avg(proficiency), 0) into v_skills, v_skill_avg
    from public.user_skills where user_id = p_user_id;

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
    ('profile_completeness', round(v_profile_filled / 7.0, 4)),
    -- CGPA is 60% of academic and courses the rest, so a student who has not
    -- entered a CGPA is not stuck at zero.
    ('academic',             round(0.6 * least(v_cgpa / 0.9, 1) + 0.4 * least(v_courses / 8.0, 1), 4)),
    ('skills',               round(0.7 * least(v_skills / 12.0, 1) + 0.3 * (v_skill_avg / 5.0), 4)),
    ('projects',             round(least(v_projects / 3.0, 1), 4)),
    ('activities',           round(least(v_activities / 3.0, 1), 4)),
    ('experience',           round(least(v_exp_months / 12.0, 1), 4)),
    -- A parsed CV scores on its parse quality; an unparsed one still counts
    -- for something, because having a CV at all beats having none.
    ('cv_quality',           round(case when v_cv_quality > 0 then v_cv_quality
                                        when v_has_cv then 0.35 else 0 end, 4)),
    ('certifications',       round(least(v_certs / 3.0, 1), 4)),
    ('interview_practice',   round(0.6 * least(v_sessions / 4.0, 1) + 0.4 * (v_session_avg / 10.0), 4)),
    ('application_activity', round(0.6 * least(v_apps / 10.0, 1) + 0.4 * least(v_interviews / 2.0, 1), 4)),
    ('roadmap_progress',     round(case when v_tasks = 0 then 0 else v_tasks_done::numeric / v_tasks end, 4));
end $$;

-- Computes the score and writes a snapshot. Returns the new row.
-- Skips the write when nothing changed, so the 90-day trend stays readable.
create or replace function public.recompute_readiness(p_user_id uuid, p_reason text default null)
returns public.readiness_scores
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mode year_mode;
  v_total int;
  v_components jsonb;
  v_prev int;
  v_row public.readiness_scores;
begin
  select mode into v_mode from public.profiles where id = p_user_id;
  if v_mode is null then return null; end if;

  with r as (select * from public.readiness_ratios(p_user_id)),
       w as (select component, weight from public.score_weights where mode = v_mode),
       j as (
         select w.component,
                w.weight                                as max,
                round(w.weight * coalesce(r.ratio, 0))::int as earned,
                coalesce(r.ratio, 0)                    as ratio
         from w left join r on r.component = w.component
       )
  select sum(earned),
         jsonb_object_agg(component, jsonb_build_object(
           'earned', earned, 'max', max,
           'available', max - earned,
           'ratio', ratio))
    into v_total, v_components
    from j;

  v_total := least(100, greatest(0, coalesce(v_total, 0)));

  select total into v_prev from public.readiness_scores
    where user_id = p_user_id order by computed_at desc limit 1;

  if v_prev is not null and v_prev = v_total then
    select * into v_row from public.readiness_scores
      where user_id = p_user_id order by computed_at desc limit 1;
    return v_row;
  end if;

  insert into public.readiness_scores (user_id, total, mode, components, delta, reason)
    values (p_user_id, v_total, v_mode, v_components, v_total - coalesce(v_prev, 0), p_reason)
    returning * into v_row;

  return v_row;
end $$;

-- Convenience for the client: the current score without writing a snapshot.
create or replace function public.current_readiness()
returns public.readiness_scores
language sql
stable
security invoker
as $$
  select * from public.readiness_scores
    where user_id = (select auth.uid())
    order by computed_at desc limit 1
$$;

-- Every table that feeds a component enqueues a recompute rather than running
-- it inline, so a task tick stays a single fast write.
create or replace function public.enqueue_readiness_recompute()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare uid uuid;
begin
  uid := coalesce(
    case when tg_op = 'DELETE' then null else (to_jsonb(new)->>'user_id')::uuid end,
    (to_jsonb(coalesce(old, new))->>'user_id')::uuid
  );
  if uid is null then return null; end if;

  insert into public.jobs_queue (user_id, type, payload, idempotency_key, run_after)
    values (uid, 'recompute_readiness',
            jsonb_build_object('user_id', uid, 'source', tg_table_name),
            'readiness:' || uid || ':' || to_char(now(), 'YYYYMMDDHH24MI'),
            now() + interval '20 seconds')
  on conflict (idempotency_key) do nothing;

  return null;
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'education','courses','activities','experiences','projects','certifications',
    'user_skills','documents','cv_parse_results','job_applications',
    'interview_sessions','roadmap_tasks','profiles'
  ] loop
    execute format(
      'create trigger %I after insert or update or delete on public.%I
         for each row execute function public.enqueue_readiness_recompute()',
      t || '_readiness_recompute', t);
  end loop;
end $$;
