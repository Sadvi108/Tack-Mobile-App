import type { Handler } from "./handlers.ts";
import { quotaRemaining, runCompletion } from "../ai/gateway.ts";
import { COACH_SYSTEM } from "../ai/coach_prompt.ts";
import {
  answerFeedbackSchema,
  answerFeedbackShape,
  interviewQuestionsSchema,
} from "../ai/schemas.ts";

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
};
