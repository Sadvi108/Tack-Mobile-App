-- One assembled document, two renderers.
--
-- Tack has held a complete portfolio since the beginning — projects with repo
-- URLs, experiences, certifications with credential links, activities,
-- courses, skills with proficiency — and has never shown it to anybody. The CV
-- builder and the public profile page both change that, and both render the
-- same tables.
--
-- Built as two renderers over one assembled document rather than two sets of
-- queries. Two would drift: a field added to the CV would quietly go missing
-- from the public page, and the bug would be invisible until a student noticed
-- their own profile was wrong. This function is the single definition of "what
-- Tack knows about you".
--
-- Ordering is part of the contract, not a detail left to the caller. Every
-- collection comes back newest-first by the date a reader cares about — the
-- end of a job, the completion of a project — because that is the order a CV
-- is read in, and a renderer that had to sort would be a second place for the
-- rule to live.

create or replace function public.my_profile_document()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_doc jsonb;
begin
  if v_uid is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'identity', (
      select jsonb_build_object(
        'full_name', p.full_name,
        'city', c.name,
        'country', co.name,
        -- Deliberately included. The CV renderer prints them; the public page
        -- must not, and that filtering happens in one audited place rather
        -- than by leaving them out of the document and breaking the CV.
        'phone', nullif(concat_ws(' ', p.dial_code, p.phone), ''),
        'target_role', p.target_role,
        'headline', coalesce(p.target_role, p.intended_field),
        'education_stage', p.education_stage::text
      )
      from public.profiles p
      left join public.cities c on c.id = p.city_id
      left join public.countries co on co.id = p.country_id
      where p.id = v_uid
    ),

    'education', coalesce((
      select jsonb_agg(jsonb_build_object(
        'institution', coalesce(e.university_name, e.institution_name),
        'degree', e.degree,
        'field_of_study', e.field_of_study,
        'start_year', e.start_year,
        'graduation_year', e.graduation_year,
        'cgpa', e.cgpa,
        'cgpa_scale', e.cgpa_scale,
        'is_current', e.is_current
      ) order by e.is_current desc nulls last,
                 e.graduation_year desc nulls last)
      from public.education e
      where e.user_id = v_uid and e.deleted_at is null
    ), '[]'::jsonb),

    'experiences', coalesce((
      select jsonb_agg(jsonb_build_object(
        'company', x.company_name,
        'title', x.title,
        'employment_type', x.employment_type,
        'location', x.location,
        'start_date', x.start_date,
        'end_date', x.end_date,
        'is_current', x.is_current,
        'description', x.description
      ) order by x.is_current desc nulls last, x.start_date desc nulls last)
      from public.experiences x
      where x.user_id = v_uid and x.deleted_at is null
    ), '[]'::jsonb),

    'projects', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pr.id,
        'title', pr.title,
        'summary', pr.summary,
        'url', pr.url,
        'repo_url', pr.repo_url,
        'started_on', pr.started_on,
        'completed_on', pr.completed_on
      ) order by pr.completed_on desc nulls first, pr.started_on desc nulls last)
      from public.projects pr
      where pr.user_id = v_uid and pr.deleted_at is null
    ), '[]'::jsonb),

    'certifications', coalesce((
      select jsonb_agg(jsonb_build_object(
        'title', cf.title,
        'issuer', cf.issuer,
        'issued_on', cf.issued_on,
        'expires_on', cf.expires_on,
        'credential_url', cf.credential_url
      ) order by cf.issued_on desc nulls last)
      from public.certifications cf
      where cf.user_id = v_uid and cf.deleted_at is null
    ), '[]'::jsonb),

    -- Strongest first: a CV that opens with a skill the student rated 2 out of
    -- 5 is selling them short.
    'skills', coalesce((
      select jsonb_agg(jsonb_build_object(
        'name', s.name,
        'category', s.category,
        'proficiency', us.proficiency,
        'source', us.source
      ) order by us.proficiency desc nulls last, s.name)
      from public.user_skills us
      join public.skills s on s.id = us.skill_id
      where us.user_id = v_uid
    ), '[]'::jsonb),

    'activities', coalesce((
      select jsonb_agg(jsonb_build_object(
        'category', a.category::text,
        'title', a.title,
        'organisation', a.organisation,
        'role', a.role,
        'start_date', a.start_date,
        'end_date', a.end_date,
        'description', a.description
      ) order by a.start_date desc nulls last)
      from public.activities a
      where a.user_id = v_uid and a.deleted_at is null
    ), '[]'::jsonb),

    'courses', coalesce((
      select jsonb_agg(jsonb_build_object(
        'semester', cu.semester,
        'code', cu.code,
        'title', cu.title,
        'grade', cu.grade,
        'credits', cu.credits
      ) order by cu.semester_order desc nulls last, cu.title)
      from public.courses cu
      where cu.user_id = v_uid and cu.deleted_at is null
    ), '[]'::jsonb),

    'links', coalesce((
      select jsonb_agg(jsonb_build_object('kind', pl.kind, 'url', pl.url)
                       order by pl.kind)
      from public.portfolio_links pl
      where pl.user_id = v_uid and pl.deleted_at is null
    ), '[]'::jsonb)
  ) into v_doc;

  return v_doc;
end $$;

comment on function public.my_profile_document() is
  'Everything Tack knows about the signed-in student, assembled once. The CV '
  'builder renders it to PDF; the public page renders a filtered subset to '
  'HTML. Neither queries the underlying tables directly.';

grant execute on function public.my_profile_document() to authenticated;

-- ------------------------------------------------------------- cv_layouts
--
-- What the student chose to show and in what order. One row each; the absence
-- of a row means "the default layout", so nothing has to be written before a
-- CV can be built.
create table if not exists public.cv_layouts (
  user_id    uuid primary key references public.profiles(id) on delete cascade,
  template   text not null default 'clean',
  -- An ordered array of section keys. Order is the render order; a key that is
  -- absent is hidden. Storing the order in the data rather than a per-section
  -- boolean means reordering needs no schema change.
  sections   jsonb not null default
    '["experiences","projects","education","skills","certifications","activities"]'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.cv_layouts enable row level security;
alter table public.cv_layouts force row level security;

drop policy if exists cv_layouts_own on public.cv_layouts;
create policy cv_layouts_own on public.cv_layouts
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop trigger if exists cv_layouts_updated_at on public.cv_layouts;
create trigger cv_layouts_updated_at before update on public.cv_layouts
  for each row execute function public.set_updated_at();

comment on table public.cv_layouts is
  'Which CV sections a student shows, in what order. No row means the default.';

-- ------------------------------------------------------------------- checked
do $$
declare
  v_user uuid;
  v_doc  jsonb;
  v_key  text;
begin
  select id into v_user from public.profiles limit 1;
  if v_user is null then
    raise notice 'no profiles yet; the shape check needs a caller to be';
    return;
  end if;

  -- auth.uid() reads the sub claim, so setting it locally is how a migration
  -- calls a security-definer function as somebody. `true` scopes it to this
  -- transaction, so it is gone whether this commits or rolls back.
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_user)::text, true);

  v_doc := public.my_profile_document();

  -- Every key a renderer expects must be present even for a student who has
  -- filled in nothing. Otherwise the PDF builder null-checks nine times and
  -- eventually misses one — on the section the student actually has.
  foreach v_key in array array['identity', 'education', 'experiences', 'projects',
                               'certifications', 'skills', 'activities',
                               'courses', 'links']
  loop
    if not (v_doc ? v_key) then
      raise exception 'my_profile_document is missing the % key', v_key;
    end if;
  end loop;

  -- The collections must be arrays rather than null, for the same reason.
  if jsonb_typeof(v_doc->'projects') <> 'array' then
    raise exception 'projects came back as %, not an array',
      jsonb_typeof(v_doc->'projects');
  end if;
end $$;
