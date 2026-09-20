import { z } from "zod";
import type { Listing, ProviderResult, Query } from "./providers.ts";

const text = z.string().trim().min(1).nullish().catch(null);
const httpUrl = z.string().url().refine((s) => /^https?:\/\//i.test(s));
const rowSchema = z.object({
  job_id: z.string().trim().min(1),
  job_title: z.string().trim().min(1),
  job_apply_link: httpUrl,
  employer_name: text,
  job_location: text,
  job_city: text,
  job_state: text,
  job_country: text,
  job_is_remote: z.boolean().nullish().catch(null),
  job_employment_type: text,
  job_description: text,
  job_salary: text,
  job_min_salary: z.number().finite().nonnegative().nullish().catch(null),
  job_max_salary: z.number().finite().nonnegative().nullish().catch(null),
  job_salary_currency: text,
  job_salary_period: text,
  job_posted_at_datetime_utc: text,
});
const responseSchema = z.object({
  status: z.literal("OK"),
  data: z.array(z.unknown()),
});

/** Reject malformed rows independently so one bad posting cannot lose a page. */
export function normalizeJsearch(rows: unknown[], query: Query): Listing[] {
  const listings: Listing[] = [];
  for (const row of rows) {
    const parsed = rowSchema.safeParse(row);
    if (!parsed.success) continue;
    const r = parsed.data;
    // Unknown is not evidence that a role is in person. Keep it out of the
    // boolean-only cache until the provider explicitly states the arrangement.
    if (r.job_is_remote == null) continue;
    if (query.remote != null && r.job_is_remote !== query.remote) continue;
    const location = r.job_location ?? [r.job_city, r.job_state, r.job_country]
      .filter(Boolean).join(", ");
    // country is a search hint upstream, not a guarantee about each result.
    if (
      !r.job_is_remote && !/^(bd|bangladesh)$/i.test(r.job_country ?? "") &&
      !/\bbangladesh\b/i.test(location)
    ) continue;
    const salaryRange = [r.job_min_salary, r.job_max_salary]
      .filter((n): n is number => n != null).map(String).join("–");
    const salary = r.job_salary ??
      (salaryRange && r.job_salary_currency
        ? `${r.job_salary_currency} ${salaryRange}${
          r.job_salary_period ? ` / ${r.job_salary_period.toLowerCase()}` : ""
        }`
        : null);
    const date = r.job_posted_at_datetime_utc
      ? Date.parse(r.job_posted_at_datetime_utc)
      : NaN;
    listings.push({
      source: "jsearch",
      externalId: r.job_id,
      title: r.job_title,
      company: r.employer_name ?? null,
      location: /\bbangladesh\b/i.test(location) || r.job_is_remote
        ? location || null
        : `${location}, Bangladesh`,
      isRemote: r.job_is_remote,
      employmentType: r.job_employment_type ?? null,
      description:
        r.job_description?.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim()
          .slice(0, 4000) || null,
      url: r.job_apply_link,
      applyUrl: r.job_apply_link,
      salaryText: salary || null,
      category: null,
      level: null,
      postedAt: Number.isFinite(date) ? new Date(date).toISOString() : null,
    });
    if (listings.length >= (query.limit ?? 40)) break;
  }
  return listings;
}

const kinds: Record<string, string> = {
  full_time: "FULLTIME",
  part_time: "PARTTIME",
  internship: "INTERN",
  contract: "CONTRACTOR",
};

// Shared only within a warm isolate; bounded, with no student identifiers.
// Identical concurrent searches share one request. Failures are never cached.
const cache = new Map<string, { until: number; result: ProviderResult }>();
const pending = new Map<string, Promise<ProviderResult>>();

export async function jsearch(query: Query): Promise<ProviderResult> {
  const key = Deno.env.get("JSEARCH_API_KEY");
  if (!key) {
    return { source: "jsearch", listings: [], problem: "not configured" };
  }
  const place = query.location?.trim() || "Bangladesh";
  const params = new URLSearchParams({
    query: `${query.q?.trim() || "jobs"} in ${place}${
      /\bbangladesh\b/i.test(place) ? "" : ", Bangladesh"
    }`,
    country: "bd",
    language: "en",
    num_pages: "1",
    date_posted: "month",
  });
  // false means both arrangements to JSearch; normalizeJsearch enforces false.
  if (query.remote === true) params.set("work_from_home", "true");
  if (query.kind && kinds[query.kind]) {
    params.set("employment_types", kinds[query.kind]);
  }
  const cacheKey = `${params}|${query.remote}|${query.limit}`;
  const hit = cache.get(cacheKey);
  if (hit && hit.until > Date.now()) return hit.result;
  const running = pending.get(cacheKey);
  if (running) return await running;
  const request = (async (): Promise<ProviderResult> => {
    try {
      const response = await fetch(
        `https://api.openwebninja.com/jsearch/search?${params}`,
        {
          headers: { "x-api-key": key },
          signal: AbortSignal.timeout(8000),
        },
      );
      if (!response.ok) {
        return {
          source: "jsearch",
          listings: [],
          problem: `http ${response.status}`,
        };
      }
      const body = responseSchema.safeParse(await response.json());
      if (!body.success) {
        return { source: "jsearch", listings: [], problem: "invalid response" };
      }
      const result: ProviderResult = {
        source: "jsearch",
        listings: normalizeJsearch(body.data.data, query),
      };
      if (cache.size >= 100) cache.delete(cache.keys().next().value!);
      cache.set(cacheKey, { until: Date.now() + 15 * 60 * 1000, result });
      return result;
    } catch {
      // Never return a fetch error that might contain credentials or URLs.
      return { source: "jsearch", listings: [], problem: "unreachable" };
    }
  })();
  pending.set(cacheKey, request);
  try {
    return await request;
  } finally {
    pending.delete(cacheKey);
  }
}
