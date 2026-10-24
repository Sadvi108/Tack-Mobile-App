-- The coach's career guides: Tack's own catalog, cut into quotable chunks and
-- searchable, so a question about a career path is answered from what Tack
-- has written — with the words it used — or not at all.
--
-- Borrowed from Typed RAG in awesome-llm-apps
-- (rag_tutorials/agentic_typed_rag_pydanticai): evidence has a source and an
-- id, a quote must be a verbatim span of the evidence it cites, and a question
-- the evidence cannot carry is refused before any model is called. Retrieval
-- here is Postgres full-text search over the catalog rather than embeddings:
-- no new provider, no new key, and nothing about a student leaves the
-- database to find the evidence.

-- ------------------------------------------------------------ the chunks
create table if not exists public.career_catalog_chunks (
  -- <path slug>:<kind>:<n>, stable across rebuilds so a stored citation
  -- still points at the same sentence.
  chunk_id   text primary key,
  path_id    uuid not null references public.career_paths(id) on delete cascade,
  path_slug  text not null,
  path_title text not null,
  kind       text not null,
  text       text not null,
  tsv        tsvector not null
);

create index if not exists career_catalog_chunks_tsv
  on public.career_catalog_chunks using gin (tsv);

alter table public.career_catalog_chunks enable row level security;
alter table public.career_catalog_chunks force row level security;
-- Read through search_career_catalog() by the coach endpoint, never queried
-- by the app.
revoke all on public.career_catalog_chunks from anon, authenticated;

create or replace function public.rebuild_career_catalog_chunks()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.career_catalog_chunks;

  insert into public.career_catalog_chunks
    (chunk_id, path_id, path_slug, path_title, kind, text, tsv)
  select c.chunk_id, c.path_id, c.slug, c.title, c.kind, c.text,
         -- The path's title rides along in every chunk, so "what does a data
         -- analyst do" finds the data analyst's day even though that sentence
         -- never says "data analyst".
         setweight(to_tsvector('english', c.title), 'A')
           || to_tsvector('english', c.text)
    from (
      select p.id as path_id, p.slug, p.title,
             p.slug || ':summary:1' as chunk_id, 'summary' as kind,
             p.summary as text
        from public.career_paths p
       where p.is_active
      union all
      select p.id, p.slug, p.title,
             p.slug || ':day:' || d.n, 'day_to_day',
             'Day to day: ' || d.item
        from public.career_paths p,
             unnest(p.day_to_day) with ordinality as d(item, n)
       where p.is_active
      union all
      select p.id, p.slug, p.title,
             p.slug || ':fit:' || f.n, 'good_fit',
             'A good fit if: ' || f.item
        from public.career_paths p,
             unnest(p.good_fit_if) with ordinality as f(item, n)
       where p.is_active
      union all
      select p.id, p.slug, p.title,
             p.slug || ':salary:1', 'salary',
             'Salary: a starting ' || lower(p.title) || ' usually earns '
               || to_char(p.salary_min_bdt, 'FM999,999,999') || ' to '
               || to_char(coalesce(p.salary_max_bdt, p.salary_min_bdt), 'FM999,999,999')
               || ' taka a month.'
        from public.career_paths p
       where p.is_active and p.salary_min_bdt is not null
      union all
      select p.id, p.slug, p.title,
             p.slug || ':demand:1', 'demand',
             'Demand: hiring for this role in Bangladesh is ' || p.demand_level || '.'
        from public.career_paths p
       where p.is_active and p.demand_level is not null
      union all
      select p.id, p.slug, p.title,
             p.slug || ':ready:1', 'time_to_ready',
             'Time to job-ready: about ' || p.months_to_job_ready
               || ' months of steady work.'
        from public.career_paths p
       where p.is_active and p.months_to_job_ready is not null
      union all
      select p.id, p.slug, p.title,
             p.slug || ':step:' || (m.order_index + 1), 'step',
             'Step ' || (m.order_index + 1) || ': '
               || concat_ws(' ', m.title || '.', m.description, m.unlock_text)
        from public.career_paths p
        join public.career_path_milestones m on m.path_id = p.id
       where p.is_active
    ) c
   where nullif(btrim(c.text), '') is not null;
$$;

revoke all on function public.rebuild_career_catalog_chunks() from public, anon, authenticated;

-- The catalog is small and edited rarely, so any change rebuilds the lot. A
-- citation must never point at a sentence the catalog no longer says.
create or replace function public.career_catalog_changed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.rebuild_career_catalog_chunks();
  return null;
end $$;

revoke all on function public.career_catalog_changed() from public, anon, authenticated;

drop trigger if exists career_paths_reindex on public.career_paths;
create trigger career_paths_reindex
  after insert or update or delete on public.career_paths
  for each statement execute function public.career_catalog_changed();

drop trigger if exists career_path_milestones_reindex on public.career_path_milestones;
create trigger career_path_milestones_reindex
  after insert or update or delete on public.career_path_milestones
  for each statement execute function public.career_catalog_changed();

select public.rebuild_career_catalog_chunks();

-- ---------------------------------------------------------------- the search
--
-- Scores each chunk by how much of the question it covers: the share of the
-- question's words (stemmed, stop words dropped) that appear in the chunk or
-- its path's title. Simple, explainable, and the same every time.
-- title_hit says the question named the path itself; the coach answers from
-- the guides only when the top chunk names its path or covers most of the
-- question (GROUNDED in supabase/functions/_shared/coach/cited.ts).
create or replace function public.search_career_catalog(p_query text, p_k int default 4)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with q as (
    select coalesce(array_agg(distinct lexeme), '{}') as terms
      from unnest(to_tsvector('english', coalesce(p_query, '')))
  ),
  query as (
    select terms,
           case when cardinality(terms) = 0 then null
                else to_tsquery('simple', array_to_string(
                       array(select quote_literal(t) from unnest(terms) t), ' | '))
           end as tsq
      from q
  ),
  scored as (
    select c.chunk_id, c.path_slug, c.path_title, c.text,
           (select count(*) from unnest(query.terms) t
             where t = any (tsvector_to_array(c.tsv)))::numeric
             / cardinality(query.terms) as coverage,
           exists (select 1
                     from unnest(tsvector_to_array(to_tsvector('english', c.path_title))) l
                    where l = any (query.terms)) as title_hit,
           ts_rank_cd(c.tsv, query.tsq) as rank
      from public.career_catalog_chunks c, query
     where query.tsq is not null
       and c.tsv @@ query.tsq
  ),
  top as (
    select * from scored
     order by coverage desc, title_hit desc, rank desc, chunk_id
     limit greatest(1, least(coalesce(p_k, 4), 8))
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'chunk_id', chunk_id,
           'path_slug', path_slug,
           'path_title', path_title,
           'text', text,
           'score', round(coverage, 3),
           'title_hit', title_hit
         ) order by coverage desc, title_hit desc, rank desc, chunk_id), '[]'::jsonb)
    from top;
$$;

revoke all on function public.search_career_catalog(text, int) from public, anon, authenticated;

-- --------------------------------------------------- citations on a reply
-- What a grounded coach reply stood on: [{chunk_id, path_slug, path_title,
-- quote}], every quote already checked against the chunk it cites.
alter table public.chat_messages add column if not exists citations jsonb;
