-- A question pool for every role, a role chosen from the student's own data,
-- and a free way to start practising.
--
-- Until now interview practice had one fixed set of five questions per role,
-- type and difficulty (0069), for ten software and business roles. A civil
-- engineering student practised "Management trainee" questions or nothing, a
-- student who practised twice got the same five questions twice, and a role
-- outside the ten sent the interview function to a model, which cost one of
-- the student's daily AI actions for questions nobody had checked.
--
-- This adds the shape that fixes all three. 0098 fills it; this file only
-- builds it, so it is safe to apply before any content exists.
--
--   * interview_roles: the roles a student can practise, each in a career
--     field, one of them the field's default. interview_role_aliases holds
--     the names job ads use ("sqa", "mto"), interview_role_paths maps catalog
--     career paths that have no role of their own onto the nearest one.
--   * interview_pool_questions: fifteen hand-written questions per role (five
--     per tier) and one behavioural pool shared by every role, each with the
--     key points a strong answer covers. Questions never come from a model any
--     more: a role with no pool resolves to the nearest role that has one.
--   * interview_draw(): picks a session from the pool. Variety comes from the
--     pool, not from a model: the draw prefers questions this student has not
--     seen in the last ninety days, so a second session is a new interview.
--   * start_practice_session(): the whole start in one call, in one
--     transaction, with no model and no quota. Practice is free.
--   * interview_resolve_role_for() / interview_catalog(): which role to
--     suggest, from the student's path, target role or field, in that order,
--     with a reason the app can show ("Closest match in Civil engineering").
--
-- The seed guard. interview_question_bank keeps serving old app builds, and
-- the worker still writes model sets into it for jobs queued before this
-- round. A model set must never replace a hand-written one. The worker's
-- PostgREST upsert names only its payload columns in ON CONFLICT ... DO
-- UPDATE, so `new.source` would still read 'seed' and a comparison of it
-- proves nothing. Instead a BEFORE UPDATE trigger skips every update to a
-- seed row unless the transaction set `tack.seeding = 'on'`, which only a
-- seed migration does (0098, for its own transaction only). This file never
-- sets it outside its own checks.

-- ------------------------------------------------------------- 1. the roles
create table if not exists public.interview_roles (
  slug             text primary key check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  title            text not null check (length(title) between 3 and 60),
  cluster          text not null check (cluster in ('software','engineering','rmg',
                     'business','pharma_development','creative_public')),
  field_slug       text not null references public.career_fields(slug),
  summary          text not null default '' check (length(summary) <= 160),
  is_field_default boolean not null default false,
  sort_order       int not null default 100,
  is_active        boolean not null default true,
  created_at       timestamptz not null default now()
);
create unique index if not exists interview_roles_field_default
  on public.interview_roles(field_slug) where is_field_default and is_active;
create index if not exists interview_roles_field_idx
  on public.interview_roles(field_slug);

comment on table public.interview_roles is
  'Roles a student can practise an interview for, one default per career '
  'field. Reference data written only by seed migrations (0098).';

create table if not exists public.interview_role_aliases (
  alias     text primary key check (alias = lower(btrim(alias)) and length(alias) between 2 and 60),
  role_slug text not null references public.interview_roles(slug) on delete cascade
);
create index if not exists interview_role_aliases_role_idx
  on public.interview_role_aliases(role_slug);

comment on table public.interview_role_aliases is
  'Other names for a role, as job ads write them ("sqa", "mto"). Lower case.';

create table if not exists public.interview_role_paths (
  path_slug text primary key references public.career_paths(slug) on delete cascade,
  role_slug text not null references public.interview_roles(slug) on delete cascade
);
create index if not exists interview_role_paths_role_idx
  on public.interview_role_paths(role_slug);

comment on table public.interview_role_paths is
  'Career paths with no role of their own, mapped onto the nearest role.';

create table if not exists public.interview_pool_questions (
  id          uuid primary key,                 -- uuid5 from build.py, stable across runs
  role_slug   text references public.interview_roles(slug) on delete cascade,
  kind        text not null check (kind in ('behavioural', 'role')),
  difficulty  difficulty_level not null,
  category    text not null check (category ~ '^[A-Z0-9][A-Za-z0-9 +&/''-]{1,29}$'),
  question    text not null check (length(question) between 12 and 240),
  key_points  jsonb not null default '[]'::jsonb
                check (jsonb_typeof(key_points) = 'array' and jsonb_array_length(key_points) <= 4),
  source_url  text check (source_url is null or source_url ~ '^https://'),
  sort_order  int not null default 0,           -- authoring order within the role
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  check ((kind = 'behavioural') = (role_slug is null))
);
create unique index if not exists interview_pool_questions_text
  on public.interview_pool_questions (coalesce(role_slug, ''), lower(question));
create index if not exists interview_pool_questions_draw
  on public.interview_pool_questions (role_slug, kind, difficulty) where is_active;

comment on table public.interview_pool_questions is
  'Hand-written interview questions: fifteen per role and one shared '
  'behavioural pool, each with the key points a strong answer covers. Written '
  'only by seed migrations; never by the worker and never by a model.';

-- Reference data: any signed-in student reads it, nobody but a migration
-- writes it.
alter table public.interview_roles enable row level security;
alter table public.interview_roles force row level security;
drop policy if exists interview_roles_select_all on public.interview_roles;
create policy interview_roles_select_all on public.interview_roles
  for select to authenticated using (true);
revoke insert, update, delete, truncate on public.interview_roles from anon, authenticated;

alter table public.interview_role_aliases enable row level security;
alter table public.interview_role_aliases force row level security;
drop policy if exists interview_role_aliases_select_all on public.interview_role_aliases;
create policy interview_role_aliases_select_all on public.interview_role_aliases
  for select to authenticated using (true);
revoke insert, update, delete, truncate on public.interview_role_aliases from anon, authenticated;

alter table public.interview_role_paths enable row level security;
alter table public.interview_role_paths force row level security;
drop policy if exists interview_role_paths_select_all on public.interview_role_paths;
create policy interview_role_paths_select_all on public.interview_role_paths
  for select to authenticated using (true);
revoke insert, update, delete, truncate on public.interview_role_paths from anon, authenticated;

alter table public.interview_pool_questions enable row level security;
alter table public.interview_pool_questions force row level security;
drop policy if exists interview_pool_questions_select_all on public.interview_pool_questions;
create policy interview_pool_questions_select_all on public.interview_pool_questions
  for select to authenticated using (true);
revoke insert, update, delete, truncate on public.interview_pool_questions from anon, authenticated;


-- ------------------------------------------------------ 2. the new columns
--
-- A session remembers its role's slug as well as its title. `role` keeps the
-- title, so history, interview_due().role, the application checklist (0082,
-- 0083) and coach_context() read exactly what they read before.
alter table public.interview_sessions
  add column if not exists role_slug text references public.interview_roles(slug) on delete set null;
create index if not exists interview_sessions_role_slug_idx
  on public.interview_sessions(role_slug) where role_slug is not null;

-- A question remembers which pool question it was, so the next draw can avoid
-- it, and carries its key points, so the free self-check works offline.
-- self_check is what the student ticked: {"covered": [0, 2], "total": 4}. The
-- existing interview_questions_update policy already lets the owner write
-- their own row, and the 0078 trigger queues the answer for Practise again.
alter table public.interview_questions
  add column if not exists pool_question_id uuid
    references public.interview_pool_questions(id) on delete set null,
  add column if not exists key_points jsonb not null default '[]'::jsonb
    check (jsonb_typeof(key_points) = 'array' and jsonb_array_length(key_points) <= 4),
  add column if not exists self_check jsonb
    check (self_check is null or jsonb_typeof(self_check) = 'object');
create index if not exists interview_questions_user_pool_idx
  on public.interview_questions(user_id, pool_question_id) where pool_question_id is not null;

-- Where each fixed set came from. The ten roles 0069 seeded by hand are seed;
-- anything else in the table was written by the worker from a model.
alter table public.interview_question_bank
  add column if not exists source text not null default 'model'
    check (source in ('seed', 'model'));
update public.interview_question_bank set source = 'seed'
 where role_slug in ('frontend-developer','backend-developer','data-analyst','digital-marketer',
   'hr-executive','business-analyst','graphic-designer','qa-engineer','accountant','content-writer')
   and source <> 'seed';


-- ---------------------------------------------------------- 3. the seed guard
create or replace function public.interview_bank_keep_seed()
returns trigger language plpgsql set search_path = public as $$
begin
  -- A model-written set never replaces a hand-written one. Only a seed
  -- migration, which turns tack.seeding on for its own transaction, may change
  -- a seed row.
  if old.source = 'seed'
     and coalesce(current_setting('tack.seeding', true), '') <> 'on' then
    return null;
  end if;
  return new;
end $$;
revoke all on function public.interview_bank_keep_seed() from public, anon, authenticated;
drop trigger if exists interview_bank_keep_seed on public.interview_question_bank;
create trigger interview_bank_keep_seed before update on public.interview_question_bank
  for each row execute function public.interview_bank_keep_seed();


-- -------------------------------------------------------------- 4. helpers
--
-- A role name as a slug. The same rule as `slugify` in
-- supabase/seed/interview_bank/validate.py and `slugifyRole` in
-- supabase/functions/_shared/interview/bank.ts; the three are held equal by
-- the checks at the bottom and by their own tests. Anything that is not a
-- latin letter or digit becomes a hyphen, so a Bangla name slugs to ''.
create or replace function public.interview_slug(p_text text)
returns text
language sql
immutable
set search_path = public
as $$
  select trim(both '-' from
           regexp_replace(lower(btrim(coalesce(p_text, ''))), '[^a-z0-9]+', '-', 'g'));
$$;
revoke all on function public.interview_slug(text) from public, anon, authenticated;

-- The tiers of an n-question session, easiest first. An easy interview still
-- ends on medium and a hard one still opens on medium, as 0069's sets did:
-- n = 5 gives E,E,E,M,M · E,M,M,M,H · M,M,H,H,H.
create or replace function public.interview_slots(p_difficulty difficulty_level, p_count int)
returns difficulty_level[]
language plpgsql
immutable
set search_path = public
as $$
declare
  n    int := greatest(coalesce(p_count, 0), 0);
  n_e  int;
  n_h  int;
begin
  n_e := round(n * case p_difficulty when 'easy' then 0.6 when 'medium' then 0.2 else 0 end);
  n_h := round(n * case p_difficulty when 'hard' then 0.6 when 'medium' then 0.2 else 0 end);
  return array_fill('easy'::difficulty_level, array[n_e])
      || array_fill('medium'::difficulty_level, array[n - n_e - n_h])
      || array_fill('hard'::difficulty_level, array[n_h]);
end $$;
revoke all on function public.interview_slots(difficulty_level, int) from public, anon, authenticated;


-- ------------------------------------------------------ 5. role resolution
--
-- None of this calls a model, and none of it guesses: a role is found by its
-- own name, an alias, a career path, or the default of a field.

-- A catalog career path's role: a role with the path's own slug, else the
-- role the path is mapped to, else its field's default (`how` = 'field').
create or replace function public.interview_role_for_path(p_path_slug text)
returns table(role_slug text, how text)
language sql
stable
security definer
set search_path = public
as $$
  select hit.role_slug, hit.how
    from (
      select r.slug as role_slug, 'path'::text as how, 1 as prio
        from public.interview_roles r
       where r.slug = p_path_slug and r.is_active
      union all
      select r.slug, 'path', 2
        from public.interview_role_paths rp
        join public.interview_roles r on r.slug = rp.role_slug and r.is_active
       where rp.path_slug = p_path_slug
      union all
      select r.slug, 'field', 3
        from public.career_paths cp
        join public.career_fields f on f.id = cp.field_id
        join public.interview_roles r
          on r.field_slug = f.slug and r.is_field_default and r.is_active
       where cp.slug = p_path_slug
    ) hit
   order by hit.prio
   limit 1;
$$;
revoke all on function public.interview_role_for_path(text) from public, anon, authenticated;

-- Free text, as a student or an old app build writes a role: its slug or
-- title (`exact`), an alias (`alias`), or a catalog path's slug or title
-- (then `path` or `field`, from interview_role_for_path). "Not sure yet" and
-- friends are not a role.
create or replace function public.interview_role_from_text(p_text text)
returns table(role_slug text, how text)
language sql
stable
security definer
set search_path = public
as $$
  with q as (
    select t.txt, public.interview_slug(t.txt) as slug
      from (select regexp_replace(lower(btrim(coalesce(p_text, ''))), '\s+', ' ', 'g') as txt) t
     where t.txt not in ('', 'undecided', 'not sure', 'not sure yet', 'none')
  ),
  hit as (
    select r.slug as role_slug, 'exact'::text as how, 1 as prio, 0 as sub, r.slug as tie
      from q
      join public.interview_roles r
        on r.is_active and (r.slug = q.slug or lower(r.title) = q.txt)
    union all
    select r.slug, 'alias', 2, 0, a.alias
      from q
      join public.interview_role_aliases a on a.alias = q.txt
      join public.interview_roles r on r.slug = a.role_slug and r.is_active
    union all
    -- "UI-UX designer" is the alias "ui ux designer" written differently.
    select r.slug, 'alias', 2, 1, a.alias
      from q
      join public.interview_role_aliases a
        on q.slug <> '' and public.interview_slug(a.alias) = q.slug
      join public.interview_roles r on r.slug = a.role_slug and r.is_active
    union all
    select x.role_slug, x.how, 3, case when cp.slug = q.slug then 0 else 1 end, cp.slug
      from q
      join public.career_paths cp
        on cp.is_active and (cp.slug = q.slug or lower(cp.title) = q.txt)
      cross join lateral public.interview_role_for_path(cp.slug) x
  )
  select hit.role_slug, hit.how
    from hit
   order by hit.prio, hit.sub, hit.tie
   limit 1;
$$;
revoke all on function public.interview_role_from_text(text) from public, anon, authenticated;

-- The role to suggest to one student, and why. First hit wins:
--   1. the hint the caller passed (an old app's free-text role)
--   2. the student's primary career path        -> your_path or your_field
--   3. career_preferences.target_role           -> your_target or your_field
--   4. the field they said they intend to study -> your_field
--   5. general graduate questions               -> general
-- 0041 resolves the same chain for CV fit; the column use follows it.
-- Takes a user id, so it is the service role's alone: a student reaches it
-- only through interview_catalog(), which passes their own id.
create or replace function public.interview_resolve_role_for(p_user_id uuid, p_hint text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_role   text;
  v_how    text;
  v_from   text;
  v_hint   boolean := false;
  v_path   text;
  v_target text;
  v_field  text;
  v_out    jsonb;
begin
  -- 1. The hint.
  select f.role_slug, f.how into v_role, v_how
    from public.interview_role_from_text(p_hint) f;
  if v_role is not null then
    v_from := v_how;
    v_hint := true;
  end if;

  -- 2. The path they follow.
  if v_role is null and p_user_id is not null then
    select cp.slug into v_path
      from public.user_career_paths ucp
      join public.career_paths cp on cp.id = ucp.path_id
     where ucp.user_id = p_user_id and ucp.is_primary and ucp.deleted_at is null
     order by ucp.selected_at desc nulls last
     limit 1;
    if v_path is not null then
      select f.role_slug, f.how into v_role, v_how
        from public.interview_role_for_path(v_path) f;
      if v_role is not null then
        v_from := case v_how when 'field' then 'your_field' else 'your_path' end;
      end if;
    end if;
  end if;

  -- 3. The role they said they want.
  if v_role is null and p_user_id is not null then
    select cp.target_role into v_target
      from public.career_preferences cp
     where cp.user_id = p_user_id;
    select f.role_slug, f.how into v_role, v_how
      from public.interview_role_from_text(v_target) f;
    if v_role is not null then
      v_from := case v_how when 'field' then 'your_field' else 'your_target' end;
    end if;
  end if;

  -- 4. The field they intend to study: a school student's chosen field, else
  -- profiles.intended_field, which holds a slug or a field's name.
  if v_role is null and p_user_id is not null then
    select f.slug into v_field
      from public.high_school_profiles h
      join public.career_fields f on f.id = h.intended_field_id
     where h.user_id = p_user_id;
    if v_field is null then
      select f.slug into v_field
        from public.profiles p
        join public.career_fields f
          on f.slug = lower(btrim(p.intended_field))
          or lower(f.name) = lower(btrim(p.intended_field))
       where p.id = p_user_id
       order by (f.slug = lower(btrim(p.intended_field))) desc, f.slug
       limit 1;
    end if;
    if v_field is not null then
      select r.slug into v_role
        from public.interview_roles r
       where r.field_slug = v_field and r.is_field_default and r.is_active;
      if v_role is not null then
        v_from := 'your_field';
      end if;
    end if;
  end if;

  -- 5. Questions any graduate can practise.
  if v_role is null then
    v_role := 'management-trainee';
    v_from := 'general';
  end if;

  select jsonb_build_object(
           'role_slug',     v_role,
           'role_title',    r.title,
           'field_slug',    f.slug,
           'field_name',    f.name,
           'resolved_from', v_from,
           'hint_matched',  v_hint)
    into v_out
    from (select 1) one
    left join public.interview_roles r on r.slug = v_role
    left join public.career_fields f on f.slug = r.field_slug;
  return v_out;
end $$;
revoke all on function public.interview_resolve_role_for(uuid, text) from public, anon, authenticated;
grant execute on function public.interview_resolve_role_for(uuid, text) to service_role;


-- --------------------------------------------------------------- 6. the draw
--
-- Picks up to n pool questions for one session. Slots come from
-- interview_slots(). A behavioural session draws every slot from the
-- behavioural pool, a technical one none, and a mixed one its first
-- greatest(1, round(n * 0.4)) slots, which are the gentlest: medium/mixed/5
-- is behavioural E,M then the role's M,M,H, so "hard, mixed" stays hard.
--
-- Per slot, among active questions not already chosen: the slot's own tier
-- first, then the nearest (easier before harder on a tie), then the ones this
-- student has not seen, then the least recently seen (p_seen is most recent
-- first), then chance. A slot with nothing left is skipped.
create or replace function public.interview_draw(
  p_role_slug    text,
  p_session_type interview_type,
  p_difficulty   difficulty_level,
  p_count        int,
  p_seen         uuid[] default '{}'
)
returns table(ord int, pool_question_id uuid)
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_tiers  constant difficulty_level[] := enum_range(null::difficulty_level);
  v_slots  difficulty_level[] := public.interview_slots(p_difficulty, p_count);
  v_n      int;
  v_b      int;
  v_seen   uuid[] := coalesce(p_seen, '{}'::uuid[]);
  v_len    int;
  v_rank   int;
  v_chosen uuid[] := '{}'::uuid[];
  v_id     uuid;
  v_k      int := 0;
begin
  v_n   := coalesce(array_length(v_slots, 1), 0);
  v_len := coalesce(array_length(v_seen, 1), 0);
  v_b   := case p_session_type
             when 'behavioural' then v_n
             when 'technical'   then 0
             else least(v_n, greatest(1, round(v_n * 0.4)::int))
           end;

  for i in 1 .. v_n loop
    v_rank := array_position(v_tiers, v_slots[i]);

    select q.id into v_id
      from public.interview_pool_questions q
     where q.is_active
       and q.id <> all (v_chosen)
       and case when i <= v_b
                then q.kind = 'behavioural'
                else q.kind = 'role' and q.role_slug = p_role_slug
           end
     order by abs(array_position(v_tiers, q.difficulty) - v_rank),
              array_position(v_tiers, q.difficulty),
              coalesce(v_len - array_position(v_seen, q.id) + 1, 0),
              random()
     limit 1;

    if found then
      v_k      := v_k + 1;
      v_chosen := v_chosen || v_id;
      ord              := v_k;
      pool_question_id := v_id;
      return next;
    end if;
  end loop;
end $$;
revoke all on function public.interview_draw(text, interview_type, difficulty_level, int, uuid[])
  from public, anon, authenticated;


-- ------------------------------------------------------------- 7. client API

-- Everything the setup screen needs in one round trip: the suggested role
-- with its reason, and every field that has a role, each with its roles.
-- Works before 0098 has run: no roles gives `suggested` null and `fields` [].
create or replace function public.interview_catalog()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid       uuid := (select auth.uid());
  v_res       jsonb;
  v_suggested jsonb;
  v_fields    jsonb;
begin
  if v_uid is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;

  v_res := public.interview_resolve_role_for(v_uid, null);

  select jsonb_build_object(
           'slug',          r.slug,
           'title',         r.title,
           'field_slug',    f.slug,
           'field_name',    f.name,
           'resolved_from', v_res->>'resolved_from')
    into v_suggested
    from public.interview_roles r
    join public.career_fields f on f.slug = r.field_slug
   where r.slug = v_res->>'role_slug' and r.is_active;

  select coalesce(jsonb_agg(jsonb_build_object(
           'slug',  f.slug,
           'name',  f.name,
           'roles', rl.role_list)
           order by f.sort_order, f.name), '[]'::jsonb)
    into v_fields
    from public.career_fields f
    cross join lateral (
      select jsonb_agg(jsonb_build_object(
               'slug',             r.slug,
               'title',            r.title,
               'summary',          r.summary,
               'question_count',   (select count(*)
                                      from public.interview_pool_questions q
                                     where q.role_slug = r.slug
                                       and q.kind = 'role' and q.is_active),
               'is_field_default', r.is_field_default,
               'aliases',          coalesce((select jsonb_agg(a.alias order by a.alias)
                                               from public.interview_role_aliases a
                                              where a.role_slug = r.slug), '[]'::jsonb))
             order by r.sort_order, r.title) as role_list
        from public.interview_roles r
       where r.field_slug = f.slug and r.is_active
    ) rl
   where rl.role_list is not null;

  return jsonb_build_object('suggested', v_suggested, 'fields', v_fields);
end $$;
revoke all on function public.interview_catalog() from public, anon, authenticated;
grant execute on function public.interview_catalog() to authenticated;

-- Starts a practice session: free, atomic, no model, no quota.
--
-- Draws from the pool, avoiding what this student saw in the last ninety
-- days, and writes the session and its questions together. Rows written by
-- old app builds carry no pool_question_id; they are matched to the pool by
-- their exact text, so those questions count as seen too.
create or replace function public.start_practice_session(
  p_role_slug    text,
  p_session_type interview_type   default 'mixed',
  p_difficulty   difficulty_level default 'medium',
  p_count        int              default 5,
  p_timer        boolean          default false
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_uid     uuid := (select auth.uid());
  v_type    interview_type   := coalesce(p_session_type, 'mixed');
  v_level   difficulty_level := coalesce(p_difficulty, 'medium');
  v_title   text;
  v_seen    uuid[];
  v_ids     uuid[];
  v_n       int;
  v_session uuid;
begin
  if v_uid is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;
  if p_count is null or p_count not between 3 and 10 then
    raise exception 'choose between 3 and 10 questions' using errcode = '22023';
  end if;

  select r.title into v_title
    from public.interview_roles r
   where r.slug = p_role_slug and r.is_active;
  if v_title is null then
    raise exception 'that role is not in the bank' using errcode = 'P0002';
  end if;

  -- One start at a time per student: the count and the seen list below are
  -- read, then written on.
  perform pg_advisory_xact_lock(hashtextextended('tack:practice:' || v_uid::text, 0));

  -- Free does not mean unbounded. Forty a day is far past any real practice
  -- and stops a client stuck in a loop from filling the table. Every session
  -- started counts, deleted or not: a student can delete their own sessions,
  -- so a cap that skipped deleted ones could be reset at will.
  if (select count(*)
        from public.interview_sessions s
       where s.user_id = v_uid
         and s.started_at > now() - interval '1 day') >= 40 then
    raise exception 'too_many_sessions' using errcode = 'P0001';
  end if;

  select coalesce(array_agg(x.pid order by x.last_seen desc, x.pid), '{}'::uuid[])
    into v_seen
    from (
      select coalesce(q.pool_question_id, p.id) as pid, max(s.started_at) as last_seen
        from public.interview_questions q
        join public.interview_sessions s on s.id = q.session_id
        left join public.interview_pool_questions p
          on q.pool_question_id is null and p.question = q.question
       where q.user_id = v_uid
         and s.started_at > now() - interval '90 days'
       group by 1
    ) x
   where x.pid is not null;

  select coalesce(array_agg(d.pool_question_id order by d.ord), '{}'::uuid[])
    into v_ids
    from public.interview_draw(p_role_slug, v_type, v_level, p_count, v_seen) d;

  v_n := coalesce(array_length(v_ids, 1), 0);
  if v_n < 3 then
    raise exception 'not enough questions for that role' using errcode = 'P0001';
  end if;

  insert into public.interview_sessions
    (user_id, role, role_slug, session_type, difficulty, timer_enabled, question_count)
  values
    (v_uid, v_title, p_role_slug, v_type, v_level, coalesce(p_timer, false), v_n)
  returning id into v_session;

  insert into public.interview_questions
    (session_id, user_id, order_index, question, category, pool_question_id, key_points)
  select v_session, v_uid, (t.ord - 1)::int, p.question, p.category, p.id, p.key_points
    from unnest(v_ids) with ordinality as t(id, ord)
    join public.interview_pool_questions p on p.id = t.id
   order by t.ord;

  return jsonb_build_object(
    'session_id',     v_session,
    'role_slug',      p_role_slug,
    'role_title',     v_title,
    'question_count', v_n);
end $$;
revoke all on function public.start_practice_session(text, interview_type, difficulty_level, int, boolean)
  from public, anon, authenticated;
grant execute on function public.start_practice_session(text, interview_type, difficulty_level, int, boolean)
  to authenticated;

-- 0078's Practise again list, with each question's key points and category,
-- so the review shows what a strong answer covers. Nothing else changes.
create or replace function public.interview_due()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(item order by due_on, reps), '[]'::jsonb)
    from (
      select jsonb_build_object(
               'question_id',   r.question_id,
               'due_on',        r.due_on,
               'interval_days', r.interval_days,
               'reps',          r.reps,
               'role',          s.role,
               'question',      q.question,
               'answer_text',   q.answer_text,
               'score',         f.score,
               'to_improve',    f.to_improve,
               'model_answer',  f.model_answer,
               'key_points',    q.key_points,
               'category',      q.category
             ) as item,
             r.due_on,
             r.reps
        from public.interview_reviews r
        join public.interview_questions q on q.id = r.question_id
        join public.interview_sessions s
          on s.id = q.session_id and s.deleted_at is null
        left join public.interview_feedback f on f.question_id = q.id
       where r.user_id = (select auth.uid())
         and r.due_on <= public.tack_today()
       order by r.due_on, r.reps
       limit 10
    ) due
$$;
revoke all on function public.interview_due() from public, anon, authenticated;
grant execute on function public.interview_due() to authenticated;


-- ------------------------------------------------------------------ checked
do $$
declare
  v_d     difficulty_level;
  v_n     int;
  v_slots difficulty_level[];
  v_fn    text;
  v_user  uuid;
  v_res   jsonb;
  v_cat   jsonb;
  v_text  text;
begin
  -- The slots: 0069's three five-question sets exactly, and for every size the
  -- app offers, the right length, easiest first, and no easy question in a
  -- hard interview or hard one in an easy interview.
  if public.interview_slots('easy', 5) <> array['easy','easy','easy','medium','medium']::difficulty_level[]
  or public.interview_slots('medium', 5) <> array['easy','medium','medium','medium','hard']::difficulty_level[]
  or public.interview_slots('hard', 5) <> array['medium','medium','hard','hard','hard']::difficulty_level[] then
    raise exception 'interview_slots: the five-question sets are not 0069''s';
  end if;
  foreach v_d in array enum_range(null::difficulty_level) loop
    for v_n in 3 .. 10 loop
      v_slots := public.interview_slots(v_d, v_n);
      if coalesce(array_length(v_slots, 1), 0) <> v_n then
        raise exception 'interview_slots(%, %) has % slots', v_d, v_n,
          coalesce(array_length(v_slots, 1), 0);
      end if;
      if v_slots <> (select array_agg(s order by s) from unnest(v_slots) s) then
        raise exception 'interview_slots(%, %) is not easiest first', v_d, v_n;
      end if;
      if (v_d = 'easy' and 'hard'::difficulty_level = any(v_slots))
      or (v_d = 'hard' and 'easy'::difficulty_level = any(v_slots)) then
        raise exception 'interview_slots(%, %) crosses easy and hard', v_d, v_n;
      end if;
    end loop;
  end loop;

  -- The slug rule, equal to validate.py's slugify and bank.ts's slugifyRole.
  if public.interview_slug('Frontend developer') <> 'frontend-developer'
  or public.interview_slug('UI and UX designer') <> 'ui-and-ux-designer'
  or public.interview_slug('C++ developer') <> 'c-developer'
  or public.interview_slug('  বাংলা  ') <> ''
  or public.interview_slug(null) <> '' then
    raise exception 'interview_slug does not match the generator''s slugify';
  end if;

  -- The seed guard: a plain update and the worker's upsert both leave a seed
  -- row alone; the same update with tack.seeding on changes it.
  insert into public.interview_question_bank (role_slug, session_type, difficulty, questions, source)
  values ('__probe__', 'mixed', 'easy', '[]'::jsonb, 'seed');

  update public.interview_question_bank
     set questions = '[{"question": "model"}]'::jsonb
   where role_slug = '__probe__';
  insert into public.interview_question_bank (role_slug, session_type, difficulty, questions)
  values ('__probe__', 'mixed', 'easy', '[{"question": "model"}]'::jsonb)
  on conflict (role_slug, session_type, difficulty) do update set questions = excluded.questions;
  if (select questions from public.interview_question_bank where role_slug = '__probe__')
     <> '[]'::jsonb then
    raise exception 'the seed guard let a model set overwrite a seed row';
  end if;

  perform set_config('tack.seeding', 'on', true);
  update public.interview_question_bank
     set questions = '[{"question": "seed"}]'::jsonb
   where role_slug = '__probe__';
  if (select questions from public.interview_question_bank where role_slug = '__probe__')
     <> '[{"question": "seed"}]'::jsonb then
    raise exception 'the seed guard blocked a seed migration';
  end if;
  perform set_config('tack.seeding', '', true);
  delete from public.interview_question_bank where role_slug = '__probe__';

  -- Who may call what. Practice is a client API; everything under it is not.
  if not has_function_privilege('authenticated', 'public.interview_catalog()', 'EXECUTE')
  or not has_function_privilege('authenticated',
       'public.start_practice_session(text, public.interview_type, public.difficulty_level, int, boolean)',
       'EXECUTE')
  or not has_function_privilege('authenticated', 'public.interview_due()', 'EXECUTE')
  or not has_function_privilege('authenticated',
       'public.review_interview_question(uuid, text)', 'EXECUTE') then
    raise exception 'a student cannot reach interview practice';
  end if;
  foreach v_fn in array array[
    'public.interview_catalog()',
    'public.start_practice_session(text, public.interview_type, public.difficulty_level, int, boolean)',
    'public.interview_due()'
  ] loop
    if has_function_privilege('anon', v_fn, 'EXECUTE') then
      raise exception '% is callable without signing in', v_fn;
    end if;
  end loop;
  foreach v_fn in array array[
    'public.interview_slug(text)',
    'public.interview_slots(public.difficulty_level, int)',
    'public.interview_draw(text, public.interview_type, public.difficulty_level, int, uuid[])',
    'public.interview_role_from_text(text)',
    'public.interview_role_for_path(text)',
    'public.interview_resolve_role_for(uuid, text)',
    'public.interview_bank_keep_seed()'
  ] loop
    if has_function_privilege('authenticated', v_fn, 'EXECUTE')
    or has_function_privilege('anon', v_fn, 'EXECUTE') then
      raise exception '% is callable by a client', v_fn;
    end if;
  end loop;
  if not has_function_privilege('service_role',
       'public.interview_resolve_role_for(uuid, text)', 'EXECUTE') then
    raise exception 'the interview function cannot resolve a role';
  end if;

  -- The four tables: RLS on and forced, read-only to students.
  select count(*) into v_n
    from pg_class c
    join pg_namespace ns on ns.oid = c.relnamespace
   where ns.nspname = 'public'
     and c.relname in ('interview_roles', 'interview_role_aliases',
                       'interview_role_paths', 'interview_pool_questions')
     and c.relrowsecurity and c.relforcerowsecurity;
  if v_n <> 4 then
    raise exception 'only % of the four pool tables force row level security', v_n;
  end if;
  if exists (select 1 from pg_policies
              where schemaname = 'public'
                and tablename in ('interview_roles', 'interview_role_aliases',
                                  'interview_role_paths', 'interview_pool_questions')
                and cmd <> 'SELECT') then
    raise exception 'a pool table has a policy that writes';
  end if;
  foreach v_fn in array array['public.interview_roles', 'public.interview_role_aliases',
                              'public.interview_role_paths', 'public.interview_pool_questions'] loop
    if has_table_privilege('authenticated', v_fn, 'INSERT')
    or has_table_privilege('authenticated', v_fn, 'UPDATE')
    or has_table_privilege('authenticated', v_fn, 'DELETE') then
      raise exception 'a student can write %', v_fn;
    end if;
  end loop;

  -- The new columns, with the defaults old rows and old clients rely on.
  select count(*) into v_n
    from information_schema.columns
   where table_schema = 'public'
     and ((table_name = 'interview_sessions' and column_name = 'role_slug')
       or (table_name = 'interview_questions'
           and column_name in ('pool_question_id', 'key_points', 'self_check'))
       or (table_name = 'interview_question_bank' and column_name = 'source'));
  if v_n <> 5 then
    raise exception 'expected 5 new interview columns, found %', v_n;
  end if;
  select column_default into v_text
    from information_schema.columns
   where table_schema = 'public' and table_name = 'interview_questions'
     and column_name = 'key_points' and is_nullable = 'NO';
  if position('[]' in coalesce(v_text, '')) = 0 then
    raise exception 'interview_questions.key_points must default to an empty list';
  end if;
  select column_default into v_text
    from information_schema.columns
   where table_schema = 'public' and table_name = 'interview_question_bank'
     and column_name = 'source' and is_nullable = 'NO';
  if position('model' in coalesce(v_text, '')) = 0 then
    raise exception 'interview_question_bank.source must default to model';
  end if;
  if exists (select 1 from public.interview_question_bank
              where role_slug in ('frontend-developer','backend-developer','data-analyst',
                                  'digital-marketer','hr-executive','business-analyst',
                                  'graphic-designer','qa-engineer','accountant','content-writer')
                and source <> 'seed') then
    raise exception 'a set 0069 wrote by hand is not marked seed';
  end if;

  -- As a real student, the two reads the app makes, so every column name in
  -- the resolution chain is proved without writing a row.
  select id into v_user from public.profiles limit 1;
  if v_user is null then
    raise notice 'no profiles yet; the catalog check needs a caller';
  else
    perform set_config('request.jwt.claims',
                       json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
    v_cat := public.interview_catalog();
    if jsonb_typeof(v_cat) <> 'object'
    or not (v_cat ? 'suggested') or not (v_cat ? 'fields')
    or jsonb_typeof(v_cat->'fields') <> 'array' then
      raise exception 'interview_catalog returned %', v_cat;
    end if;
    v_res := public.interview_resolve_role_for(v_user, null);
    if coalesce(v_res->>'resolved_from', '') not in
       ('exact', 'alias', 'path', 'field', 'your_path', 'your_target', 'your_field', 'general') then
      raise exception 'interview_resolve_role_for returned %', v_res;
    end if;
    perform set_config('request.jwt.claims', '', true);
  end if;
end $$;

-- ----------------------------------------------------- checked: the draw
--
-- 0098 checks the draw against the real pool. This proves it now, on a probe
-- role that exists only inside this block: every write here is rolled back
-- by the last statement, which raises a code only this block catches.
do $$
declare
  v_field  text;
  v_user   uuid;
  v_tiers  difficulty_level[];
  v_kinds  text[];
  v_ords   int[];
  v_ids    uuid[];
  v_want   uuid[];
  v_seen   uuid[];
  v_first  jsonb;
  v_second jsonb;
  v_n      int;
begin
  select slug into v_field from public.career_fields order by sort_order, slug limit 1;
  if v_field is null then
    raise notice 'no career fields yet; the draw check needs one';
    return;
  end if;

  begin
    insert into public.interview_roles (slug, title, cluster, field_slug, summary, sort_order)
    values ('tack-probe-role', 'Tack probe role', 'business', v_field,
            'A role that exists only inside this check.', 9999);

    -- Fifteen role questions, five per tier, authored easy to hard; and six
    -- behavioural ones, two per tier.
    insert into public.interview_pool_questions
      (id, role_slug, kind, difficulty, category, question, key_points, sort_order)
    select gen_random_uuid(), 'tack-probe-role', 'role', t.d, 'Probe',
           format('Tack probe role question %s %s?', t.d, g),
           '["Probe point one", "Probe point two"]'::jsonb,
           (t.n - 1) * 5 + g
      from unnest(enum_range(null::difficulty_level)) with ordinality as t(d, n),
           generate_series(1, 5) g;
    insert into public.interview_pool_questions
      (id, role_slug, kind, difficulty, category, question, key_points, sort_order)
    select gen_random_uuid(), null, 'behavioural', t.d, 'Probe',
           format('Tack probe behavioural question %s %s?', t.d, g),
           '["Probe point one", "Probe point two"]'::jsonb,
           (t.n - 1) * 2 + g
      from unnest(enum_range(null::difficulty_level)) with ordinality as t(d, n),
           generate_series(1, 2) g;

    -- Technical, medium, five: the role's E,M,M,M,H, numbered 1..5.
    select array_agg(q.difficulty order by d.ord), array_agg(q.kind order by d.ord),
           array_agg(d.ord order by d.ord)
      into v_tiers, v_kinds, v_ords
      from public.interview_draw('tack-probe-role', 'technical', 'medium', 5) d
      join public.interview_pool_questions q on q.id = d.pool_question_id;
    if v_tiers is distinct from array['easy','medium','medium','medium','hard']::difficulty_level[]
    or v_kinds is distinct from array['role','role','role','role','role']
    or v_ords is distinct from array[1,2,3,4,5] then
      raise exception 'interview_draw technical/medium/5 gave % % %', v_tiers, v_kinds, v_ords;
    end if;

    -- Mixed takes the two gentlest slots from the behavioural pool.
    select array_agg(q.difficulty order by d.ord), array_agg(q.kind order by d.ord)
      into v_tiers, v_kinds
      from public.interview_draw('tack-probe-role', 'mixed', 'medium', 5) d
      join public.interview_pool_questions q on q.id = d.pool_question_id;
    if v_tiers is distinct from array['easy','medium','medium','medium','hard']::difficulty_level[]
    or v_kinds is distinct from array['behavioural','behavioural','role','role','role'] then
      raise exception 'interview_draw mixed/medium/5 gave % %', v_tiers, v_kinds;
    end if;

    -- Behavioural draws only from the behavioural pool; ten questions from a
    -- pool of fifteen are ten different ones; three hard ones are M,H,H.
    select count(distinct d.pool_question_id) filter (where q.kind = 'behavioural')
      into v_n
      from public.interview_draw('tack-probe-role', 'behavioural', 'hard', 5) d
      join public.interview_pool_questions q on q.id = d.pool_question_id;
    if v_n <> 5 then
      raise exception 'interview_draw behavioural/hard/5 gave % behavioural questions', v_n;
    end if;
    select count(distinct d.pool_question_id) into v_n
      from public.interview_draw('tack-probe-role', 'technical', 'easy', 10) d;
    if v_n <> 10 then
      raise exception 'interview_draw technical/easy/10 gave % distinct questions', v_n;
    end if;
    select array_agg(q.difficulty order by d.ord) into v_tiers
      from public.interview_draw('tack-probe-role', 'technical', 'hard', 3) d
      join public.interview_pool_questions q on q.id = d.pool_question_id;
    if v_tiers is distinct from array['medium','hard','hard']::difficulty_level[] then
      raise exception 'interview_draw technical/hard/3 gave %', v_tiers;
    end if;
    if exists (select 1 from public.interview_draw('tack-no-such-role', 'technical', 'medium', 5)) then
      raise exception 'interview_draw found questions for a role that does not exist';
    end if;

    -- Freshness: with everything else seen, the draw returns exactly the
    -- first easy, the first three medium and the first hard question.
    select array_agg(q.id) into v_want
      from public.interview_pool_questions q
     where q.role_slug = 'tack-probe-role'
       and q.sort_order in (1, 6, 7, 8, 11);
    select array_agg(q.id) into v_seen
      from public.interview_pool_questions q
     where q.role_slug = 'tack-probe-role'
       and not (q.id = any(v_want));
    select array_agg(d.pool_question_id) into v_ids
      from public.interview_draw('tack-probe-role', 'technical', 'medium', 5, v_seen) d;
    if coalesce(array_length(v_ids, 1), 0) <> 5
    or not (v_ids <@ v_want and v_want <@ v_ids) then
      raise exception 'interview_draw did not prefer the questions this student has not seen';
    end if;

    -- The start itself, as a real student: the session, its questions with
    -- their key points, and a second start that avoids the first one's. The
    -- student who practised least today, so the daily cap cannot trip it.
    select p.id into v_user
      from public.profiles p
     order by (select count(*) from public.interview_sessions s
                where s.user_id = p.id and s.started_at > now() - interval '1 day'), p.id
     limit 1;
    if v_user is not null then
      perform set_config('request.jwt.claims',
                         json_build_object('sub', v_user, 'role', 'authenticated')::text, true);

      v_first := public.start_practice_session('tack-probe-role', 'technical', 'medium', 5, false);
      if (v_first->>'question_count')::int <> 5
      or v_first->>'role_title' <> 'Tack probe role'
      or v_first->>'role_slug' <> 'tack-probe-role' then
        raise exception 'start_practice_session returned %', v_first;
      end if;
      if not exists (select 1 from public.interview_sessions s
                      where s.id = (v_first->>'session_id')::uuid and s.user_id = v_user
                        and s.role = 'Tack probe role' and s.role_slug = 'tack-probe-role'
                        and s.session_type = 'technical' and s.difficulty = 'medium'
                        and s.question_count = 5) then
        raise exception 'start_practice_session wrote the session wrong';
      end if;
      select count(*) into v_n
        from public.interview_questions q
       where q.session_id = (v_first->>'session_id')::uuid
         and q.user_id = v_user and q.order_index between 0 and 4
         and q.pool_question_id is not null and q.category = 'Probe'
         and jsonb_array_length(q.key_points) = 2 and q.answer_text is null;
      if v_n <> 5 then
        raise exception 'start_practice_session wrote % of 5 questions right', v_n;
      end if;
      if exists (select 1 from public.interview_reviews r
                   join public.interview_questions q on q.id = r.question_id
                  where q.session_id = (v_first->>'session_id')::uuid) then
        raise exception 'an unanswered question joined the practice list';
      end if;

      v_second := public.start_practice_session('tack-probe-role', 'technical', 'medium', 5, false);
      -- Five medium questions and three medium slots: only the third medium
      -- slot can repeat one, because tier beats freshness.
      select count(*) into v_n
        from public.interview_questions a
        join public.interview_questions b on b.pool_question_id = a.pool_question_id
       where a.session_id = (v_first->>'session_id')::uuid
         and b.session_id = (v_second->>'session_id')::uuid;
      if v_n > 1 then
        raise exception 'a second session repeated % of the first one''s questions', v_n;
      end if;

      begin
        perform public.start_practice_session('tack-probe-role', 'technical', 'medium', 2, false);
        raise exception 'start_practice_session accepted two questions';
      exception when sqlstate '22023' then null;
      end;
      begin
        perform public.start_practice_session('tack-no-such-role', 'technical', 'medium', 5, false);
        raise exception 'start_practice_session accepted a role that does not exist';
      exception when sqlstate 'P0002' then null;
      end;
      perform set_config('request.jwt.claims', '', true);
      begin
        perform public.start_practice_session('tack-probe-role', 'technical', 'medium', 5, false);
        raise exception 'start_practice_session worked signed out';
      exception when sqlstate '42501' then null;
      end;
    end if;

    -- Undo every write above. Only this code is caught; any failed check
    -- raises another and fails the migration.
    raise exception 'probe finished' using errcode = 'TKP01';
  exception when sqlstate 'TKP01' then
    null;
  end;
  perform set_config('request.jwt.claims', '', true);
end $$;
