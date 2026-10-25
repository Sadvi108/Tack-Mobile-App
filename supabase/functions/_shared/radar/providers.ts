/**
 * Job providers, normalised to one shape.
 *
 * Each provider answers the same question — "what is open that looks like
 * this" — and returns the same record, so the rest of Radar never knows or
 * cares which board a listing came from. Adding a board is one function and
 * one entry in `providers`.
 *
 * Nothing here takes a student's IP or user agent. Careerjet asks for both,
 * for click attribution, and Tack does not send them: a student's address is
 * theirs, and no line of this app's copy promises a job board anything about
 * them. The cost is attribution accuracy on Careerjet's side, which is their
 * business model and not a student's problem.
 */

import { jsearch } from "./jsearch.ts";

export type Source =
  | "bdjobs"
  | "linkedin"
  | "jsearch"
  | "careerjet"
  | "aijobs"
  | "remotive"
  | "arbeitnow"
  | "themuse"
  | "jobicy";

export interface Listing {
  source: Source;
  externalId: string;
  title: string;
  company: string | null;
  location: string | null;
  isRemote: boolean;
  employmentType: string | null;
  description: string | null;
  url: string;
  applyUrl: string | null;
  salaryText: string | null;
  category: string | null;
  level: string | null;
  postedAt: string | null;
  workplaceKnown?: boolean;
  expiresAt?: string | null;
  seenAt?: string;
}

export interface Query {
  /** Free text — a role, usually taken from the student's chosen path. */
  q?: string;
  location?: string;
  remote?: boolean;
  limit?: number;
  kind?: string;
}

/**
 * Descriptions are what the fit score reads.
 *
 * The first board Radar shipped with published none, so every listing scored
 * "we could not tell" and the one number that makes Radar worth opening was
 * inert. Boards that carry a description are worth more here than boards that
 * carry more jobs, and these are capped rather than truncated to nothing:
 * enough text to find the skills, not so much that a page of listings is a
 * megabyte of HTML.
 */
function description(raw: unknown, limit = 4000): string | null {
  const text = typeof raw === "string" ? raw : null;
  if (!text) return null;
  const stripped = text
    .replace(/<[^>]+>/g, " ")
    .replace(/&[a-z]+;/gi, " ")
    .replace(/\s+/g, " ")
    .trim();
  return stripped === "" ? null : stripped.slice(0, limit);
}

export interface ProviderResult {
  source: Source;
  listings: Listing[];
  /** Set when the provider could not be reached or is not configured. */
  problem?: string;
}

const TIMEOUT_MS = 8000;

/**
 * The distinctive half of a role name.
 *
 * Boards match the search string as a phrase. "Backend developer" returns two
 * results and "Frontend developer" returns none, while "backend" returns
 * fifty — because no posting is titled the way a student describes the job
 * they want. Dropping the generic half of the phrase is what turns a target
 * role into a query a job board can answer.
 *
 * If every word is generic ("graduate trainee"), the phrase is left alone —
 * an empty query would return the whole board.
 */
const GENERIC = new Set([
  "developer",
  "engineer",
  "intern",
  "internship",
  "junior",
  "senior",
  "specialist",
  "associate",
  "executive",
  "officer",
  "assistant",
  "graduate",
  "trainee",
  "the",
  "and",
  "for",
]);

export function broaden(query: string): string {
  const words = query.toLowerCase().split(/\s+/).filter((w) => w.length >= 3);
  const specific = words.filter((w) => !GENERIC.has(w));
  if (specific.length === 0) return query.trim();
  return specific.join(" ");
}

/** Never let one slow board hold up the whole search. */
async function getJson(
  url: string,
  headers: HeadersInit = {},
): Promise<unknown> {
  const abort = new AbortController();
  const timer = setTimeout(() => abort.abort(), TIMEOUT_MS);
  try {
    const res = await fetch(url, { headers, signal: abort.signal });
    if (!res.ok) throw new Error(`http ${res.status}`);
    return await res.json();
  } finally {
    clearTimeout(timer);
  }
}

/** A stable id for a board that does not give one. */
export async function hashUrl(url: string): Promise<string> {
  const bytes = new TextEncoder().encode(url);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest).slice(0, 16))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function str(value: unknown): string | null {
  return typeof value === "string" && value.trim() !== "" ? value.trim() : null;
}

// --------------------------------------------------------------------- aijobs
//
// Free, unauthenticated, JSON, refreshed twice a day. AI and ML roles only, so
// it is narrow — but its `remote=true` filter is the part that matters here:
// a remote role is one a student in Dhaka can actually take.
export async function aiJobs(query: Query): Promise<ProviderResult> {
  const params = new URLSearchParams({
    limit: String(Math.min(query.limit ?? 30, 200)),
  });
  if (query.q) params.set("q", broaden(query.q));
  if (query.remote) params.set("remote", "true");
  // The city filter is deliberately not sent. This board is global and lists
  // almost nothing outside a handful of tech capitals — `city=Dhaka` returns
  // zero, which reads to a student as "there is no work for you" rather than
  // "this board does not cover your city". Location filtering happens in
  // radar_feed, where a remote role still counts as reachable.

  try {
    const body = await getJson(
      `https://artificialintelligencejobs.co/api/jobs?${params}`,
    ) as { jobs?: unknown[] };

    const rows = Array.isArray(body?.jobs) ? body.jobs : [];
    const listings: Listing[] = [];

    for (const row of rows) {
      if (typeof row !== "object" || row === null) continue;
      const r = row as Record<string, unknown>;
      const url = str(r.url) ?? str(r.apply_url);
      const title = str(r.title);
      if (!url || !title) continue;

      listings.push({
        source: "aijobs",
        externalId: str(r.id) ?? await hashUrl(url),
        title,
        company: str(r.company),
        location: str(r.location),
        isRemote: r.remote === true,
        employmentType: null,
        description: str(r.description),
        url,
        applyUrl: str(r.apply_url),
        salaryText: str(r.salary),
        category: str(r.category),
        level: str(r.level),
        postedAt: str(r.posted),
      });
    }
    return { source: "aijobs", listings };
  } catch (e) {
    return {
      source: "aijobs",
      listings: [],
      problem: e instanceof Error ? e.message : "unreachable",
    };
  }
}

// ------------------------------------------------------------------ careerjet
//
// The one that actually covers Bangladesh. Needs an affiliate key, which lives
// in Edge Function secrets and never reaches the app.
export async function careerjet(query: Query): Promise<ProviderResult> {
  const key = Deno.env.get("CAREERJET_API_KEY");
  if (!key) {
    return {
      source: "careerjet",
      listings: [],
      problem: "not configured",
    };
  }

  const params = new URLSearchParams({
    locale_code: Deno.env.get("CAREERJET_LOCALE") ?? "en_BD",
    pagesize: String(Math.min(query.limit ?? 30, 99)),
    // Careerjet documents user_ip and user_agent as required. Tack sends its
    // own, never the student's — see the note at the top of this file.
    user_ip: "0.0.0.0",
    user_agent: "Tack/1.0 (+https://tack.app)",
  });
  // Careerjet is location-aware and covers Bangladesh, so it gets the city.
  // It keeps the full phrase: it searches descriptions, not just titles.
  if (query.q) params.set("keywords", query.q);
  if (query.location) params.set("location", query.location);

  try {
    const body = await getJson(
      `https://search.api.careerjet.net/v4/query?${params}`,
      { Authorization: `Basic ${btoa(`${key}:`)}` },
    ) as { jobs?: unknown[] };

    const rows = Array.isArray(body?.jobs) ? body.jobs : [];
    const listings: Listing[] = [];

    for (const row of rows) {
      if (typeof row !== "object" || row === null) continue;
      const r = row as Record<string, unknown>;
      const url = str(r.url);
      const title = str(r.title);
      if (!url || !title) continue;

      const locations = str(r.locations);
      listings.push({
        source: "careerjet",
        externalId: str(r.id) ?? await hashUrl(url),
        title,
        company: str(r.company),
        // As the board gave it. Appending "Bangladesh" for the en_BD locale
        // made the word useless as evidence of where a job is (0095).
        location: locations,
        isRemote: /\bremote\b/i.test(`${title} ${locations ?? ""}`),
        employmentType: null,
        description: str(r.description),
        url,
        applyUrl: null,
        salaryText: str(r.salary),
        category: null,
        level: null,
        postedAt: str(r.date),
      });
    }
    return { source: "careerjet", listings };
  } catch (e) {
    return {
      source: "careerjet",
      listings: [],
      problem: e instanceof Error ? e.message : "unreachable",
    };
  }
}

// --------------------------------------------------------------- remotive
//
// Free, no key, and every listing is remote by definition — which for a
// student in Dhaka is the category that matters most, because a remote role
// is one they can actually take. Carries a description and a clean job_type.
export async function remotive(query: Query): Promise<ProviderResult> {
  const params = new URLSearchParams({
    limit: String(Math.min(query.limit ?? 30, 100)),
  });
  if (query.q) params.set("search", broaden(query.q));

  try {
    const body = await getJson(
      `https://remotive.com/api/remote-jobs?${params}`,
    ) as { jobs?: unknown[] };

    const listings: Listing[] = [];
    for (const row of Array.isArray(body?.jobs) ? body.jobs : []) {
      if (typeof row !== "object" || row === null) continue;
      const r = row as Record<string, unknown>;
      const url = str(r.url);
      const title = str(r.title);
      if (!url || !title) continue;

      listings.push({
        source: "remotive",
        externalId: str(r.id) ?? await hashUrl(url),
        title,
        company: str(r.company_name),
        location: str(r.candidate_required_location),
        isRemote: true,
        employmentType: str(r.job_type),
        description: description(r.description),
        url,
        applyUrl: null,
        salaryText: str(r.salary),
        category: str(r.category),
        level: null,
        postedAt: str(r.publication_date),
      });
    }
    return { source: "remotive", listings };
  } catch (e) {
    return {
      source: "remotive",
      listings: [],
      problem: e instanceof Error ? e.message : "unreachable",
    };
  }
}

// Arbeitnow (Germany) and The Muse (US) were asked on every search and
// contributed nothing a student in Bangladesh could take: no row of theirs
// passes the reach rule in 0095. Their old rows age out of the cache.
export const providers = [
  jsearch,
  aiJobs,
  remotive,
  careerjet,
];

/**
 * Asks every board at once and keeps whatever answers in time.
 *
 * One board being down, slow or unconfigured must never empty the screen, so
 * failures come back as a `problem` on that provider and the listings from the
 * others are returned regardless.
 */
export async function searchAll(query: Query): Promise<ProviderResult[]> {
  const selected = query.remote === false
    ? providers.filter((p) => p !== remotive)
    : providers;
  return await Promise.all(selected.map((p) => p(query)));
}

/**
 * Same opening, two boards. Deduplicates on the apply URL, keeping the first
 * seen — providers are asked in a fixed order, so this is stable.
 */
export function dedupe(listings: Listing[]): Listing[] {
  const seen = new Set<string>();
  const out: Listing[] = [];
  for (const listing of listings) {
    let key: string;
    try {
      const url = new URL(listing.applyUrl ?? listing.url);
      url.hash = "";
      for (const name of [...url.searchParams.keys()]) {
        if (/^utm_/i.test(name) || /^(gclid|fbclid)$/i.test(name)) {
          url.searchParams.delete(name);
        }
      }
      url.searchParams.sort();
      url.pathname = url.pathname.replace(/\/+$/, "") || "/";
      key = url.toString();
    } catch {
      key = listing.url;
    }
    const identity = `${listing.source}:${listing.externalId}`;
    if (seen.has(key) || seen.has(identity)) continue;
    seen.add(key);
    seen.add(identity);
    out.push(listing);
  }
  return out;
}
