-- A rhythm that forgives a quiet day.
--
-- The streak counts consecutive days, so one missed day takes a 40-day run to
-- zero. That is honest about runs and harsh about everything else: a student
-- who works three evenings a week for a whole semester never sees more than
-- three on the card, and a single sick day wipes a month.
--
-- The rhythm is the habit-strength model from Loop Habit Tracker
-- (github.com/iSoron/uhabits, `Score.compute`): every day the score moves a
-- small step toward 1 if the student kept their rhythm and toward 0 if not,
--
--   score = score * m + earned * (1 - m),   m = 0.5 ^ (sqrt(frequency) / 13)
--
-- with frequency three days in seven. A day is earned when something was done
-- on it, or when the seven days ending on it already hold three active days,
-- the same rule Loop uses to auto-fill a "3 times a week" habit. Keeping three
-- days a week keeps the score full; a quiet week costs about a fifth of it, and
-- it comes back at the same rate.
--
-- It is pure arithmetic over the active days the feed already computes, so it
-- takes no user id and reads no table. The checks at the bottom run it against
-- fixed calendars, so the migration refuses to apply if the arithmetic drifts.

create or replace function public.tack_rhythm(p_days date[], p_today date)
returns jsonb
language plpgsql
immutable
set search_path = public
as $$
declare
  c_target   constant int := 3;
  c_mult     constant double precision := power(0.5, sqrt(3.0 / 7.0) / 13);
  v_score    double precision := 0;
  v_week_ago double precision := 0;
  v_recent   int := 0;
  v_earned   boolean;
  r          record;
begin
  for r in
    with active as (
      select distinct d as day
        from unnest(coalesce(p_days, '{}'::date[])) as d
       where d is not null and d <= p_today
    ),
    cal as (
      select g::date as day, (a.day is not null) as did
        from generate_series((select min(day) from active)::timestamp,
                             p_today::timestamp, interval '1 day') as g
        left join active a on a.day = g::date
    )
    -- Seven rows is seven days: the calendar has no gaps.
    select day, did,
           count(*) filter (where did)
             over (order by day rows between 6 preceding and current row) as in_window
      from cal
     order by day
  loop
    v_earned := r.did or r.in_window >= c_target;

    if r.did and r.day > p_today - 7 then
      v_recent := v_recent + 1;
    end if;

    -- Today is not over. Nothing done yet today is not a day missed, so today
    -- can add to the score and never take from it. Same rule as the streak.
    exit when r.day = p_today and not v_earned;

    v_score := v_score * c_mult + case when v_earned then 1 - c_mult else 0 end;

    if r.day = p_today - 7 then
      v_week_ago := v_score;
    end if;
  end loop;

  return jsonb_build_object(
    'score',       round(v_score * 100)::int,
    'week_change', round(v_score * 100)::int - round(v_week_ago * 100)::int,
    'recent_days', v_recent,
    'target',      c_target
  );
end $$;

revoke all on function public.tack_rhythm(date[], date) from public, anon, authenticated;


-- The feed, unchanged from 0049 except for one key in the streak block.
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
      'rhythm',  public.tack_rhythm(v_days, v_today),
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
declare
  d0      constant date := date '2026-01-05';  -- a Monday
  v_days  date[];
  v_now   int;
  v_then  int;
begin
  if not has_function_privilege('authenticated', 'public.dashboard_feed()', 'EXECUTE') then
    raise exception 'dashboard_feed is not callable by a signed-in student';
  end if;

  -- Nothing done: nothing to show.
  if (public.tack_rhythm('{}'::date[], d0)->>'score')::int <> 0
  or (public.tack_rhythm(null, d0)->>'score')::int <> 0 then
    raise exception 'tack_rhythm: an empty history must score 0';
  end if;

  -- Monday, Tuesday and Wednesday for thirty weeks is a full rhythm.
  select array_agg(d0 + w * 7 + k) into v_days
    from generate_series(0, 29) w, generate_series(0, 2) k;
  if (public.tack_rhythm(v_days, d0 + 30 * 7 - 1)->>'score')::int < 99 then
    raise exception 'tack_rhythm: three days a week must keep the score full';
  end if;
  if (public.tack_rhythm(v_days, d0 + 30 * 7 - 1)->>'recent_days')::int <> 3 then
    raise exception 'tack_rhythm: recent_days must count the last seven days';
  end if;

  -- One quiet week costs some of it, not all of it.
  v_now := (public.tack_rhythm(v_days, d0 + 31 * 7 - 1)->>'score')::int;
  if v_now not between 70 and 90 then
    raise exception 'tack_rhythm: one quiet week should cost about a fifth, got %', v_now;
  end if;

  -- An unfinished today never lowers the score.
  v_then := (public.tack_rhythm(v_days, d0 + 30 * 7)->>'score')::int;
  v_now  := (public.tack_rhythm(v_days, d0 + 30 * 7 - 1)->>'score')::int;
  if v_then < v_now then
    raise exception 'tack_rhythm: a quiet morning lowered the score from % to %', v_now, v_then;
  end if;

  -- A first active day today shows as a small start, not as nothing.
  if (public.tack_rhythm(array[d0], d0)->>'score')::int not between 1 and 5 then
    raise exception 'tack_rhythm: a first day should score a small start';
  end if;

  if has_function_privilege('authenticated', 'public.tack_rhythm(date[], date)', 'EXECUTE') then
    raise exception 'tack_rhythm is callable by a student';
  end if;
end $$;
