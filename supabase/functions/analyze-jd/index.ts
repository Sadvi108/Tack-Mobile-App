import { analysisRequest, readRequest } from "../_shared/util/requests.ts";
import { enqueueStudentJob } from "../_shared/jobs/enqueue.ts";
import { requireUser, serviceClient } from "../_shared/util/auth.ts";
import { fail, json, preflight } from "../_shared/util/http.ts";
import { hashText, quotaRemaining } from "../_shared/ai/gateway.ts";
import { matchSkills } from "../_shared/ai/matching.ts";
import { redact } from "../_shared/ai/redact.ts";

/**
 * Job description analysis.
 *
 * Returns 202 with a job id and never blocks: the model call happens in the
 * worker. An identical description that has already been analysed is served
 * straight from the content-addressed cache, costs no quota, and returns 200.
 */
Deno.serve(async (req) => {
  const early = preflight(req);
  if (early) return early;

  const auth = await requireUser(req);
  if (!auth) return fail("You are signed out. Log in and try again.", 401);

  const body = await readRequest(req, analysisRequest);
  if (body instanceof Response) return body;
  const text = body.text;

  const service = serviceClient();
  const hash = await hashText(text);

  // Cache first, before quota is touched. The same posting shared between
  // students is analysed once for everyone.
  const { data: existing } = await service
    .from("job_analyses")
    .select("id, extracted")
    .eq("raw_text_hash", hash)
    .maybeSingle();

  if (existing) {
    const match = await computeMatch(
      service,
      auth.userId,
      existing.id,
      existing.extracted,
    );
    return json({
      status: "ready",
      cached: true,
      analysisId: existing.id,
      extracted: existing.extracted,
      match,
      quotaRemaining: await quotaRemaining(service, auth.userId),
    });
  }

  const { text: clean } = redact(text);
  return enqueueStudentJob(service, auth.userId, "analyse_jd", {
    text: clean,
    hash,
    jobId: body.jobId ?? null,
  }, `analyse_jd:${auth.userId}:${hash}`);
});

/** Deterministic. No model call. */
async function computeMatch(
  service: ReturnType<typeof serviceClient>,
  userId: string,
  analysisId: string,
  extracted: { skills?: string[] },
) {
  const { data: userSkills } = await service
    .from("user_skills")
    .select("skills(name)")
    .eq("user_id", userId);

  const names = ((userSkills ?? []) as unknown as Array<
    { skills?: { name?: string } | null }
  >)
    .map((row) => row.skills?.name)
    .filter((n): n is string => Boolean(n));

  const result = matchSkills(extracted.skills ?? [], names);

  await service.from("job_match_scores").upsert(
    {
      user_id: userId,
      analysis_id: analysisId,
      match_percent: result.matchPercent,
      matched_skills: result.matched,
      missing_skills: result.missing,
    },
    { onConflict: "user_id,analysis_id" },
  );

  return result;
}
