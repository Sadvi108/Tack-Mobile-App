-- Radar shows only what a student in Bangladesh can actually take.
--
-- No Bangladesh source had a key, so the cache held nothing but four foreign
-- boards, and radar_feed kept every row a board marked remote. The boards mark
-- hybrid and country-restricted roles remote: "USA - Remote", "Berlin",
-- "Canada (Remote)" and "Remote, New York City, or Oakland" all reached a
-- student in Dhaka, and none of them is open to one.
--
-- A listing reaches Bangladesh when:
--   * Nothing rules it out: a foreign country or region, "except",
--     "excluding" or "outside", or "not" in front of a Bangladeshi place.
--     This comes first and applies to every source.
--   * Then: it comes from Bdjobs or LinkedIn. Only the Apify importer writes those
--     two sources, and it drops anything isBangladeshPosting cannot place in
--     Bangladesh (_shared/radar/apify_sources.ts), using the actor's country
--     field where the location is blank or just "Remote". If a live provider
--     ever starts writing either source, this shortcut has to go.
--   * Or its location names Bangladesh or a place in it.
--   * Or it is remote and its location opens it to Bangladesh: worldwide,
--     anywhere, global, APAC, Asia-Pacific, South Asia, or Asia when it is not
--     South-East, East, Central, West or North Asia, with no "only" or "not".
--
-- A bare "Remote" is not enough. On these boards it usually means remote
-- inside the board's own country, and a foreign role shown as reachable costs
-- a student more than one left out. That also hides lists like "Europe, USA,
-- Canada, APAC": precision over recall.
--
-- The answer is stored on the row by a trigger, because the rule runs about
-- two hundred country patterns and the feed reads every fresh row. Any later
-- change to this rule, the place names or the countries table has to
-- recompute the column, as the update below does.

-- The same names as `places` in _shared/radar/apify_sources.ts: districts,
-- Dhaka neighbourhoods and the older spellings a board may still use. A Deno
-- test fails if the two lists drift.
create or replace function public.bangladesh_place_names()
returns text[]
language sql
immutable
set search_path = public
as $$
  select array[
    'Bangladesh',
    'Dhaka',
    'Chattogram',
    'Chittagong',
    'Cumilla',
    'Comilla',
    'Cox''s Bazar',
    'Coxs Bazar',
    'Brahmanbaria',
    'Chandpur',
    'Feni',
    'Khagrachhari',
    'Lakshmipur',
    'Laxmipur',
    'Noakhali',
    'Rangamati',
    'Bandarban',
    'Faridpur',
    'Gazipur',
    'Gopalganj',
    'Kishoreganj',
    'Madaripur',
    'Manikganj',
    'Munshiganj',
    'Narayanganj',
    'Narsingdi',
    'Rajbari',
    'Shariatpur',
    'Tangail',
    'Bagerhat',
    'Chuadanga',
    'Jashore',
    'Jessore',
    'Jhenaidah',
    'Khulna',
    'Kushtia',
    'Magura',
    'Meherpur',
    'Narail',
    'Satkhira',
    'Jamalpur',
    'Mymensingh',
    'Netrokona',
    'Sherpur',
    'Bogra',
    'Bogura',
    'Joypurhat',
    'Naogaon',
    'Natore',
    'Chapainawabganj',
    'Pabna',
    'Rajshahi',
    'Sirajganj',
    'Dinajpur',
    'Gaibandha',
    'Kurigram',
    'Lalmonirhat',
    'Nilphamari',
    'Panchagarh',
    'Rangpur',
    'Thakurgaon',
    'Habiganj',
    'Moulvibazar',
    'Sunamganj',
    'Sylhet',
    'Barguna',
    'Barishal',
    'Barisal',
    'Bhola',
    'Jhalokati',
    'Patuakhali',
    'Pirojpur',
    'Savar',
    'Tongi',
    'Dhanmondi',
    'Gulshan',
    'Banani',
    'Tejgaon',
    'Agrabad'
  ]::text[];
$$;

create or replace function public.listing_reaches_bangladesh(
  p_source public.radar_source,
  p_location text,
  p_is_remote boolean
) returns boolean
language plpgsql
stable
set search_path = public
as $$
declare
  v_place   text := coalesce(p_location, '');
  v_foreign boolean;
  -- Bangla names. Postgres word boundaries fail after a vowel sign (ঢাকা ends
  -- in one), so these are bounded by spaces and punctuation instead.
  v_bangla  text := '(বাংলাদেশ|ঢাকা|চট্টগ্রাম)([[:space:][:punct:]]|$)';
begin
  select exists (
           select 1 from public.countries k
            where k.iso2 not in ('BD', 'ZZ', 'Other')
              and v_place ~* ('\m' || regexp_replace(k.name, '([.^$*+?()\[\]{}|\\])', '\\\1', 'g') || '\M')
         )
         or v_place ~* '\m(turkey|russia|korea|vietnam|czech republic|holland)\M'
         -- Regions the countries table cannot name, none of which includes
         -- Bangladesh.
         or v_place ~* '\m(europe|european union|emea|latam|latin america|north america|south america|americas|africa|middle east|mena|gcc|oceania|nordics|scandinavia|dach|benelux)\M'
         or v_place ~* '(^|[^a-z])(usa|u\.s\.a?\.?|us|uk|u\.k\.|uae|eu|ksa)([^a-z]|$)'
    into v_foreign;

  -- Ruled out whatever the source: Bdjobs also lists vacancies abroad, and
  -- the importer's own check lets "Gopalganj, India" through.
  if v_foreign
     or v_place ~* '\m(except|excluding|outside)\M'
     or v_place ~* ('\mnot\s+(in\s+)?(' || array_to_string(public.bangladesh_place_names(), '|') || ')\M')
     or v_place ~* ('\mnot\s+(in\s+)?' || v_bangla) then
    return false;
  end if;

  -- The importer places these in Bangladesh, from the actor's country field
  -- when the location is blank or just "Remote".
  if p_source in ('bdjobs', 'linkedin') then
    return true;
  end if;

  -- A place in Bangladesh.
  if (
       v_place ~* ('\m(' || array_to_string(public.bangladesh_place_names(), '|') || ')\M')
       or v_place ~ ('(^|[[:space:][:punct:]])' || v_bangla)
     ) then
    return true;
  end if;

  -- Remote, and open to Bangladesh.
  return coalesce(p_is_remote, false)
     and v_place !~* '\m(only|not)\M'
     and (
       v_place ~* '\m(worldwide|anywhere|global|globally|apac|asia[- ]pacific|south asia)\M'
       or (v_place ~* '\masia\M'
           and v_place !~* '\m(south[- ]?east|east|eastern|central|west|western|north|northern)[- ]asia\M')
     );
end;
$$;

revoke all on function public.listing_reaches_bangladesh(public.radar_source, text, boolean)
  from public, anon;
grant execute on function public.listing_reaches_bangladesh(public.radar_source, text, boolean)
  to authenticated, service_role;

alter table public.job_listings
  add column reaches_bangladesh boolean not null default false;

create or replace function public.stamp_listing_reach()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.reaches_bangladesh :=
    public.listing_reaches_bangladesh(new.source, new.location, new.is_remote);
  return new;
end;
$$;

create trigger job_listings_reach
  before insert or update of source, location, is_remote on public.job_listings
  for each row execute function public.stamp_listing_reach();

update public.job_listings
   set reaches_bangladesh =
       public.listing_reaches_bangladesh(source, location, is_remote);

-- Unchanged from 0094 except the reach check.
CREATE OR REPLACE FUNCTION public.radar_feed(p_query text DEFAULT NULL::text, p_location text DEFAULT NULL::text, p_remote boolean DEFAULT NULL::boolean, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0, p_kind text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
       and l.reaches_bangladesh
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
end $function$;

revoke all on function public.radar_feed(text, text, boolean, int, int, text) from public, anon;
grant execute on function public.radar_feed(text, text, boolean, int, int, text) to authenticated;
