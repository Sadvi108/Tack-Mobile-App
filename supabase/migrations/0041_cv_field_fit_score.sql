-- The CV field-fit score: how well a student's CV matches the field they are
-- aiming at, out of 10.
--
-- Nothing in this file calls a model, by design. The same rule that governs
-- the readiness score governs this one: a model turns CV prose into structured
-- facts, and Postgres turns those facts into a number. That is what makes the
-- score reproducible, explainable, free to recompute when a student changes
-- what they are aiming at, and impossible to move by writing instructions into
-- a CV.
--
-- Two inputs, both stored on cv_parse_results:
--   parsed   what the model extracted  — skills, education, experience, projects
--   metrics  what the worker measured  — word counts, bullets, dates, sections
--
-- metrics is deliberately not asked of the model. Counting bullets that
-- contain a digit is arithmetic, and arithmetic done by a language model is
-- both slower and less correct than arithmetic done here.

-- ---------------------------------------------------------------- parse side
alter table public.cv_parse_results
  add column if not exists metrics jsonb not null default '{}'::jsonb;

comment on column public.cv_parse_results.metrics is
  'Deterministic structural measurements taken by the worker from the extracted '
  'text, never from a model. Contract: chars, words, pages, bullets, '
  'bullets_quantified, bullets_action_led, sections[], has_contact, '
  'dated_entries, undated_entries, latest_entry_date, placeholder_hits, '
  'extractor, truncated.';

comment on column public.cv_parse_results.quality_score is
  'Owned by score_cv_fit, not by the model: the 0..100 field-fit score, written '
  'back here so readiness_ratios picks it up for its cv_quality component '
  'without needing to know this table exists. The model''s own opinion of '
  'quality stays inside parsed and is advisory only.';

-- Re-uploading a file you already uploaded should cost nothing, so the parse
-- cache is keyed on the checksum of the bytes. Scoped to one student on
-- purpose: sharing a parse between two people who happen to hold identical
-- files buys very little and reasons about privacy the hard way.
create index if not exists documents_user_checksum_idx
  on public.documents(user_id, checksum)
  where type = 'cv' and deleted_at is null;

-- ---------------------------------------------------------------- weights
create table if not exists public.cv_score_weights (
  mode      year_mode not null,
  component text      not null,
  weight    int       not null check (weight >= 0),
  primary key (mode, component)
);
alter table public.cv_score_weights enable row level security;
alter table public.cv_score_weights force row level security;
create policy cv_score_weights_select_all on public.cv_score_weights
  for select to authenticated using (true);
revoke all on public.cv_score_weights from anon;

-- Eight components, weighted by the student's mode. Weights sum to 100 in
-- every mode, and the assertion below refuses the migration if they do not.
--
-- The shape of the table is the product argument: evidence_depth is worth 4 to
-- a school student and 20 to a final-year. A first-year has no job to write
-- about and must not be told their CV is a 3 because of it, so the weight that
-- would punish them for it is moved onto the things they can actually control
-- — structure, length and hygiene.
insert into public.cv_score_weights (mode, component, weight) values
  ('discover','field_skill_coverage',12), ('discover','evidence_depth', 4), ('discover','recency', 2),
  ('discover','structure',           24), ('discover','quantification', 8), ('discover','action_language',12),
  ('discover','length_density',      16), ('discover','hygiene',       22),

  ('explore','field_skill_coverage', 16), ('explore','evidence_depth',  6), ('explore','recency', 4),
  ('explore','structure',            22), ('explore','quantification',  8), ('explore','action_language',12),
  ('explore','length_density',       14), ('explore','hygiene',        18),

  ('build','field_skill_coverage',   20), ('build','evidence_depth',   12), ('build','recency', 5),
  ('build','structure',              18), ('build','quantification',    9), ('build','action_language',11),
  ('build','length_density',         11), ('build','hygiene',          14),

  ('prove','field_skill_coverage',   26), ('prove','evidence_depth',   16), ('prove','recency', 8),
  ('prove','structure',              12), ('prove','quantification',   10), ('prove','action_language', 8),
  ('prove','length_density',          8), ('prove','hygiene',          12),

  ('launch','field_skill_coverage',  28), ('launch','evidence_depth',  20), ('launch','recency',10),
  ('launch','structure',             10), ('launch','quantification',  12), ('launch','action_language', 7),
  ('launch','length_density',         6), ('launch','hygiene',          7),

  -- A graduate is judged on the gap since their last dated entry more sharply
  -- than anyone else, which is the one place recency should bite.
  ('graduate','field_skill_coverage',28), ('graduate','evidence_depth',20), ('graduate','recency',13),
  ('graduate','structure',            9), ('graduate','quantification', 12), ('graduate','action_language', 6),
  ('graduate','length_density',       5), ('graduate','hygiene',         7)
on conflict (mode, component) do update set weight = excluded.weight;

do $$
declare r record;
begin
  for r in select mode, sum(weight) as total from public.cv_score_weights group by mode loop
    if r.total <> 100 then
      raise exception 'cv_score_weights: mode % sums to %, not 100', r.mode, r.total;
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------- scores
create table if not exists public.cv_scores (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references public.profiles(id) on delete cascade,
  document_id    uuid not null references public.documents(id) on delete cascade,
  parse_id       uuid references public.cv_parse_results(id) on delete set null,
  field_id       uuid references public.career_fields(id) on delete set null,
  path_id        uuid references public.career_paths(id) on delete set null,
  -- Which skill set the field components were scored against, or 'generic'
  -- when the student has not told us what they are aiming at yet.
  basis          text not null check (basis in ('path','field','generic')),
  mode           year_mode not null,
  score_raw      int not null check (score_raw between 0 and 100),
  score_10       numeric(3,1) not null check (score_10 between 0 and 10),
  components     jsonb not null default '{}'::jsonb,
  matched_skills jsonb not null default '[]'::jsonb,
  missing_skills jsonb not null default '[]'::jsonb,
  fixes          jsonb not null default '[]'::jsonb,
  delta          int,
  -- Without this you cannot tell "your score went up because you improved"
  -- from "your score went up because we changed the formula", and the app
  -- shows the student a delta.
  algo_version   int not null,
  computed_at    timestamptz not null default now()
);
create index if not exists cv_scores_user_idx     on public.cv_scores(user_id, computed_at desc);
create index if not exists cv_scores_document_idx on public.cv_scores(document_id, computed_at desc);

alter table public.cv_scores enable row level security;
alter table public.cv_scores force row level security;

create policy cv_scores_select_own on public.cv_scores for select to authenticated
  using (user_id = (select auth.uid()));

-- Deliberately not scoped TO authenticated. This exists so score_cv_fit, which
-- runs SECURITY DEFINER as the table owner under FORCE row level security, can
-- write a row. The grants below are what stop a student POSTing a score of
-- their own choosing: PostgREST connects as `authenticated`, which has select
-- and nothing else, and grants are checked before policies.
create policy cv_scores_insert_own on public.cv_scores for insert
  with check (user_id = (select auth.uid()));

grant select on public.cv_scores to authenticated;
revoke insert, update, delete on public.cv_scores from authenticated;
revoke all on public.cv_scores from anon;

-- ---------------------------------------------------------------- fix copy
-- What to tell the student for each component that scored badly. The list the
-- app shows is derived from the same numbers as the score, so it can never
-- contradict it. Sentence case, and it never blames the reader.
create or replace function public.cv_fix_copy(p_component text)
returns jsonb
language sql
immutable
as $$
  select case p_component
    when 'field_skill_coverage' then jsonb_build_object(
      'title', 'Name the skills this field asks for',
      'body',  'Your CV does not mention some of the skills employers in this field list first. Add the ones you actually have.')
    when 'evidence_depth' then jsonb_build_object(
      'title', 'Show where you used each skill',
      'body',  'A skills list on its own is hard to believe. Mention each skill inside a project or a role, so a reader can see it in use.')
    when 'recency' then jsonb_build_object(
      'title', 'Add something recent',
      'body',  'The newest dated thing on your CV is a while back. Add a recent project, course or role, and put a date on it.')
    when 'structure' then jsonb_build_object(
      'title', 'Add the sections a reader looks for',
      'body',  'A CV is skimmed in about twenty seconds. Contact details, education, experience or projects, and skills should each be easy to find.')
    when 'quantification' then jsonb_build_object(
      'title', 'Put numbers on what you did',
      'body',  'Numbers make a line concrete. Say how many, how much or how long — "led a team of four", not "led a team".')
    when 'action_language' then jsonb_build_object(
      'title', 'Start each line with what you did',
      'body',  'Open with a verb: built, ran, taught, fixed. It reads faster than "was responsible for".')
    when 'length_density' then jsonb_build_object(
      'title', 'Get the length into range',
      'body',  'Your CV is outside the length that suits your stage. Cut what no longer helps, or add detail to the work that does.')
    when 'hygiene' then jsonb_build_object(
      'title', 'Tidy the basics',
      'body',  'Check your contact details are there, every entry has a date, and nothing is left as placeholder text.')
    else jsonb_build_object('title', p_component, 'body', '')
  end
$$;
revoke all on function public.cv_fix_copy(text) from public, anon, authenticated;

-- ---------------------------------------------------------------- the scorer
create or replace function public.score_cv_fit(p_user_id uuid, p_document_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  c_algo constant int := 1;

  v_mode      year_mode;
  v_parse_id  uuid;
  v_parsed    jsonb;
  v_metrics   jsonb;
  v_path_id   uuid;
  v_field_id  uuid;
  v_basis     text := 'generic';
  v_target    text;
  v_blob_all  text;
  v_blob_ev   text;

  v_core_total int := 0; v_core_hit int := 0;
  v_imp_total  int := 0; v_imp_hit  int := 0;
  v_matched jsonb := '[]'::jsonb;
  v_missing jsonb := '[]'::jsonb;
  v_ev_total int := 0; v_ev_hit int := 0;

  r_field numeric; r_evidence numeric;
  r_recency numeric := 0; r_structure numeric := 0; r_quant numeric := 0;
  r_action numeric := 0; r_length numeric := 0; r_hygiene numeric := 0;

  v_words int; v_bullets int; v_pages int;
  v_lo int; v_hi int; v_page_cap int;
  v_latest date;
  v_sections text[];

  v_ratios     jsonb;
  v_components jsonb;
  v_earned     numeric;
  v_available  numeric;
  v_raw int; v_prev int;
  v_fixes jsonb;
  v_id uuid;
begin
  select mode into v_mode from public.profiles where id = p_user_id;
  if v_mode is null then return null; end if;

  -- The newest parse for this document. No parse, nothing to score.
  select id, parsed, metrics
    into v_parse_id, v_parsed, v_metrics
    from public.cv_parse_results
   where document_id = p_document_id and user_id = p_user_id
   order by created_at desc
   limit 1;
  if v_parse_id is null then return null; end if;

  v_parsed  := coalesce(v_parsed,  '{}'::jsonb);
  v_metrics := coalesce(v_metrics, '{}'::jsonb);

  v_blob_all := lower(v_parsed::text);
  v_blob_ev  := lower(coalesce(v_parsed->'experience', '[]'::jsonb)::text || ' ' ||
                      coalesce(v_parsed->'projects',   '[]'::jsonb)::text);

  -- ------------------------------------------------- what are they aiming at
  -- A chosen path beats an inferred field, because it names the exact skill
  -- set rather than the union of a whole field's worth of them.
  select ucp.path_id, cp.field_id
    into v_path_id, v_field_id
    from public.user_career_paths ucp
    join public.career_paths cp on cp.id = ucp.path_id
   where ucp.user_id = p_user_id and ucp.is_primary and ucp.deleted_at is null
   order by ucp.selected_at desc nulls last
   limit 1;

  if v_path_id is not null then
    v_basis := 'path';
  else
    select hsp.intended_field_id into v_field_id
      from public.high_school_profiles hsp where hsp.user_id = p_user_id;

    if v_field_id is null then
      select cp.target_role into v_target
        from public.career_preferences cp where cp.user_id = p_user_id;
      if nullif(btrim(coalesce(v_target, '')), '') is not null then
        select p.field_id into v_field_id
          from public.career_paths p
         where p.is_active
           and (lower(p.title) = lower(btrim(v_target))
                or p.slug = lower(regexp_replace(btrim(v_target), '\s+', '-', 'g')))
         limit 1;
      end if;
    end if;

    if v_field_id is not null then v_basis := 'field'; end if;
  end if;

  -- ------------------------------------------------- 1. field skill coverage
  if v_basis <> 'generic' then
    with expected as (
      select cps.skill_id, cps.importance
        from public.career_path_skills cps
       where v_basis = 'path' and cps.path_id = v_path_id
      union
      select fes.skill_id, fes.importance
        from public.field_expected_skills(v_field_id) fes
       where v_basis = 'field'
    ),
    terms as (
      select lower(btrim(t)) as term
        from jsonb_array_elements_text(
               case when jsonb_typeof(v_parsed->'skills') = 'array'
                    then v_parsed->'skills' else '[]'::jsonb end) t
    ),
    ex as (
      select e.skill_id, e.importance, s.name, s.aliases
        from expected e
        join public.skills s on s.id = e.skill_id
       where s.is_active
    ),
    hit as (
      select ex.importance, ex.name,
             (exists (select 1 from terms c
                       where c.term = lower(ex.name)
                          or c.term = any (select lower(a) from unnest(coalesce(ex.aliases, '{}')) a))
              or position(lower(ex.name) in v_blob_all) > 0) as matched
        from ex
    )
    select count(*) filter (where importance = 'core'),
           count(*) filter (where importance = 'core' and matched),
           count(*) filter (where importance = 'important'),
           count(*) filter (where importance = 'important' and matched),
           coalesce(jsonb_agg(name order by name) filter (where matched), '[]'::jsonb),
           coalesce(jsonb_agg(name order by name)
                    filter (where not matched and importance in ('core','important')), '[]'::jsonb)
      into v_core_total, v_core_hit, v_imp_total, v_imp_hit, v_matched, v_missing
      from hit;

    if v_core_total + v_imp_total > 0 then
      r_field := round(
        case when v_core_total > 0 and v_imp_total > 0
               then 0.7 * v_core_hit::numeric / v_core_total
                  + 0.3 * v_imp_hit::numeric  / v_imp_total
             when v_core_total > 0 then v_core_hit::numeric / v_core_total
             else                       v_imp_hit::numeric  / v_imp_total
        end, 4);
    end if;
  end if;

  -- ------------------------------------------------- 2. evidence depth
  -- A skill listed but never used anywhere is a claim; a skill named inside a
  -- project or a role is evidence. Only matched skills are asked about, so
  -- this cannot be gamed by listing more.
  if r_field is not null then
    select count(*), count(*) filter (where position(lower(n) in v_blob_ev) > 0)
      into v_ev_total, v_ev_hit
      from jsonb_array_elements_text(v_matched) n;
    if v_ev_total > 0 then
      r_evidence := round(v_ev_hit::numeric / v_ev_total, 4);
    else
      r_evidence := 0;
    end if;
  end if;

  -- ------------------------------------------------- 3. recency
  if coalesce(v_metrics->>'latest_entry_date', '') ~ '^[0-9]{4}-[0-9]{2}$' then
    v_latest := to_date(v_metrics->>'latest_entry_date', 'YYYY-MM');
  end if;
  r_recency := case
    when v_latest is null                                       then 0
    when v_latest > (current_date - interval '12 months')::date then 1.0
    when v_latest > (current_date - interval '24 months')::date then 0.6
    else 0.2
  end;

  -- ------------------------------------------------- 4. structure
  select array(
    select jsonb_array_elements_text(
      case when jsonb_typeof(v_metrics->'sections') = 'array'
           then v_metrics->'sections' else '[]'::jsonb end))
    into v_sections;

  r_structure := round((
      (('contact' = any(v_sections)) or coalesce((v_metrics->>'has_contact')::boolean, false))::int
    + ('education' = any(v_sections))::int
    + (('experience' = any(v_sections)) or ('projects' = any(v_sections)))::int
    + ('skills' = any(v_sections))::int
  )::numeric / 4, 4);

  -- ------------------------------------------------- 5 and 6. bullets
  v_bullets := coalesce((v_metrics->>'bullets')::int, 0);
  if v_bullets > 0 then
    r_quant  := round(least(1, coalesce((v_metrics->>'bullets_quantified')::int, 0)::numeric / v_bullets), 4);
    r_action := round(least(1, coalesce((v_metrics->>'bullets_action_led')::int, 0)::numeric / v_bullets), 4);
  end if;

  -- ------------------------------------------------- 7. length
  -- The band widens with the stage. A first-year with a short CV is normal; a
  -- graduate with the same one is not.
  case v_mode
    when 'discover' then v_lo := 200; v_hi := 500;
    when 'explore'  then v_lo := 250; v_hi := 600;
    when 'build'    then v_lo := 300; v_hi := 700;
    when 'prove'    then v_lo := 350; v_hi := 800;
    else                 v_lo := 400; v_hi := 900;
  end case;

  v_words := coalesce((v_metrics->>'words')::int, 0);
  r_length := round(case
    when v_words = 0                       then 0
    when v_words between v_lo and v_hi     then 1.0
    when v_words < v_lo                    then greatest(0, v_words::numeric / v_lo)
    else greatest(0, 1 - (v_words - v_hi)::numeric / v_hi)
  end, 4);

  -- ------------------------------------------------- 8. hygiene
  v_pages    := coalesce((v_metrics->>'pages')::int, 1);
  v_page_cap := case when v_mode in ('launch','graduate') then 2 else 1 end;

  r_hygiene := round((
      coalesce((v_metrics->>'has_contact')::boolean, false)::int
    + (coalesce((v_metrics->>'undated_entries')::int, 0) = 0)::int
    + (coalesce((v_metrics->>'placeholder_hits')::int, 0) = 0)::int
    + (v_pages <= v_page_cap)::int
    + (not coalesce((v_metrics->>'truncated')::boolean, false))::int
  )::numeric / 5, 4);

  -- ------------------------------------------------- weigh it
  -- Under 'generic' the two field components are null, and a null ratio drops
  -- out of both the numerator and the denominator. A student who has not
  -- picked a path yet is scored on what Tack can actually see, rather than
  -- marked down for a question they have not been asked.
  v_ratios := jsonb_build_object(
    'field_skill_coverage', r_field,
    'evidence_depth',       r_evidence,
    'recency',              r_recency,
    'structure',            r_structure,
    'quantification',       r_quant,
    'action_language',      r_action,
    'length_density',       r_length,
    'hygiene',              r_hygiene
  );

  with j as (
    select w.component, w.weight, (v_ratios->>w.component)::numeric as ratio
      from public.cv_score_weights w
     where w.mode = v_mode
       and jsonb_typeof(v_ratios->w.component) = 'number'
  )
  select sum(weight * ratio), sum(weight),
         jsonb_object_agg(component, jsonb_build_object(
           'ratio',  round(ratio, 4),
           'weight', weight,
           'earned', round(weight * ratio, 2)))
    into v_earned, v_available, v_components
    from j;

  if coalesce(v_available, 0) = 0 then return null; end if;

  v_raw := least(100, greatest(0, round(v_earned / v_available * 100)::int));

  -- The fix list, ordered by the points it would actually recover.
  with j as (
    select w.component, w.weight, (v_ratios->>w.component)::numeric as ratio
      from public.cv_score_weights w
     where w.mode = v_mode
       and jsonb_typeof(v_ratios->w.component) = 'number'
  ),
  g as (
    select component, round((1 - ratio) * weight / v_available * 100)::int as points
      from j
     where ratio < 0.999
  ),
  top as (select * from g where points > 0 order by points desc, component limit 4)
  select coalesce(jsonb_agg(jsonb_build_object(
           'component', component,
           'points',    points,
           'title',     public.cv_fix_copy(component)->>'title',
           'body',      public.cv_fix_copy(component)->>'body') order by points desc, component),
         '[]'::jsonb)
    into v_fixes
    from top;

  select score_raw into v_prev
    from public.cv_scores
   where document_id = p_document_id and algo_version = c_algo
   order by computed_at desc
   limit 1;

  insert into public.cv_scores (
    user_id, document_id, parse_id, field_id, path_id, basis, mode,
    score_raw, score_10, components, matched_skills, missing_skills, fixes,
    delta, algo_version)
  values (
    p_user_id, p_document_id, v_parse_id, v_field_id, v_path_id, v_basis, v_mode,
    v_raw, round(v_raw / 10.0, 1), coalesce(v_components, '{}'::jsonb), v_matched, v_missing, v_fixes,
    case when v_prev is null then null else v_raw - v_prev end, c_algo)
  returning id into v_id;

  -- Write the number back where readiness already looks for it. This is the
  -- whole integration: readiness_ratios reads cv_parse_results.quality_score
  -- for its cv_quality component and needs no knowledge of cv_scores, and the
  -- update fires the readiness recompute trigger that migration 0012 already
  -- put on this table.
  update public.cv_parse_results
     set quality_score = v_raw
   where id = v_parse_id
     and quality_score is distinct from v_raw;

  return v_id;
end $$;

revoke all on function public.score_cv_fit(uuid, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------- client path
-- score_cv_fit takes a user id and is SECURITY DEFINER, so it is service-role
-- only — the lesson of migration 0024 is that a definer function handed the
-- caller's choice of user id is not protected by row level security at all.
-- This wrapper takes no user id and can only ever act on the caller, which is
-- what makes it safe to grant. Same shape as recompute_my_readiness.
create or replace function public.recompute_my_cv_score(p_document_id uuid default null)
returns public.cv_scores
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_doc uuid;
  v_id  uuid;
  v_row public.cv_scores;
begin
  if v_uid is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;

  -- An id belonging to someone else resolves to nothing rather than to an
  -- error that would confirm the row exists.
  if p_document_id is not null then
    select d.id into v_doc
      from public.documents d
     where d.id = p_document_id and d.user_id = v_uid
       and d.type = 'cv' and d.deleted_at is null;
  else
    select d.id into v_doc
      from public.documents d
      join public.cv_parse_results r on r.document_id = d.id
     where d.user_id = v_uid and d.type = 'cv' and d.deleted_at is null
     order by d.is_default desc, r.created_at desc
     limit 1;
  end if;

  if v_doc is null then return null; end if;

  v_id := public.score_cv_fit(v_uid, v_doc);
  if v_id is null then return null; end if;

  select * into v_row from public.cv_scores where id = v_id;
  return v_row;
end $$;

grant execute on function public.recompute_my_cv_score(uuid) to authenticated;

-- The current score, without recomputing.
create or replace function public.current_cv_score()
returns public.cv_scores
language sql
stable
security invoker
as $$
  select * from public.cv_scores
    where user_id = (select auth.uid())
    order by computed_at desc
    limit 1
$$;

grant execute on function public.current_cv_score() to authenticated;

-- ---------------------------------------------------------------- staying fresh
-- Changing what you are aiming at changes what your CV is being measured
-- against, so the score has to follow. Enqueued rather than run inline, and
-- coalesced to one pending job per student by the partial unique index — the
-- same fix migration 0021 made for readiness after a burst of skill inserts
-- silently dropped every recompute but the first.
create unique index if not exists jobs_queue_one_pending_cv_score
  on public.jobs_queue (user_id, type)
  where status = 'pending' and type = 'score_cv';

create or replace function public.enqueue_cv_rescore()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  rec jsonb := to_jsonb(coalesce(new, old));
  uid uuid;
begin
  if tg_table_name = 'profiles' then
    uid := (rec->>'id')::uuid;
  else
    uid := (rec->>'user_id')::uuid;
  end if;
  if uid is null then return null; end if;

  -- Gone already during a cascading account delete.
  if not exists (select 1 from public.profiles where id = uid) then
    return null;
  end if;

  -- Nothing to rescore until a CV has been parsed. This is also what keeps
  -- the trigger inert until the worker's parse_cv handler ships: no parse
  -- rows exist yet, so no job of a type the worker cannot handle is queued.
  if not exists (select 1 from public.cv_parse_results where user_id = uid) then
    return null;
  end if;

  insert into public.jobs_queue (user_id, type, payload, run_after)
    values (uid, 'score_cv',
            jsonb_build_object('user_id', uid, 'source', tg_table_name),
            now() + interval '10 seconds')
  on conflict do nothing;

  return null;
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'user_career_paths', 'career_preferences', 'user_skills', 'profiles'
  ] loop
    execute format(
      'create trigger %I after insert or update or delete on public.%I
         for each row execute function public.enqueue_cv_rescore()',
      t || '_cv_rescore', t);
  end loop;
end $$;
