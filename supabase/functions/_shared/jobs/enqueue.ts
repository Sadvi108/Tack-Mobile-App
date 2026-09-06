import type { SupabaseClient } from "@supabase/supabase-js";
import { fail, json } from "../util/http.ts";

export async function enqueueStudentJob(
  service: SupabaseClient,
  userId: string,
  type: string,
  payload: Record<string, unknown>,
  key: string,
  extra: Record<string, unknown> = {},
): Promise<Response> {
  const { data, error } = await service.rpc("enqueue_student_job", {
    p_user_id: userId,
    p_type: type,
    p_payload: payload,
    p_key: key,
  });
  if (error) {
    if (error.message.includes("quota_exhausted")) {
      return fail(
        "Today's AI actions are used. They reset at midnight in Bangladesh. Free checks and questions about your progress are still available.",
        429,
        "quota_exhausted",
      );
    }
    if (error.message.includes("queue_busy")) {
      return fail(
        "Your earlier requests are still running. Let one finish and try again.",
        429,
        "queue_busy",
      );
    }
    if (error.message.includes("not_owned")) {
      return fail("That item is not available.", 404, "not_found");
    }
    return fail(
      "That could not be queued. Try again in a moment.",
      503,
      "queue_unavailable",
    );
  }
  if (!data?.jobId) {
    return fail(
      "That could not be queued. Try again.",
      503,
      "queue_unavailable",
    );
  }
  return json({
    ...extra,
    ...(data.threadId ? { threadId: data.threadId } : {}),
    status: "queued",
    jobId: data.jobId,
    duplicate: data.duplicate,
    quotaRemaining: data.remaining,
    remaining: data.remaining,
    message: "Your request is saved. You can close the app and come back.",
  }, 202);
}
