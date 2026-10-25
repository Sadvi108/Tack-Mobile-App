import { z } from "zod";
import type { Listing } from "./providers.ts";
import { APIFY_JOB_ACTOR_IDS, APIFY_JOB_ACTORS } from "./apify_actors.ts";

// Search, not the details-only actor originally supplied. Collection runs on
// an Apify schedule; Tack only reads completed runs and never starts paid work
// from a student's search. No student data or search terms leave Tack here.
export const BDJOBS_ACTOR = "scrapingmonkey~bdjobs-scraper";
export const BDJOBS_PAGE_SIZE = 100;
export const BDJOBS_MAX_AGE_MS = 48 * 60 * 60 * 1000;
const identifier = z.string().regex(/^[A-Za-z0-9]{1,100}$/);
const date = z.string().datetime({ offset: true });
export const bdjobsPageSchema = z.object({
  // Older queued pages predate multiple adapters.
  actorId: z.enum(APIFY_JOB_ACTOR_IDS).default(APIFY_JOB_ACTORS.scrapingmonkey),
  runId: identifier,
  datasetId: identifier,
  finishedAt: date,
  offset: z.number().int().min(0).max(100000),
});
export type BdjobsPage = z.infer<typeof bdjobsPageSchema>;

const text = z.string().trim().max(50000).nullish().catch(null);
const rowSchema = z.object({
  result_type: z.literal("bdjobs-job-search"),
  status: z.literal("success"),
  id: z.string().regex(/^\d+$/),
  url: z.string().url(),
  title: z.string().trim().min(1).max(500),
  company_name: text,
  location: text,
  description: text,
  education: text,
  experience: text,
  salary: text,
  employment_type: text,
  workplace: text,
  posted_at: text,
  deadline: text,
  closed: z.boolean().nullish().catch(null),
});

function plain(value: string | null | undefined, max = 4000): string | null {
  return value?.replace(/<[^>]*>/g, " ").replace(
    /&(?:nbsp|amp|lt|gt|quot);/gi,
    " ",
  )
    .replace(/\s+/g, " ").trim().slice(0, max) || null;
}

/** Date-only deadlines mean the end of that day in Bangladesh, not UTC. */
export function bdjobsDeadline(
  value: string | null | undefined,
): string | null {
  if (!value) return null;
  const match = /^(\d{4}-\d{2}-\d{2})(?:T00:00:00(?:\.000)?Z)?$/.exec(value);
  if (match) {
    const instant = Date.parse(`${match[1]}T00:00:00+06:00`);
    if (!Number.isFinite(instant)) return null;
    // Date.parse normalises dates like February 30. Do not accept those.
    if (
      new Date(instant + 6 * 3600000).toISOString().slice(0, 10) !== match[1]
    ) {
      return null;
    }
    return new Date(instant + 24 * 3600000).toISOString();
  }
  const instant = Date.parse(value);
  return Number.isFinite(instant) ? new Date(instant).toISOString() : null;
}

/** Preserve an unknown workplace; a Bangladesh location does not prove onsite. */
export function normalizeBdjobs(
  rows: unknown[],
  finishedAt: string,
  now = Date.now(),
): Listing[] {
  const out = new Map<string, Listing>();
  for (const raw of rows) {
    const parsed = rowSchema.safeParse(raw);
    if (!parsed.success) continue;
    const r = parsed.data;
    const url = new URL(r.url);
    // Keep a canonical first-party posting URL and require matching identity.
    if (
      url.protocol !== "https:" || url.hostname !== "bdjobs.com" ||
      url.port || url.username || url.password ||
      url.pathname !== `/h/details/${r.id}`
    ) continue;
    const deadline = bdjobsDeadline(r.deadline);
    if (r.deadline && !deadline) continue;
    // Close existing cached rows too; skipping closed rows would leave them live.
    const expiresAt = r.closed ? new Date(now).toISOString() : deadline;
    const workplace = plain(r.workplace)?.toLowerCase() ?? "";
    const isRemote = /^(remote|work from home|work at home)$/.test(workplace);
    const known = isRemote ||
      /^(work at office|office|on[ -]?site)$/.test(workplace);
    const posted = r.posted_at ? Date.parse(r.posted_at) : NaN;
    out.set(r.id, {
      source: "bdjobs",
      externalId: r.id,
      title: r.title,
      company: plain(r.company_name, 500),
      location: plain(r.location, 500),
      isRemote,
      workplaceKnown: known,
      employmentType: plain(r.employment_type, 120),
      description: plain(
        [r.description, r.education, r.experience].filter(Boolean).join("\n"),
      ),
      url: `https://bdjobs.com/h/details/${r.id}`,
      applyUrl: `https://bdjobs.com/h/details/${r.id}`,
      salaryText: plain(r.salary, 500),
      category: null,
      level: plain(r.experience, 500),
      postedAt: Number.isFinite(posted) ? new Date(posted).toISOString() : null,
      expiresAt,
      seenAt: finishedAt,
    });
  }
  return [...out.values()];
}

/** Bound time, redirects and body size; never expose provider error bodies. */
async function apifyJson(path: string, token: string): Promise<unknown> {
  try {
    return await readApifyJson(path, token);
  } catch (error) {
    if (
      error instanceof Error &&
      /^bdjobs_(http_\d+|empty_response|response_too_large)$/.test(
        error.message,
      )
    ) {
      throw error;
    }
    throw new Error("bdjobs_unreachable");
  }
}

async function readApifyJson(path: string, token: string): Promise<unknown> {
  const response = await fetch(`https://api.apify.com/v2/${path}`, {
    headers: { Authorization: `Bearer ${token}` },
    signal: AbortSignal.timeout(8000),
    redirect: "error",
  });
  if (!response.ok) {
    await response.body?.cancel();
    throw new Error(`bdjobs_http_${response.status}`);
  }
  const reader = response.body?.getReader();
  if (!reader) throw new Error("bdjobs_empty_response");
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.length;
      if (length > 4 * 1024 * 1024) {
        await reader.cancel();
        throw new Error("bdjobs_response_too_large");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  return JSON.parse(new TextDecoder().decode(bytes));
}

export async function latestBdjobsRun(
  token: string,
  taskId: string,
): Promise<BdjobsPage> {
  identifier.parse(taskId);
  const schema = z.object({
    data: z.object({
      id: identifier,
      actId: z.enum(APIFY_JOB_ACTOR_IDS),
      status: z.literal("SUCCEEDED"),
      defaultDatasetId: identifier,
      finishedAt: date,
    }),
  });
  const parsed = schema.safeParse(
    await apifyJson(`actor-tasks/${taskId}/runs/last?status=SUCCEEDED`, token),
  );
  if (!parsed.success) throw new Error("bdjobs_invalid_run");
  const run = parsed.data.data;
  const age = Date.now() - Date.parse(run.finishedAt);
  if (age > BDJOBS_MAX_AGE_MS || age < -60000) {
    throw new Error("bdjobs_stale_run");
  }
  return {
    actorId: run.actId,
    runId: run.id,
    datasetId: run.defaultDatasetId,
    finishedAt: run.finishedAt,
    offset: 0,
  };
}

export async function readBdjobsPage(
  token: string,
  page: BdjobsPage,
): Promise<unknown[]> {
  const safe = bdjobsPageSchema.parse(page);
  const rows = await apifyJson(
    `datasets/${safe.datasetId}/items?format=json&clean=true&offset=${safe.offset}&limit=${BDJOBS_PAGE_SIZE}`,
    token,
  );
  if (!Array.isArray(rows) || rows.length > BDJOBS_PAGE_SIZE) {
    throw new Error("bdjobs_invalid_page");
  }
  return rows;
}
