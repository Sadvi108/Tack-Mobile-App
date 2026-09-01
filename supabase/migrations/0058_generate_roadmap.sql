-- A roadmap shaped by what the student already told us.
--
-- Until now every student following the same path received a byte-identical
-- copy of the template: generateFromPath ran four client round trips and read
-- nothing at all about the person. A final-year who already ships React apps
-- was locked out of everything past "Learn the three basics" until they ticked
-- all six of them.
--
-- The 261 hand-written tasks stay exactly as written — they are the best
-- content in this product and no generator improves on "get the page loading
-- in under 3 seconds on 3G". What changes is which of them a given student is
-- handed, when they are due, and where the roadmap opens.
--
-- Generation moves into one transactional function for the same reason the
-- dashboard and radar did: four sequential writes from a phone on a Dhaka 3G
-- connection is four chances to half-build a roadmap, and the idempotency
-- guard then cached the broken one forever.

-- How many template steps were dropped because the student already had the
-- skill. Kept so the screen can say so out loud — a roadmap that is quietly
-- shorter than someone else's looks like a bug, not a courtesy.
alter table public.roadmaps
  add column if not exists skipped_count int not null default 0;


-- Recompute every milestone state in one roadmap, in one pass.
--
-- Replaces the per-row trigger that only ever advanced one step and never
-- reversed. Un-ticking a task re-opened its own milestone but left the *next*
-- one unlocked, so progress was a ratchet: a real roadmap in production is
-- sitting at milestone 1 two-of-six done with milestone 2 also active.
--
-- Stating the whole roadmap at once is also the only version that is correct
-- after generation, where several leading milestones can be complete before
-- the student has done anything.
create or replace function public.recompute_milestone_states(p_roadmap_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Done is done: a milestone with no live unfinished task is completed.
  update public.roadmap_milestones m
     set state = 'completed',
         completed_at = coalesce(m.completed_at, now())
   where m.roadmap_id = p_roadmap_id
     and not exists (
       select 1 from public.roadmap_tasks t
        where t.milestone_id = m.id and t.deleted_at is null and not t.is_done
     )
     -- A milestone with no tasks at all is not "complete", it is empty. The
     -- old trigger counted zero unfinished tasks and marked it done, so
     -- deleting the last step in a milestone finished it and opened the next.
     and exists (
       select 1 from public.roadmap_tasks t
        where t.milestone_id = m.id and t.deleted_at is null
     );

  -- Everything with work left is locked, then exactly one is re-opened below.
  update public.roadmap_milestones m
     set state = 'locked', completed_at = null
   where m.roadmap_id = p_roadmap_id
     and exists (
       select 1 from public.roadmap_tasks t
        where t.milestone_id = m.id and t.deleted_at is null and not t.is_done
     );

  -- The earliest milestone with work left is where the student is.
  update public.roadmap_milestones
     set state = 'active'
   where id = (
     select m.id
       from public.roadmap_milestones m
      where m.roadmap_id = p_roadmap_id and m.state = 'locked'
      order by m.order_index
      limit 1
   );
end $$;

revoke all on function public.recompute_milestone_states(uuid) from public, anon, authenticated;


-- The trigger now defers to the whole-roadmap recompute.
--
-- Still per row, because that is when we learn a task changed, but the work it
-- does is idempotent and self-correcting rather than a single forward step.
create or replace function public.advance_milestone_state()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  m_id uuid := coalesce(new.milestone_id, old.milestone_id);
  r_id uuid;
begin
  -- Set by generate_roadmap while it bulk-inserts ~29 tasks. Without it the
  -- trigger runs a count-and-update cycle per row, 29 times, for a state it
  -- computes once at the end anyway.
  if coalesce(current_setting('tack.skip_milestone_advance', true), '') = 'on' then
    return null;
  end if;

  select roadmap_id into r_id from public.roadmap_milestones where id = m_id;
  if r_id is null then return null; end if;

  perform public.recompute_milestone_states(r_id);
  return null;
end $$;


-- Builds a roadmap for the caller from a career path template.
--
-- Everything below is deterministic. No model is involved, and the same
-- student with the same skills and the same graduation date gets the same
-- roadmap twice — which matters because roadmap_progress feeds the readiness
-- score, and a score built on a wobbling denominator is not a score.
create or replace function public.generate_roadmap(p_path_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid        uuid := (select auth.uid());
  v_path       record;
  v_roadmap    uuid;
  v_graduation date;
  v_today      date;
  v_milestones int;
  v_skipped    int := 0;
begin
  if v_uid is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;

  select id, title into v_path
    from public.career_paths where id = p_path_id and is_active;
  if not found then
    raise exception 'that career path is not available' using errcode = 'no_data_found';
  end if;

  -- Idempotent, and matched by the roadmaps_one_per_path unique index so two
  -- taps on a slow connection cannot make two roadmaps.
  select id into v_roadmap
    from public.roadmaps
   where user_id = v_uid and path_id = p_path_id and deleted_at is null;
  if v_roadmap is not null then
    return v_roadmap;
  end if;

  v_today := public.tack_today();
  select p.expected_graduation into v_graduation
    from public.profiles p where p.id = v_uid;

  -- Dates are only offered when the student told us when they finish. An
  -- invented deadline is worse than none: it is a date they will miss for no
  -- reason.
  if v_graduation is not null and v_graduation <= v_today then
    v_graduation := null;
  end if;

  insert into public.roadmaps (user_id, path_id, title, origin)
    values (v_uid, p_path_id, v_path.title, 'template')
    returning id into v_roadmap;

  select count(*) into v_milestones
    from public.career_path_milestones where path_id = p_path_id;

  -- Milestones are copied whole. Which of them is open is decided at the end,
  -- from what actually survived the skip rules.
  insert into public.roadmap_milestones (
    roadmap_id, user_id, source_milestone_id, order_index,
    title, description, unlock_text, typical_semester, state
  )
  select v_roadmap, v_uid, m.id, m.order_index,
         m.title, m.description, m.unlock_text, m.typical_semester, 'locked'
    from public.career_path_milestones m
   where m.path_id = p_path_id;

  -- Tasks, minus the ones this student has demonstrably outgrown.
  --
  -- A task is skipped only when it is a "learn X" step (type = 'skill'), it
  -- names the skill it teaches, and the student holds that skill at
  -- proficiency 3 or better. Onboarding writes a flat proficiency of 2 for
  -- everything a student ticks off a list, so 2 means "I have heard of it" and
  -- is far too weak to cancel a learning step.
  --
  -- A project task keeps its place even when the skill is known: having HTML
  -- on a profile is not the same as having built anything with it, and the
  -- portfolio is what an employer actually reads.
  set local tack.skip_milestone_advance = 'on';

  with mine as (
    select skill_id from public.user_skills
     where user_id = v_uid and proficiency >= 3
  ),
  src as (
    select t.*, rm.id as target_milestone, rm.order_index as milestone_order
      from public.career_path_tasks t
      join public.career_path_milestones cm on cm.id = t.milestone_id
      join public.roadmap_milestones rm
        on rm.roadmap_id = v_roadmap and rm.source_milestone_id = cm.id
     where cm.path_id = p_path_id
  ),
  kept as (
    select s.*,
           row_number() over (
             partition by s.target_milestone order by s.order_index
           ) as nth,
           count(*) over (partition by s.target_milestone) as of_many
      from src s
     where not (
       s.type = 'skill'
       and s.skill_id is not null
       and s.skill_id in (select skill_id from mine)
     )
  )
  insert into public.roadmap_tasks (
    milestone_id, user_id, order_index, title, type, points,
    est_minutes, skill_id, due_date, shared_with_roadmaps
  )
  select k.target_milestone, v_uid, k.order_index, k.title, k.type, k.points,
         k.est_minutes, k.skill_id,
         -- Milestones divide the time the student actually has left, and each
         -- task is spread inside its own milestone's slice rather than sharing
         -- one date with its five siblings. Six steps all due the same Tuesday
         -- reads as a wall; six steps a fortnight apart reads as a plan, and
         -- the dashboard timeline shows them one at a time instead of six
         -- identical rows.
         --
         -- A final-year with four months gets tight dates and a first-year
         -- gets spacious ones, from one template.
         case when v_graduation is null then null
              else v_today + (
                (v_graduation - v_today) * (
                  k.milestone_order::numeric
                  + (k.nth::numeric / greatest(k.of_many, 1))
                ) / greatest(v_milestones, 1)
              )::int
         end,
         array[v_roadmap]
    from kept k;

  select count(*) into v_skipped
    from public.career_path_tasks t
    join public.career_path_milestones cm on cm.id = t.milestone_id
   where cm.path_id = p_path_id
     and t.type = 'skill'
     and t.skill_id is not null
     and t.skill_id in (
       select skill_id from public.user_skills
        where user_id = v_uid and proficiency >= 3
     );

  update public.roadmaps set skipped_count = v_skipped where id = v_roadmap;

  set local tack.skip_milestone_advance = 'off';

  -- One pass, once, now that we know what survived.
  perform public.recompute_milestone_states(v_roadmap);

  return v_roadmap;
end $$;

revoke all on function public.generate_roadmap(uuid) from public, anon;
grant execute on function public.generate_roadmap(uuid) to authenticated;


-- Repair the roadmaps already carrying the ratchet's damage.
do $$
declare r record;
begin
  for r in select id from public.roadmaps where deleted_at is null loop
    perform public.recompute_milestone_states(r.id);
  end loop;
end $$;


do $$
begin
  if not has_function_privilege('authenticated', 'public.generate_roadmap(uuid)', 'EXECUTE') then
    raise exception 'generate_roadmap is not callable by a signed-in student';
  end if;
  if has_function_privilege('anon', 'public.generate_roadmap(uuid)', 'EXECUTE') then
    raise exception 'generate_roadmap must not be reachable with the anon key alone';
  end if;
  if has_function_privilege('authenticated', 'public.recompute_milestone_states(uuid)', 'EXECUTE') then
    raise exception 'recompute_milestone_states takes a roadmap id and must stay definer-only';
  end if;
end $$;
