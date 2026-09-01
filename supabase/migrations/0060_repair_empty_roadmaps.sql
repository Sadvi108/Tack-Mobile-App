-- A roadmap with no milestones is a failed generation, not a roadmap.
--
-- The old client-side generateFromPath was four sequential round trips with no
-- transaction: insert the roadmap, read the template milestones, insert them,
-- read the template tasks, insert those. A phone that lost the connection
-- after the first write left a roadmaps row with nothing under it — and the
-- idempotency guard then found that row and returned it forever, so the
-- student could never generate the roadmap again. The screen showed "0 of 0
-- steps done" and there was no way back.
--
-- One such roadmap exists in production right now: a "Content writer" roadmap
-- with zero milestones and zero tasks, which is also why that path was being
-- reported as the student's target on the dashboard.
--
-- 0058 made generation transactional so this cannot recur. This makes the
-- guard able to recognise the wreckage the old version left, and clears what
-- is already there.

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

  -- Retire any half-built roadmap for this path before looking for a real one,
  -- so the guard below cannot hand back a shell.
  update public.roadmaps r
     set deleted_at = now()
   where r.user_id = v_uid
     and r.path_id = p_path_id
     and r.deleted_at is null
     and not exists (
       select 1 from public.roadmap_milestones m where m.roadmap_id = r.id
     );

  select id into v_roadmap
    from public.roadmaps
   where user_id = v_uid and path_id = p_path_id and deleted_at is null;
  if v_roadmap is not null then
    return v_roadmap;
  end if;

  v_today := public.tack_today();
  select p.expected_graduation into v_graduation
    from public.profiles p where p.id = v_uid;

  if v_graduation is not null and v_graduation <= v_today then
    v_graduation := null;
  end if;

  insert into public.roadmaps (user_id, path_id, title, origin)
    values (v_uid, p_path_id, v_path.title, 'template')
    returning id into v_roadmap;

  select count(*) into v_milestones
    from public.career_path_milestones where path_id = p_path_id;

  insert into public.roadmap_milestones (
    roadmap_id, user_id, source_milestone_id, order_index,
    title, description, unlock_text, typical_semester, state
  )
  select v_roadmap, v_uid, m.id, m.order_index,
         m.title, m.description, m.unlock_text, m.typical_semester, 'locked'
    from public.career_path_milestones m
   where m.path_id = p_path_id;

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

  perform public.recompute_milestone_states(v_roadmap);

  -- A roadmap that arrived empty is worse than no roadmap, and the guard above
  -- would hand it back forever. Fail loudly instead, and let the transaction
  -- take the shell with it.
  if not exists (select 1 from public.roadmap_milestones where roadmap_id = v_roadmap) then
    raise exception 'that career path has no milestones to build from'
      using errcode = 'no_data_found';
  end if;

  return v_roadmap;
end $$;

revoke all on function public.generate_roadmap(uuid) from public, anon;
grant execute on function public.generate_roadmap(uuid) to authenticated;


-- Clear the wreckage the old client-side generator left behind.
update public.roadmaps r
   set deleted_at = now()
 where r.deleted_at is null
   and not exists (
     select 1 from public.roadmap_milestones m where m.roadmap_id = r.id
   );
