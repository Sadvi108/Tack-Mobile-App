-- Row Level Security for every table in public.
--
-- Three shapes:
--   owned     — user_id = auth.uid(), full CRUD by the owner
--   child     — owned, plus a WITH CHECK proving the parent is also owned, so a
--               user cannot attach a row they own to a parent they do not
--   reference — readable by any authenticated user, writable by none via the API
--
-- Anything the client must not write at all (quota, usage, queue, audit) is
-- select-only here and mutated exclusively by Edge Functions holding the
-- service role, which bypasses RLS by design.

-- ---------------------------------------------------------------- helpers
create or replace function public.owns_roadmap(p_roadmap_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.roadmaps where id = p_roadmap_id and user_id = (select auth.uid()))
$$;

create or replace function public.owns_milestone(p_milestone_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.roadmap_milestones where id = p_milestone_id and user_id = (select auth.uid()))
$$;

create or replace function public.owns_application(p_application_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.job_applications where id = p_application_id and user_id = (select auth.uid()))
$$;

create or replace function public.owns_document(p_document_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.documents where id = p_document_id and user_id = (select auth.uid()))
$$;

create or replace function public.owns_session(p_session_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.interview_sessions where id = p_session_id and user_id = (select auth.uid()))
$$;

create or replace function public.owns_question(p_question_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.interview_questions where id = p_question_id and user_id = (select auth.uid()))
$$;

create or replace function public.owns_course(p_course_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.courses where id = p_course_id and user_id = (select auth.uid()))
$$;

-- ------------------------------------------------------- enable everywhere
do $$
declare t text;
begin
  for t in
    select tablename from pg_tables
      where schemaname = 'public' and tablename <> 'schema_migrations'
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
  end loop;
  execute 'alter table public.schema_migrations enable row level security';
end $$;

-- ------------------------------------------------------------ owned tables
do $$
declare t text;
begin
  foreach t in array array[
    'education','courses','activities','experiences','projects','certifications',
    'portfolio_links','user_skills','user_career_paths','roadmaps',
    'job_applications','documents','cv_parse_results','job_match_scores',
    'readiness_scores','interview_sessions','notifications'
  ] loop
    execute format($f$
      create policy %I on public.%I for select to authenticated
        using (user_id = (select auth.uid()))$f$, t || '_select_own', t);
    execute format($f$
      create policy %I on public.%I for insert to authenticated
        with check (user_id = (select auth.uid()))$f$, t || '_insert_own', t);
    execute format($f$
      create policy %I on public.%I for update to authenticated
        using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))$f$, t || '_update_own', t);
    execute format($f$
      create policy %I on public.%I for delete to authenticated
        using (user_id = (select auth.uid()))$f$, t || '_delete_own', t);
  end loop;
end $$;

-- profiles keys on id, not user_id, and may never be inserted by the client —
-- the on-signup trigger creates it.
create policy profiles_select_own on public.profiles for select to authenticated
  using (id = (select auth.uid()));
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- ------------------------------------------------------------ child tables
create policy roadmap_milestones_select on public.roadmap_milestones for select to authenticated
  using (user_id = (select auth.uid()));
create policy roadmap_milestones_insert on public.roadmap_milestones for insert to authenticated
  with check (user_id = (select auth.uid()) and public.owns_roadmap(roadmap_id));
create policy roadmap_milestones_update on public.roadmap_milestones for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()) and public.owns_roadmap(roadmap_id));
create policy roadmap_milestones_delete on public.roadmap_milestones for delete to authenticated
  using (user_id = (select auth.uid()));

create policy roadmap_tasks_select on public.roadmap_tasks for select to authenticated
  using (user_id = (select auth.uid()));
create policy roadmap_tasks_insert on public.roadmap_tasks for insert to authenticated
  with check (user_id = (select auth.uid()) and public.owns_milestone(milestone_id));
create policy roadmap_tasks_update on public.roadmap_tasks for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()) and public.owns_milestone(milestone_id));
create policy roadmap_tasks_delete on public.roadmap_tasks for delete to authenticated
  using (user_id = (select auth.uid()));

-- Status history is written by a trigger; the client may read it and nothing else.
create policy application_status_history_select on public.application_status_history for select to authenticated
  using (user_id = (select auth.uid()));

create policy interview_questions_select on public.interview_questions for select to authenticated
  using (user_id = (select auth.uid()));
create policy interview_questions_insert on public.interview_questions for insert to authenticated
  with check (user_id = (select auth.uid()) and public.owns_session(session_id));
create policy interview_questions_update on public.interview_questions for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()) and public.owns_session(session_id));

create policy interview_feedback_select on public.interview_feedback for select to authenticated
  using (user_id = (select auth.uid()));

create policy course_skills_select on public.course_skills for select to authenticated
  using (public.owns_course(course_id));
create policy course_skills_insert on public.course_skills for insert to authenticated
  with check (public.owns_course(course_id));
create policy course_skills_delete on public.course_skills for delete to authenticated
  using (public.owns_course(course_id));

-- jobs: a student's own rows, plus curated public listings.
create policy jobs_select on public.jobs for select to authenticated
  using (user_id = (select auth.uid()) or is_public);
create policy jobs_insert on public.jobs for insert to authenticated
  with check (user_id = (select auth.uid()) and is_public = false);
create policy jobs_update on public.jobs for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()) and is_public = false);
create policy jobs_delete on public.jobs for delete to authenticated
  using (user_id = (select auth.uid()));

-- A shared JD analysis is visible only to students who have run it themselves.
create policy job_analyses_select on public.job_analyses for select to authenticated
  using (exists (
    select 1 from public.job_match_scores m
      where m.analysis_id = public.job_analyses.id and m.user_id = (select auth.uid())
  ));

-- ------------------------------------------------------- reference tables
do $$
declare t text;
begin
  foreach t in array array[
    'cities','universities','skills','career_paths','career_path_skills',
    'career_path_milestones','career_path_tasks','companies','interview_question_bank'
  ] loop
    execute format($f$
      create policy %I on public.%I for select to authenticated using (true)$f$, t || '_select_all', t);
  end loop;
end $$;

-- ------------------------------------------- read-only, server-written tables
create policy ai_usage_select_own on public.ai_usage for select to authenticated
  using (user_id = (select auth.uid()));
create policy rate_limits_select_own on public.rate_limits for select to authenticated
  using (user_id = (select auth.uid()));
create policy jobs_queue_select_own on public.jobs_queue for select to authenticated
  using (user_id = (select auth.uid()));
create policy audit_log_select_own on public.audit_log for select to authenticated
  using (user_id = (select auth.uid()));

-- schema_migrations and the cohort matview are never client-readable.
revoke all on public.schema_migrations from anon, authenticated;
revoke all on public.cohort_averages from anon, authenticated;

-- Cohort comparison, but only where the cohort is large enough that a single
-- student's score cannot be inferred from it.
create view public.cohort_benchmarks
  with (security_invoker = false) as
  select year_of_study, mode, avg_total, cohort_size
    from public.cohort_averages
    where cohort_size >= 5;
grant select on public.cohort_benchmarks to authenticated;

-- The anon role reaches nothing in public; it exists only to sign in.
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke all on all functions in schema public from anon;
