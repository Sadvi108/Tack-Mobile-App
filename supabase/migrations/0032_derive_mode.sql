-- The mode is derived, never stored as a free value.
--
-- If a student corrects their graduation year the mode has to follow. Storing
-- a mode string means it goes stale silently, which is the worst kind of
-- wrong: everything keeps working and everything is subtly misaddressed.
--
-- Three rules the naive version gets wrong:
--   * final year is relative to the programme, so year 4 of 4 is launch while
--     year 4 of 5 is still prove
--   * a graduation date already in the past means graduated, whatever stage
--     the student last selected — people forget to update it
--   * high school is discover regardless of any year that happens to be set
create or replace function public.derive_mode(
  p_stage           education_stage,
  p_year_of_study   int,
  p_years_total     int,
  p_graduation_year int  default null,
  p_graduation_month int default null
)
returns year_mode
language sql
immutable
as $$
  select case
    -- Nothing about school depends on a year.
    when p_stage in ('primary', 'high_school') then 'discover'::year_mode
    when p_stage = 'graduated' then 'launch'::year_mode

    -- A date that has already passed outranks the stated stage.
    when p_graduation_year is not null
     and make_date(p_graduation_year, coalesce(p_graduation_month, 12), 1)
         < date_trunc('month', now())::date
      then 'launch'::year_mode

    when p_year_of_study is null then 'explore'::year_mode
    when p_years_total is not null and p_year_of_study >= p_years_total
      then 'launch'::year_mode
    when p_year_of_study = 1 then 'explore'::year_mode
    when p_year_of_study = 2 then 'build'::year_mode
    else 'prove'::year_mode
  end
$$;

-- Point the generated column at it. The cohort view sits on the column, so
-- both come down and go back up.
drop view if exists public.cohort_benchmarks;
drop materialized view if exists public.cohort_averages;

alter table public.profiles drop column mode;
alter table public.profiles add column mode year_mode
  generated always as (
    public.derive_mode(education_stage, year_of_study, years_total, null, null)
  ) stored;

create materialized view public.cohort_averages as
  select p.year_of_study,
         p.mode,
         round(avg(r.total))::int as avg_total,
         count(*)::int            as cohort_size
  from public.profiles p
  join lateral (
    select total from public.readiness_scores
      where user_id = p.id order by computed_at desc limit 1
  ) r on true
  where p.deleted_at is null and p.mode is not null
  group by p.year_of_study, p.mode;
create unique index cohort_averages_key on public.cohort_averages(year_of_study, mode);

create view public.cohort_benchmarks
  with (security_invoker = false) as
  select year_of_study, mode, avg_total, cohort_size
    from public.cohort_averages
    where cohort_size >= 5;
grant select on public.cohort_benchmarks to authenticated;
revoke all on public.cohort_averages from anon, authenticated;

-- The weight table follows the rename, and graduate rows go: a graduate is in
-- launch mode now, so those rows were unreachable.
update public.score_weights set mode = 'discover' where mode::text = 'school';
delete from public.score_weights where mode::text = 'graduate';

revoke all on function public.derive_mode(education_stage, int, int, int, int)
  from public, anon, authenticated;
