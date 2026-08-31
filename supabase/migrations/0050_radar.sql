-- Radar: openings from outside Tack, ranked by how well they fit.
--
-- Two rules shape everything here.
--
-- First, a listing from Careerjet or an AI jobs board is *shared* data. It is
-- not owned by the student who happened to search for it, and it must not be
-- written into their own `jobs` rows — otherwise the feed and their tracker
-- become the same table, and an expired listing would silently rewrite an
-- application they had already sent. Listings are cached here; saving one
-- copies it into a job the student owns, exactly the way a career path
-- template is copied into a roadmap.
--
-- Second, the fit score is deterministic. It reads the same `skills`
-- vocabulary the rest of Tack uses, and the same match arithmetic. No model is
-- involved anywhere in this file. A student is being asked to trust this
-- number against a real job, and it has to give the same answer twice.

do $$ begin
  create type radar_source as enum ('careerjet', 'aijobs');
exception when duplicate_object then null; end $$;

create table public.job_listings (
  id              uuid primary key default gen_random_uuid(),
  source          radar_source not null,

  -- The provider's own id where it gives one, otherwise a hash of the URL.
  -- This is what stops the same opening arriving twice a day forever.
  external_id     text not null,

  title           text not null,
  company_name    text,
  location        text,
  is_remote       boolean not null default false,
  employment_type text,
  description     text,
  url             text not null,
  apply_url       text,

  salary_min      numeric,
  salary_max      numeric,
  salary_currency text,
  salary_text     text,

  category        text,
  level           text,
  posted_at       timestamptz,

  first_seen_at   timestamptz not null default now(),
  last_seen_at    timestamptz not null default now(),

  unique (source, external_id)
);

create index job_listings_seen_idx on public.job_listings(last_seen_at desc);
create index job_listings_remote_idx on public.job_listings(is_remote) where is_remote;
create index job_listings_title_trgm on public.job_listings using gin (title gin_trgm_ops);

alter table public.job_listings enable row level security;
alter table public.job_listings force row level security;

-- Shared, and carrying nothing about any student. Readable by anyone signed
-- in; written only by the service role, from the radar Edge Function.
create policy job_listings_select on public.job_listings
  for select to authenticated using (true);


-- The skills a listing asks for, resolved against Tack's own vocabulary.
--
-- Deliberately not a model call. The `skills` table already holds the names
-- and aliases that matter in this market, and matching text against it is a
-- set operation — the same listing gives the same skills today and next week,
-- which is the whole reason the score can be shown to a student.
create table public.job_listing_skills (
  listing_id uuid not null references public.job_listings(id) on delete cascade,
  skill_id   uuid not null references public.skills(id) on delete cascade,
  primary key (listing_id, skill_id)
);

alter table public.job_listing_skills enable row level security;
alter table public.job_listing_skills force row level security;
create policy job_listing_skills_select on public.job_listing_skills
  for select to authenticated using (true);


-- Finds every known skill mentioned in a listing.
--
-- Word-boundary matching on the skill name and each of its aliases. Without
-- the boundary, "Go" matches "Google" and "R" matches every listing ever
-- written, which is how a naive version of this tells a student they are a 90%
-- fit for a job they cannot do.
--
-- One- and two-letter names are matched **case-sensitively**, and only those.
-- The vocabulary contains exactly three of them — C, R and Go — and all three
-- are also ordinary English. The boundary rule alone still matched "we go
-- fast" as the Go programming language. The language is always written
-- capitalised and the verb almost never is, so case is the cheapest signal
-- that separates them. Everything three characters or longer (SQL, AWS, Git)
-- is unambiguous and stays case-insensitive, because a student writing "sql"
-- on their CV means SQL.
create or replace function public.extract_listing_skills(p_text text)
returns setof uuid
language sql
stable
as $$
  select s.id
    from public.skills s
   where s.is_active
     and exists (
       select 1
         from unnest(array[s.name] || coalesce(s.aliases, '{}')) as term
        where length(term) >= 1
          and case
                when length(term) <= 2 then
                  p_text ~ ('(^|[^A-Za-z0-9+#])'
                    || regexp_replace(term, '([.^$*+?()\[\]{}|\\-])', '\\\1', 'g')
                    || '($|[^A-Za-z0-9+#])')
                else
                  p_text ~* ('(^|[^a-z0-9+#])'
                    || regexp_replace(term, '([.^$*+?()\[\]{}|\\-])', '\\\1', 'g')
                    || '($|[^a-z0-9+#])')
              end
     )
$$;


-- Re-resolves the skills for a listing. Called by the radar function after an
-- upsert, as the service role.
create or replace function public.reindex_listing_skills(p_listing_id uuid)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_text text;
  v_n int;
begin
  select concat_ws(' ', title, company_name, category, level, description)
    into v_text from public.job_listings where id = p_listing_id;
  if v_text is null then return 0; end if;

  delete from public.job_listing_skills where listing_id = p_listing_id;
  insert into public.job_listing_skills (listing_id, skill_id)
    select p_listing_id, sid from public.extract_listing_skills(v_text) as sid
  on conflict do nothing;

  get diagnostics v_n = row_count;
  return v_n;
end $$;

revoke all on function public.reindex_listing_skills(uuid) from public, anon, authenticated;


-- The feed, ranked for the caller.
--
-- Fit is the share of the skills a listing asks for that the student already
-- has, with a bonus when the listing lines up with the career path they chose.
-- A listing Tack cannot read any skills from scores null rather than zero:
-- "we could not tell" and "you match none of it" are different answers and
-- must not look the same.
create or replace function public.radar_feed(
  p_query    text default null,
  p_location text default null,
  p_remote   boolean default null,
  p_limit    int default 20,
  p_offset   int default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid    uuid := (select auth.uid());
  v_path   uuid;
  v_result jsonb;
begin
  if v_uid is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;

  select ucp.path_id into v_path
    from public.user_career_paths ucp
   where ucp.user_id = v_uid and ucp.deleted_at is null and ucp.is_primary
   limit 1;

  with mine as (
    select skill_id from public.user_skills where user_id = v_uid
  ),
  wanted as (
    select cps.skill_id from public.career_path_skills cps where cps.path_id = v_path
  ),
  matched as (
    select l.id,
           count(ls.skill_id)                                              as asks,
           count(ls.skill_id) filter (where ls.skill_id in (select skill_id from mine))   as have,
           count(ls.skill_id) filter (where ls.skill_id in (select skill_id from wanted)) as on_path
      from public.job_listings l
      left join public.job_listing_skills ls on ls.listing_id = l.id
     where (p_remote is null or l.is_remote = p_remote)
       and (p_query is null or p_query = ''
            or l.title ilike '%' || p_query || '%'
            or l.company_name ilike '%' || p_query || '%')
       and (p_location is null or p_location = '' or l.is_remote
            or l.location ilike '%' || p_location || '%')
     group by l.id
  ),
  scored as (
    select m.id,
           m.asks, m.have, m.on_path,
           case when m.asks = 0 then null
                else least(100, round(
                  -- 80 points for what they already have, 20 for the listing
                  -- pointing at the path they chose.
                  80.0 * m.have / m.asks
                  + case when m.on_path = 0 then 0
                         else 20.0 * least(m.on_path, 3) / 3 end
                ))::int
           end as fit
      from matched m
  )
  select coalesce(jsonb_agg(item order by ord), '[]'::jsonb) into v_result
    from (
      select jsonb_build_object(
               'id', l.id,
               'source', l.source,
               'title', l.title,
               'company', l.company_name,
               'location', l.location,
               'remote', l.is_remote,
               'employment_type', l.employment_type,
               'url', l.url,
               'apply_url', coalesce(l.apply_url, l.url),
               'salary', l.salary_text,
               'posted_at', l.posted_at,
               'level', l.level,
               'fit', s.fit,
               'asks', s.asks,
               'have', s.have,
               'matched_skills', coalesce((
                 select jsonb_agg(sk.name order by sk.name)
                   from public.job_listing_skills ls
                   join public.skills sk on sk.id = ls.skill_id
                  where ls.listing_id = l.id
                    and ls.skill_id in (select skill_id from public.user_skills where user_id = v_uid)
               ), '[]'::jsonb),
               'missing_skills', coalesce((
                 select jsonb_agg(sk.name order by sk.name)
                   from public.job_listing_skills ls
                   join public.skills sk on sk.id = ls.skill_id
                  where ls.listing_id = l.id
                    and ls.skill_id not in (select skill_id from public.user_skills where user_id = v_uid)
               ), '[]'::jsonb),
               -- So the list can say "saved" without a second query.
               'saved_application_id', (
                 select a.id from public.job_applications a
                   join public.jobs j on j.id = a.job_id
                  where a.user_id = v_uid and a.deleted_at is null
                    and j.source_url = l.url
                  limit 1
               )
             ) as item,
             -- Best fit first, then freshest. A null fit sorts below anything
             -- scored rather than above it.
             row_number() over (
               order by s.fit desc nulls last, l.posted_at desc nulls last, l.last_seen_at desc
             ) as ord
        from scored s
        join public.job_listings l on l.id = s.id
       order by s.fit desc nulls last, l.posted_at desc nulls last, l.last_seen_at desc
       limit greatest(1, least(coalesce(p_limit, 20), 50))
      offset greatest(0, coalesce(p_offset, 0))
    ) page;

  return v_result;
end $$;

revoke all on function public.radar_feed(text, text, boolean, int, int) from public, anon;
grant execute on function public.radar_feed(text, text, boolean, int, int) to authenticated;


-- Saving a listing.
--
-- Copies it into a job the student owns and opens an application on it, so
-- the tracker keeps working exactly as it did and a listing that later expires
-- cannot rewrite something the student already sent. Idempotent: saving twice
-- returns the application that already exists.
create or replace function public.save_listing(p_listing_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  l     record;
  v_job uuid;
  v_app uuid;
begin
  if v_uid is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;

  select * into l from public.job_listings where id = p_listing_id;
  if not found then
    raise exception 'that opening is no longer listed' using errcode = 'no_data_found';
  end if;

  select a.id into v_app
    from public.job_applications a
    join public.jobs j on j.id = a.job_id
   where a.user_id = v_uid and a.deleted_at is null and j.source_url = l.url
   limit 1;
  if v_app is not null then return v_app; end if;

  insert into public.jobs (user_id, company_name, title, location, employment_type,
                           description, source_url)
    values (v_uid, l.company_name, l.title, l.location, l.employment_type,
            l.description, l.url)
    returning id into v_job;

  insert into public.job_applications (user_id, job_id, status, source)
    values (v_uid, v_job, 'saved', l.source::text)
    returning id into v_app;

  return v_app;
end $$;

revoke all on function public.save_listing(uuid) from public, anon;
grant execute on function public.save_listing(uuid) to authenticated;


do $$
begin
  if not has_function_privilege('authenticated', 'public.radar_feed(text, text, boolean, int, int)', 'EXECUTE')
  or not has_function_privilege('authenticated', 'public.save_listing(uuid)', 'EXECUTE') then
    raise exception 'radar is not callable by a signed-in student';
  end if;
  if has_function_privilege('anon', 'public.radar_feed(text, text, boolean, int, int)', 'EXECUTE') then
    raise exception 'radar must not be reachable with the anon key alone';
  end if;
end $$;
