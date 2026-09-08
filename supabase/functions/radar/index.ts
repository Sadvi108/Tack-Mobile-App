import { radarRequest, readRequest } from "../_shared/util/requests.ts";
import { requireUser, serviceClient } from "../_shared/util/auth.ts";
import { fail, json, preflight } from "../_shared/util/http.ts";
import { dedupe, searchAll } from "../_shared/radar/providers.ts";

/**
 * Radar: refresh the shared listing cache, then hand back the caller's own
 * ranked feed.
 *
 * Two clients, on purpose. The service client writes listings, because those
 * are shared rows a student may read but must never write. The *user's* client
 * reads `radar_feed`, so the ranking runs as them and the fit score is
 * computed against their skills and nobody else's — the function never handles
 * a user id it was given.
 *
 * No quota is charged. Nothing here calls a model: the boards are ordinary
 * HTTP and the fit score is set arithmetic in Postgres, so there is nothing to
 * ration and no reason to make a student spend a daily AI action
 * looking at jobs.
 */
Deno.serve(async (req) => {
  const early = preflight(req);
  if (early) return early;

  const auth = await requireUser(req);
  if (!auth) return fail("You are signed out. Log in and try again.", 401);

  const body = await readRequest(req, radarRequest);
  if (body instanceof Response) return body;
  const { query, location, remote, limit, offset } = body;
  const kind = body.kind ?? null;

  const problems: Record<string, string> = {};
  let fetched = 0;

  // Paging through what is already cached does not need the boards again.
  if (body.refresh !== false && offset === 0) {
    const service = serviceClient();
    const results = await searchAll({ q: query, location, remote, limit: 40 });
    const listings = dedupe(results.flatMap((r) => r.listings));

    for (const r of results) {
      if (r.problem) problems[r.source] = r.problem;
    }

    if (listings.length > 0) {
      const { data, error } = await service
        .from("job_listings")
        .upsert(
          listings.map((l) => ({
            source: l.source,
            external_id: l.externalId,
            title: l.title,
            company_name: l.company,
            location: l.location,
            is_remote: l.isRemote,
            employment_type: l.employmentType,
            // `kind` is stamped by a trigger from this plus the title, so the
            // rule holds whoever writes the row.
            description: l.description,
            url: l.url,
            apply_url: l.applyUrl,
            salary_text: l.salaryText,
            category: l.category,
            level: l.level,
            posted_at: l.postedAt,
            last_seen_at: new Date().toISOString(),
          })),
          { onConflict: "source,external_id" },
        )
        .select("id");

      if (error) {
        // A cache that failed to write is not a failed search: whatever is
        // already stored is still worth showing.
        problems.cache = error.message;
      } else {
        fetched = data?.length ?? 0;
        // One call, not one per listing. Resolving skills for forty listings
        // used to be forty round trips, which was most of the two to four
        // seconds a warm search took.
        await service.rpc("reindex_listings", {
          p_listing_ids: (data ?? []).map(({ id }) => id),
        });
      }
    }
  }

  const { data: feed, error: feedError } = await auth.client.rpc("radar_feed", {
    p_query: query || null,
    p_location: location || null,
    p_remote: remote ?? null,
    p_limit: limit,
    p_offset: offset,
    p_kind: kind,
  });

  if (feedError) {
    return fail("Radar could not be loaded. Try again in a moment.", 500);
  }

  return json({
    listings: feed ?? [],
    fetched,
    // Named so the screen can say "Careerjet is not set up yet" rather than
    // pretending there is simply nothing out there.
    problems,
  });
});
