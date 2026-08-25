import { requireUser, serviceClient } from '../_shared/util/auth.ts';
import { fail, json, preflight } from '../_shared/util/http.ts';
import {
  DAILY_AI_QUOTA,
  QuotaExhausted,
  quotaRemaining,
  recordCacheHit,
  runCompletion,
} from '../_shared/ai/gateway.ts';
import { redact } from '../_shared/ai/redact.ts';
import {
  answerFeedbackSchema,
  answerFeedbackShape,
  interviewQuestionsSchema,
} from '../_shared/ai/schemas.ts';

/**
 * Interview practice: question sets and answer feedback.
 *
 * Question sets are cached by (role, type, difficulty), so the second student
 * to practise for the same role costs nothing. Feedback is per answer and is
 * charged, because it is genuinely per student.
 */
Deno.serve(async (req) => {
  const early = preflight(req);
  if (early) return early;

  const auth = await requireUser(req);
  if (!auth) return fail('You are signed out. Log in and try again.', 401);

  const url = new URL(req.url);
  const action = url.pathname.split('/').filter(Boolean).pop();

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return fail('That request could not be read.', 400);
  }

  const service = serviceClient();

  try {
    if (action === 'questions') return await questions(service, auth.userId, body);
    if (action === 'evaluate') return await evaluate(service, auth.userId, body);
    return fail('Unknown action.', 404);
  } catch (error) {
    if (error instanceof QuotaExhausted) {
      return fail(
        `You have used your ${DAILY_AI_QUOTA} AI actions for today. They reset at midnight.`,
        429,
        'quota_exhausted',
      );
    }
    console.error(error);
    return fail('That did not work. Try again in a moment.', 500);
  }
});

async function questions(
  service: ReturnType<typeof serviceClient>,
  userId: string,
  body: Record<string, unknown>,
): Promise<Response> {
  const role = String(body.role ?? '').trim();
  const sessionType = String(body.sessionType ?? 'mixed');
  const difficulty = String(body.difficulty ?? 'medium');
  const count = Math.min(Math.max(Number(body.count ?? 5), 3), 10);

  if (!role) return fail('Pick a role to practise for.', 400);

  const roleSlug = role.toLowerCase().replace(/[^a-z0-9]+/g, '-');

  const { data: cached } = await service
    .from('interview_question_bank')
    .select('questions')
    .eq('role_slug', roleSlug)
    .eq('session_type', sessionType)
    .eq('difficulty', difficulty)
    .maybeSingle();

  if (cached) {
    await recordCacheHit(service, userId, 'interview_questions');
    return json({
      questions: (cached.questions as unknown[]).slice(0, count),
      cached: true,
      quotaRemaining: await quotaRemaining(service, userId),
    });
  }

  const outcome = await runCompletion(
    service,
    userId,
    {
      feature: 'interview_questions',
      system:
        'You write interview questions for entry-level roles in Bangladesh. Plain English, ' +
        'short sentences, no jargon. Reply with JSON only.',
      user: `Role: ${role}. Type: ${sessionType}. Difficulty: ${difficulty}. ` +
        `Write ${count} questions an interviewer would actually ask a final-year student.`,
      schema: interviewQuestionsSchema,
    },
    { questions: 'object[]' },
    ['questions'],
  );

  const generated = (outcome.data as { questions: unknown[] }).questions;

  await service.from('interview_question_bank').upsert(
    {
      role_slug: roleSlug,
      session_type: sessionType,
      difficulty,
      questions: generated,
    },
    { onConflict: 'role_slug,session_type,difficulty' },
  );

  return json({
    questions: generated.slice(0, count),
    cached: false,
    quotaRemaining: outcome.remaining,
  });
}

async function evaluate(
  service: ReturnType<typeof serviceClient>,
  userId: string,
  body: Record<string, unknown>,
): Promise<Response> {
  const questionId = String(body.questionId ?? '');
  const answer = String(body.answer ?? '').trim();

  if (!questionId) return fail('That answer is not linked to a question.', 400);
  if (answer.length < 20) {
    return fail('Write a little more and we can give you useful feedback.', 400);
  }

  // The question belongs to the caller, or there is nothing to evaluate. The
  // id in the body is never trusted on its own.
  const { data: question } = await service
    .from('interview_questions')
    .select('id, question, session_id, user_id')
    .eq('id', questionId)
    .eq('user_id', userId)
    .maybeSingle();

  if (!question) return fail('That question is not one of yours.', 403);

  // Students write their own name and number into answers more often than you
  // would expect. Strip them before anything leaves.
  const { text: cleanAnswer } = redact(answer);

  const outcome = await runCompletion(
    service,
    userId,
    {
      feature: 'evaluate_answer',
      system:
        'You give feedback on interview answers to university students in Bangladesh. ' +
        'Be specific and kind. Say what went well before what to improve. Plain English, ' +
        'short sentences. Reply with JSON only.',
      user: `Question: ${question.question}\n\nAnswer: ${cleanAnswer}`,
      schema: answerFeedbackSchema,
    },
    answerFeedbackShape,
    ['score', 'went_well', 'to_improve'],
  );

  const feedback = outcome.data as {
    score: number;
    went_well: string[];
    to_improve: string[];
    model_answer?: string;
  };

  await service.from('interview_questions').update({
    answer_text: answer,
    answered_at: new Date().toISOString(),
  }).eq('id', questionId);

  await service.from('interview_feedback').upsert(
    {
      question_id: questionId,
      user_id: userId,
      score: Math.min(10, Math.max(0, feedback.score)),
      went_well: feedback.went_well,
      to_improve: feedback.to_improve,
      model_answer: feedback.model_answer ?? null,
    },
    { onConflict: 'question_id' },
  );

  return json({ feedback, quotaRemaining: outcome.remaining });
}
