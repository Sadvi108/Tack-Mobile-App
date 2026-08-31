-- One definition of "the student did something".
--
-- 0047 shipped two. The streak counted eleven sources — skills, courses,
-- projects, certificates, activities, experiences, documents, applications,
-- status changes, practice sessions and roadmap tasks — while the week summary
-- counted four. On a real account that had added seven skills and nothing
-- else, the same snapshot said both of these at once:
--
--   SHOWING UP    active on 26 August
--   THIS WEEK     "last week you got through 0 things"
--
-- Two cards, one screen, one moment, contradicting each other. That is exactly
-- the class of bug the single-snapshot feed was built to remove, and it came
-- back because the definition was written out twice instead of once.
--
-- It is now written once, here, and everything else aggregates it.

-- Every thing this student did, with the Dhaka day it happened on.
--
-- Takes a user id, so it is never granted to anyone: it is reachable only from
-- inside the SECURITY DEFINER functions below, which have already resolved the
-- caller from auth.uid(). Same rule as tack_week_summary, same reason.
create or replace function public.tack_activity(p_user_id uuid)
returns table (day date, kind text)
language sql
stable
security definer
set search_path = public
as $$
  select (t.done_at at time zone 'Asia/Dhaka')::date, 'task'
    from public.roadmap_tasks t
   where t.user_id = p_user_id and t.is_done and t.done_at is not null
     and t.deleted_at is null

  union all
  select (a.created_at at time zone 'Asia/Dhaka')::date, 'application'
    from public.job_applications a
   where a.user_id = p_user_id and a.deleted_at is null

  -- Only real transitions. The history trigger also writes a row on insert,
  -- with a null from_status, and counting that would score every new
  -- application twice.
  union all
  select (h.changed_at at time zone 'Asia/Dhaka')::date, 'status'
    from public.application_status_history h
   where h.user_id = p_user_id and h.from_status is not null

  union all
  select (s.completed_at at time zone 'Asia/Dhaka')::date, 'interview'
    from public.interview_sessions s
   where s.user_id = p_user_id and s.completed_at is not null
     and s.deleted_at is null

  union all
  select (x.created_at at time zone 'Asia/Dhaka')::date, 'document'
    from public.documents x where x.user_id = p_user_id and x.deleted_at is null

  union all
  select (x.created_at at time zone 'Asia/Dhaka')::date, 'skill'
    from public.user_skills x where x.user_id = p_user_id

  union all
  select (x.created_at at time zone 'Asia/Dhaka')::date, 'project'
    from public.projects x where x.user_id = p_user_id and x.deleted_at is null

  union all
  select (x.created_at at time zone 'Asia/Dhaka')::date, 'certificate'
    from public.certifications x
   where x.user_id = p_user_id and x.deleted_at is null

  union all
  select (x.created_at at time zone 'Asia/Dhaka')::date, 'activity'
    from public.activities x where x.user_id = p_user_id and x.deleted_at is null

  union all
  select (x.created_at at time zone 'Asia/Dhaka')::date, 'experience'
    from public.experiences x
   where x.user_id = p_user_id and x.deleted_at is null

  union all
  select (x.created_at at time zone 'Asia/Dhaka')::date, 'course'
    from public.courses x where x.user_id = p_user_id and x.deleted_at is null
$$;

revoke all on function public.tack_activity(uuid) from public, anon, authenticated;


-- One week of it. `moves` is now counted here rather than summed from four
-- fields on the client, so the total and the streak can no longer drift apart.
create or replace function public.tack_week_summary(
  p_user_id uuid,
  p_from    date,
  p_to      date
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with a as (
    select kind from public.tack_activity(p_user_id)
     where day >= p_from and day < p_to
  ),
  d as (
    select count(distinct day)::int as n from public.tack_activity(p_user_id)
     where day >= p_from and day < p_to
  )
  select jsonb_build_object(
    'from', p_from,
    'to',   p_to - 1,

    -- Everything, by the same rule the streak uses.
    'moves',       (select count(*) from a),
    'active_days', (select n from d),

    -- The named few, for copy that says what was done rather than how much.
    'tasks_done',           (select count(*) from a where kind = 'task'),
    'applications_added',   (select count(*) from a where kind = 'application'),
    'interviews_practised', (select count(*) from a where kind = 'interview'),
    'documents_added',      (select count(*) from a where kind = 'document'),
    'skills_added',         (select count(*) from a where kind = 'skill'),
    'projects_added',       (select count(*) from a where kind = 'project'),

    'task_points', coalesce((
      select sum(t.points) from public.roadmap_tasks t
       where t.user_id = p_user_id and t.is_done and t.deleted_at is null
         and (t.done_at at time zone 'Asia/Dhaka')::date >= p_from
         and (t.done_at at time zone 'Asia/Dhaka')::date <  p_to
    ), 0),

    -- Score moved during the window: the last snapshot inside it, against the
    -- last one before it.
    'score_gained', coalesce(
      (select r.total from public.readiness_scores r
        where r.user_id = p_user_id
          and (r.computed_at at time zone 'Asia/Dhaka')::date >= p_from
          and (r.computed_at at time zone 'Asia/Dhaka')::date <  p_to
        order by r.computed_at desc limit 1)
      -
      (select r.total from public.readiness_scores r
        where r.user_id = p_user_id
          and (r.computed_at at time zone 'Asia/Dhaka')::date < p_from
        order by r.computed_at desc limit 1),
      0)
  )
$$;

revoke all on function public.tack_week_summary(uuid, date, date) from public, anon, authenticated;


-- The feed, rebuilt on the shared definition. Only the streak block and the
-- new paths.available field differ from 0047; everything else is unchanged.
create or replace function public.dashboard_feed()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid          uuid := (select auth.uid());
  v_today        date;
  v_week_start   date;
  v_profile      record;
  v_score        record;
  v_days         date[];
  v_streak_now   int := 0;
  v_streak_best  int := 0;
  v_week_change  int := 0;
  v_primary_path uuid;
  v_result       jsonb;
begin
  if v_uid is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;

  v_today      := public.tack_today();
  v_week_start := date_trunc('week', v_today)::date;

  select p.id, p.full_name, p.mode, p.target_role, p.year_of_study,
         p.years_total, p.education_stage, p.onboarding_completed_at,
         p.expected_graduation
    into v_profile
    from public.profiles p
   where p.id = v_uid and p.deleted_at is null;

  if not found then
    return null;
  end if;

  select r.total, r.delta, r.components, r.computed_at, r.mode
    into v_score
    from public.readiness_scores r
   where r.user_id = v_uid
   order by r.computed_at desc
   limit 1;

  -- The one definition. Readiness recomputes are still not in it: they are
  -- enqueued by a trigger twenty seconds after any write, so counting them
  -- would credit the student with a streak the app awarded itself.
  select array_agg(distinct day order by day) into v_days
    from public.tack_activity(v_uid)
   where day is not null and day <= v_today;

  -- Gaps and islands. A run that ended yesterday is still alive: a student who
  -- has not opened the app yet today has not broken anything, and telling them
  -- the streak is zero at 9am is how you get somebody to stop caring about it.
  if v_days is not null then
    with numbered as (
      select day, row_number() over (order by day) as rn
        from unnest(v_days) as day
    ),
    islands as (
      select max(day) as end_day, count(*)::int as len
        from (select day, day - rn::int as grp from numbered) g
       group by grp
    )
    select coalesce(max(len) filter (where end_day >= v_today - 1), 0),
           coalesce(max(len), 0)
      into v_streak_now, v_streak_best
      from islands;
  end if;

  select coalesce(
           coalesce(v_score.total, 0) - (
             select h.total from public.readiness_scores h
              where h.user_id = v_uid and h.computed_at < now() - interval '7 days'
              order by h.computed_at desc limit 1),
           coalesce(v_score.total, 0) - (
             select h.total from public.readiness_scores h
              where h.user_id = v_uid order by h.computed_at asc limit 1),
           0)
    into v_week_change;

  select ucp.path_id into v_primary_path
    from public.user_career_paths ucp
   where ucp.user_id = v_uid and ucp.deleted_at is null
   order by ucp.is_primary desc, ucp.selected_at asc
   limit 1;

  select jsonb_build_object(
    'generated_at', now(),
    'today',        v_today,

    'profile', jsonb_build_object(
      'id',                     v_profile.id,
      'full_name',              v_profile.full_name,
      'mode',                   v_profile.mode,
      'stage',                  v_profile.education_stage,
      'target_role',            v_profile.target_role,
      'year_of_study',          v_profile.year_of_study,
      'years_total',            v_profile.years_total,
      'expected_graduation',    v_profile.expected_graduation,
      'onboarding_completed_at', v_profile.onboarding_completed_at
    ),

    'score', jsonb_build_object(
      'total',       coalesce(v_score.total, 0),
      'delta',       coalesce(v_score.delta, 0),
      'mode',        coalesce(v_score.mode, v_profile.mode),
      'components',  coalesce(v_score.components, '{}'::jsonb),
      'computed_at', v_score.computed_at,
      'week_change', v_week_change
    ),

    'cohort', (
      select jsonb_build_object('average', c.avg_total, 'size', c.cohort_size)
        from public.cohort_benchmarks c
       where c.mode = v_profile.mode
         and c.year_of_study is not distinct from v_profile.year_of_study
       limit 1
    ),

    'trend', coalesce((
      select jsonb_agg(jsonb_build_object('week', wk, 'total', total) order by wk)
        from (
          select date_trunc('week', (r.computed_at at time zone 'Asia/Dhaka'))::date as wk,
                 (array_agg(r.total order by r.computed_at desc))[1]                 as total
            from public.readiness_scores r
           where r.user_id = v_uid
             and (r.computed_at at time zone 'Asia/Dhaka')::date >= v_week_start - 77
           group by 1
        ) w
    ), '[]'::jsonb),

    'streak', jsonb_build_object(
      'current', v_streak_now,
      'longest', v_streak_best,
      'days', coalesce((
        select jsonb_agg(day order by day)
          from unnest(coalesce(v_days, '{}'::date[])) as day
         where day > v_today - 28
      ), '[]'::jsonb)
    ),

    'this_week', public.tack_week_summary(v_uid, v_week_start, v_week_start + 7),
    'last_week', public.tack_week_summary(v_uid, v_week_start - 7, v_week_start),

    'roadmap', (
      select jsonb_build_object(
        'done',    count(*) filter (where t.is_done),
        'total',   count(*),
        'overdue', count(*) filter (
                     where not t.is_done and t.due_date is not null and t.due_date < v_today),
        'active_milestone', (
          select m.title from public.roadmap_milestones m
            join public.roadmaps rm on rm.id = m.roadmap_id and rm.deleted_at is null
           where m.user_id = v_uid and m.state = 'active'
           order by m.order_index limit 1
        ),
        'next_task', (
          select jsonb_build_object('id', nt.id, 'title', nt.title, 'points', nt.points,
                                    'est_minutes', nt.est_minutes, 'type', nt.type)
            from public.roadmap_tasks nt
            join public.roadmap_milestones nm on nm.id = nt.milestone_id and nm.state = 'active'
            join public.roadmaps nr on nr.id = nm.roadmap_id and nr.deleted_at is null
           where nt.user_id = v_uid and not nt.is_done and nt.deleted_at is null
           order by nt.due_date nulls last, nm.order_index, nt.order_index
           limit 1
        )
      )
      from public.roadmap_tasks t
      join public.roadmap_milestones ms on ms.id = t.milestone_id
      join public.roadmaps r2 on r2.id = ms.roadmap_id and r2.deleted_at is null
      where t.user_id = v_uid and t.deleted_at is null
    ),

    'applications', (
      select coalesce(jsonb_object_agg(status, n), '{}'::jsonb)
        from (
          select a.status::text as status, count(*)::int as n
            from public.job_applications a
           where a.user_id = v_uid and a.deleted_at is null
           group by a.status
        ) s
    ),

    'timeline', coalesce((
      select jsonb_agg(item order by (item->>'on')::date, item->>'kind')
        from (
          select jsonb_build_object(
                   'kind', 'task', 'id', t.id, 'title', t.title,
                   'subtitle', ms.title, 'on', t.due_date,
                   'points', t.points, 'route', '/roadmap',
                   'overdue', t.due_date < v_today) as item
            from public.roadmap_tasks t
            join public.roadmap_milestones ms on ms.id = t.milestone_id
            join public.roadmaps r3 on r3.id = ms.roadmap_id and r3.deleted_at is null
           where t.user_id = v_uid and t.deleted_at is null and not t.is_done
             and t.due_date is not null
             and t.due_date between v_today - 30 and v_today + 14

          union all
          select jsonb_build_object(
                   'kind', 'application', 'id', a.id,
                   'title', coalesce(a.next_action, 'Follow up'),
                   'subtitle', concat_ws(' · ', j.title, j.company_name),
                   'on', a.next_action_date, 'points', 0,
                   'route', '/applications/' || a.id,
                   'overdue', a.next_action_date < v_today)
            from public.job_applications a
            join public.jobs j on j.id = a.job_id
           where a.user_id = v_uid and a.deleted_at is null
             and a.next_action_date is not null
             and a.next_action_date between v_today - 30 and v_today + 14

          union all
          select jsonb_build_object(
                   'kind', 'closing', 'id', a.id,
                   'title', 'Applications close',
                   'subtitle', concat_ws(' · ', j.title, j.company_name),
                   'on', j.closes_at, 'points', 0,
                   'route', '/applications/' || a.id,
                   'overdue', j.closes_at < v_today)
            from public.job_applications a
            join public.jobs j on j.id = a.job_id
           where a.user_id = v_uid and a.deleted_at is null
             and j.closes_at is not null and a.status in ('saved', 'applied')
             and j.closes_at between v_today - 30 and v_today + 14
        ) merged
    ), '[]'::jsonb),

    'skill_gap', coalesce((
      select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name,
                                          'importance', cps.importance)
                       order by case cps.importance
                                  when 'core' then 0 when 'important' then 1 else 2 end,
                                s.name)
        from public.career_path_skills cps
        join public.skills s on s.id = cps.skill_id
       where cps.path_id = v_primary_path
         and not exists (select 1 from public.user_skills us
                          where us.user_id = v_uid and us.skill_id = cps.skill_id)
    ), '[]'::jsonb),

    'skill_fit', (
      select jsonb_build_object(
        'total', count(*),
        'have',  count(*) filter (
                   where exists (select 1 from public.user_skills us
                                  where us.user_id = v_uid and us.skill_id = cps.skill_id))
      )
      from public.career_path_skills cps
      where cps.path_id = v_primary_path
    ),

    'paths', jsonb_build_object(
      'chosen', (select count(*) from public.user_career_paths
                  where user_id = v_uid and deleted_at is null),
      -- How many there actually are to explore. The dashboard used to say
      -- "Ten real jobs" in hardcoded copy, which was true only for as long as
      -- nobody added an eleventh or retired one.
      'available', (select count(*) from public.career_paths where is_active),
      'primary_title', (select cp.title from public.career_paths cp where cp.id = v_primary_path),
      'primary_slug',  (select cp.slug  from public.career_paths cp where cp.id = v_primary_path)
    ),

    'documents', jsonb_build_object(
      'count',  (select count(*) from public.documents
                  where user_id = v_uid and deleted_at is null),
      'has_cv', exists (select 1 from public.documents
                         where user_id = v_uid and type = 'cv'
                           and status <> 'failed' and deleted_at is null)
    ),

    'unread_notifications', (
      select count(*) from public.notifications
       where user_id = v_uid and read_at is null
    )
  ) into v_result;

  return v_result;
end $$;

revoke all on function public.dashboard_feed() from public, anon;
grant execute on function public.dashboard_feed() to authenticated;

do $$
begin
  if not has_function_privilege('authenticated', 'public.dashboard_feed()', 'EXECUTE') then
    raise exception 'dashboard_feed is not callable by a signed-in student';
  end if;
  for i in 1..1 loop
    if has_function_privilege('authenticated', 'public.tack_activity(uuid)', 'EXECUTE')
    or has_function_privilege('authenticated', 'public.tack_week_summary(uuid, date, date)', 'EXECUTE') then
      raise exception 'a helper taking a user id is callable by a student';
    end if;
  end loop;
end $$;
