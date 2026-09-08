import { requireUser, serviceClient } from "../_shared/util/auth.ts";
import { fail, preflight } from "../_shared/util/http.ts";
import { documentRequest, readRequest } from "../_shared/util/requests.ts";
import { enqueueStudentJob } from "../_shared/jobs/enqueue.ts";
import { isExtractable, SUPPORTED_CV_MESSAGE } from "../_shared/cv/extract.ts";

Deno.serve(async (req) => {
  const early = preflight(req);
  if (early) return early;
  const auth = await requireUser(req);
  if (!auth) return fail("Sign in first.", 401);
  const body = await readRequest(req, documentRequest);
  if (body instanceof Response) return body;
  const { data: document } = await auth.client.from("documents")
    .select("mime_type").eq("id", body.documentId).eq("user_id", auth.userId)
    .eq("type", "cv").is("deleted_at", null).maybeSingle();
  if (!document) return fail("That CV is not available.", 404);
  if (!isExtractable(document.mime_type)) {
    return fail(SUPPORTED_CV_MESSAGE, 400, "unreadable_type");
  }
  return enqueueStudentJob(
    serviceClient(),
    auth.userId,
    "check_cv",
    { document_id: body.documentId },
    `check_cv:v1:${auth.userId}:${body.documentId}`,
    { free: true },
  );
});
