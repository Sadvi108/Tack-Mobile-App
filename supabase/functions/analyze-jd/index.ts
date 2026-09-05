import { requireUser, serviceClient } from "../_shared/util/auth.ts";
import { fail, json, preflight } from "../_shared/util/http.ts";
import {
  hashText,
  quotaRemaining,
} from "../_shared/ai/gateway.ts";
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

  let body: { text?: string; jobId?: string };
  try {
    body = await req.json();
  } catch {
    return fail("That request could not be read.", 400);
  }

  const text = (body.text ?? "").trim();
  if (text.length < 80) {
    return fail(
      "Paste the whole job description — a line or two is not enough to analyse.",
      400,
    );
  }
  if (text.length > 20000) {
    return fail(
      "That description is very long. Paste just the role and requirements.",
      400,
    );
  }

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

  const remaining = await quotaRemaining(service, auth.userId);
  if (remaining <= 0) {
    return fail(
      "You have used today's AI actions. They reset at midnight.",
      429,
      "quota_exhausted",
    );
  }

  // Contact details are stripped here, on the way in, so they never reach the
  // queue payload let alone the model.
  const { text: clean } = redact(text);

  const { data: job, error } = await service
    .from("jobs_queue")
    .insert({
      user_id: auth.userId,
      type: "analyse_jd",
      payload: { text: clean, hash, jobId: body.jobId ?? null },
      idempotency_key: `analyse_jd:${auth.userId}:${hash}`,
    })
    .select("id")
    .single();

  if (error) {
    // A duplicate key means this student already queued this exact text.
    if (error.code === "23505") {
      return json({
        status: "queued",
        duplicate: true,
        quotaRemaining: remaining,
      }, 202);
    }
    return fail("That could not be queued. Try again in a moment.", 500);
  }

  return json(
    {
      status: "queued",
      jobId: job.id,
      quotaRemaining: remaining,
      message:
        "This takes about a minute. You can close the app and come back.",
    },
    202,
  );
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
