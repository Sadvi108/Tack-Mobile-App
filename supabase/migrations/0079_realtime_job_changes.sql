-- Follow a job without asking every three seconds.
--
-- The analyser used to read its job's row every three seconds until the worker
-- finished: up to 240 reads for one analysis, most of them answered "still
-- running". Publishing jobs_queue to Realtime lets the app hear the row change
-- instead, and read it once.
--
-- Nothing new becomes readable. Realtime checks every change against the
-- subscriber's own select policy (jobs_queue_select_own, 0010), so a student
-- hears about their own jobs and nobody else's, exactly as a select would
-- return. The app treats a change as a hint and reads the row through the
-- same RLS-scoped query as before; it never trusts the payload.
--
-- The app opens the socket only while it is following a job and closes it
-- when the result is in.

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'jobs_queue'
  ) then
    alter publication supabase_realtime add table public.jobs_queue;
  end if;
end $$;
