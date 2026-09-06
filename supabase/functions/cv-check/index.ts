import { requireUser, serviceClient } from "../_shared/util/auth.ts";
import { fail, preflight } from "../_shared/util/http.ts";
import { documentRequest, readRequest } from "../_shared/util/requests.ts";
import { enqueueStudentJob } from "../_shared/jobs/enqueue.ts";

Deno.serve(async (req) => {
  const early = preflight(req);
  if (early) return early;
  const auth = await requireUser(req);
  if (!auth) return fail("Sign in first.", 401);
  const body = await readRequest(req, documentRequest);
  if (body instanceof Response) return body;
  return enqueueStudentJob(
    serviceClient(),
    auth.userId,
    "check_cv",
    { document_id: body.documentId },
    `check_cv:v1:${auth.userId}:${body.documentId}`,
    { free: true },
  );
});
