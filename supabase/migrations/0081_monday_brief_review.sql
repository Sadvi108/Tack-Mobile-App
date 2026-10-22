-- Review fixes for the Monday brief (0080).
--
-- 1. "Closing" means the posting closes. 0080 also read the student's own
--    next_action_date as a close date, so a reminder to call HR on Tuesday
--    became "Acme closes Tue" and the most urgent thing of the week. Closing
--    now reads jobs.closes_at alone, as the dashboard does (0077), and only
--    for an application not yet sent: once it is sent, the posting closing
--    asks nothing of the student.
-- 2. An interview-stage application's next_action_date is the student's next
--    step, not necessarily the interview. The item says the step in the
--    student's own words instead of claiming an interview on that day.
-- 3. Practice due ignored deleted sessions. interview_due() hides them, so
--    they could never be graded, and the brief would have announced them
--    every Monday forever.
-- 4. The push body is the fixed "why" line, never an item title. Titles carry
--    what the student typed — a company, a next step — and the push body
--    leaves for the phone through FCM. The titles stay in the in-app payload.
-- 5. The new-matches line said "80% of what you know", which is not what the
--    fit measures.
-- 6. The digest takes the day it is for, so its delivery time can be tested
--    exactly, and the Monday brief can no longer take the nightly sweep down
--    with it: an error in the brief is caught and logged, and the cleanup and
--    the digest still run.
-- 7. Digest pushes queued by 0066 for the morning after the morning they
--    meant are dropped. Left, they would land at 09:00 alongside the first
--    correctly-timed digest: two pushes in one morning. Their inbox rows were
--    written when they were queued and stay.

-- --------------------------------------------------------------- 1, 2, 3, 5
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
             when a.status = 'saved'
              and j.closes_at between p_today and p_today + 3
               then array['closing']
             when a.status = 'interview'
              and a.next_action_date between p_today and p_today + 7
               then array['interview']
           end as reasons,
           case when a.status = 'interview' then a.next_action_date
                else j.closes_at end as on_date,
           coalesce(nullif(trim(j.company_name), ''), j.title) as name,
           nullif(trim(a.next_action), '') as step,
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
           null::text as step,
           count(*) filter (where not is_done and due_date < p_today) as n
      from tasks
  ),
  practice as (
    select 'practice'::text as kind,
           null::text as ref,
           array['practice_due'] as reasons,
           min(r.due_on) as on_date,
           null::text as name,
           null::text as step,
           count(*) as n
      from public.interview_reviews r
      join public.interview_questions q on q.id = r.question_id
      join public.interview_sessions s on s.id = q.session_id
     where r.user_id = p_user
       and r.due_on <= p_today
       -- What interview_due() shows: a deleted session's questions are gone.
       and s.deleted_at is null
    having count(*) > 0
  ),
  matches as (
    select 'matches'::text as kind,
           null::text as ref,
           array['new_matches'] as reasons,
           null::date as on_date,
           null::text as name,
           null::text as step,
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
             when 'interview'    then name || ': ' || coalesce(step, 'next step')
                                      || ', ' || to_char(on_date, 'Dy DD Mon')
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
                                           else 'Your skills cover most of what each one asks for.' end
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

-- ------------------------------------------------------------------------ 4
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
        -- Fixed copy only: this text leaves for the phone through FCM, and
        -- the item titles hold what the student typed.
        v_items -> 0 ->> 'why',
        jsonb_build_object('items', v_items),
        'digest:' || r.id || ':' || p_today,
        v_when
      );
    end if;
  end loop;

  return v_out;
end $$;

-- ------------------------------------------------------------------------ 6
drop function if exists public.enqueue_daily_digest();

create or replace function public.enqueue_daily_digest(
  p_today date default public.tack_today()
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  r         record;
  v_today   date := p_today;
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

revoke all on function public.enqueue_daily_digest(date) from public, anon, authenticated;

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
  -- steps aside. Its own block, so a fault in the brief costs the brief and
  -- nothing else: the cleanup above and the digest below still happen.
  if extract(isodow from public.tack_today()) = 1 then
    begin
      perform public.enqueue_weekly_brief(false);
    exception when others then
      raise warning 'weekly brief failed: %', sqlerrm;
    end;
  end if;

  perform public.enqueue_daily_digest();
end $$;

-- ------------------------------------------------------------------------ 7
-- The key's date is the day the digest was for; 0066 queued the push for the
-- morning after it. Only those are dropped.
delete from public.jobs_queue
 where type = 'send_push'
   and status = 'pending'
   and idempotency_key like 'push:digest:%'
   and (run_after at time zone 'Asia/Dhaka')::date
       > split_part(idempotency_key, ':', 4)::date;
