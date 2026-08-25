import { SupabaseClient } from 'jsr:@supabase/supabase-js@2';

import { isWorkerAuthorised, serviceClient } from '../_shared/util/auth.ts';
import { fail, json, preflight } from '../_shared/util/http.ts';
import { runCompletion } from '../_shared/ai/gateway.ts';
import { matchSkills } from '../_shared/ai/matching.ts';
import { assertClean } from '../_shared/ai/redact.ts';
import { jdAnalysisSchema, jdAnalysisShape } from '../_shared/ai/schemas.ts';

/**
 * Drains the job queue.
 *
 * Called by a cron trigger every two minutes and guarded by a bearer secret.
 * Works to a time budget rather than emptying the queue, so it always returns
 * before the platform's limit and the next run picks up where it stopped.
 */
const BUDGET_MS = 25_000;
const BATCH = 5;

type Handler = (
  service: SupabaseClient,
  job: { id: string; user_id: string | null; payload: Record<string, unknown> },
) => Promise<unknown>;

const handlers: Record<string, Handler> = {
  recompute_readiness: async (service, job) => {
    const userId = (job.payload.user_id as string) ?? job.user_id;
    if (!userId) return { skipped: 'no user' };
    const { error } = await service.rpc('recompute_readiness', {
      p_user_id: userId,
      p_reason: (job.payload.source as string) ?? 'queue',
    });
    if (error) throw error;
    return { recomputed: true };
  },

  analyse_jd: async (service, job) => {
    const text = job.payload.text as string;
    const hash = job.payload.hash as string;
    const userId = job.user_id;
    if (!userId) throw new Error('analyse_jd requires a user');

    // Belt and braces: the endpoint redacted this, and nothing reaches the
    // model without the check running again here.
    assertClean(text);

    const { data: cached } = await service
      .from('job_analyses')
      .select('id, extracted')
      .eq('raw_text_hash', hash)
      .maybeSingle();

    let analysisId: string;
    let extracted: { skills?: string[] };

    if (cached) {
      analysisId = cached.id;
      extracted = cached.extracted;
    } else {
      const outcome = await runCompletion(
        service,
        userId,
        {
          feature: 'analyse_jd',
          system:
            'You read job descriptions and extract what they ask for. Reply with JSON only. ' +
            'Use the wording of the description; do not invent requirements it does not state.',
          user: text,
          schema: jdAnalysisSchema,
        },
        jdAnalysisShape,
        ['job_title', 'skills', 'qualifications', 'responsibilities'],
        // The student was already charged when they submitted.
        { consumeQuota: false },
      );

      extracted = outcome.data as { skills?: string[] };

      const { data: inserted, error } = await service
        .from('job_analyses')
        .upsert(
          {
            raw_text_hash: hash,
            source_job_id: (job.payload.jobId as string) ?? null,
            job_title: (extracted as { job_title?: string }).job_title ?? null,
            extracted,
          },
          { onConflict: 'raw_text_hash' },
        )
        .select('id')
        .single();
      if (error) throw error;
      analysisId = inserted.id;
    }

    // Matching is deterministic and never involves the model.
    const { data: userSkills } = await service
      .from('user_skills')
      .select('skills(name)')
      .eq('user_id', userId);
    const names = ((userSkills ?? []) as unknown as Array<{ skills?: { name?: string } | null }>)
      .map((row) => row.skills?.name)
      .filter((n): n is string => Boolean(n));

    const match = matchSkills(extracted.skills ?? [], names);

    await service.from('job_match_scores').upsert(
      {
        user_id: userId,
        analysis_id: analysisId,
        match_percent: match.matchPercent,
        matched_skills: match.matched,
        missing_skills: match.missing,
      },
      { onConflict: 'user_id,analysis_id' },
    );

    await service.from('notifications').insert({
      user_id: userId,
      type: 'analysis_ready',
      title: 'Your job analysis is ready',
      body: `You match ${match.matchPercent}% of what this role asks for.`,
      payload: { analysis_id: analysisId },
    });

    return { analysisId, matchPercent: match.matchPercent };
  },
};

Deno.serve(async (req) => {
  const early = preflight(req);
  if (early) return early;

  if (!isWorkerAuthorised(req)) {
    return fail('Not allowed.', 401);
  }

  const service = serviceClient();
  const worker = `worker-${crypto.randomUUID().slice(0, 8)}`;
  const startedAt = Date.now();

  let processed = 0;
  let failed = 0;

  while (Date.now() - startedAt < BUDGET_MS) {
    const { data: jobs, error } = await service.rpc('claim_jobs', {
      p_limit: BATCH,
      p_worker: worker,
    });
    if (error) return fail('The queue could not be read.', 500);
    if (!jobs || jobs.length === 0) break;

    for (const job of jobs) {
      if (Date.now() - startedAt > BUDGET_MS) {
        // Hand it back rather than starting work that cannot finish.
        await service.rpc('fail_job', { p_id: job.id, p_error: 'worker budget reached' });
        continue;
      }

      const handler = handlers[job.type];
      if (!handler) {
        await service
          .from('jobs_queue')
          .update({ status: 'dead', last_error: `no handler for ${job.type}` })
          .eq('id', job.id);
        failed++;
        continue;
      }

      try {
        const result = await handler(service, job);
        await service
          .from('jobs_queue')
          .update({ status: 'done', result, locked_at: null, locked_by: null })
          .eq('id', job.id);
        processed++;
      } catch (error) {
        // fail_job applies the backoff and dead-letters after max attempts.
        await service.rpc('fail_job', {
          p_id: job.id,
          p_error: (error as Error).message.slice(0, 500),
        });
        failed++;
      }
    }
  }

  return json({ worker, processed, failed, elapsedMs: Date.now() - startedAt });
});
