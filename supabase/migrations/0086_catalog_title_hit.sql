-- A question names a path only when it says the whole title.
--
-- 0085 counted any one word of a path's title, so "a marine biologist" named
-- "Marine engineering" and the coach would have answered a question about
-- biology from an engineering guide. Every word of the title (as stemmed by
-- the search) must now be in the question; "backend development" still names
-- "Backend developer", because both stem to the same words.
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
           tsvector_to_array(to_tsvector('english', c.path_title)) <@ query.terms
             and cardinality(tsvector_to_array(to_tsvector('english', c.path_title))) > 0
             as title_hit,
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
