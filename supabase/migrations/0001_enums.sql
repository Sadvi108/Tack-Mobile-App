-- Tack — enums and shared helpers.
create extension if not exists "uuid-ossp";
create extension if not exists pgcrypto;
create extension if not exists pg_trgm;

do $$ begin
  create type year_mode as enum ('explore', 'build', 'prove', 'launch');
exception when duplicate_object then null; end $$;

do $$ begin
  create type application_status as enum ('saved', 'applied', 'assessment', 'interview', 'offer', 'rejected');
exception when duplicate_object then null; end $$;

do $$ begin
  create type document_type as enum ('cv', 'certificate', 'project', 'transcript', 'other');
exception when duplicate_object then null; end $$;

do $$ begin
  create type document_status as enum ('pending', 'processing', 'ready', 'failed');
exception when duplicate_object then null; end $$;

do $$ begin
  create type task_type as enum ('skill', 'project', 'certificate', 'networking', 'application', 'cv');
exception when duplicate_object then null; end $$;

do $$ begin
  create type milestone_state as enum ('locked', 'active', 'completed');
exception when duplicate_object then null; end $$;

do $$ begin
  create type queue_status as enum ('pending', 'running', 'done', 'failed', 'dead');
exception when duplicate_object then null; end $$;

do $$ begin
  create type activity_category as enum ('club', 'volunteering', 'competition', 'leadership', 'sports', 'research', 'other');
exception when duplicate_object then null; end $$;

do $$ begin
  create type skill_source as enum ('self', 'cv', 'course', 'roadmap');
exception when duplicate_object then null; end $$;

do $$ begin
  create type skill_importance as enum ('core', 'important', 'nice');
exception when duplicate_object then null; end $$;

do $$ begin
  create type interview_type as enum ('behavioural', 'technical', 'mixed');
exception when duplicate_object then null; end $$;

do $$ begin
  create type difficulty_level as enum ('easy', 'medium', 'hard');
exception when duplicate_object then null; end $$;

do $$ begin
  create type roadmap_origin as enum ('template', 'ai');
exception when duplicate_object then null; end $$;

-- Shared updated_at trigger.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- Maps year of study to the app's mode. Single source of truth: used by the
-- profiles generated column and by the scoring engine's weight lookup.
create or replace function public.year_to_mode(year_of_study int, years_total int)
returns year_mode
language sql
immutable
as $$
  select case
    when year_of_study is null then 'explore'::year_mode
    when years_total is not null and year_of_study >= years_total then 'launch'::year_mode
    when year_of_study <= 1 then 'explore'::year_mode
    when year_of_study = 2 then 'build'::year_mode
    when year_of_study = 3 then 'prove'::year_mode
    else 'launch'::year_mode
  end
$$;
