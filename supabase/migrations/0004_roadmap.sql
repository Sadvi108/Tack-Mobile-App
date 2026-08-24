-- A roadmap is a student's own copy of a path template, so edits never mutate the template.
create table public.roadmaps (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,
  path_id      uuid references public.career_paths(id) on delete set null,
  title        text not null,
  origin       roadmap_origin not null default 'template',
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);
create index roadmaps_user_idx on public.roadmaps(user_id) where deleted_at is null;
create unique index roadmaps_one_per_path on public.roadmaps(user_id, path_id) where deleted_at is null;
create trigger roadmaps_updated_at before update on public.roadmaps
  for each row execute function public.set_updated_at();

create table public.roadmap_milestones (
  id                  uuid primary key default gen_random_uuid(),
  roadmap_id          uuid not null references public.roadmaps(id) on delete cascade,
  user_id             uuid not null references public.profiles(id) on delete cascade,
  source_milestone_id uuid references public.career_path_milestones(id) on delete set null,
  order_index         int not null,
  title               text not null,
  description         text,
  unlock_text         text,
  typical_semester    int,
  state               milestone_state not null default 'locked',
  completed_at        timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (roadmap_id, order_index)
);
create index roadmap_milestones_user_idx on public.roadmap_milestones(user_id, roadmap_id);
create trigger roadmap_milestones_updated_at before update on public.roadmap_milestones
  for each row execute function public.set_updated_at();

create table public.roadmap_tasks (
  id             uuid primary key default gen_random_uuid(),
  milestone_id   uuid not null references public.roadmap_milestones(id) on delete cascade,
  user_id        uuid not null references public.profiles(id) on delete cascade,
  order_index    int not null default 0,
  title          text not null,
  type           task_type not null default 'skill',
  points         int not null default 2,
  est_minutes    int,
  skill_id       uuid references public.skills(id) on delete set null,
  due_date       date,
  is_done        boolean not null default false,
  done_at        timestamptz,
  is_custom      boolean not null default false,
  -- When two paths share a task, this lists every roadmap it counts toward.
  shared_with_roadmaps uuid[] not null default '{}',
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz
);
create index roadmap_tasks_milestone_idx on public.roadmap_tasks(milestone_id, order_index) where deleted_at is null;
create index roadmap_tasks_user_due_idx on public.roadmap_tasks(user_id, due_date) where deleted_at is null and is_done = false;
create trigger roadmap_tasks_updated_at before update on public.roadmap_tasks
  for each row execute function public.set_updated_at();

-- Keeps done_at honest without trusting the client.
create or replace function public.stamp_task_done()
returns trigger
language plpgsql
as $$
begin
  if new.is_done and not coalesce(old.is_done, false) then
    new.done_at := now();
  elsif not new.is_done then
    new.done_at := null;
  end if;
  return new;
end $$;

create trigger roadmap_tasks_done_stamp
  before insert or update of is_done on public.roadmap_tasks
  for each row execute function public.stamp_task_done();

-- A milestone becomes completed the moment its last live task is done, and
-- the next locked milestone in the same roadmap opens.
create or replace function public.advance_milestone_state()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  m_id uuid := coalesce(new.milestone_id, old.milestone_id);
  r_id uuid;
  m_order int;
  remaining int;
begin
  select roadmap_id, order_index into r_id, m_order
    from public.roadmap_milestones where id = m_id;

  select count(*) into remaining
    from public.roadmap_tasks
    where milestone_id = m_id and deleted_at is null and is_done = false;

  if remaining = 0 then
    update public.roadmap_milestones
      set state = 'completed', completed_at = coalesce(completed_at, now())
      where id = m_id and state <> 'completed';

    update public.roadmap_milestones
      set state = 'active'
      where roadmap_id = r_id and order_index = m_order + 1 and state = 'locked';
  else
    update public.roadmap_milestones
      set state = 'active', completed_at = null
      where id = m_id and state = 'completed';
  end if;

  return null;
end $$;

create trigger roadmap_tasks_advance_milestone
  after insert or update of is_done, deleted_at or delete on public.roadmap_tasks
  for each row execute function public.advance_milestone_state();
