-- A target is something a student chose, not something they browsed.
--
-- `user_career_paths.is_primary` has been false for every row ever written:
-- PathRepository.choose() defaults it to false and the one caller — the path
-- detail screen — never passes anything else. Nobody has a primary path.
--
-- 0047 and 0048 papered over that with `order by is_primary desc`, which on a
-- table where the column is always false just means "any path they follow".
-- So a student who tapped Follow on Content writer while looking around was
-- shown, on their home screen, over a profile whose target role says Backend
-- developer:
--
--   YOUR TARGET
--   Content writer                                              31%
--
-- Live data, correctly read, and completely wrong — two sources of truth for
-- "what am I aiming at", with the dashboard silently preferring the weaker one.
--
-- This makes the first path a student follows their primary, keeps exactly one
-- primary alive, and stops the feed calling anything else a target. Existing
-- rows are deliberately NOT backfilled: guessing which of somebody's paths was
-- meant to be the target is the same mistake in a different place. They surface
-- on the dashboard as "you are following X — make it your target?" instead.

create or replace function public.ensure_one_primary_path()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- The first path a student follows is what they are aiming at. Anything
  -- after it is a comparison until they say otherwise.
  if not exists (
    select 1 from public.user_career_paths
     where user_id = new.user_id and deleted_at is null and id <> new.id
  ) then
    new.is_primary := true;
  end if;
  return new;
end $$;

create trigger user_career_paths_first_is_primary
  before insert on public.user_career_paths
  for each row execute function public.ensure_one_primary_path();

-- Dropping the target leaves the other path holding it, rather than leaving
-- the student with no target and a path they still follow.
create or replace function public.promote_next_primary_path()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from public.user_career_paths
     where user_id = old.user_id and deleted_at is null and is_primary
  ) then
    return null;
  end if;

  update public.user_career_paths
     set is_primary = true
   where id = (
     select id from public.user_career_paths
      where user_id = old.user_id and deleted_at is null
      order by selected_at asc limit 1
   );
  return null;
end $$;

create trigger user_career_paths_promote_next
  after update of deleted_at on public.user_career_paths
  for each row when (new.deleted_at is not null and old.deleted_at is null)
  execute function public.promote_next_primary_path();


-- Choosing a target. "Exactly one primary path" is a rule that has to hold
-- whoever is writing, so it is one statement in Postgres rather than two
-- round trips from a client that might only make the first.
create or replace function public.set_primary_path(p_path_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.user_career_paths
     where user_id = v_uid and path_id = p_path_id and deleted_at is null
  ) then
    raise exception 'you are not following that path' using errcode = '42501';
  end if;

  update public.user_career_paths
     set is_primary = (path_id = p_path_id)
   where user_id = v_uid and deleted_at is null;
end $$;

revoke all on function public.set_primary_path(uuid) from public, anon;
grant execute on function public.set_primary_path(uuid) to authenticated;


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

  -- A target is a path the student marked primary, and nothing else.
  --
  -- This used to fall back to "any path they follow", which meant somebody who
  -- tapped Follow on Content writer while browsing was shown "YOUR TARGET:
  -- Content writer" on their home screen — over a profile that said Backend
  -- developer. Following something is not the same as aiming at it, and the
  -- dashboard must not promote a browse into a decision.
  select ucp.path_id into v_primary_path
    from public.user_career_paths ucp
   where ucp.user_id = v_uid and ucp.deleted_at is null and ucp.is_primary
   order by ucp.selected_at asc
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

      -- Null unless the student actually picked a target.
      'primary_title', (select cp.title from public.career_paths cp where cp.id = v_primary_path),
      'primary_slug',  (select cp.slug  from public.career_paths cp where cp.id = v_primary_path),

      -- Paths they follow but have not committed to. The screen offers these
      -- as a question rather than presenting one of them as a decision.
      'following', coalesce((
        select jsonb_agg(jsonb_build_object('id', cp.id, 'title', cp.title,
                                           'slug', cp.slug)
                         order by ucp.selected_at)
          from public.user_career_paths ucp
          join public.career_paths cp on cp.id = ucp.path_id
         where ucp.user_id = v_uid and ucp.deleted_at is null and not ucp.is_primary
      ), '[]'::jsonb)
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
  if not has_function_privilege('authenticated', 'public.set_primary_path(uuid)', 'EXECUTE') then
    raise exception 'a student cannot choose their own target';
  end if;
  if has_function_privilege('authenticated', 'public.tack_activity(uuid)', 'EXECUTE')
  or has_function_privilege('authenticated', 'public.tack_week_summary(uuid, date, date)', 'EXECUTE') then
    raise exception 'a helper taking a user id is callable by a student';
  end if;
end $$;
