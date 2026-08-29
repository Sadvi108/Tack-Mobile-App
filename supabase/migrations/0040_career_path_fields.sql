-- Link career paths to career fields.
--
-- The CV score has to answer "how well does this CV match the field you are
-- aiming at", which needs a set of expected skills per field. Two seed sets
-- exist and neither can answer it alone:
--
--   career_paths  -> career_path_skills -> skills, with core/important/nice.
--                    361 seeded rows. Rich, but keyed by path, not field.
--   career_fields  21 rows, but they only know which school subjects lead
--                    there. No skills at all.
--
-- Rather than hand-author a second skill map that would immediately drift from
-- the first, join them: a field's expected skills are the union of its paths'
-- skills. One column and a backfill buys the whole thing.

alter table public.career_paths
  add column if not exists field_id uuid references public.career_fields(id) on delete set null;

create index if not exists career_paths_field_idx on public.career_paths(field_id);

-- The ten seeded paths, mapped by category. Left as a slug join rather than
-- hard-coded ids so re-running against a fresh database gives the same result.
update public.career_paths p
   set field_id = f.id
  from public.career_fields f
 where f.slug = case p.slug
         when 'frontend-developer' then 'computer-science'
         when 'backend-developer'  then 'computer-science'
         when 'qa-engineer'        then 'computer-science'
         when 'data-analyst'       then 'statistics'
         when 'digital-marketer'   then 'marketing'
         when 'hr-executive'       then 'business'
         when 'business-analyst'   then 'business'
         when 'graphic-designer'   then 'design'
         when 'accountant'         then 'accounting'
         when 'content-writer'     then 'media'
       end;

-- A path with no field cannot contribute to a field score, so it is worth
-- knowing at migration time rather than discovering it as a silently low score.
do $$
declare v_orphans int;
begin
  select count(*) into v_orphans from public.career_paths where field_id is null and is_active;
  if v_orphans > 0 then
    raise warning 'career_paths: % active path(s) have no field_id', v_orphans;
  end if;
end $$;

-- The union, taking the strongest importance where a skill appears under more
-- than one path in the same field.
--
-- The rank is written out rather than using min() on the enum directly:
-- PostgreSQL gives enums comparison operators but no min/max aggregate, so
-- min(importance) fails at runtime, not at migration time.
create or replace function public.field_expected_skills(p_field_id uuid)
returns table (skill_id uuid, importance skill_importance)
language sql
stable
security definer
set search_path = public
as $$
  select cps.skill_id,
         (array['core','important','nice']::skill_importance[])[
           min(case cps.importance
                 when 'core'      then 1
                 when 'important' then 2
                 else                  3
               end)
         ] as importance
    from public.career_path_skills cps
    join public.career_paths cp on cp.id = cps.path_id
   where cp.field_id = p_field_id
     and cp.is_active
   group by cps.skill_id
$$;

revoke all on function public.field_expected_skills(uuid) from public, anon, authenticated;
