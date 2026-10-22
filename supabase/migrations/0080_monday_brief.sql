-- The Monday brief: one push a week with the three things that matter most.
--
-- Borrowed from Release Radar (github.com/Shubhamsaboo/awesome-llm-apps,
-- always_on_agents/release_radar_agent/ranker.py): every signal has a fixed
-- score, an item scores its strongest signal plus five for each extra one,
-- anything without a signal is dropped, and every item carries one fixed line
-- about why it matters. And from its scheduler (scheduler_api.py): a run is a
-- dry run unless told otherwise, so nothing reaches a student from a console
-- by accident.
--
-- Arithmetic over the student's own rows, so it costs nobody an AI action and
-- gives the same answer every time it is asked.
--
-- It shares the daily digest's key, digest:<user>:<date>, and runs before it
-- on a Monday. A student still hears from Tack at most once a day.
--
-- Also fixes the daily digest. It runs at 00:20 Dhaka and asked to be
-- delivered at 09:00 the *next* day, about 33 hours later, so a step it called
-- "due soon" could be overdue by the time it arrived.

-- ------------------------------------------------------------ listing fit
--
-- The fit radar_feed computes (0076), for one listing and one student, so the
-- brief can count new openings without running the feed as that student.
-- tool/verify_weekly_brief.js holds the two to the same number.
create or replace function public.listing_fit(p_user uuid, p_listing uuid)
returns int
language sql
stable
security definer
set search_path = public
as $$
  with path as (
    select ucp.path_id
      from public.user_career_paths ucp
     where ucp.user_id = p_user and ucp.deleted_at is null and ucp.is_primary
     limit 1
  ),
  counted as (
    select count(ls.skill_id) as asks,
           count(ls.skill_id) filter (where ls.skill_id in (
             select us.skill_id from public.user_skills us
              where us.user_id = p_user)) as have,
           count(ls.skill_id) filter (where ls.skill_id in (
             select cps.skill_id from public.career_path_skills cps
              where cps.path_id = (select path_id from path))) as on_path
      from public.job_listing_skills ls
     where ls.listing_id = p_listing
  )
  select case when asks = 0 then null
              else least(100, round(
                80.0 * have / asks
                + case when on_path = 0 then 0
                       else 20.0 * least(on_path, 3) / 3 end
              ))::int
         end
    from counted;
$$;

revoke all on function public.listing_fit(uuid, uuid) from public, anon, authenticated;

-- ------------------------------------------------------------- the ranking
--
-- At most three items for one student, strongest first. Each item is one
-- thing: an application, the roadmap, the practice queue, the new openings.
create or replace function public.weekly_brief_items(
  p_user  uuid,
  p_today date default public.tack_today()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_mode    text;
  v_city    text;
  v_hunting boolean;
  v_result  jsonb;
begin
  select p.mode::text, c.name
    into v_mode, v_city
    from public.profiles p
    left join public.cities c on c.id = p.city_id
   where p.id = p_user;

  if v_mode is null then
    return '[]'::jsonb;
  end if;

  -- Deadlines and interviews are for the years that are looking for work. A
  -- first-year is never told about a deadline (AGENTS.md, the mode table).
  v_hunting := v_mode in ('prove', 'launch', 'graduate');

  with signals(name, score) as (
    values ('closing', 100), ('interview', 90), ('steps_late', 80),
           ('new_matches', 70), ('practice_due', 60), ('idle_roadmap', 50)
  ),
  applications as (
    select 'application'::text as kind,
           a.id::text as ref,
           case
             -- least() skips nulls: the earlier of the posting's close date
             -- and the student's own next date, whichever exists.
             when a.status in ('saved', 'applied')
              and least(j.closes_at, a.next_action_date) between p_today and p_today + 3
               then array['closing']
             when a.status = 'interview'
              and a.next_action_date between p_today and p_today + 7
               then array['interview']
           end as reasons,
           case when a.status = 'interview' then a.next_action_date
                else least(j.closes_at, a.next_action_date) end as on_date,
           coalesce(nullif(trim(j.company_name), ''), j.title) as name,
           0::bigint as n
      from public.job_applications a
      join public.jobs j on j.id = a.job_id
     where v_hunting
       and a.user_id = p_user
       and a.deleted_at is null
  ),
  tasks as (
    select t.due_date, t.is_done, greatest(t.updated_at, t.done_at) as touched
      from public.roadmap_tasks t
      join public.roadmap_milestones m on m.id = t.milestone_id
      join public.roadmaps r on r.id = m.roadmap_id and r.deleted_at is null
     where t.user_id = p_user
       and t.deleted_at is null
  ),
  roadmap as (
    select 'roadmap'::text as kind,
           null::text as ref,
           array_remove(array[
             case when count(*) filter (where not is_done and due_date < p_today) > 0
                  then 'steps_late' end,
             -- Quiet for two weeks: nothing ticked or edited anywhere, and
             -- something still open. One line about the roadmap, never one per
             -- step, or every long roadmap would fill the brief.
             case when count(*) filter (where not is_done) > 0
                   and max(touched) < (p_today - 14)::timestamp at time zone 'Asia/Dhaka'
                  then 'idle_roadmap' end
           ], null) as reasons,
           min(due_date) filter (where not is_done and due_date < p_today) as on_date,
           null::text as name,
           count(*) filter (where not is_done and due_date < p_today) as n
      from tasks
  ),
  practice as (
    select 'practice'::text as kind,
           null::text as ref,
           array['practice_due'] as reasons,
           min(r.due_on) as on_date,
           null::text as name,
           count(*) as n
      from public.interview_reviews r
     where r.user_id = p_user
       and r.due_on <= p_today
    having count(*) > 0
  ),
  matches as (
    select 'matches'::text as kind,
           null::text as ref,
           array['new_matches'] as reasons,
           null::date as on_date,
           null::text as name,
           count(*) as n
      from public.job_listings l
     where v_mode in ('build', 'prove', 'launch', 'graduate')
       and l.first_seen_at >= (p_today - 7)::timestamp at time zone 'Asia/Dhaka'
       -- The radar's own default: remote, or in the student's city.
       and (l.is_remote
            or coalesce(l.location, '') ilike '%' || coalesce(v_city, 'Dhaka') || '%')
       and public.listing_fit(p_user, l.id) >= 80
    having count(*) > 0
  ),
  items as (
    select * from applications where reasons is not null
    union all select * from roadmap where cardinality(reasons) > 0
    union all select * from practice
    union all select * from matches
  ),
  scored as (
    select i.*,
           (select s.name from signals s
             where s.name = any (i.reasons)
             order by s.score desc limit 1) as top,
           (select max(s.score) from signals s where s.name = any (i.reasons))
             + 5 * (cardinality(i.reasons) - 1) as score
      from items i
  ),
  ranked as (
    select * from scored
     order by score desc, on_date asc nulls last, ref
     limit 3
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'kind', kind,
           'reasons', to_jsonb(reasons),
           'score', score,
           'title', case top
             when 'closing'      then name || ' closes ' || to_char(on_date, 'Dy DD Mon')
             when 'interview'    then name || ' interview, ' || to_char(on_date, 'Dy DD Mon')
             when 'steps_late'   then case when n = 1 then 'One roadmap step is late'
                                           else n || ' roadmap steps are late' end
             when 'new_matches'  then case when n = 1 then 'One new opening fits you'
                                           else n || ' new openings fit you' end
             when 'practice_due' then case when n = 1 then 'One practice question is back'
                                           else n || ' practice questions are back' end
             else 'Your roadmap has been quiet for two weeks'
           end,
           'why', case top
             when 'closing'      then 'Send your application before then, or let it go. Either is fine.'
             when 'interview'    then 'Practise three questions for this role before the day.'
             when 'steps_late'   then 'Move a date or tick one off. Nothing is lost.'
             when 'new_matches'  then case when v_mode = 'build'
                                           then 'Worth a look, even before you are ready to send one.'
                                           else 'Each one matches at least 80% of what you know.' end
             when 'practice_due' then 'Say the answers out loud. It takes about five minutes.'
             else case when v_mode in ('discover', 'explore')
                       then 'Try one step for ten minutes this week.'
                       else 'Ten minutes on one step this week keeps it moving.' end
           end,
           'route', case kind
             when 'application' then '/applications/' || ref
             when 'roadmap'     then '/roadmap'
             when 'practice'    then '/interview'
             when 'matches'     then '/radar'
           end
         ) order by score desc, on_date asc nulls last, ref), '[]'::jsonb)
    into v_result
    from ranked;

  return v_result;
end $$;

revoke all on function public.weekly_brief_items(uuid, date) from public, anon, authenticated;

-- --------------------------------------------------------------- the send
--
-- A dry run by default: it returns what it would send and sends nothing.
-- p_only narrows it to one student, which is how the verify script runs it
-- for real without touching anybody else.
create or replace function public.enqueue_weekly_brief(
  p_dry_run boolean default true,
  p_today   date default public.tack_today(),
  p_only    uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r       record;
  v_items jsonb;
  v_count int;
  v_out   jsonb := '[]'::jsonb;
  -- The nightly sweep runs at 00:20 Dhaka, so 09:00 is the same morning.
  v_when  timestamptz := p_today::timestamp at time zone 'Asia/Dhaka' + interval '9 hours';
begin
  for r in
    select p.id
      from public.profiles p
     where p.onboarding_completed_at is not null
       and (p_only is null or p.id = p_only)
  loop
    v_items := public.weekly_brief_items(r.id, p_today);
    v_count := jsonb_array_length(v_items);

    -- A quiet week sends nothing. A brief that always arrives is a brief
    -- people learn to swipe away.
    continue when v_count = 0;

    v_out := v_out || jsonb_build_array(
      jsonb_build_object('user_id', r.id, 'items', v_items));

    if not p_dry_run then
      perform public.notify(
        r.id,
        'weekly_brief',
        case when v_count = 1 then 'Your week: one thing'
             else 'Your week: ' || v_count || ' things' end,
        v_items -> 0 ->> 'title',
        jsonb_build_object('items', v_items),
        'digest:' || r.id || ':' || p_today,
        v_when
      );
    end if;
  end loop;

  return v_out;
end $$;

revoke all on function public.enqueue_weekly_brief(boolean, date, uuid) from public, anon, authenticated;

comment on function public.enqueue_weekly_brief(boolean, date, uuid) is
  'The Monday brief. Dry run unless p_dry_run is false. Shares the daily '
  'digest''s dedupe key, so it and the digest never both reach a student on '
  'the same day.';

-- ------------------------------------------------- the digest, delivered on time
--
-- Unchanged from 0066 except for v_when, which asked for the morning after the
-- morning it meant.
create or replace function public.enqueue_daily_digest()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  r         record;
  v_today   date := public.tack_today();
  v_sent    int := 0;
  v_title   text;
  v_body    text;
  -- 09:00 in Dhaka on the morning this runs. The nightly sweep fires at 00:20
  -- Dhaka; nobody wants a careers reminder then, or a day after it was due.
  v_when    timestamptz := v_today::timestamp
                           at time zone 'Asia/Dhaka' + interval '9 hours';
begin
  for r in
    select p.id as user_id,
           -- Steps that are late, and steps due today or tomorrow. Two days
           -- rather than one so a digest is not the first the student hears
           -- of a deadline that is already tomorrow morning.
           count(*) filter (
             where t.due_date < v_today) as overdue,
           count(*) filter (
             where t.due_date between v_today and v_today + 1) as due_soon
      from public.profiles p
      join public.roadmap_tasks t on t.user_id = p.id
      join public.roadmap_milestones m on m.id = t.milestone_id
      join public.roadmaps rm on rm.id = m.roadmap_id and rm.deleted_at is null
     where p.onboarding_completed_at is not null
       and t.deleted_at is null
       and not t.is_done
       and t.due_date is not null
       and t.due_date <= v_today + 1
     group by p.id
  loop
    if r.overdue = 0 and r.due_soon = 0 then
      continue;
    end if;

    if r.overdue > 0 and r.due_soon > 0 then
      v_title := r.overdue || ' late, ' || r.due_soon || ' coming up';
      v_body  := 'Open your roadmap and move a date, or tick one off — '
                 || 'either is fine.';
    elsif r.overdue > 0 then
      v_title := case when r.overdue = 1
                      then 'One step is late'
                      else r.overdue || ' steps are late' end;
      v_body  := 'Nothing is lost. Move the date or tick it off.';
    else
      v_title := case when r.due_soon = 1
                      then 'One step is due soon'
                      else r.due_soon || ' steps are due soon' end;
      v_body  := 'A good day to get one out of the way.';
    end if;

    -- The date in the key is the cap: one digest per student per day, whatever
    -- else runs or retries. On a Monday the brief has usually taken it.
    perform public.notify(
      r.user_id,
      'step_due',
      v_title,
      v_body,
      jsonb_build_object('overdue', r.overdue, 'due_soon', r.due_soon),
      'digest:' || r.user_id || ':' || v_today,
      v_when
    );
    v_sent := v_sent + 1;
  end loop;

  return v_sent;
end $$;

-- ------------------------------------------------------- hang it off the sweep
create or replace function public.nightly_maintenance()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.documents
    where deleted_at is not null and purge_after is not null and purge_after < now();

  delete from public.jobs_queue
    where status in ('done', 'dead') and updated_at < now() - interval '7 days';

  delete from public.analytics_events where occurred_at < now() - interval '90 days';
  delete from public.error_reports    where occurred_at < now() - interval '90 days';

  -- A token the app has not refreshed in two months belongs to an install that
  -- is gone. Pushing to it wastes a job and, on FCM, earns an UNREGISTERED.
  delete from public.device_tokens where last_seen_at < now() - interval '60 days';

  perform public.reap_stuck_jobs();
  perform public.sweep_stuck_documents();

  -- Monday: the brief first, so it takes the day's one slot and the digest
  -- steps aside. Any other day the digest has the slot to itself.
  if extract(isodow from public.tack_today()) = 1 then
    perform public.enqueue_weekly_brief(false);
  end if;

  perform public.enqueue_daily_digest();
end $$;
