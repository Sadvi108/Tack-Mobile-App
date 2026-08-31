-- Resolving skills for a page of listings, in one statement.
--
-- The radar function was calling reindex_listing_skills() once per listing.
-- A refresh brings back forty, so that was forty round trips to Postgres for
-- what is one set operation, and it showed: a search took between two and four
-- seconds warm, most of it waiting.
--
-- Same matching, same vocabulary, same deterministic result — one call.

create or replace function public.reindex_listings(p_listing_ids uuid[])
returns int
language plpgsql
security definer
set search_path = public
as $$
declare v_n int;
begin
  if p_listing_ids is null or array_length(p_listing_ids, 1) is null then
    return 0;
  end if;

  delete from public.job_listing_skills where listing_id = any(p_listing_ids);

  with texts as (
    select l.id,
           concat_ws(' ', l.title, l.company_name, l.category, l.level, l.description) as body
      from public.job_listings l
     where l.id = any(p_listing_ids)
  )
  insert into public.job_listing_skills (listing_id, skill_id)
  select t.id, x
    from texts t
    cross join lateral public.extract_listing_skills(t.body) as x
  on conflict do nothing;

  get diagnostics v_n = row_count;
  return v_n;
end $$;

revoke all on function public.reindex_listings(uuid[]) from public, anon, authenticated;

-- The single-listing version stays: it is the honest unit, and the batch one
-- is the optimisation. Nothing calls it now, but a one-off fix-up for a single
-- row should not have to build an array.
comment on function public.reindex_listing_skills(uuid) is
  'One listing. For a page, use reindex_listings(uuid[]) — it is one statement.';


-- The cache is a cache. Anything a board has stopped returning for a fortnight
-- is gone from it, and nothing is lost: a listing a student saved was copied
-- into a job they own at the moment they saved it.
create or replace function public.prune_job_listings(p_older_than interval default '14 days')
returns int
language plpgsql
security definer
set search_path = public
as $$
declare v_n int;
begin
  delete from public.job_listings
   where last_seen_at < now() - p_older_than;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

revoke all on function public.prune_job_listings(interval) from public, anon, authenticated;
