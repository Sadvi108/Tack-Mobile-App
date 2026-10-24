import type { Handler } from "../jobs/handlers.ts";
import { z } from "zod";
import { hasSupportedApifyRows, normalizeApifyJobs } from "./apify_sources.ts";
import {
  BDJOBS_MAX_AGE_MS,
  BDJOBS_PAGE_SIZE,
  bdjobsPageSchema,
  latestBdjobsRun,
  readBdjobsPage,
} from "./bdjobs.ts";

/** Keep the original single-task setting compatible; isolate each task's failures. */
export function apifyJobTasks(multiple?: string, legacy?: string): string[] {
  const tasks = [
    ...new Set(
      [...(multiple ?? "").split(/[\s,]+/), legacy?.trim() ?? ""].filter(
        Boolean,
      ),
    ),
  ];
  return z.array(z.string().regex(/^[A-Za-z0-9]{1,100}$/)).max(8).parse(tasks);
}

/** Each page is a separate durable, replay-safe job, within the worker budget. */
export const importBdjobs: Handler = async (service, job) => {
  const token = Deno.env.get("APIFY_API_TOKEN");
  const tasks = apifyJobTasks(
    Deno.env.get("APIFY_JOB_TASK_IDS"),
    Deno.env.get("APIFY_BDJOBS_TASK_ID"),
  );
  if (!token || !tasks.length) return { skipped: "bdjobs not configured" };
  if (Object.keys(job.payload).length === 0) {
    // A task's failed/empty collection must not prevent another from importing.
    const slot = new Date().toISOString().slice(0, 13);
    for (const taskId of tasks) {
      const { error } = await service.from("jobs_queue").upsert({
        type: "import_bdjobs",
        payload: { taskId },
        idempotency_key: `apify:task:${taskId}:${slot}`,
      }, { onConflict: "idempotency_key", ignoreDuplicates: true });
      if (error) throw new Error("bdjobs_enqueue_failed");
    }
    return { queuedTasks: tasks.length };
  }
  const first = "taskId" in job.payload;
  const task = first
    ? z.strictObject({ taskId: z.string().regex(/^[A-Za-z0-9]{1,100}$/) })
      .parse(job.payload)
    : null;
  if (task && !tasks.includes(task.taskId)) {
    return { skipped: "task removed from configuration" };
  }
  const page = task
    ? await latestBdjobsRun(token, task.taskId)
    : bdjobsPageSchema.parse(job.payload);
  if (Date.now() - Date.parse(page.finishedAt) > BDJOBS_MAX_AGE_MS) {
    return { skipped: "bdjobs run is stale" };
  }
  // Queue the first page as well. One GET to discover a dataset is never
  // coupled to a paid Actor start, and a retry never recopies another run.
  if (first) {
    const { error } = await service.from("jobs_queue").upsert({
      type: "import_bdjobs",
      payload: page,
      idempotency_key: `bdjobs:${page.runId}:0`,
    }, { onConflict: "idempotency_key", ignoreDuplicates: true });
    if (error) throw new Error("bdjobs_enqueue_failed");
    return { queued: true, runId: page.runId };
  }

  const rows = await readBdjobsPage(token, page);
  const listings = normalizeApifyJobs(page.actorId, rows, page.finishedAt);
  if (
    rows.length && !listings.length &&
    !hasSupportedApifyRows(page.actorId, rows, page.finishedAt)
  ) {
    throw new Error("bdjobs_no_valid_rows");
  }
  if (listings.length) {
    const { error } = await service.rpc("cache_apify_job_page", {
      p_rows: listings.map((listing) => ({
        source: listing.source,
        external_id: listing.externalId,
        title: listing.title,
        company_name: listing.company,
        location: listing.location,
        is_remote: listing.isRemote,
        workplace_known: listing.workplaceKnown,
        employment_type: listing.employmentType,
        description: listing.description,
        url: listing.url,
        apply_url: listing.applyUrl,
        salary_text: listing.salaryText,
        category: listing.category,
        level: listing.level,
        posted_at: listing.postedAt,
        expires_at: listing.expiresAt,
        last_seen_at: listing.seenAt,
      })),
    });
    if (error) throw new Error("bdjobs_cache_failed");
  }
  const next = page.offset + rows.length;
  if (rows.length === BDJOBS_PAGE_SIZE) {
    if (next > 100000) throw new Error("bdjobs_dataset_limit_exceeded");
    const { error } = await service.from("jobs_queue").upsert({
      type: "import_bdjobs",
      payload: { ...page, offset: next },
      idempotency_key: `bdjobs:${page.runId}:${next}`,
    }, { onConflict: "idempotency_key", ignoreDuplicates: true });
    if (error) throw new Error("bdjobs_enqueue_failed");
  }
  return {
    runId: page.runId,
    offset: page.offset,
    imported: listings.length,
    skipped: rows.length - listings.length,
    complete: rows.length < BDJOBS_PAGE_SIZE,
  };
};
