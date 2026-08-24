-- Reference: the skill vocabulary. Shared by every user, written only by seeds.
create table public.skills (
  id         uuid primary key default gen_random_uuid(),
  slug       text not null unique,
  name       text not null,
  category   text not null default 'general',
  aliases    text[] not null default '{}',
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);
create index skills_name_trgm on public.skills using gin (name gin_trgm_ops);
create index skills_category_idx on public.skills(category) where is_active;

create table public.user_skills (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  skill_id    uuid not null references public.skills(id) on delete cascade,
  proficiency int not null default 2 check (proficiency between 1 and 5),
  source      skill_source not null default 'self',
  evidence    text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (user_id, skill_id)
);
create index user_skills_user_idx on public.user_skills(user_id);
create trigger user_skills_updated_at before update on public.user_skills
  for each row execute function public.set_updated_at();

create table public.course_skills (
  course_id uuid not null references public.courses(id) on delete cascade,
  skill_id  uuid not null references public.skills(id) on delete cascade,
  primary key (course_id, skill_id)
);

-- Reference: hand-written career paths. No AI involved in producing these.
create table public.career_paths (
  id                  uuid primary key default gen_random_uuid(),
  slug                text not null unique,
  title               text not null,
  summary             text not null,
  category            text not null default 'general',
  salary_min_bdt      int,
  salary_max_bdt      int,
  months_to_job_ready int,
  demand_level        text check (demand_level in ('low','moderate','high','very high')),
  day_to_day          text[] not null default '{}',
  good_fit_if         text[] not null default '{}',
  sort_order          int not null default 100,
  is_active           boolean not null default true,
  created_at          timestamptz not null default now()
);

create table public.career_path_skills (
  path_id    uuid not null references public.career_paths(id) on delete cascade,
  skill_id   uuid not null references public.skills(id) on delete cascade,
  importance skill_importance not null default 'important',
  primary key (path_id, skill_id)
);

create table public.career_path_milestones (
  id               uuid primary key default gen_random_uuid(),
  path_id          uuid not null references public.career_paths(id) on delete cascade,
  order_index      int not null,
  title            text not null,
  description      text,
  unlock_text      text,
  typical_semester int,
  unique (path_id, order_index)
);

create table public.career_path_tasks (
  id            uuid primary key default gen_random_uuid(),
  milestone_id  uuid not null references public.career_path_milestones(id) on delete cascade,
  order_index   int not null,
  title         text not null,
  type          task_type not null default 'skill',
  points        int not null default 2,
  est_minutes   int,
  skill_id      uuid references public.skills(id) on delete set null,
  unique (milestone_id, order_index)
);

-- A student may follow at most two paths; enforced by trigger below.
create table public.user_career_paths (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  path_id     uuid not null references public.career_paths(id) on delete cascade,
  is_primary  boolean not null default false,
  selected_at timestamptz not null default now(),
  deleted_at  timestamptz,
  unique (user_id, path_id)
);
create index user_career_paths_user_idx on public.user_career_paths(user_id) where deleted_at is null;

create or replace function public.enforce_max_two_paths()
returns trigger
language plpgsql
as $$
declare n int;
begin
  select count(*) into n
    from public.user_career_paths
    where user_id = new.user_id and deleted_at is null and id <> new.id;
  if n >= 2 then
    raise exception 'a student may follow at most two career paths'
      using errcode = 'check_violation';
  end if;
  return new;
end $$;

create trigger user_career_paths_max_two
  before insert or update on public.user_career_paths
  for each row when (new.deleted_at is null)
  execute function public.enforce_max_two_paths();
