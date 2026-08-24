create table public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  type       text not null,
  title      text not null,
  body       text,
  payload    jsonb not null default '{}'::jsonb,
  read_at    timestamptz,
  created_at timestamptz not null default now()
);
create index notifications_user_unread_idx on public.notifications(user_id, created_at desc) where read_at is null;

-- Durable background work. Claimed with FOR UPDATE SKIP LOCKED so several
-- workers can drain it without double-processing.
create table public.jobs_queue (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid references public.profiles(id) on delete cascade,
  type            text not null,
  payload         jsonb not null default '{}'::jsonb,
  status          queue_status not null default 'pending',
  attempts        int not null default 0,
  max_attempts    int not null default 3,
  idempotency_key text unique,
  run_after       timestamptz not null default now(),
  locked_at       timestamptz,
  locked_by       text,
  last_error      text,
  result          jsonb,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index jobs_queue_claim_idx on public.jobs_queue(status, run_after) where status = 'pending';
create index jobs_queue_user_idx on public.jobs_queue(user_id, created_at desc);
create trigger jobs_queue_updated_at before update on public.jobs_queue
  for each row execute function public.set_updated_at();

create or replace function public.claim_jobs(p_limit int, p_worker text)
returns setof public.jobs_queue
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with claimed as (
    select id from public.jobs_queue
      where status = 'pending' and run_after <= now()
      order by run_after
      limit p_limit
      for update skip locked
  )
  update public.jobs_queue q
    set status = 'running', attempts = q.attempts + 1, locked_at = now(), locked_by = p_worker
    from claimed c
    where q.id = c.id
    returning q.*;
end $$;

-- Backoff: 30s, 2m, 8m. After max_attempts the job is dead-lettered, never retried.
create or replace function public.fail_job(p_id uuid, p_error text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare a int; m int;
begin
  select attempts, max_attempts into a, m from public.jobs_queue where id = p_id;
  if a >= m then
    update public.jobs_queue
      set status = 'dead', last_error = p_error, locked_at = null, locked_by = null
      where id = p_id;
  else
    update public.jobs_queue
      set status = 'pending', last_error = p_error, locked_at = null, locked_by = null,
          run_after = now() + (interval '30 seconds' * power(4, a))
      where id = p_id;
  end if;
end $$;

create table public.audit_log (
  id         bigserial primary key,
  user_id    uuid references public.profiles(id) on delete set null,
  action     text not null,
  entity     text not null,
  entity_id  uuid,
  meta       jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index audit_log_user_idx on public.audit_log(user_id, created_at desc);
create index audit_log_entity_idx on public.audit_log(entity, entity_id);
