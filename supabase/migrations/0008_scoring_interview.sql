-- A snapshot per recompute. components holds every sub-score so the detail
-- screen and the 90-day trend read from one place.
create table public.readiness_scores (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  total       int not null check (total between 0 and 100),
  mode        year_mode not null,
  components  jsonb not null default '{}'::jsonb,
  delta       int not null default 0,
  reason      text,
  computed_at timestamptz not null default now()
);
create index readiness_scores_user_time_idx on public.readiness_scores(user_id, computed_at desc);

-- Cohort benchmark: the average score per year of study, refreshed nightly.
-- A materialised view keeps the dashboard read cheap on a slow connection.
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
  where p.deleted_at is null and p.year_of_study is not null
  group by p.year_of_study, p.mode;
create unique index cohort_averages_key on public.cohort_averages(year_of_study, mode);

create table public.interview_sessions (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references public.profiles(id) on delete cascade,
  role           text not null,
  session_type   interview_type not null default 'mixed',
  difficulty     difficulty_level not null default 'medium',
  timer_enabled  boolean not null default false,
  question_count int not null default 5,
  started_at     timestamptz not null default now(),
  completed_at   timestamptz,
  overall_score  numeric(4,2) check (overall_score between 0 and 10),
  strongest_area text,
  weakest_area   text,
  points_earned  int not null default 0,
  summary        jsonb not null default '{}'::jsonb,
  deleted_at     timestamptz
);
create index interview_sessions_user_idx on public.interview_sessions(user_id, started_at desc) where deleted_at is null;

create table public.interview_questions (
  id           uuid primary key default gen_random_uuid(),
  session_id   uuid not null references public.interview_sessions(id) on delete cascade,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  order_index  int not null,
  question     text not null,
  category     text,
  answer_text  text,
  skipped      boolean not null default false,
  answered_at  timestamptz,
  unique (session_id, order_index)
);

create table public.interview_feedback (
  id           uuid primary key default gen_random_uuid(),
  question_id  uuid not null references public.interview_questions(id) on delete cascade unique,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  score        numeric(4,2) not null check (score between 0 and 10),
  went_well    jsonb not null default '[]'::jsonb,
  to_improve   jsonb not null default '[]'::jsonb,
  model_answer text,
  created_at   timestamptz not null default now()
);

-- Cached question sets keyed by (role, type, difficulty) so a repeat setup
-- costs no model call.
create table public.interview_question_bank (
  id           uuid primary key default gen_random_uuid(),
  role_slug    text not null,
  session_type interview_type not null,
  difficulty   difficulty_level not null,
  questions    jsonb not null,
  created_at   timestamptz not null default now(),
  unique (role_slug, session_type, difficulty)
);
