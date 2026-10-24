import { requireUser, serviceClient } from "../_shared/util/auth.ts";
import { fail, json, preflight } from "../_shared/util/http.ts";
import { prepRequest, readRequest } from "../_shared/util/requests.ts";
import { quotaRemaining } from "../_shared/ai/gateway.ts";
import { enqueueStudentJob } from "../_shared/jobs/enqueue.ts";
import { loadPrepInputs, prepHash } from "../_shared/prep/inputs.ts";

/**
 * An interview prep brief for one application.
 *
 * A brief built from the same inputs comes back at once and free. Otherwise
 * the work is queued and this answers 202 with a job id, like every AI
 * endpoint: the model call and the evidence gate happen in the worker.
 */
Deno.serve(async (req) => {
  const early = preflight(req);
  if (early) return early;
  const auth = await requireUser(req);
  if (!auth) return fail("You are signed out. Log in and try again.", 401);
  const body = await readRequest(req, prepRequest);
  if (body instanceof Response) return body;

  const service = serviceClient();
  const inputs = await loadPrepInputs(service, auth.userId, body.applicationId);
  if (!inputs) {
    return fail(
      "A prep brief is for an application at the interview stage. Move it there first.",
      409,
      "not_at_interview",
    );
  }
  const hash = await prepHash(inputs);

  const { data: cached } = await service.from("interview_prep_briefs")
    .select("id, brief").eq("application_id", body.applicationId)
    .eq("input_hash", hash).eq("user_id", auth.userId).maybeSingle();
  if (cached) {
    return json({
      status: "ready",
      briefId: cached.id,
      brief: cached.brief,
      cached: true,
      quotaRemaining: await quotaRemaining(service, auth.userId),
    });
  }

  return enqueueStudentJob(
    service,
    auth.userId,
    "interview_prep",
    { application_id: body.applicationId },
    `interview_prep:${auth.userId}:${body.applicationId}:${hash.slice(0, 24)}`,
  );
});
