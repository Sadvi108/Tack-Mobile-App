import type { Handler } from "./handlers.ts";
import { quotaRemaining, runCompletion } from "../ai/gateway.ts";
import { COACH_SYSTEM } from "../ai/coach_prompt.ts";
import {
  answerFeedbackSchema,
  answerFeedbackShape,
  interviewQuestionsSchema,
  prepBriefSchema,
  prepBriefShape,
} from "../ai/schemas.ts";
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

export const conversationHandlers: Record<string, Handler> = {
  coach_reply: async (service, job) => {
    if (!job.user_id) throw new Error("user_required");
    const threadId = job.payload.thread_id as string;
    const { data: previous } = await service.from("chat_messages").select(
      "body",
    )
      .eq("job_id", job.id).eq("role", "coach").eq("user_id", job.user_id)
      .maybeSingle();
    let reply = previous?.body;
    if (!reply) {
      const outcome = await runCompletion(
        service,
        job.user_id,
        {
          feature: "coach_chat",
          system: `${COACH_SYSTEM}\nReply with JSON containing a reply string.`,
          user:
            `Student: ${job.payload.context}\n\nQuestion: ${job.payload.question}`,
          schema: {
            type: "object",
            properties: { reply: { type: "string" } },
            required: ["reply"],
          },
          temperature: 0.6,
          thinking: "low",
          maxOutputTokens: 1500,
        },
        { reply: "string" },
        ["reply"],
        { consumeQuota: false },
      );
      reply = (outcome.data as { reply: string }).reply;
      const { error } = await service.from("chat_messages").upsert({
        job_id: job.id,
        thread_id: threadId,
        user_id: job.user_id,
        role: "coach",
        body: reply,
        answered_by: "model",
      }, { onConflict: "job_id,role" });
      if (error) throw error;
    }
    return {
      threadId,
      reply,
      answeredBy: "model",
      spent: true,
      remaining: await quotaRemaining(service, job.user_id),
    };
  },
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
      .select("body, citations").eq("job_id", job.id).eq("role", "coach")
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
    }, { onConflict: "job_id,role" });
    if (error) throw error;

    return {
      threadId,
      reply: checked.text,
      citations: checked.citations,
      answeredBy: "model",
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
