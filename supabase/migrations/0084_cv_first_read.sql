-- The CV first read: three readers' verdicts on one version of a CV.
--
-- Keyed by the document and its checksum, so the same file is never read
-- twice and an edited CV gets a fresh read. What is stored is what the
-- screen shows: the section of each chunk and its length, and each reader's
-- needle, quit point, retelling, the phrases they remembered (already held to
-- the CV's own words by the worker) and the one change they would ask for.
-- Not the CV's text: that stays in the file.

create table if not exists public.cv_first_reads (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  document_id uuid not null references public.documents(id) on delete cascade,
  checksum    text not null,
  chunks      jsonb not null,
  readers     jsonb not null,
  job_id      uuid references public.jobs_queue(id) on delete set null,
  created_at  timestamptz not null default now(),
  unique (document_id, checksum)
);

create index if not exists cv_first_reads_user_idx
  on public.cv_first_reads(user_id, created_at desc);

alter table public.cv_first_reads enable row level security;
alter table public.cv_first_reads force row level security;

drop policy if exists cv_first_reads_own on public.cv_first_reads;
create policy cv_first_reads_own on public.cv_first_reads
  for select to authenticated
  using (user_id = (select auth.uid()));

-- Written only by the worker. Students read their own and nothing else.
revoke all on public.cv_first_reads from anon, authenticated;
grant select on public.cv_first_reads to authenticated;
