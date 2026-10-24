import { requireUser, serviceClient } from "../_shared/util/auth.ts";
import { fail, json, preflight } from "../_shared/util/http.ts";
import { documentRequest, readRequest } from "../_shared/util/requests.ts";
import { quotaRemaining } from "../_shared/ai/gateway.ts";
import { enqueueStudentJob } from "../_shared/jobs/enqueue.ts";
import { isExtractable, SUPPORTED_CV_MESSAGE } from "../_shared/cv/extract.ts";

/**
 * A first read of one CV: three readers, where each stopped, and what stuck.
 *
 * The same file read before comes back at once and free. Otherwise the read
 * is queued and this answers 202 with a job id; the model call happens in the
 * worker. The key carries the document, so asking twice for the same file is
 * one job and one charge. Uploading the same file again makes a new document,
 * which is read again.
 */
Deno.serve(async (req) => {
  const early = preflight(req);
  if (early) return early;
  const auth = await requireUser(req);
  if (!auth) return fail("You are signed out. Log in and try again.", 401);
  const body = await readRequest(req, documentRequest);
  if (body instanceof Response) return body;

  const { data: document } = await auth.client.from("documents")
    .select("id, mime_type").eq("id", body.documentId)
    .eq("user_id", auth.userId).eq("type", "cv").is("deleted_at", null)
    .maybeSingle();
  if (!document) return fail("That CV is not available.", 404);
  if (!isExtractable(document.mime_type)) {
    return fail(SUPPORTED_CV_MESSAGE, 400, "unreadable_type");
  }
  // A document's file never changes after upload, so its id is its version
  // (see the cv_first_read handler).
  const checksum = document.id as string;

  const service = serviceClient();
  const { data: existing } = await service.from("cv_first_reads")
    .select("id, chunks, readers").eq("document_id", document.id)
    .eq("checksum", checksum).eq("user_id", auth.userId).maybeSingle();
  if (existing) {
    return json({
      status: "ready",
      readId: existing.id,
      chunks: existing.chunks,
      readers: existing.readers,
      cached: true,
      quotaRemaining: await quotaRemaining(service, auth.userId),
    });
  }

  return enqueueStudentJob(
    service,
    auth.userId,
    "cv_first_read",
    { document_id: document.id },
    `cv_first_read:${auth.userId}:${document.id}`,
  );
});
