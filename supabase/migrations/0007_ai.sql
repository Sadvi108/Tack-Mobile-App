-- One row per distinct job description text. raw_text_hash makes the cache
-- content-addressed, so the same JD is never sent to the model twice.
create table public.job_analyses (
  id            uuid primary key default gen_random_uuid(),
  raw_text_hash text not null unique,
  source_job_id uuid references public.jobs(id) on delete set null,
  job_title     text,
  company_name  text,
  extracted     jsonb not null default '{}'::jsonb,
  model         text,
  created_at    timestamptz not null default now()
);

-- The per-user link to a shared analysis, plus the deterministic match result.
create table public.job_match_scores (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references public.profiles(id) on delete cascade,
  analysis_id    uuid not null references public.job_analyses(id) on delete cascade,
  match_percent  int not null check (match_percent between 0 and 100),
  matched_skills jsonb not null default '[]'::jsonb,
  missing_skills jsonb not null default '[]'::jsonb,
  computed_at    timestamptz not null default now(),
  unique (user_id, analysis_id)
);
create index job_match_scores_user_idx on public.job_match_scores(user_id, computed_at desc);

create table public.ai_usage (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid references public.profiles(id) on delete set null,
  feature           text not null,
  provider          text not null,
  model             text,
  prompt_tokens     int not null default 0,
  completion_tokens int not null default 0,
  cached            boolean not null default false,
  succeeded         boolean not null default true,
  error_code        text,
  queue_job_id      uuid,
  created_at        timestamptz not null default now()
);
create index ai_usage_user_day_idx on public.ai_usage(user_id, created_at desc);

-- Daily AI quota. One row per user per bucket per UTC day.
create table public.rate_limits (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,
  bucket       text not null,
  window_start date not null,
  count        int not null default 0,
  unique (user_id, bucket, window_start)
);

-- Atomically consumes one unit of quota. Returns remaining, or -1 when exhausted.
-- Called only from Edge Functions with the service role.
create or replace function public.consume_quota(p_user_id uuid, p_bucket text, p_limit int)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  today date := (now() at time zone 'utc')::date;
  n int;
begin
  insert into public.rate_limits(user_id, bucket, window_start, count)
    values (p_user_id, p_bucket, today, 1)
  on conflict (user_id, bucket, window_start) do update
    set count = case when public.rate_limits.count < p_limit
                     then public.rate_limits.count + 1
                     else public.rate_limits.count end
  returning count into n;

  if n > p_limit then return -1; end if;
  return p_limit - n;
end $$;

create or replace function public.quota_remaining(p_user_id uuid, p_bucket text, p_limit int)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select greatest(0, p_limit - coalesce(
    (select count from public.rate_limits
      where user_id = p_user_id and bucket = p_bucket
        and window_start = (now() at time zone 'utc')::date), 0))
$$;
