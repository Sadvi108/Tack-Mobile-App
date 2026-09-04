-- A profile a student can actually send to somebody.
--
-- Tack has held a whole portfolio since the first migration — projects with
-- repo URLs, certifications with credential links, skills, education,
-- activities — and shown it to nobody. Most Bangladeshi undergraduates have no
-- LinkedIn worth sending and no portfolio site, so the profile they already
-- filled in is the most useful thing Tack could hand them.
--
-- Three decisions worth stating, because each is a place this could go wrong:
--
--   1. **Off by default.** A student publishes deliberately or not at all.
--   2. **The phone number is never on the page**, under any setting. It is not
--      a toggle, because a toggle is a thing somebody can get wrong once and
--      not notice for a year. `public_profile()` does not select it.
--   3. **An unpublished handle is a 404**, not "this student is private".
--      The second confirms the handle belongs to somebody, which is exactly
--      what a person checking whether an ex-classmate is on Tack wants to
--      know.
--
-- The filtering lives here rather than in the Edge Function that renders the
-- page. In SQL it is enforced by the query; in TypeScript it would be enforced
-- by remembering to delete keys, which is the kind of thing that survives
-- review and fails in production.

-- ---------------------------------------------------------------- the handle
alter table public.profiles
  add column if not exists handle text,
  add column if not exists is_public boolean not null default false;

-- Lowercase, letter-first, no leading or trailing hyphen. Letter-first keeps
-- handles from colliding with anything that looks like an id or a version.
alter table public.profiles
  drop constraint if exists profiles_handle_shape;
alter table public.profiles
  add constraint profiles_handle_shape
  check (handle is null or handle ~ '^[a-z][a-z0-9-]{1,28}[a-z0-9]$');

create unique index if not exists profiles_handle_key
  on public.profiles(handle) where handle is not null;

comment on column public.profiles.handle is
  'The public page address. Null until the student picks one.';

-- Names the page router needs, plus the ones that would be confusing or
-- impersonating. Kept as a table rather than a constraint so it can grow
-- without a migration each time.
create table if not exists public.reserved_handles (handle text primary key);

insert into public.reserved_handles(handle) values
  ('admin'), ('administrator'), ('api'), ('app'), ('about'), ('auth'),
  ('billing'), ('blog'), ('contact'), ('dashboard'), ('help'), ('home'),
  ('login'), ('logout'), ('privacy'), ('profile'), ('profiles'), ('root'),
  ('security'), ('settings'), ('signin'), ('signup'), ('support'), ('system'),
  ('tack'), ('team'), ('terms'), ('test'), ('user'), ('users'), ('www')
on conflict do nothing;

alter table public.reserved_handles enable row level security;
alter table public.reserved_handles force row level security;

-- ------------------------------------------------------------ what is shown
create table if not exists public.public_profile_settings (
  user_id             uuid primary key references public.profiles(id) on delete cascade,
  show_education      boolean not null default true,
  show_experience     boolean not null default true,
  show_projects       boolean not null default true,
  show_skills         boolean not null default true,
  show_certifications boolean not null default true,
  show_activities     boolean not null default false,
  -- Off by default and separate from the rest: how far through a roadmap
  -- somebody is says more about how long they have been trying than about
  -- what they can do, and a student should choose to show that.
  show_roadmap        boolean not null default false,
  updated_at          timestamptz not null default now()
);

alter table public.public_profile_settings enable row level security;
alter table public.public_profile_settings force row level security;

drop policy if exists public_profile_settings_own on public.public_profile_settings;
create policy public_profile_settings_own on public.public_profile_settings
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop trigger if exists public_profile_settings_updated_at on public.public_profile_settings;
create trigger public_profile_settings_updated_at
  before update on public.public_profile_settings
  for each row execute function public.set_updated_at();

-- ------------------------------------------------------- project verification
--
-- A claim with evidence behind it is the whole difference between a CV and a
-- portfolio. `projects.repo_url` has been captured all along and never checked.
create table if not exists public.project_verifications (
  project_id    uuid primary key references public.projects(id) on delete cascade,
  provider      text not null default 'github',
  state         text not null default 'pending'
                check (state in ('pending', 'verified', 'missing', 'error')),
  stars         int,
  language      text,
  last_push_at  timestamptz,
  checked_at    timestamptz,
  error         text
);

alter table public.project_verifications enable row level security;
alter table public.project_verifications force row level security;

drop policy if exists project_verifications_own on public.project_verifications;
create policy project_verifications_own on public.project_verifications
  for select to authenticated
  using (exists (select 1 from public.projects p
                  where p.id = project_id and p.user_id = (select auth.uid())));

-- Queue a check whenever a repo url appears or changes. The page must never
-- call GitHub itself: unauthenticated it allows 60 requests an hour per IP and
-- Edge Functions share addresses, so a popular profile would rate-limit
-- everybody else's.
create or replace function public.enqueue_project_verification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.repo_url is null or trim(new.repo_url) = '' then
    delete from public.project_verifications where project_id = new.id;
    return new;
  end if;

  if tg_op = 'UPDATE' and new.repo_url is not distinct from old.repo_url then
    return new;
  end if;

  insert into public.project_verifications (project_id, state)
  values (new.id, 'pending')
  on conflict (project_id) do update set state = 'pending', error = null;

  insert into public.jobs_queue (user_id, type, payload, idempotency_key)
  values (
    new.user_id, 'verify_project',
    jsonb_build_object('project_id', new.id, 'repo_url', new.repo_url),
    'verify_project:' || new.id || ':' || md5(new.repo_url)
  )
  on conflict (idempotency_key) do nothing;

  return new;
end $$;

drop trigger if exists projects_verify_repo on public.projects;
create trigger projects_verify_repo
  after insert or update of repo_url on public.projects
  for each row execute function public.enqueue_project_verification();

-- -------------------------------------------------------------- the handle API
create or replace function public.handle_available(p_handle text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_handle ~ '^[a-z][a-z0-9-]{1,28}[a-z0-9]$'
     and not exists (select 1 from public.reserved_handles r where r.handle = p_handle)
     and not exists (select 1 from public.profiles p
                      where p.handle = p_handle and p.id <> coalesce((select auth.uid()), '00000000-0000-0000-0000-000000000000'::uuid));
$$;

grant execute on function public.handle_available(text) to authenticated;

create or replace function public.set_handle(p_handle text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := (select auth.uid());
  v_clean text := lower(trim(coalesce(p_handle, '')));
begin
  if v_uid is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;
  if not public.handle_available(v_clean) then
    raise exception 'that address is not available'
      using errcode = 'check_violation';
  end if;

  update public.profiles set handle = v_clean where id = v_uid;

  insert into public.public_profile_settings (user_id) values (v_uid)
    on conflict (user_id) do nothing;
end $$;

grant execute on function public.set_handle(text) to authenticated;

-- ---------------------------------------------------------- the page itself
--
-- Not granted to anon or authenticated. The Edge Function reads it with the
-- service client, which is what keeps "nothing of ours is anon-callable" true
-- while still serving a page to somebody who is not signed in.
create or replace function public.public_profile(p_handle text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id  uuid;
  v_set public.public_profile_settings;
  v_doc jsonb;
begin
  select p.id into v_id
    from public.profiles p
   where p.handle = lower(trim(p_handle))
     and p.is_public
     and p.deleted_at is null;

  -- Null, not an "is private" marker. Telling a caller that a handle exists
  -- but is hidden answers the question they were asking.
  if v_id is null then
    return null;
  end if;

  select * into v_set from public.public_profile_settings where user_id = v_id;
  if v_set is null then
    v_set.show_education := true;
    v_set.show_experience := true;
    v_set.show_projects := true;
    v_set.show_skills := true;
    v_set.show_certifications := true;
    v_set.show_activities := false;
    v_set.show_roadmap := false;
  end if;

  select jsonb_build_object(
    -- No phone. No email. Not a setting.
    'name', p.full_name,
    'handle', p.handle,
    'headline', coalesce(p.target_role, p.intended_field),
    'location', nullif(concat_ws(', ', c.name, co.name), ''),

    'education', case when v_set.show_education then coalesce((
      select jsonb_agg(jsonb_build_object(
        'institution', coalesce(e.university_name, e.institution_name),
        'degree', e.degree, 'field_of_study', e.field_of_study,
        'start_year', e.start_year, 'graduation_year', e.graduation_year,
        'is_current', e.is_current)
        order by e.is_current desc nulls last, e.graduation_year desc nulls last)
      from public.education e
      where e.user_id = v_id and e.deleted_at is null), '[]'::jsonb)
      else '[]'::jsonb end,

    'experiences', case when v_set.show_experience then coalesce((
      select jsonb_agg(jsonb_build_object(
        'company', x.company_name, 'title', x.title,
        'start_date', x.start_date, 'end_date', x.end_date,
        'is_current', x.is_current, 'description', x.description)
        order by x.is_current desc nulls last, x.start_date desc nulls last)
      from public.experiences x
      where x.user_id = v_id and x.deleted_at is null), '[]'::jsonb)
      else '[]'::jsonb end,

    -- The verification travels with the project, so the page can show that a
    -- repository is real without asking GitHub at render time.
    'projects', case when v_set.show_projects then coalesce((
      select jsonb_agg(jsonb_build_object(
        'title', pr.title, 'summary', pr.summary,
        'url', pr.url, 'repo_url', pr.repo_url,
        'completed_on', pr.completed_on,
        'verified', pv.state = 'verified',
        'language', pv.language, 'stars', pv.stars)
        order by pr.completed_on desc nulls first)
      from public.projects pr
      left join public.project_verifications pv on pv.project_id = pr.id
      where pr.user_id = v_id and pr.deleted_at is null), '[]'::jsonb)
      else '[]'::jsonb end,

    'certifications', case when v_set.show_certifications then coalesce((
      select jsonb_agg(jsonb_build_object(
        'title', cf.title, 'issuer', cf.issuer,
        'issued_on', cf.issued_on, 'credential_url', cf.credential_url)
        order by cf.issued_on desc nulls last)
      from public.certifications cf
      where cf.user_id = v_id and cf.deleted_at is null), '[]'::jsonb)
      else '[]'::jsonb end,

    'skills', case when v_set.show_skills then coalesce((
      select jsonb_agg(s.name order by us.proficiency desc nulls last, s.name)
      from public.user_skills us
      join public.skills s on s.id = us.skill_id
      where us.user_id = v_id), '[]'::jsonb)
      else '[]'::jsonb end,

    'activities', case when v_set.show_activities then coalesce((
      select jsonb_agg(jsonb_build_object(
        'title', a.title, 'organisation', a.organisation, 'role', a.role)
        order by a.start_date desc nulls last)
      from public.activities a
      where a.user_id = v_id and a.deleted_at is null), '[]'::jsonb)
      else '[]'::jsonb end,

    'links', coalesce((
      select jsonb_agg(jsonb_build_object('kind', pl.kind, 'url', pl.url)
                       order by pl.kind)
      from public.portfolio_links pl
      where pl.user_id = v_id and pl.deleted_at is null), '[]'::jsonb)
  ) into v_doc
  from public.profiles p
  left join public.cities c on c.id = p.city_id
  left join public.countries co on co.id = p.country_id
  where p.id = v_id;

  return v_doc;
end $$;

comment on function public.public_profile(text) is
  'The published page for a handle, or null. Never selects the phone number, '
  'under any setting. Read by the profile Edge Function as service_role.';

-- ------------------------------------------------------------------- checked
do $$
declare
  v_user uuid;
begin
  select id into v_user from public.profiles limit 1;
  if v_user is null then
    raise notice 'no profiles yet; skipping the handle checks';
    return;
  end if;

  if public.handle_available('admin') then
    raise exception 'a reserved handle was offered as available';
  end if;
  if public.handle_available('ab') then
    raise exception 'a two-character handle was accepted';
  end if;
  if public.handle_available('Has-Capitals') then
    raise exception 'an uppercase handle was accepted';
  end if;
  if public.handle_available('-leading') then
    raise exception 'a handle starting with a hyphen was accepted';
  end if;
  if not public.handle_available('rafiq-hossain') then
    raise exception 'an ordinary handle was refused';
  end if;

  -- An unpublished profile must be indistinguishable from one that does not
  -- exist.
  if public.public_profile('definitely-not-a-real-handle') is not null then
    raise exception 'an unknown handle returned a page';
  end if;
end $$;
