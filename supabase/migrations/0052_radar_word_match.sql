-- Radar matched a search phrase against job titles as one string, so it found
-- nothing.
--
-- The search box is seeded with the student's own target role, which is how a
-- careers app should behave — and target roles read like "Backend developer".
-- No real job title contains that phrase. The titles the boards return are
-- "Backend Software Engineer", "Staff Software Engineer, Backend", "Senior
-- Backend Engineer (Applied AI)". A substring match on the whole phrase hits
-- none of them, so the feature that had just been deployed showed an empty
-- screen to the one student it was seeded for.
--
-- Matching is per word now. Any significant word in the query matching the
-- title or the company is enough to be a candidate; the fit score is what
-- decides the order. That is the right division of labour — the text filter
-- exists to find plausible rows, and ranking them is a job this schema already
-- does properly.
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
  v_words  text[];
  v_result jsonb;
begin
  if v_uid is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;

  select ucp.path_id into v_path
    from public.user_career_paths ucp
   where ucp.user_id = v_uid and ucp.deleted_at is null and ucp.is_primary
   limit 1;

  -- Words worth searching on. Two letters or fewer carry no signal in a job
  -- title, and the generic half of a role name ("developer", "engineer")
  -- matches nearly everything, so it is dropped when something more
  -- distinctive survives.
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
       and (v_words is null or exists (
             select 1 from unnest(v_words) as w
              where l.title ilike '%' || w || '%'
                 or coalesce(l.company_name, '') ilike '%' || w || '%'
           ))
       -- A role that is not remote and not where the student is, is not a role
       -- they can take. Remote always passes.
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

revoke all on function public.radar_feed(text, text, boolean, int, int) from public, anon;
grant execute on function public.radar_feed(text, text, boolean, int, int) to authenticated;
