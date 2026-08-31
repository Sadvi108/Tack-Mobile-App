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

export interface Listing {
  source: "careerjet" | "aijobs";
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
}

export interface Query {
  /** Free text — a role, usually taken from the student's chosen path. */
  q?: string;
  location?: string;
  remote?: boolean;
  limit?: number;
}

export interface ProviderResult {
  source: Listing["source"];
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

export const providers = [aiJobs, careerjet];

/**
 * Asks every board at once and keeps whatever answers in time.
 *
 * One board being down, slow or unconfigured must never empty the screen, so
 * failures come back as a `problem` on that provider and the listings from the
 * others are returned regardless.
 */
export async function searchAll(query: Query): Promise<ProviderResult[]> {
  return await Promise.all(providers.map((p) => p(query)));
}

/**
 * Same opening, two boards. Deduplicates on the apply URL, keeping the first
 * seen — providers are asked in a fixed order, so this is stable.
 */
export function dedupe(listings: Listing[]): Listing[] {
  const seen = new Set<string>();
  const out: Listing[] = [];
  for (const listing of listings) {
    const key = listing.url.replace(/[?#].*$/, "").replace(/\/+$/, "")
      .toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(listing);
  }
  return out;
}
