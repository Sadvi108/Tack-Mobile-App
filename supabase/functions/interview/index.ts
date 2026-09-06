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
    const role = redact(body.role).text;
    const roleSlug = role.toLowerCase().replace(/[^a-z0-9]+/g, "-");
    const { data: cached } = await service.from("interview_question_bank")
      .select("questions")
      .eq("role_slug", roleSlug).eq("session_type", body.sessionType)
      .eq("difficulty", body.difficulty).maybeSingle();
    if (cached && cached.questions.length >= body.count) {
      return json({
        questions: cached.questions.slice(0, body.count),
        cached: true,
        quotaRemaining: await quotaRemaining(service, auth.userId),
      });
    }
    const hash = await hashText(
      `${roleSlug}:${body.sessionType}:${body.difficulty}:${body.count}`,
    );
    return enqueueStudentJob(service, auth.userId, "interview_questions", {
      role,
      role_slug: roleSlug,
      session_type: body.sessionType,
      difficulty: body.difficulty,
      count: body.count,
    }, `interview_questions:${auth.userId}:${hash}`);
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
