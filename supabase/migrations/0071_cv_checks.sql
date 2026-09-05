-- A CV check that costs nothing.
--
-- Everything this stores was already being computed, and was already free:
-- metrics.ts counts sections, bullets, quantified bullets, undated entries and
-- leftover template text without a model, and extract_listing_skills() matches
-- the 440-skill taxonomy against any text at all — it is named for job
-- listings but has never cared what the text was.
--
-- All of it ran only inside parse_cv, which costs one of a student's daily AI
-- actions. So a student had to spend one to be told their CV has no Projects
-- section, which is arithmetic. That is the whole change: the counting becomes
-- free and unlimited, and the model is kept for the one thing counting cannot
-- do — reading prose and recognising a skill the taxonomy has never heard of.
--
-- Kept as history rather than a single current row. A student who fixes three
-- things and runs it again should be able to see that the list got shorter;
-- that is most of what makes them run it again.

create table if not exists public.cv_checks (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  document_id uuid not null references public.documents(id) on delete cascade,
  -- The raw counts, so a later version can say what changed without re-reading
  -- the file.
  metrics     jsonb not null default '{}'::jsonb,
  -- What the taxonomy recognised, by name.
  skills      text[] not null default '{}',
  findings    jsonb not null default '[]'::jsonb,
  problems    int not null default 0,
  suggestions int not null default 0,
  created_at  timestamptz not null default now()
);

create index if not exists cv_checks_user_idx
  on public.cv_checks(user_id, created_at desc);

alter table public.cv_checks enable row level security;
alter table public.cv_checks force row level security;

drop policy if exists cv_checks_own on public.cv_checks;
create policy cv_checks_own on public.cv_checks
  for select to authenticated
  using (user_id = (select auth.uid()));

comment on table public.cv_checks is
  'Deterministic CV findings. No model is involved and no quota is spent, so '
  'a student may run this as often as they like.';

-- ------------------------------------------------------- the skills it found
--
-- extract_listing_skills is internal and returns ids; the worker wants names.
-- Wrapped rather than granted, so the client still cannot reach the extractor
-- directly.
create or replace function public.skills_named_in(p_text text)
returns text[]
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(array_agg(s.name order by s.name), '{}')
    from public.skills s
   where s.id in (select public.extract_listing_skills(p_text));
$$;

comment on function public.skills_named_in(text) is
  'Skill names the taxonomy recognises in any text, deterministically. Used by '
  'the free CV check and the free job-description match.';

-- ------------------------------------------------------------------- checked
do $$
declare
  v_found text[];
begin
  -- The extractor is the load-bearing part of two free features, so this
  -- asserts it actually finds something rather than trusting that it does.
  v_found := public.skills_named_in(
    'We need someone comfortable with Python and SQL who has used Excel.');

  if array_length(v_found, 1) is null then
    raise exception 'skills_named_in found nothing in an obvious sentence';
  end if;
  if not ('Python' = any(v_found)) then
    raise exception 'skills_named_in missed Python: %', v_found;
  end if;

  -- And that it does not hallucinate one into empty text.
  if array_length(public.skills_named_in('   '), 1) is not null then
    raise exception 'skills_named_in invented a skill in blank text';
  end if;
end $$;
