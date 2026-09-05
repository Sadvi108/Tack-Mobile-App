import { requireUser, serviceClient } from "../_shared/util/auth.ts";
import { fail, json, preflight } from "../_shared/util/http.ts";

/**
 * Checking a CV, free and as often as you like.
 *
 * Queues the work and returns 202 exactly as `score-cv` does — reading a PDF,
 * and especially running OCR over a photograph, is far too slow to hold a
 * request open on a phone connection.
 *
 * The difference from `score-cv` is what it does *not* do: it never reaches a
 * model, so it never touches `consume_quota` and cannot cost a student one of
 * their daily actions. That is the whole point of it existing separately
 * rather than as a flag on the scoring endpoint — two paths that share a
 * function eventually share a quota call by accident.
 */
Deno.serve(async (req) => {
  const early = preflight(req);
  if (early) return early;
  if (req.method !== "POST") return fail("Use POST.", 405);

  const auth = await requireUser(req);
  if (!auth) return fail("Sign in first.", 401);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return fail("That request could not be read.", 400);
  }

  const documentId = String(body.documentId ?? "").trim();
  if (!documentId) return fail("Pick a CV to check.", 400);

  // Read as the student, so Row Level Security decides whether this document
  // is theirs rather than this function deciding.
  const { data: doc } = await auth.client
    .from("documents")
    .select("id, status")
    .eq("id", documentId)
    .maybeSingle();
  if (!doc) return fail("That document is not one of yours.", 404);

  const service = serviceClient();

  // One pending check per document. Re-checking the same file before the first
  // has run would return the same answer twice and drain the queue for nothing;
  // re-checking after it has finished is welcome, and is the point.
  const { data: job, error } = await service
    .from("jobs_queue")
    .insert({
      user_id: auth.userId,
      type: "check_cv",
      payload: { document_id: documentId },
      idempotency_key: `check_cv:${documentId}:${Date.now()}`,
    })
    .select("id")
    .single();

  if (error) {
    console.error("cv-check:", error.message);
    return fail("The check could not be started. Try again in a moment.", 500);
  }

  return json(
    {
      status: "queued",
      jobId: job.id,
      free: true,
      message: "Reading your CV. This takes a few seconds.",
    },
    202,
  );
});
