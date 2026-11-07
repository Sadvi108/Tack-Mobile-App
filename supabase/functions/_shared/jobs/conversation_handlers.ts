import type { SupabaseClient } from "@supabase/supabase-js";
import type { Handler } from "./handlers.ts";
import {
  InvalidModelReply,
  quotaRemaining,
  runCompletion,
} from "../ai/gateway.ts";
import {
  coachSystem,
  coachUserPrompt,
  modelRoutesFor,
} from "../ai/coach_prompt.ts";
import type { LLMProvider } from "../ai/provider.ts";
import { redactJson } from "../ai/redact.ts";
import {
  answerFeedbackSchema,
  answerFeedbackShape,
  coachReplySchema,
  coachReplyShape,
  interviewQuestionsSchema,
  prepBriefSchema,
  prepBriefShape,
} from "../ai/schemas.ts";
import { finaliseActions, normaliseMode } from "../coach/actions.ts";
import { compactContext } from "../coach/context.ts";
import { loadHistoryRows, prepareHistory } from "../coach/history.ts";
import { checkCoachReply, type CoachModelReply } from "../coach/reply.ts";
import { answerIntent, type Context } from "../coach/router.ts";
import { PREP_SYSTEM } from "../ai/prep_prompt.ts";
import { citedAnswerSchema, citedAnswerShape } from "../ai/schemas.ts";
import {
  CITED_SYSTEM,
  type CitedAnswer,
  citedPrompt,
  type Evidence,
  validateCitations,
} from "../coach/cited.ts";
import { loadPrepInputs, prepHash, prepPrompt } from "../prep/inputs.ts";
import { groundBrief, isGrounded, type PrepBrief } from "../prep/evidence.ts";

type Job = Parameters<Handler>[1];

/** Said before the free answer when a model reply could not be trusted. */
export const FALLBACK_LEAD =
  "I could not give you a good answer to that one, so it did not use an AI action. Try asking it another way. Here is what I can see from your numbers:";

/**
 * The context a coach job carries: an object since 0097's endpoint, a
 * redacted JSON string before it. Anything unreadable is an empty context,
 * which every free answer copes with.
 */
export function jobContext(raw: unknown): Context {
  if (raw !== null && typeof raw === "object" && !Array.isArray(raw)) {
    return raw as Context;
  }
  if (typeof raw === "string") {
    try {
      const parsed = JSON.parse(raw);
      if (parsed !== null && typeof parsed === "object") {
        return parsed as Context;
      }
    } catch {
      // An old payload whose redaction broke the JSON (D11).
    }
  }
  return {};
}

/**
 * A coach question that needs language. The model's reply is checked in code
 * as well as by schema; a reply that fails twice is replaced by Tack's own
 * "what next" answer, saved as free, and refunded (`skipped`).
 */
export async function replyToCoach(
  service: SupabaseClient,
  job: Job,
  provider?: LLMProvider,
): Promise<Record<string, unknown>> {
  if (!job.user_id) throw new Error("user_required");
  const userId = job.user_id;
  const threadId = job.payload.thread_id as string;

  // A retry after the reply was saved returns it as it was.
  const { data: previous } = await service.from("chat_messages")
    .select("body, actions, answered_by, intent")
    .eq("job_id", job.id).eq("role", "coach").eq("user_id", userId)
    .maybeSingle();
  if (previous) {
    const fallback = previous.intent === "fallback";
    return {
      threadId,
      reply: previous.body,
      actions: previous.actions ?? [],
      answeredBy: previous.answered_by ?? "model",
      intent: previous.intent ?? "model",
      spent: !fallback,
      remaining: await quotaRemaining(service, userId),
      ...(fallback ? { skipped: "invalid_reply" } : {}),
    };
  }

  const ctx = jobContext(job.payload.context);
  const mode = normaliseMode(job.payload.mode ?? ctx.mode);
  const history = prepareHistory(
    await loadHistoryRows(service, { id: job.id, userId, threadId }),
  );
  // Compacted and redacted again here: a second line behind the endpoint,
  // and the only line for a job queued by the old one.
  const user = coachUserPrompt({
    facts: redactJson(compactContext(ctx, mode)),
    history,
    question: String(job.payload.question ?? ""),
  });

  const save = async (row: Record<string, unknown>) => {
    const { error } = await service.from("chat_messages").upsert({
      job_id: job.id,
      thread_id: threadId,
      user_id: userId,
      role: "coach",
      ...row,
    }, { onConflict: "job_id,role" });
    if (error) throw error;
  };

  try {
    const outcome = await runCompletion(
      service,
      userId,
      {
        feature: "coach_chat",
        system: coachSystem(mode),
        user,
        schema: coachReplySchema(modelRoutesFor(mode)),
        temperature: 0.5,
        thinking: "low",
        maxOutputTokens: 1500,
      },
      coachReplyShape,
      ["body", "actions"],
      {
        consumeQuota: false,
        check: (data) =>
          checkCoachReply(data as CoachModelReply, { mode, factsText: user }),
        provider,
      },
    );
    const reply = outcome.data as CoachModelReply;
    const body = reply.body.trim();
    const actions = finaliseActions(reply.actions, mode, ctx);
    await save({ body, actions, intent: "model", answered_by: "model" });
    return {
      threadId,
      reply: body,
      actions,
      answeredBy: "model",
      intent: "model",
      spent: true,
      remaining: await quotaRemaining(service, userId),
    };
  } catch (error) {
    // Anything else (a provider that is down) is retried, dead-lettered and
    // refunded by the queue as before.
    if (!(error instanceof InvalidModelReply)) throw error;
    // `next` is total, so there is always something true to say.
    const next = answerIntent("next", { ...ctx, mode })!;
    const body = `${FALLBACK_LEAD}\n\n${next.body}`;
    await save({
      body,
      actions: next.actions,
      intent: "fallback",
      answered_by: "data",
    });
    return {
      threadId,
      reply: body,
      actions: next.actions,
      answeredBy: "data",
      intent: "fallback",
      spent: false,
      skipped: "invalid_reply",
      remaining: await quotaRemaining(service, userId),
    };
  }
}

export const conversationHandlers: Record<string, Handler> = {
  coach_reply: (service, job) => replyToCoach(service, job),
  interview_questions: async (service, job) => {
    if (!job.user_id) throw new Error("user_required");
    const p = job.payload;
    const { data: cached } = await service.from("interview_question_bank")
      .select("questions")
      .eq("role_slug", p.role_slug).eq("session_type", p.session_type).eq(
        "difficulty",
        p.difficulty,
      ).maybeSingle();
    const count = p.count as number;
    if (cached && cached.questions.length >= count) {
      return {
        questions: cached.questions.slice(0, count),
        cached: true,
      };
    }
    const outcome = await runCompletion(
      service,
      job.user_id,
      {
        feature: "interview_questions",
        system:
          "Write interview questions for entry-level roles in Bangladesh. Use plain English and JSON only. Categories are technical or behavioural.",
        user:
          `Role: ${p.role}. Type: ${p.session_type}. Difficulty: ${p.difficulty}. Write ${count} questions.`,
        schema: interviewQuestionsSchema,
      },
      { questions: "object[]" },
      ["questions"],
      { consumeQuota: false },
    );
    const questions = (outcome.data as { questions: unknown[] }).questions;
    if (questions.length < count) throw new Error("incomplete_question_set");
    const { error } = await service.from("interview_question_bank").upsert({
      role_slug: p.role_slug,
      session_type: p.session_type,
      difficulty: p.difficulty,
      questions,
    }, { onConflict: "role_slug,session_type,difficulty" });
    if (error) throw error;
    return {
      questions: questions.slice(0, count),
      cached: false,
      quotaRemaining: outcome.remaining,
    };
  },
  interview_evaluate: async (service, job) => {
    if (!job.user_id) throw new Error("user_required");
    const questionId = job.payload.question_id as string;
    const { data: question } = await service.from("interview_questions").select(
      "question",
    )
      .eq("id", questionId).eq("user_id", job.user_id).maybeSingle();
    if (!question) return { skipped: "question_deleted" };
    const { data: prior } = await service.from("interview_feedback").select("*")
      .eq("question_id", questionId).eq("job_id", job.id).eq(
        "user_id",
        job.user_id,
      ).maybeSingle();
    if (prior) return { feedback: prior };
    const outcome = await runCompletion(
      service,
      job.user_id,
      {
        feature: "evaluate_answer",
        system:
          "Give specific, kind feedback to a Bangladeshi university student. Say what went well first. Use plain English and JSON. Score from zero to ten.",
        user: `Question: ${question.question}\n\nAnswer: ${job.payload.answer}`,
        schema: answerFeedbackSchema,
      },
      answerFeedbackShape,
      ["score", "went_well", "to_improve"],
      { consumeQuota: false },
    );
    const feedback = outcome.data as Record<string, unknown>;
    const { error } = await service.rpc("save_interview_feedback", {
      p_job_id: job.id,
      p_feedback: feedback,
    });
    if (error) throw error;
    return { feedback, quotaRemaining: outcome.remaining };
  },
  /**
   * A career question answered from Tack's guides, with every quote checked
   * against the chunk it cites. An answer the evidence cannot carry becomes a
   * refusal, saved as the reply and refunded (`skipped`).
   */
  coach_cited: async (service, job) => {
    if (!job.user_id) throw new Error("user_required");
    const threadId = job.payload.thread_id as string;
    const evidence = (job.payload.evidence ?? []) as Evidence[];

    const { data: previous } = await service.from("chat_messages")
      .select("body, citations, intent").eq("job_id", job.id).eq(
        "role",
        "coach",
      )
      .eq("user_id", job.user_id).maybeSingle();
    if (previous) {
      // A retry after the reply was saved. A saved refusal (no citations) is
      // still a refusal, and still refunded.
      const cited = (previous.citations ?? []) as unknown[];
      return {
        threadId,
        reply: previous.body,
        citations: cited,
        answeredBy: "model",
        intent: previous.intent ??
          (cited.length > 0 ? "cited" : "guide_refusal"),
        spent: cited.length > 0,
        remaining: await quotaRemaining(service, job.user_id),
        ...(cited.length > 0 ? {} : { skipped: "ungrounded" }),
      };
    }

    const outcome = await runCompletion(
      service,
      job.user_id,
      {
        feature: "coach_cited",
        system: CITED_SYSTEM,
        user: citedPrompt(job.payload.question as string, evidence),
        schema: citedAnswerSchema,
        temperature: 0.2,
        thinking: "low",
        maxOutputTokens: 2048,
      },
      citedAnswerShape,
      ["answered", "text", "citations"],
      { consumeQuota: false },
    );
    const checked = validateCitations(outcome.data as CitedAnswer, evidence);

    const { error } = await service.from("chat_messages").upsert({
      job_id: job.id,
      thread_id: threadId,
      user_id: job.user_id,
      role: "coach",
      body: checked.text,
      answered_by: "model",
      // [] for a refusal: the app shows it as the guides finding nothing,
      // which cost nothing, rather than as a paid answer.
      citations: checked.citations,
      intent: checked.answered ? "cited" : "guide_refusal",
    }, { onConflict: "job_id,role" });
    if (error) throw error;

    return {
      threadId,
      reply: checked.text,
      citations: checked.citations,
      answeredBy: "model",
      intent: checked.answered ? "cited" : "guide_refusal",
      spent: checked.answered,
      remaining: await quotaRemaining(service, job.user_id),
      ...(checked.answered ? {} : { skipped: "ungrounded" }),
    };
  },
  /**
   * The interview prep brief. A result with `cached` or `skipped` in it is
   * refunded by the queue's trigger, so a brief the student already has, or
   * one the evidence gate would not stand behind, costs them nothing.
   */
  interview_prep: async (service, job) => {
    if (!job.user_id) throw new Error("user_required");
    const applicationId = job.payload.application_id as string;
    const inputs = await loadPrepInputs(service, job.user_id, applicationId);
    if (!inputs) return { skipped: "not_at_interview" };
    const hash = await prepHash(inputs);

    const { data: existing } = await service.from("interview_prep_briefs")
      .select("id, brief").eq("application_id", applicationId)
      .eq("input_hash", hash).eq("user_id", job.user_id).maybeSingle();
    if (existing) {
      return { briefId: existing.id, brief: existing.brief, cached: true };
    }

    const outcome = await runCompletion(
      service,
      job.user_id,
      {
        feature: "interview_prep",
        system: PREP_SYSTEM,
        user: prepPrompt(inputs),
        schema: prepBriefSchema,
        temperature: 0.4,
        // Room for the model's thinking and four lists, which the default
        // 2048 shares between them.
        maxOutputTokens: 4096,
      },
      prepBriefShape,
      ["talking_points", "likely_questions", "questions_to_ask", "gaps"],
      { consumeQuota: false },
    );
    const { brief, dropped } = groundBrief(outcome.data as PrepBrief, {
      skills: inputs.skills,
      projects: inputs.projects.map((p) => p.title),
    });
    if (!isGrounded(brief)) return { skipped: "ungrounded", dropped };

    const { data: saved, error } = await service.from("interview_prep_briefs")
      .upsert({
        user_id: job.user_id,
        application_id: applicationId,
        input_hash: hash,
        brief,
        job_id: job.id,
      }, { onConflict: "application_id,input_hash" })
      .select("id").single();
    if (error) throw error;
    return { briefId: saved.id, brief, dropped };
  },
};
