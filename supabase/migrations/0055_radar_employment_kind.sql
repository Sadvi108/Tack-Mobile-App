-- What kind of work an opening is, so Radar can be filtered by it.
--
-- The first version of Radar had one board and it published neither an
-- employment type nor a description: every one of the 190 cached listings had
-- employment_type null. A filter over that data would have returned zero every
-- time, which is worse than not having the filter.
--
-- Boards describe this in their own words and none agree — "Full Time", "Full
-- time", "fulltime permanent", "berufserfahren", "Intern", "Student". The
-- normalising happens here, once, so the app filters on one vocabulary rather
-- than on whatever each board happened to type.

do $$ begin
  create type employment_kind as enum (
    'full_time', 'part_time', 'internship', 'contract', 'volunteer', 'unknown'
  );
exception when duplicate_object then null; end $$;

alter table public.job_listings
  add column if not exists kind employment_kind not null default 'unknown';

create index if not exists job_listings_kind_idx on public.job_listings(kind);


-- Maps a board's own words onto the one vocabulary.
--
-- Order matters: a posting tagged both "Intern" and "Full Time" is an
-- internship, because that is the fact a student is filtering on. Volunteer
-- outranks everything for the same reason — somebody looking for unpaid work
-- to build a CV is not looking for a salaried job that happens to mention it.
create or replace function public.classify_employment(
  p_raw   text,
  p_title text default null
)
returns employment_kind
language sql
immutable
as $$
  with t as (select lower(concat_ws(' ', coalesce(p_raw, ''), coalesce(p_title, ''))) as s)
  select case
    when (select s from t) ~ '\m(volunteer|voluntary|pro bono|unpaid)\M'      then 'volunteer'
    when (select s from t) ~ '\m(intern|internship|praktikum|placement|trainee|student)\M'
                                                                              then 'internship'
    when (select s from t) ~ '\m(part[ _-]?time|teilzeit|werkstudent)\M'      then 'part_time'
    when (select s from t) ~ '\m(contract|freelance|contractor|temporary|consultant)\M'
                                                                              then 'contract'
    when (select s from t) ~ '\m(full[ _-]?time|vollzeit|permanent|festanstellung)\M'
                                                                              then 'full_time'
    else 'unknown'
  end::employment_kind
$$;

grant execute on function public.classify_employment(text, text) to authenticated;


-- Everything already cached was classified from its title alone, because that
-- is all the first board gave us. Most stay 'unknown', honestly.
update public.job_listings
   set kind = public.classify_employment(employment_type, title)
 where kind = 'unknown';


-- radar_feed gains a kind filter, and remote stays separate.
--
-- "Remote" and "internship" are different questions — one is where the work
-- happens, the other is what the job is — and a student filtering for an
-- internship should not have to decide whether they mind it being remote.
create or replace function public.radar_feed(
  p_query    text default null,
  p_location text default null,
  p_remote   boolean default null,
  p_limit    int default 20,
  p_offset   int default 0,
  p_kind     text default null
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
  v_words  text[];
  v_kind   employment_kind;
  v_result jsonb;
begin
  if v_uid is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;

  if p_kind is not null and p_kind <> '' then
    begin
      v_kind := p_kind::employment_kind;
    exception when invalid_text_representation then
      v_kind := null;
    end;
  end if;

  select ucp.path_id into v_path
    from public.user_career_paths ucp
   where ucp.user_id = v_uid and ucp.deleted_at is null and ucp.is_primary
   limit 1;

  select array_agg(w) into v_words
    from (
      select distinct w
        from unnest(string_to_array(lower(coalesce(p_query, '')), ' ')) as w
       where length(w) >= 3
    ) t;

  if v_words is not null then
    declare v_specific text[];
    begin
      select array_agg(w) into v_specific
        from unnest(v_words) as w
       where w not in ('developer','engineer','intern','internship','junior',
                       'senior','specialist','associate','executive','officer',
                       'assistant','graduate','trainee','the','and','for');
      if v_specific is not null then v_words := v_specific; end if;
    end;
  end if;

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
       and (v_kind is null or l.kind = v_kind)
       and (v_words is null or exists (
             select 1 from unnest(v_words) as w
              where l.title ilike '%' || w || '%'
                 or coalesce(l.company_name, '') ilike '%' || w || '%'
           ))
       and (p_location is null or p_location = '' or l.is_remote
            or coalesce(l.location, '') ilike '%' || p_location || '%')
     group by l.id
  ),
  scored as (
    select m.id, m.asks, m.have, m.on_path,
           case when m.asks = 0 then null
                else least(100, round(
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
               'id', l.id, 'source', l.source, 'title', l.title,
               'company', l.company_name, 'location', l.location,
               'remote', l.is_remote, 'employment_type', l.employment_type,
               'kind', l.kind,
               'url', l.url, 'apply_url', coalesce(l.apply_url, l.url),
               'salary', l.salary_text, 'posted_at', l.posted_at, 'level', l.level,
               'fit', s.fit, 'asks', s.asks, 'have', s.have,
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
               'saved_application_id', (
                 select a.id from public.job_applications a
                   join public.jobs j on j.id = a.job_id
                  where a.user_id = v_uid and a.deleted_at is null
                    and j.source_url = l.url
                  limit 1
               )
             ) as item,
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

revoke all on function public.radar_feed(text, text, boolean, int, int, text) from public, anon;
grant execute on function public.radar_feed(text, text, boolean, int, int, text) to authenticated;

-- The five-argument version is gone: leaving it callable means a client that
-- has not been updated silently gets an unfiltered feed and nobody notices.
drop function if exists public.radar_feed(text, text, boolean, int, int);


-- What is actually available to filter on, so the screen can grey out a chip
-- rather than offering one that returns nothing.
create or replace function public.radar_kinds()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_object_agg(k, n), '{}'::jsonb)
    from (
      select kind::text as k, count(*)::int as n
        from public.job_listings group by kind
      union all
      select 'remote', count(*)::int from public.job_listings where is_remote
      union all
      select 'onsite', count(*)::int from public.job_listings where not is_remote
    ) x
$$;

revoke all on function public.radar_kinds() from public, anon;
grant execute on function public.radar_kinds() to authenticated;
