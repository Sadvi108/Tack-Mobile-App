-- Index every foreign key.
--
-- Postgres does not create these automatically, and without them two things
-- are slow in ways that only show up once there is data:
--
--   * deleting a row scans the whole child table to check the constraint, so
--     closing an account walks every table that references it
--   * joins along the key fall back to a sequential scan
--
-- These are all small, cheap indexes on columns that are already the join
-- path the app actually uses.

create index if not exists application_status_history_user_idx on public.application_status_history(user_id);
create index if not exists career_path_skills_skill_idx        on public.career_path_skills(skill_id);
create index if not exists career_path_tasks_skill_idx         on public.career_path_tasks(skill_id);
create index if not exists certifications_document_idx         on public.certifications(document_id);
create index if not exists course_skills_skill_idx             on public.course_skills(skill_id);
create index if not exists cv_parse_results_document_idx       on public.cv_parse_results(document_id);
create index if not exists documents_parent_idx                on public.documents(parent_document_id);
create index if not exists education_university_idx            on public.education(university_id);
create index if not exists error_reports_user_idx              on public.error_reports(user_id);
create index if not exists interview_feedback_user_idx         on public.interview_feedback(user_id);
create index if not exists interview_questions_user_idx        on public.interview_questions(user_id);
create index if not exists job_analyses_source_job_idx         on public.job_analyses(source_job_id);
create index if not exists job_applications_cv_document_idx    on public.job_applications(cv_document_id);
create index if not exists job_applications_job_idx            on public.job_applications(job_id);
create index if not exists job_match_scores_analysis_idx       on public.job_match_scores(analysis_id);
create index if not exists jobs_company_idx                    on public.jobs(company_id);
create index if not exists profiles_city_idx                   on public.profiles(city_id);
create index if not exists roadmap_milestones_source_idx       on public.roadmap_milestones(source_milestone_id);
create index if not exists roadmap_tasks_skill_idx             on public.roadmap_tasks(skill_id);
create index if not exists roadmaps_path_idx                   on public.roadmaps(path_id);
create index if not exists universities_city_idx               on public.universities(city_id);
create index if not exists user_career_paths_path_idx          on public.user_career_paths(path_id);
create index if not exists user_skills_skill_idx               on public.user_skills(skill_id);
