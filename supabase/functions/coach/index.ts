import { requireUser, serviceClient } from "../_shared/util/auth.ts";
import { fail, json, preflight } from "../_shared/util/http.ts";
import { DAILY_AI_QUOTA, quotaRemaining } from "../_shared/ai/gateway.ts";
import { redact } from "../_shared/ai/redact.ts";
import { selectProvider } from "../_shared/ai/provider.ts";
import { answerFromData, type Context } from "../_shared/coach/router.ts";

/**
 * The coach.
 *
 * Answers from Tack's own numbers wherever it can, and spends one of the
 * student's three daily AI actions only when the question genuinely needs
 * language. That is not a cost trick — it is the same rule the rest of the
 * codebase follows. A score is arithmetic and must give the same answer twice;
 * asking a model to read it back would make it wobble.
 *
 * What reaches Google: the context object built by `coach_context()`, with
 * contact details stripped by `redact()` on the way past. No CV text, no
 * application notes, no document contents, no email or phone. The boundary is
 * drawn in SQL rather than in the prompt, where it would be a matter of
 * wording.
 */

const SYSTEM = `
You are the careers coach inside Tack, an app for Bangladeshi university
students working toward their first job.

You are given a JSON object describing one student. Everything in it is real
and computed from what they entered. Use it. Never invent a number, a
deadline, a company or a skill that is not in it.

How to answer:
- Plain, short English. Many readers are second-language speakers.
- Sentence case. Never title case. No markdown headings, no bullet lists
  longer than three items.
- Answer in at most 120 words. A student reads this on a phone.
- Be specific to this student. "Build a portfolio" is useless; "you have no
  projects and that is 10 points" is useful.
- Never blame them. Never use the words deadline or apply if their mode is
  discover, explore or build — those students are not job hunting yet.
- If the question is outside careers, study or work, say briefly that this is
  not something you can help with, and name one thing you can.
`.trim();

interface Body {
  question?: string;
  threadId?: string;
}

Deno.serve(async (req) => {
  const early = preflight(req);
  if (early) return early;

  const auth = await requireUser(req);
  if (!auth) return fail("You are signed out. Log in and try again.", 401);

  let body: Body;
  try {
    body = await req.json();
  } catch {
    return fail("That request could not be read.", 400);
  }

  const question = (body.question ?? "").trim();
  if (question.length < 2) {
    return fail("Ask a question and the coach will answer it.", 400);
  }
  if (question.length > 1000) {
    return fail(
      "That is a long question. Try asking it in a sentence or two.",
      400,
    );
  }

  // The student's own client, so RLS applies and the context can only ever be
  // about them.
  const { data: context, error: contextError } = await auth.client
    .rpc("coach_context");
  if (contextError || !context) {
    return fail(
      "Your details could not be loaded. Try again in a moment.",
      500,
    );
  }
  const ctx = context as Context;

  const service = serviceClient();

  // A thread to hang the conversation from.
  let threadId = body.threadId ?? null;
  if (!threadId) {
    const { data: thread, error } = await auth.client
      .from("chat_threads")
      .insert({ user_id: auth.userId, title: question.slice(0, 60) })
      .select("id")
      .single();
    if (error) return fail("That conversation could not be started.", 500);
    threadId = thread.id as string;
  }

  await auth.client.from("chat_messages").insert({
    thread_id: threadId,
    user_id: auth.userId,
    role: "student",
    body: question,
  });

  // ---- free path: Tack already knows the answer ---------------------------
  const fromData = answerFromData(question, ctx);
  if (fromData) {
    await auth.client.from("chat_messages").insert({
      thread_id: threadId,
      user_id: auth.userId,
      role: "coach",
      body: fromData.body,
      answered_by: "data",
    });
    return json({
      threadId,
      reply: fromData.body,
      answeredBy: "data",
      remaining: await quotaRemaining(service, auth.userId),
      spent: false,
    });
  }

  // ---- paid path: the question needs language -----------------------------
  // consume_quota returns what is LEFT (p_limit - count), not what was used.
  // Subtracting it from the limit again counted upward: a student saw
  // "1 remaining" after their first question and "3" after their third.
  const { data: left, error: quotaError } = await service.rpc("consume_quota", {
    p_user_id: auth.userId,
    p_bucket: "ai",
    p_limit: DAILY_AI_QUOTA,
  });

  if (quotaError) {
    return fail("The coach is unavailable right now. Try again shortly.", 500);
  }
  if (left === -1) {
    return json({
      threadId,
      reply: null,
      answeredBy: null,
      remaining: 0,
      spent: false,
      // Said as a trade that keeps Tack free, never as a punishment.
      limit:
        "You have used today's AI actions. They are shared across Tack. " +
        `They reset tomorrow. Questions about your score, skills and roadmap ` +
        `are always free — try asking one of those.`,
    }, 200);
  }

  // Contact details never reach the model. What it is asked is the student's
  // question with those pulled out, plus the context object.
  const clean = redact(question);

  try {
    const result = await selectProvider().complete({
      feature: "coach_chat",
      system: SYSTEM,
      user: `Student: ${JSON.stringify(ctx)}\n\nQuestion: ${clean.text}`,
      format: "text",
      temperature: 0.6,
      // A student is watching a spinner. Six seconds instead of twenty-six.
      thinking: "low",
      maxOutputTokens: 1500,
    });

    const reply = typeof result.data === "string"
      ? result.data.trim()
      : String(result.data);

    await auth.client.from("chat_messages").insert({
      thread_id: threadId,
      user_id: auth.userId,
      role: "coach",
      body: reply,
      answered_by: "model",
    });

    await service.from("ai_usage").insert({
      user_id: auth.userId,
      feature: "coach_chat",
      provider: result.provider,
      model: result.model,
      prompt_tokens: result.promptTokens,
      completion_tokens: result.completionTokens,
      succeeded: true,
    });

    return json({
      threadId,
      reply,
      answeredBy: "model",
      remaining: Math.max(0, left as number),
      spent: true,
    });
  } catch {
    // The action was already counted. Give it back rather than charging a
    // student for a reply they never got.
    await service.rpc("refund_quota", {
      p_user_id: auth.userId,
      p_bucket: "ai",
    });
    return fail("The coach could not answer that just now. Try again.", 503);
  }
});
