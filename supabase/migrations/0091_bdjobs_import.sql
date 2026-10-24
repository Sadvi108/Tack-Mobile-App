-- Scheduled Apify collection -> bounded, replay-safe queue imports -> Radar.
-- No browser or student request can enqueue or start a paid scrape.
alter table public.job_listings
  add column workplace_known boolean not null default true,
  add column expires_at timestamptz;

create or replace function public.cache_bdjobs_page(p_rows jsonb)
returns int language plpgsql security definer set search_path = public
as $$
declare v_ids uuid[];
begin
  if p_rows is null or jsonb_typeof(p_rows) <> 'array'
     or jsonb_array_length(p_rows) > 100 or octet_length(p_rows::text) > 1048576 then
    raise exception 'invalid_bdjobs_page';
  end if;
  -- Fixed source and service-only execution. The seen-time guard prevents a
  -- retry of an older dataset from overwriting a newer completed collection.
  with written as (
    insert into public.job_listings (
      source, external_id, title, company_name, location, is_remote,
      workplace_known, employment_type, description, url, apply_url,
      salary_text, category, level, posted_at, expires_at, last_seen_at
    )
    select 'bdjobs', r.external_id, r.title, r.company_name, r.location,
      r.is_remote, r.workplace_known, r.employment_type, r.description,
      r.url, r.apply_url, r.salary_text, r.category, r.level, r.posted_at,
      r.expires_at, r.last_seen_at
    from jsonb_to_recordset(p_rows) as r(
      external_id text, title text, company_name text, location text,
      is_remote boolean, workplace_known boolean, employment_type text,
      description text, url text, apply_url text, salary_text text,
      category text, level text, posted_at timestamptz, expires_at timestamptz,
      last_seen_at timestamptz
    )
    on conflict (source, external_id) do update set
      title = excluded.title, company_name = excluded.company_name,
      location = excluded.location, is_remote = excluded.is_remote,
      workplace_known = excluded.workplace_known,
      employment_type = excluded.employment_type, description = excluded.description,
      url = excluded.url, apply_url = excluded.apply_url,
      salary_text = excluded.salary_text, category = excluded.category,
      level = excluded.level, posted_at = excluded.posted_at,
      expires_at = excluded.expires_at, last_seen_at = excluded.last_seen_at
    where excluded.last_seen_at >= public.job_listings.last_seen_at
    returning id
  ) select array_agg(id) into v_ids from written;
  perform public.reindex_listings(v_ids);
  return coalesce(array_length(v_ids, 1), 0);
end $$;
revoke all on function public.cache_bdjobs_page(jsonb) from public, anon, authenticated;
grant execute on function public.cache_bdjobs_page(jsonb) to service_role;

create or replace function public.enqueue_bdjobs_import()
returns void language plpgsql security definer set search_path = public
as $$
begin
  insert into public.jobs_queue(type, payload, idempotency_key)
  values ('import_bdjobs', '{}'::jsonb,
    'bdjobs:check:' || to_char(now() at time zone 'UTC', 'YYYY-MM-DD-HH24'))
  on conflict (idempotency_key) do nothing;
end $$;
revoke all on function public.enqueue_bdjobs_import() from public, anon, authenticated;
grant execute on function public.enqueue_bdjobs_import() to service_role;

-- This reads a previously completed dataset. Only the separately configured
-- Apify schedule starts collections and controls collection spend.
select cron.schedule('tack-bdjobs-import', '12 * * * *',
  'select public.enqueue_bdjobs_import()');

-- Preserve deterministic ranking, ownership, pagination and saved tracking.
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
     where (p_remote is null or (l.workplace_known and l.is_remote = p_remote))
       and (l.expires_at is null or l.expires_at > now())
       and (l.source <> 'bdjobs' or l.last_seen_at > now() - interval '48 hours')
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
               'remote', l.is_remote, 'workplace_known', l.workplace_known,
               'expires_at', l.expires_at, 'source_updated_at', l.last_seen_at,
               'employment_type', l.employment_type,
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
               order by s.fit desc nulls last, l.posted_at desc nulls last, l.last_seen_at desc, l.id
             ) as ord
        from scored s
        join public.job_listings l on l.id = s.id
       order by s.fit desc nulls last, l.posted_at desc nulls last, l.last_seen_at desc, l.id
       limit greatest(1, least(coalesce(p_limit, 20), 50))
      offset greatest(0, coalesce(p_offset, 0))
    ) page;

  return v_result;
end $$;

revoke all on function public.radar_feed(text, text, boolean, int, int, text) from public, anon;
grant execute on function public.radar_feed(text, text, boolean, int, int, text) to authenticated;
