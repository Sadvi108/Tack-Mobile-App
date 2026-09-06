import { validateResponse } from "./response_validation.ts";
import { assertClean, redact } from "./redact.ts";
import { SupabaseClient } from "@supabase/supabase-js";

import { CompletionRequest, selectProvider } from "./provider.ts";
import { validate } from "./schemas.ts";

/**
 * A fallback, not the rule.
 *
 * The daily allowance lives in `ai_daily_limit()` in the database, which
 * `consume_quota` and `quota_remaining` read for themselves — a caller passing
 * a different number can no longer grant itself a different allowance. This
 * constant is only the optimistic value used before the first round trip, and
 * `p_limit` is passed for signature compatibility and ignored server-side.
 *
 * Nothing a student reads should name a number from here; the messages say
 * "today's AI actions" so there is one place to change it and no way for the
 * two to disagree.
 */
export const DAILY_AI_QUOTA = 3;

/**
 * The one bucket the allowance is counted in.
 *
 * It used to be two. The coach charged `ai` while everything routed through
 * `runCompletion` — CV parsing, job-description analysis, interview feedback —
 * charged `ai_actions`, and `coach_allowance()` only ever read `ai`. So a
 * student silently had two separate budgets and the app showed them one of
 * them, which meant the counter on the coach screen was accurate about the
 * coach and wrong about everything else.
 *
 * Named here so a future feature cannot invent a third by typing a string.
 */
export const QUOTA_BUCKET = "ai";

export interface GatewayOutcome {
  data: unknown;
  cached: boolean;
  remaining: number;
}

export class QuotaExhausted extends Error {
  constructor() {
    super("quota exhausted");
  }
}

/**
 * Everything that has to happen around a model call.
 *
 * Quota is consumed on submission rather than on success, because a student
 * who submits twice has cost two runs whatever came back. The remaining count
 * is returned either way so the app can show it before and after.
 */
export async function runCompletion(
  service: SupabaseClient,
  userId: string,
  request: CompletionRequest,
  shape: Parameters<typeof validate>[1],
  required: string[],
  // Quota is taken when the student submits, which is usually in the endpoint
  // rather than here. The worker passes false so a queued job is not charged
  // a second time.
  options: { consumeQuota?: boolean } = {},
): Promise<GatewayOutcome> {
  let remaining = DAILY_AI_QUOTA;
  if (options.consumeQuota ?? true) {
    const { data, error: quotaError } = await service.rpc("consume_quota", {
      p_user_id: userId,
      p_bucket: QUOTA_BUCKET,
      p_limit: DAILY_AI_QUOTA,
    });
    if (quotaError) throw quotaError;
    if (data === -1) throw new QuotaExhausted();
    remaining = data as number;
  } else {
    remaining = await quotaRemaining(service, userId);
  }

  request = { ...request, user: redact(request.user).text };
  assertClean(request.user);
  const provider = selectProvider();
  let result;
  try {
    result = await provider.complete(request);
  } catch (error) {
    await service.from("ai_usage").insert({
      user_id: userId,
      feature: request.feature,
      provider: provider.name,
      succeeded: false,
      error_code: "provider_unavailable",
    });
    throw error;
  }

  let problems = [
    ...validate(result.data, shape, required),
    ...validateResponse(request.feature, result.data),
  ];

  // One corrective retry. Models occasionally return a nearly-right shape, and
  // a single re-ask is cheaper than failing the student's only run.
  if (problems.length > 0) {
    const retry = await provider.complete({
      ...request,
      user:
        `${request.user}\n\nYour previous reply was rejected: ${
          problems.join("; ")
        }. ` +
        `Reply again with valid JSON only.`,
    });
    const retryProblems = [
      ...validate(retry.data, shape, required),
      ...validateResponse(request.feature, retry.data),
    ];
    if (retryProblems.length === 0) {
      result = retry;
      problems = [];
    }
  }

  await service.from("ai_usage").insert({
    user_id: userId,
    feature: request.feature,
    provider: result.provider,
    model: result.model,
    prompt_tokens: result.promptTokens,
    completion_tokens: result.completionTokens,
    succeeded: problems.length === 0,
    error_code: problems.length === 0 ? null : "invalid_model_reply",
  });

  if (problems.length > 0) {
    throw new Error(`model reply failed validation: ${problems.join("; ")}`);
  }

  return { data: result.data, cached: false, remaining };
}

/** Records a cache hit without consuming quota. */
export async function recordCacheHit(
  service: SupabaseClient,
  userId: string,
  feature: string,
): Promise<void> {
  await service.from("ai_usage").insert({
    user_id: userId,
    feature,
    provider: "cache",
    cached: true,
    succeeded: true,
  });
}

export async function quotaRemaining(
  service: SupabaseClient,
  userId: string,
): Promise<number> {
  const { data, error } = await service.rpc("quota_remaining", {
    p_user_id: userId,
    p_bucket: QUOTA_BUCKET,
    p_limit: DAILY_AI_QUOTA,
  });
  if (error || typeof data !== "number") throw new Error("quota_unavailable");
  return data;
}

/** Content hash, so identical text is never analysed twice. */
export async function hashText(text: string): Promise<string> {
  const normalised = text.trim().toLowerCase().replace(/\s+/g, " ");
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(normalised),
  );
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/** Content hash of raw bytes, so the same file is never parsed twice. */
export async function hashBytes(bytes: ArrayBuffer): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
