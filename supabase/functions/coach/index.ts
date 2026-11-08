import { requireUser, serviceClient } from "../_shared/util/auth.ts";
import { fail, json, preflight } from "../_shared/util/http.ts";
import { coachRequest, readRequest } from "../_shared/util/requests.ts";
import { hashText, quotaRemaining } from "../_shared/ai/gateway.ts";
import {
  containsContactDetails,
  redact,
  redactJson,
} from "../_shared/ai/redact.ts";
import { answerFromData, type Context } from "../_shared/coach/router.ts";
import {
  type CoachAction,
  finaliseActions,
  normaliseMode,
} from "../_shared/coach/actions.ts";
import { compactContext } from "../_shared/coach/context.ts";
import {
  careerQuestion,
  type Evidence,
  grounded,
  REFUSAL,
} from "../_shared/coach/cited.ts";
import { enqueueStudentJob } from "../_shared/jobs/enqueue.ts";

/** A reply Tack writes itself: free, no model. */
interface FreeAnswer {
  body: string;
  intent: string;
  actions: CoachAction[];
  guideRefusal: boolean;
}

Deno.serve(async (req) => {
  const early = preflight(req);
  if (early) return early;
  const auth = await requireUser(req);
  if (!auth) return fail("You are signed out. Log in and try again.", 401);
  const body = await readRequest(req, coachRequest);
  if (body instanceof Response) return body;

  // Contact details are never sent to a model and never saved into a
  // conversation, so the student is asked to take them out rather than the
  // question being quietly changed.
  if (containsContactDetails(body.question)) {
    return fail(
      "Your question has what looks like an email address or phone number in it. Take it out and send it again.",
      400,
      "pii_in_question",
    );
  }

  const service = serviceClient();
  const { data: context, error } = await auth.client.rpc("coach_context");
  if (error || !context) {
    return fail("Your details could not be loaded. Try again.", 503);
  }
  const ctx = context as Context;
  const mode = normaliseMode(ctx.mode);

  const data = answerFromData(body.question, ctx);
  let free: FreeAnswer | null = data ? { ...data, guideRefusal: false } : null;
  const hash = await hashText(`${body.threadId ?? "new"}:${body.question}`);
  const key = `coach_reply:${auth.userId}:${body.operationId ?? hash}`;

  // Anything the free rules cannot answer is looked up in Tack's own career
  // guides first. Evidence that carries the question is answered from, with
  // citations; a question about a named kind of job the guides do not cover
  // is refused here, free. Everything else goes to the ordinary coach.
  if (!free) {
    const { data: found, error: searchError } = await service.rpc(
      "search_career_catalog",
      { p_query: body.question, p_k: 4 },
    );
    if (searchError) {
      return fail("The coach could not look that up. Try again.", 503);
    }
    const evidence = (found ?? []) as Evidence[];
    if (grounded(evidence[0])) {
      return enqueueStudentJob(service, auth.userId, "coach_cited", {
        thread_id: body.threadId ?? null,
        question: redact(body.question).text,
        evidence,
      }, `coach_cited:${auth.userId}:${body.operationId ?? hash}`);
    }
    if (careerQuestion(body.question)) {
      free = {
        body: REFUSAL,
        intent: "guide_refusal",
        actions: finaliseActions([{ route: "paths" }], mode, ctx),
        guideRefusal: true,
      };
    }
  }

  if (!free) {
    // The context goes as an object, redacted leaf by leaf, so it is still
    // valid JSON whatever a title has in it (D11).
    return enqueueStudentJob(service, auth.userId, "coach_reply", {
      thread_id: body.threadId ?? null,
      question: redact(body.question).text,
      mode,
      context: redactJson(compactContext(ctx, mode)),
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

  // Students may write only the plain columns of a message, so a reply could
  // never claim chips or citations it does not have. Both rows are written by
  // the service, always for this student and the thread checked above.
  const { error: saveError } = await service.from("chat_messages").insert([
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
      body: free.body,
      answered_by: "data",
      actions: free.actions,
      intent: free.intent,
      ...(free.guideRefusal ? { citations: [] } : {}),
    },
  ]);
  if (saveError) {
    return fail("That conversation could not be saved. Try again.", 503);
  }
  return json({
    threadId,
    reply: free.body,
    actions: free.actions,
    intent: free.intent,
    answeredBy: "data",
    citations: free.guideRefusal ? [] : undefined,
    remaining: await quotaRemaining(service, auth.userId),
    spent: false,
  });
});
