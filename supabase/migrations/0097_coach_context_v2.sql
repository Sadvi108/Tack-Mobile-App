-- The smarter coach: reply actions on chat_messages, and coach_context() v2.
--
-- What is added
--
-- 1. chat_messages.actions and chat_messages.intent. A coach reply carries up
--    to three chips, each {label, route[, slug]}, and the id of the rule (or
--    'model', 'cited', 'guide_refusal', 'fallback') that answered it. Both
--    are written only by the coach endpoint and the worker with the service
--    role. Students keep exactly the column grants 0072 gave them, so a
--    client can never forge a chip.
-- 2. coach_context() v2: the same signature and every 0053 key with its
--    name and type, plus what the coach needs to answer more for free:
--    interview practice, reviews due, the latest CV check, dates (prove and
--    later), Home's roadmap counts, the cohort average and a version.
--
-- The PII boundary
--
-- What leaves coach_context() can reach a model, so the boundary is drawn
-- here rather than in a prompt. Nothing a student typed as free text enters
-- it: no application notes, no next_action text, no interview answers, no CV
-- text, no chat bodies. Allowed: the interview role (a title the student
-- chose, capped at 60 characters), roadmap task titles, job titles and
-- company names (capped at 80). The coach endpoint still redacts every string
-- leaf before any model call (_shared/ai/redact.ts, redactJson).
--
-- Early years (discover, explore, build) are not job hunting, so their
-- applications are {} and their upcoming dates [] here, not only in the
-- router and the prompt.

-- ----------------------------------------------------------------- 1. columns
alter table public.chat_messages add column if not exists actions jsonb;
alter table public.chat_messages add column if not exists intent text;

comment on column public.chat_messages.actions is
  'Chips under a coach reply: null or an array of at most 3 {label, route[, '
  'slug]}. Route ids are the list in _shared/coach/actions.ts. Written only '
  'by the service (coach endpoint, worker); students have no grant on it.';
comment on column public.chat_messages.intent is
  'What answered a coach reply: a router id, or model, cited, guide_refusal '
  'or fallback. Written only by the service; students have no grant on it.';

-- ------------------------------------------------------------- 2. the checks
--
-- A jsonpath CHECK, not a helper function. A function in a CHECK runs with
-- the inserting role's EXECUTE privilege, and since 0065 every new function
-- is granted to nobody, so a helper would make every student insert fail.
-- The path is written once below and used both to create the constraint and
-- to probe it, so the probes test the constraint that ships.
do $$
declare
  -- Selects any element that is not a well-formed action.
  v_path constant text := '$[*] ? (@.type() != "object"
      || !exists(@.route) || @.route.type() != "string"
      || !(@.route like_regex "^(interview|practice|analyser|cv_check|cv_builder|roadmap|radar|score|paths|path|applications|profile)$")
      || !exists(@.label) || @.label.type() != "string" || !(@.label like_regex "^.{2,48}$")
      || (@.route == "path" && (!exists(@.slug) || @.slug.type() != "string"
                                || !(@.slug like_regex "^[a-z0-9-]{1,80}$")))
      || (@.route != "path" && exists(@.slug))
      || exists(@.keyvalue() ? (!(@.key like_regex "^(label|route|slug)$"))))';
  -- CASE, not AND: jsonb_array_length raises on a non-array, and SQL does not
  -- promise to evaluate AND left to right.
  v_shape constant text := 'case when jsonb_typeof(%1$s) = ''array'' '
    'then jsonb_array_length(%1$s) <= 3 '
    'and not jsonb_path_exists(%1$s, %2$L::jsonpath) else false end';
  v_ok    boolean;
  v_probe record;
begin
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.chat_messages'::regclass
                    and conname = 'chat_messages_actions_shape') then
    execute format(
      'alter table public.chat_messages add constraint chat_messages_actions_shape '
      'check (actions is null or (%s))',
      format(v_shape, 'actions', v_path));
  end if;

  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.chat_messages'::regclass
                    and conname = 'chat_messages_intent_shape') then
    alter table public.chat_messages add constraint chat_messages_intent_shape
      check (intent is null or intent ~ '^[a-z_]{1,32}$');
  end if;

  -- Probes: each value and whether the constraint must accept it.
  for v_probe in
    select * from (values
      ('[{"label": "Practise an interview", "route": "interview"},
         {"label": "Read about Data analyst", "route": "path", "slug": "data-analyst"}]',
       true, 'two valid actions'),
      ('[]', true, 'an empty list'),
      ('[{"label": "Go somewhere", "route": "nowhere"}]', false, 'an unknown route'),
      ('[{"label": "Read about it", "route": "path"}]', false, 'path without a slug'),
      ('[{"label": "Read about it", "route": "path", "slug": "Data Analyst"}]',
       false, 'path with a malformed slug'),
      ('[{"label": "Open your roadmap", "route": "roadmap", "slug": "x"}]',
       false, 'a slug on a route that is not path'),
      ('[{"label": "Open your roadmap", "route": "roadmap", "extra": 1}]',
       false, 'an extra key'),
      ('[{"label": "A", "route": "roadmap"}]', false, 'a one-letter label'),
      ('[{"route": "roadmap"}]', false, 'no label'),
      ('[{"label": 7, "route": "roadmap"}]', false, 'a label that is not a string'),
      ('["roadmap"]', false, 'an element that is not an object'),
      ('[{"label": "Open your roadmap", "route": "roadmap"},
         {"label": "See your score", "route": "score"},
         {"label": "Explore paths", "route": "paths"},
         {"label": "Update your profile", "route": "profile"}]',
       false, 'four actions'),
      ('{"label": "Open your roadmap", "route": "roadmap"}', false, 'an object, not a list')
    ) as p(value, accepted, what)
  loop
    execute format('select %s', format(v_shape, '$1', v_path))
      into v_ok using v_probe.value::jsonb;
    if v_ok is distinct from v_probe.accepted then
      raise exception 'chat_messages_actions_shape: % should be %',
        v_probe.what, case when v_probe.accepted then 'accepted' else 'refused' end;
    end if;
  end loop;

  if not ('fallback' ~ '^[a-z_]{1,32}$' and 'score_explain' ~ '^[a-z_]{1,32}$')
     or 'Model' ~ '^[a-z_]{1,32}$' or 'guide-refusal' ~ '^[a-z_]{1,32}$' then
    raise exception 'chat_messages_intent_shape: the pattern is wrong';
  end if;
end $$;

-- ------------------------------------------------------- 3. coach_context v2
create or replace function public.coach_context()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid          uuid := (select auth.uid());
  v_today        date;
  v_p            record;
  v_s            record;
  v_early        boolean;
  v_primary_path uuid;
  v_next_title   text;
  v_next_due     date;
  v_next_points  int;
begin
  if v_uid is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;

  v_today := public.tack_today();

  select p.mode, p.year_of_study, p.years_total, p.target_role,
         p.education_stage, p.expected_graduation
    into v_p
    from public.profiles p
   where p.id = v_uid and p.deleted_at is null;
  if not found then return null; end if;

  -- Anything that is not prove or later counts as early, the safe side.
  v_early := coalesce(v_p.mode::text, 'explore') not in ('prove', 'launch', 'graduate');

  select r.total, r.components into v_s
    from public.readiness_scores r
   where r.user_id = v_uid order by r.computed_at desc limit 1;

  -- The target, chosen exactly as dashboard_feed() chooses it.
  select ucp.path_id into v_primary_path
    from public.user_career_paths ucp
   where ucp.user_id = v_uid and ucp.deleted_at is null and ucp.is_primary
   order by ucp.selected_at asc
   limit 1;

  -- The next roadmap task: dashboard_feed()'s join and order (0077), so the
  -- coach and Home never name different next steps.
  select nt.title, nt.due_date, nt.points
    into v_next_title, v_next_due, v_next_points
    from public.roadmap_tasks nt
    join public.roadmap_milestones nm on nm.id = nt.milestone_id and nm.state = 'active'
    join public.roadmaps nr on nr.id = nm.roadmap_id and nr.deleted_at is null
   where nt.user_id = v_uid and not nt.is_done and nt.deleted_at is null
   order by nt.due_date nulls last, nm.order_index, nt.order_index
   limit 1;

  return jsonb_build_object(
    'version',             2,
    'today',               v_today,
    'mode',                v_p.mode,
    'year_of_study',       v_p.year_of_study,
    'years_total',         v_p.years_total,
    'stage',               v_p.education_stage,
    'target_role',         v_p.target_role,
    'expected_graduation', v_p.expected_graduation,

    'score', jsonb_build_object(
      'total',      coalesce(v_s.total, 0),
      'components', coalesce(v_s.components, '{}'::jsonb)
    ),

    -- The view already hides cohorts under five.
    'cohort', (
      select jsonb_build_object('average', c.avg_total, 'size', c.cohort_size)
        from public.cohort_benchmarks c
       where c.mode = v_p.mode
         and c.year_of_study is not distinct from v_p.year_of_study
       limit 1
    ),

    'target_path', (
      select jsonb_build_object('title', cp.title, 'slug', cp.slug)
        from public.career_paths cp
       where cp.id = v_primary_path
    ),

    'skills_held', coalesce((
      select jsonb_agg(h.name order by h.name)
        from (select s.name
                from public.user_skills us join public.skills s on s.id = us.skill_id
               where us.user_id = v_uid
               order by s.name
               limit 40) h
    ), '[]'::jsonb),

    'skill_gap', coalesce((
      select jsonb_agg(s.name order by s.name)
        from public.career_path_skills cps
        join public.skills s on s.id = cps.skill_id
       where cps.path_id = v_primary_path
         and cps.importance = 'core'
         and not exists (select 1 from public.user_skills us
                          where us.user_id = v_uid and us.skill_id = cps.skill_id)
    ), '[]'::jsonb),

    -- Counted exactly as dashboard_feed() counts it (0077): tasks of a
    -- deleted roadmap do not count (fixes D4).
    'roadmap', (
      select jsonb_build_object(
        'done',        count(*) filter (where t.is_done),
        'total',       count(*),
        'overdue',     count(*) filter (
                         where not t.is_done and t.due_date is not null
                           and t.due_date < v_today),
        'next',        v_next_title,
        'next_due',    v_next_due,
        'next_points', v_next_points
      )
      from public.roadmap_tasks t
      join public.roadmap_milestones ms on ms.id = t.milestone_id
      join public.roadmaps r2 on r2.id = ms.roadmap_id and r2.deleted_at is null
      where t.user_id = v_uid and t.deleted_at is null
    ),

    'applications', case when v_early then '{}'::jsonb else (
      select coalesce(jsonb_object_agg(status, n), '{}'::jsonb)
        from (select a.status::text status, count(*)::int n
                from public.job_applications a
               where a.user_id = v_uid and a.deleted_at is null
               group by a.status) x
    ) end,

    -- Kept for older endpoints; cv.has_cv says the same.
    'has_cv', exists (select 1 from public.documents
                       where user_id = v_uid and type = 'cv'
                         and status <> 'failed' and deleted_at is null),

    'cv', jsonb_build_object(
      'has_cv', exists (select 1 from public.documents
                         where user_id = v_uid and type = 'cv'
                           and status <> 'failed' and deleted_at is null),
      -- Finding titles are fixed templates (_shared/cv/findings.ts), never
      -- CV text.
      'last_check', (
        select jsonb_build_object(
          'on',          (c.created_at at time zone 'Asia/Dhaka')::date,
          'problems',    c.problems,
          'suggestions', c.suggestions,
          'top', coalesce((
            select jsonb_agg(jsonb_build_object('kind', f.item->>'kind',
                                                'severity', f.item->>'severity',
                                                'title', f.item->>'title')
                             order by f.sev_rank, f.n)
              from (select x.item, x.n,
                           case x.item->>'severity' when 'problem' then 0 else 1 end as sev_rank
                      from jsonb_array_elements(
                             case when jsonb_typeof(c.findings) = 'array'
                                  then c.findings else '[]'::jsonb end
                           ) with ordinality as x(item, n)
                     where x.item->>'severity' in ('problem', 'improve')
                     order by sev_rank, x.n
                     limit 3) f
          ), '[]'::jsonb)
        )
          from public.cv_checks c
          join public.documents d on d.id = c.document_id and d.deleted_at is null
         where c.user_id = v_uid
         order by c.created_at desc
         limit 1
      )
    ),

    'interview', jsonb_build_object(
      'sessions', (
        select count(*)::int from public.interview_sessions s
         where s.user_id = v_uid and s.deleted_at is null and s.completed_at is not null
      ),
      'last', (
        select jsonb_build_object(
          'on',    (s.completed_at at time zone 'Asia/Dhaka')::date,
          'role',  left(s.role, 60),
          'score', coalesce(
                     (select round(avg(f.score), 1)
                        from public.interview_feedback f
                        join public.interview_questions q on q.id = f.question_id
                       where q.session_id = s.id and f.user_id = v_uid),
                     round(s.overall_score, 1))
        )
          from public.interview_sessions s
         where s.user_id = v_uid and s.deleted_at is null and s.completed_at is not null
         order by s.completed_at desc
         limit 1
      ),
      'average', (
        select round(avg(l.overall_score), 1)
          from (select s.overall_score
                  from public.interview_sessions s
                 where s.user_id = v_uid and s.deleted_at is null
                   and s.completed_at is not null and s.overall_score is not null
                 order by s.completed_at desc
                 limit 5) l
      ),
      -- Weakest first. Only answers a model scored count.
      'by_category', coalesce((
        select jsonb_agg(jsonb_build_object('category', g.label,
                                            'average', g.average,
                                            'answers', g.answers)
                         order by g.average, g.answers desc, g.label)
          from (
            select upper(left(min(a.category), 1)) || substr(min(a.category), 2) as label,
                   round(avg(a.score), 1) as average,
                   count(*)::int as answers
              from (select btrim(q.category) as category, f.score
                      from public.interview_feedback f
                      join public.interview_questions q on q.id = f.question_id
                      join public.interview_sessions s
                        on s.id = q.session_id and s.deleted_at is null
                     where f.user_id = v_uid
                       and nullif(btrim(coalesce(q.category, '')), '') is not null
                     order by f.created_at desc
                     limit 30) a
             group by lower(a.category)
          ) g
      ), '[]'::jsonb),
      -- interview_due()'s own filter, counted rather than listed.
      'due_reviews', (
        select count(*)::int
          from public.interview_reviews r
          join public.interview_questions q on q.id = r.question_id
          join public.interview_sessions s on s.id = q.session_id and s.deleted_at is null
         where r.user_id = v_uid and r.due_on <= v_today
      )
    ),

    -- Prove and later only. A week back (kindly, as still open) to two weeks
    -- ahead. Titles only: never next_action, never notes.
    'upcoming', case when v_early then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object('kind', u.kind, 'title', u.title, 'on', u.on_date)
                       order by u.on_date, u.kind_rank, u.title)
        from (
          select * from (
            select 'task' as kind, 0 as kind_rank, left(t.title, 80) as title,
                   t.due_date as on_date
              from public.roadmap_tasks t
              join public.roadmap_milestones ms on ms.id = t.milestone_id
              join public.roadmaps r3 on r3.id = ms.roadmap_id and r3.deleted_at is null
             where t.user_id = v_uid and t.deleted_at is null and not t.is_done
               and t.due_date between v_today - 7 and v_today + 14
            union all
            select 'follow_up', 1, left(concat_ws(' · ', j.title, j.company_name), 80),
                   a.next_action_date
              from public.job_applications a
              join public.jobs j on j.id = a.job_id
             where a.user_id = v_uid and a.deleted_at is null
               and a.next_action_date between v_today - 7 and v_today + 14
            union all
            select 'closing', 2, left(concat_ws(' · ', j.title, j.company_name), 80),
                   j.closes_at
              from public.job_applications a
              join public.jobs j on j.id = a.job_id
             where a.user_id = v_uid and a.deleted_at is null
               and a.status in ('saved', 'applied')
               and j.closes_at between v_today - 7 and v_today + 14
          ) merged
          order by on_date, kind_rank, title
          limit 6
        ) u
    ), '[]'::jsonb) end,

    'streak', (
      select count(distinct day)::int from public.tack_activity(v_uid)
       where day > v_today - 14
    )
  );
end $$;

comment on function public.coach_context() is
  'Everything the coach may know about the signed-in student, version 2. '
  'Free text a student typed never enters it. See 0097.';

revoke all on function public.coach_context() from public, anon;
grant execute on function public.coach_context() to authenticated;

-- ----------------------------------------------------------- 4. self-checks
do $$
declare
  v_user uuid;
  v_ctx  jsonb;
  v_key  text;
  v_col  text;
  v_priv text;
begin
  if not has_function_privilege('authenticated', 'public.coach_context()', 'EXECUTE') then
    raise exception 'coach_context is not callable by a signed-in student';
  end if;
  if has_function_privilege('anon', 'public.coach_context()', 'EXECUTE') then
    raise exception 'coach_context must not be reachable with the anon key alone';
  end if;

  -- 0072 revoked table-level insert and update, so a column added later has
  -- no student grant. Proved rather than assumed.
  foreach v_col in array array['actions', 'intent'] loop
    foreach v_priv in array array['INSERT', 'UPDATE'] loop
      if has_column_privilege('authenticated', 'public.chat_messages', v_col, v_priv) then
        raise exception 'authenticated can % chat_messages.%', v_priv, v_col;
      end if;
    end loop;
  end loop;

  select id into v_user from public.profiles where deleted_at is null limit 1;
  if v_user is null then
    raise notice 'no profiles yet; the coach_context shape check needs a caller';
    return;
  end if;

  -- auth.uid() reads the sub claim. `true` keeps it to this transaction, and
  -- it is cleared below whether or not anything else runs after this block.
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_user, 'role', 'authenticated')::text,
                     true);
  v_ctx := public.coach_context();
  perform set_config('request.jwt.claims', '', true);

  if v_ctx is null or jsonb_typeof(v_ctx) <> 'object' then
    raise exception 'coach_context did not return an object';
  end if;
  if (v_ctx->>'version')::int is distinct from 2 then
    raise exception 'coach_context version is %, not 2', v_ctx->>'version';
  end if;
  foreach v_key in array array[
    'version', 'today', 'mode', 'year_of_study', 'years_total', 'stage',
    'target_role', 'expected_graduation', 'score', 'cohort', 'target_path',
    'skills_held', 'skill_gap', 'roadmap', 'applications', 'has_cv', 'cv',
    'interview', 'upcoming', 'streak']
  loop
    if not (v_ctx ? v_key) then
      raise exception 'coach_context is missing the % key', v_key;
    end if;
  end loop;
  foreach v_key in array array['done', 'total', 'overdue', 'next', 'next_due', 'next_points'] loop
    if not (v_ctx->'roadmap' ? v_key) then
      raise exception 'coach_context.roadmap is missing the % key', v_key;
    end if;
  end loop;
  foreach v_key in array array['sessions', 'last', 'average', 'by_category', 'due_reviews'] loop
    if not (v_ctx->'interview' ? v_key) then
      raise exception 'coach_context.interview is missing the % key', v_key;
    end if;
  end loop;
  foreach v_key in array array['has_cv', 'last_check'] loop
    if not (v_ctx->'cv' ? v_key) then
      raise exception 'coach_context.cv is missing the % key', v_key;
    end if;
  end loop;
  if jsonb_typeof(v_ctx->'upcoming') <> 'array'
     or jsonb_typeof(v_ctx->'applications') <> 'object'
     or jsonb_typeof(v_ctx->'skills_held') <> 'array'
     or jsonb_typeof(v_ctx->'interview'->'by_category') <> 'array' then
    raise exception 'coach_context has a collection of the wrong type';
  end if;
  if coalesce(v_ctx->>'mode', 'explore') not in ('prove', 'launch', 'graduate')
     and (v_ctx->'applications' <> '{}'::jsonb or v_ctx->'upcoming' <> '[]'::jsonb) then
    raise exception 'coach_context leaks applications or dates to an early year';
  end if;
end $$;
