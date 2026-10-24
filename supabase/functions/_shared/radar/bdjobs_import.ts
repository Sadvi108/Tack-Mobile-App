import type { Handler } from "../jobs/handlers.ts";
import {
  BDJOBS_MAX_AGE_MS,
  BDJOBS_PAGE_SIZE,
  bdjobsPageSchema,
  latestBdjobsRun,
  normalizeBdjobs,
  readBdjobsPage,
} from "./bdjobs.ts";

/** Each page is a separate durable, replay-safe job, within the worker budget. */
export const importBdjobs: Handler = async (service, job) => {
  const token = Deno.env.get("APIFY_API_TOKEN");
  const taskId = Deno.env.get("APIFY_BDJOBS_TASK_ID");
  if (!token || !taskId) return { skipped: "bdjobs not configured" };
  const first = Object.keys(job.payload).length === 0;
  const page = first
    ? await latestBdjobsRun(token, taskId)
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
  const listings = normalizeBdjobs(rows, page.finishedAt);
  if (rows.length && !listings.length) throw new Error("bdjobs_no_valid_rows");
  if (listings.length) {
    const { error } = await service.rpc("cache_bdjobs_page", {
      p_rows: listings.map((listing) => ({
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
