import { requireUser, serviceClient } from "../_shared/util/auth.ts";
import { fail, json, preflight } from "../_shared/util/http.ts";
import { coachRequest, readRequest } from "../_shared/util/requests.ts";
import { hashText, quotaRemaining } from "../_shared/ai/gateway.ts";
import { redact } from "../_shared/ai/redact.ts";
import { answerFromData, type Context } from "../_shared/coach/router.ts";
import { enqueueStudentJob } from "../_shared/jobs/enqueue.ts";

Deno.serve(async (req) => {
  const early = preflight(req);
  if (early) return early;
  const auth = await requireUser(req);
  if (!auth) return fail("You are signed out. Log in and try again.", 401);
  const body = await readRequest(req, coachRequest);
  if (body instanceof Response) return body;
  const service = serviceClient();
  const { data: context, error } = await auth.client.rpc("coach_context");
  if (error || !context) {
    return fail("Your details could not be loaded. Try again.", 503);
  }

  const fromData = answerFromData(body.question, context as Context);
  const hash = await hashText(`${body.threadId ?? "new"}:${body.question}`);
  const key = `coach_reply:${auth.userId}:${body.operationId ?? hash}`;
  if (!fromData) {
    return enqueueStudentJob(service, auth.userId, "coach_reply", {
      thread_id: body.threadId ?? null,
      question: redact(body.question).text,
      context: redact(JSON.stringify(context)).text,
    }, key);
  }
  let threadId = body.threadId;
  if (threadId) {
    const { data: owned } = await auth.client.from("chat_threads").select("id")
      .eq("user_id", auth.userId).eq("id", threadId).is("deleted_at", null)
      .maybeSingle();
    if (!owned) return fail("That conversation is not available.", 404);
  } else {
    const { data: thread, error } = await auth.client.from("chat_threads")
      .insert({ user_id: auth.userId, title: body.question.slice(0, 60) })
      .select("id").single();
    if (error) return fail("That conversation could not be started.", 503);
    threadId = thread.id as string;
  }
  if (fromData) {
    const { error } = await auth.client.from("chat_messages").insert([
      {
        thread_id: threadId,
        user_id: auth.userId,
        role: "student",
        body: body.question,
      },
      {
        thread_id: threadId,
        user_id: auth.userId,
        role: "coach",
        body: fromData.body,
        answered_by: "data",
      },
    ]);
    if (error) {
      return fail("That conversation could not be saved. Try again.", 503);
    }
    return json({
      threadId,
      reply: fromData.body,
      answeredBy: "data",
      remaining: await quotaRemaining(service, auth.userId),
      spent: false,
    });
  }
  return fail("That answer could not be prepared.", 503);
});
