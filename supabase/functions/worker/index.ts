import { isWorkerAuthorised, serviceClient } from "../_shared/util/auth.ts";
import { fail, json, preflight } from "../_shared/util/http.ts";
import { handlers } from "../_shared/jobs/handlers.ts";

/**
 * Drains the job queue.
 *
 * Called by a cron trigger every two minutes and guarded by a bearer secret.
 * Works to a time budget rather than emptying the queue, so it always returns
 * before the platform's limit and the next run picks up where it stopped.
 */
const BUDGET_MS = 25_000;
const BATCH = 5;

Deno.serve(async (req) => {
  const early = preflight(req);
  if (early) return early;

  if (!isWorkerAuthorised(req)) {
    return fail("Not allowed.", 401);
  }

  const service = serviceClient();
  const worker = `worker-${crypto.randomUUID().slice(0, 8)}`;
  const startedAt = Date.now();

  // A job whose worker was killed mid-run stays 'running' forever, because
  // claim_jobs only ever picks up 'pending'. CV parsing is the slowest thing
  // in the system and the most likely to be caught by a restart, so the queue
  // is swept before it is drained.
  await service.rpc("reap_stuck_jobs");

  let processed = 0;
  let failed = 0;

  while (Date.now() - startedAt < BUDGET_MS) {
    const { data: jobs, error } = await service.rpc("claim_jobs", {
      p_limit: BATCH,
      p_worker: worker,
    });
    if (error) return fail("The queue could not be read.", 500);
    if (!jobs || jobs.length === 0) break;

    for (const job of jobs) {
      if (Date.now() - startedAt > BUDGET_MS) {
        // Hand it back rather than starting work that cannot finish.
        await service.rpc("fail_job", {
          p_id: job.id,
          p_error: "worker budget reached",
        });
        continue;
      }

      const handler = handlers[job.type];
      if (!handler) {
        await service
          .from("jobs_queue")
          .update({ status: "dead", last_error: `no handler for ${job.type}` })
          .eq("id", job.id);
        failed++;
        continue;
      }

      try {
        const result = await handler(service, job);
        await service
          .from("jobs_queue")
          .update({ status: "done", result, locked_at: null, locked_by: null })
          .eq("id", job.id);
        processed++;
      } catch (error) {
        // fail_job applies the backoff and dead-letters after max attempts.
        await service.rpc("fail_job", {
          p_id: job.id,
          p_error: (error as Error).message.slice(0, 500),
        });
        failed++;
      }
    }
  }

  return json({ worker, processed, failed, elapsedMs: Date.now() - startedAt });
});
