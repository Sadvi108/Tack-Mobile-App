-- A failed/partial provider refresh must not keep abandoned cache rows visible
-- indefinitely. Freshness is based on the last actual source observation, not
-- publication age: older postings still returned by a provider remain eligible.
-- Retain cached rows and saved applications; only discovery visibility changes.
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
       and l.last_seen_at > now() - interval '48 hours'
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
