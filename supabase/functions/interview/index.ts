import { requireUser, serviceClient } from "../_shared/util/auth.ts";
import { fail, json, preflight } from "../_shared/util/http.ts";
import {
  evaluateRequest,
  questionsRequest,
  readRequest,
} from "../_shared/util/requests.ts";
import { hashText, quotaRemaining } from "../_shared/ai/gateway.ts";
import { redact } from "../_shared/ai/redact.ts";
import { enqueueStudentJob } from "../_shared/jobs/enqueue.ts";
import { questionsFor } from "../_shared/interview/bank.ts";

Deno.serve(async (req) => {
  const early = preflight(req);
  if (early) return early;
  const auth = await requireUser(req);
  if (!auth) return fail("You are signed out. Log in and try again.", 401);
  const service = serviceClient();
  const action = new URL(req.url).pathname.split("/").filter(Boolean).pop();
  if (action === "questions") {
    const body = await readRequest(req, questionsRequest);
    if (body instanceof Response) return body;
    // Hand-written questions only. A role the bank lacks gets the student's
    // nearest role, resolved in the database; nothing is ever sent to a model
    // for questions again, so this never spends an AI action.
    const served = await questionsFor(
      {
        readSet: async (roleSlug) => {
          const { data, error } = await service.from("interview_question_bank")
            .select("questions")
            .eq("role_slug", roleSlug).eq("session_type", body.sessionType)
            .eq("difficulty", body.difficulty).maybeSingle();
          return error ? null : data?.questions ?? null;
        },
        resolve: async (hint) => {
          const { data, error } = await service.rpc(
            "interview_resolve_role_for",
            { p_user_id: auth.userId, p_hint: hint },
          );
          return error ? null : data;
        },
      },
      redact(body.role).text,
      body.role,
      body.count,
    );
    if (!served) {
      return fail(
        "Practice questions could not be loaded. Try again in a moment.",
        503,
      );
    }
    return json({
      questions: served.questions,
      cached: true,
      role: served.role,
      resolvedFrom: served.resolvedFrom,
      quotaRemaining: await quotaRemaining(service, auth.userId),
    });
  }
  if (action === "evaluate") {
    const body = await readRequest(req, evaluateRequest);
    if (body instanceof Response) return body;
    const { data: question } = await auth.client.from("interview_questions")
      .select("id")
      .eq("id", body.questionId).eq("user_id", auth.userId).maybeSingle();
    if (!question) return fail("That question is not available.", 404);
    const clean = redact(body.answer).text;
    const hash = await hashText(clean);
    return enqueueStudentJob(service, auth.userId, "interview_evaluate", {
      question_id: body.questionId,
      answer: clean,
    }, `interview_evaluate:${auth.userId}:${body.questionId}:${hash}`);
  }
  return fail("Unknown action.", 404);
});
