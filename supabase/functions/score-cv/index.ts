import { requireUser, serviceClient } from "../_shared/util/auth.ts";
import { fail, json, preflight } from "../_shared/util/http.ts";
import {
  DAILY_AI_QUOTA,
  hashBytes,
  quotaRemaining,
  recordCacheHit,
} from "../_shared/ai/gateway.ts";
import { isExtractable } from "../_shared/cv/extract.ts";

/**
 * Scoring a CV.
 *
 * Returns 202 with a job id and never blocks: reading the file and calling the
 * model happen in the worker. A file this student has already had parsed is
 * served from the cache, costs no quota, and returns 200 — re-uploading your
 * own CV should not spend one of three daily actions.
 *
 * Note what this endpoint does *not* take: any text. The document id is the
 * whole request, and the bytes are read server-side from private storage. An
 * endpoint that accepted CV text would be accepting a payload the server can
 * produce itself, and would let a student route text around redaction.
 */
Deno.serve(async (req) => {
  const early = preflight(req);
  if (early) return early;

  const auth = await requireUser(req);
  if (!auth) return fail("You are signed out. Log in and try again.", 401);

  let body: { documentId?: string };
  try {
    body = await req.json();
  } catch {
    return fail("That request could not be read.", 400);
  }

  const documentId = (body.documentId ?? "").trim();
  if (!documentId) return fail("No CV was named in that request.", 400);

  // Read through the caller's own session, so row level security decides
  // whether this document exists at all. An id belonging to someone else
  // yields nothing to work with rather than a message confirming it is real.
  const { data: doc } = await auth.client
    .from("documents")
    .select("id, checksum, mime_type, storage_path, status")
    .eq("id", documentId)
    .eq("type", "cv")
    .is("deleted_at", null)
    .maybeSingle();

  if (!doc) return fail("That CV is not available.", 404);

  if (!isExtractable(doc.mime_type)) {
    return fail(
      "Tack can read PDFs and Word documents. Export your CV as a PDF and upload it again.",
      400,
      "unreadable_type",
    );
  }

  const service = serviceClient();

  // The checksum is what makes the cache work, and it has never been filled in
  // — the column has existed since migration 0006 and nothing wrote to it.
  let checksum = doc.checksum as string | null;
  if (!checksum) {
    const { data: blob, error } = await service.storage
      .from("documents")
      .download(doc.storage_path);
    if (error || !blob) {
      return fail(
        "That file could not be opened. Upload it again and Tack will try once more.",
        502,
      );
    }
    checksum = await hashBytes(await blob.arrayBuffer());
    await service.from("documents").update({ checksum }).eq("id", doc.id);
  }

  // Already parsed, so there is nothing to ask a model. Scoring is
  // deterministic and free, and it has to run again anyway because what the
  // student is aiming at may have changed since.
  const { data: own } = await service
    .from("cv_parse_results")
    .select("id")
    .eq("document_id", doc.id)
    .limit(1)
    .maybeSingle();

  if (own) {
    return json(await scored(service, auth.userId, doc.id, true));
  }

  // The same bytes under a different document id: the student re-uploaded a
  // file Tack has already read. Scoped to this student on purpose — sharing a
  // parse between two people who happen to hold identical files buys very
  // little and reasons about privacy the hard way.
  const { data: twins } = await service
    .from("documents")
    .select("id, cv_parse_results(parsed, metrics, warnings)")
    .eq("user_id", auth.userId)
    .eq("type", "cv")
    .eq("checksum", checksum)
    .neq("id", doc.id)
    .is("deleted_at", null)
    .limit(5);

  const twin = (twins ?? []).find((t) =>
    Array.isArray(t.cv_parse_results) && t.cv_parse_results.length > 0
  );

  if (twin) {
    const source = (twin.cv_parse_results as Array<Record<string, unknown>>)[0];
    await service.from("cv_parse_results").insert({
      document_id: doc.id,
      user_id: auth.userId,
      parsed: source.parsed,
      metrics: source.metrics,
      warnings: source.warnings ?? [],
    });
    await recordCacheHit(service, auth.userId, "parse_cv");
    return json(await scored(service, auth.userId, doc.id, true));
  }

  const remaining = await quotaRemaining(service, auth.userId);
  if (remaining <= 0) {
    return fail(
      `You have used your ${DAILY_AI_QUOTA} AI actions for today. They reset at midnight.`,
      429,
      "quota_exhausted",
    );
  }

  const { data: job, error } = await service
    .from("jobs_queue")
    .insert({
      user_id: auth.userId,
      type: "parse_cv",
      payload: { document_id: doc.id, checksum },
      idempotency_key: `parse_cv:${auth.userId}:${checksum}`,
    })
    .select("id")
    .single();

  if (error) {
    // A duplicate key means this student already queued this exact file.
    if (error.code === "23505") {
      return json({
        status: "queued",
        duplicate: true,
        quotaRemaining: remaining,
      }, 202);
    }
    return fail("That could not be queued. Try again in a moment.", 500);
  }

  await service
    .from("documents")
    .update({ status: "processing", failure_reason: null })
    .eq("id", doc.id);

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

/** Deterministic. No model call, no quota. */
async function scored(
  service: ReturnType<typeof serviceClient>,
  userId: string,
  documentId: string,
  cached: boolean,
) {
  await service.rpc("score_cv_fit", {
    p_user_id: userId,
    p_document_id: documentId,
  });
  await service
    .from("documents")
    .update({ status: "ready", failure_reason: null })
    .eq("id", documentId);

  const { data: score } = await service
    .from("cv_scores")
    .select(
      "id, score_10, score_raw, basis, components, matched_skills, missing_skills, fixes, delta",
    )
    .eq("document_id", documentId)
    .order("computed_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  return {
    status: "ready",
    cached,
    score,
    quotaRemaining: await quotaRemaining(service, userId),
  };
}
