import { conversationHandlers } from "./conversation_handlers.ts";
/**
 * Everything the queue knows how to do.
 *
 * Kept apart from the worker endpoint so a handler can be driven directly — by
 * a test, or by tool/verify_cv_pipeline.ts against the live database — without
 * standing up an HTTP server or deploying anything. The worker is transport;
 * this is the work.
 */
import { SupabaseClient } from "@supabase/supabase-js";

import { runCompletion } from "../ai/gateway.ts";
import { matchSkills } from "../ai/matching.ts";
import { assertClean, redact } from "../ai/redact.ts";
import {
  cvParseSchema,
  cvParseShape,
  jdAnalysisSchema,
  jdAnalysisShape,
} from "../ai/schemas.ts";
import { extractDocument, UnreadableDocument } from "../cv/extract.ts";
import { isConfigured, sendTo } from "../push/fcm.ts";
import { readRepo } from "../verify/github.ts";
import { findings, sortFindings } from "../cv/findings.ts";
import { measure } from "../cv/metrics.ts";

export type Handler = (
  service: SupabaseClient,
  job: { id: string; user_id: string | null; payload: Record<string, unknown> },
) => Promise<unknown>;

export const handlers: Record<string, Handler> = {
  ...conversationHandlers,
  recompute_readiness: async (service, job) => {
    const userId = (job.payload.user_id as string) ?? job.user_id;
    if (!userId) return { skipped: "no user" };
    const { error } = await service.rpc("recompute_readiness", {
      p_user_id: userId,
      p_reason: (job.payload.source as string) ?? "queue",
    });
    if (error) throw error;
    return { recomputed: true };
  },

  analyse_jd: async (service, job) => {
    const text = job.payload.text as string;
    const hash = job.payload.hash as string;
    const userId = job.user_id;
    if (!userId) throw new Error("analyse_jd requires a user");

    // Belt and braces: the endpoint redacted this, and nothing reaches the
    // model without the check running again here.
    assertClean(text);

    const { data: cached } = await service
      .from("job_analyses")
      .select("id, extracted")
      .eq("raw_text_hash", hash)
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
          feature: "analyse_jd",
          system:
            "You read job descriptions and extract what they ask for. Reply with JSON only. " +
            "Use the wording of the description; do not invent requirements it does not state.",
          user: text,
          schema: jdAnalysisSchema,
        },
        jdAnalysisShape,
        ["job_title", "skills", "qualifications", "responsibilities"],
        // The student was already charged when they submitted.
        { consumeQuota: false },
      );

      extracted = outcome.data as { skills?: string[] };

      const { data: inserted, error } = await service
        .from("job_analyses")
        .upsert(
          {
            raw_text_hash: hash,
            source_job_id: (job.payload.jobId as string) ?? null,
            job_title: (extracted as { job_title?: string }).job_title ?? null,
            extracted,
          },
          { onConflict: "raw_text_hash" },
        )
        .select("id")
        .single();
      if (error) throw error;
      analysisId = inserted.id;
    }

    // Matching is deterministic and never involves the model.
    const { data: userSkills } = await service
      .from("user_skills")
      .select("skills(name)")
      .eq("user_id", userId);
    const names = ((userSkills ?? []) as unknown as Array<
      { skills?: { name?: string } | null }
    >)
      .map((row) => row.skills?.name)
      .filter((n): n is string => Boolean(n));

    const match = matchSkills(extracted.skills ?? [], names);

    await service.from("job_match_scores").upsert(
      {
        user_id: userId,
        analysis_id: analysisId,
        match_percent: match.matchPercent,
        matched_skills: match.matched,
        missing_skills: match.missing,
      },
      { onConflict: "user_id,analysis_id" },
    );

    await service.rpc("notify", {
      p_user_id: userId,
      p_type: "analysis_ready",
      p_title: "Your job analysis is ready",
      p_body: `You match ${match.matchPercent}% of what this role asks for.`,
      p_payload: { analysis_id: analysisId },
      // Keyed on the analysis, so a retried job does not tell them twice.
      p_dedupe_key: `analysis:${analysisId}`,
    });

    return {
      analysisId,
      matchPercent: match.matchPercent,
      cached: Boolean(cached),
    };
  },

  /**
   * Read a CV, measure it, and score it.
   *
   * The order matters and is not negotiable: measure the raw text first,
   * because redaction replaces an email with "[email]" and would destroy the
   * has_contact signal; then redact; then, and only then, call the model.
   */
  parse_cv: async (service, job) => {
    const userId = job.user_id;
    const documentId = job.payload.document_id as string;
    if (!userId || !documentId) {
      throw new Error("parse_cv needs a user and a document");
    }

    const { data: doc } = await service
      .from("documents")
      .select("id, user_id, storage_path, mime_type")
      .eq("id", documentId)
      .maybeSingle();

    // Ownership is checked again here rather than trusted from the payload.
    if (!doc || doc.user_id !== userId) {
      throw new Error("document not found for this user");
    }

    const { data: blob, error: readError } = await service.storage
      .from("documents")
      .download(doc.storage_path);
    if (readError || !blob) throw new Error("storage read failed");

    let extraction;
    try {
      extraction = await extractDocument(
        new Uint8Array(await blob.arrayBuffer()),
        doc.mime_type,
      );
    } catch (error) {
      // A scan, a photo or a protected PDF is an expected outcome, not a
      // fault. Retrying it three times would change nothing, so the job
      // finishes and the document carries the sentence the student can act on.
      // The OCR engine failing to start is not this student's problem and not
      // something a better photo fixes, so it is recorded where it can be
      // found and the job is left to retry rather than swallowed.
      if ((error as Error)?.name === "OcrUnavailable") {
        await service.from("audit_log").insert({
          user_id: userId,
          action: "ocr_unavailable",
          entity: "documents",
          entity_id: documentId,
          meta: { message: (error as Error).message.slice(0, 300) },
        });
        throw error;
      }

      if (error instanceof UnreadableDocument) {
        await service
          .from("documents")
          .update({ status: "failed", failure_reason: error.studentMessage })
          .eq("id", documentId);
        await service.rpc("notify", {
          p_user_id: userId,
          p_type: "cv_parsed",
          p_title: "Tack could not read that CV",
          p_body: error.studentMessage,
          p_payload: { document_id: documentId },
          p_dedupe_key: `cv_unreadable:${documentId}`,
        });
        return { unreadable: true };
      }
      throw error;
    }

    const metrics = measure(extraction.text, {
      pages: extraction.pages,
      truncated: extraction.truncated,
      extractor: extraction.extractor,
      confidence: extraction.confidence,
    });

    const { text: clean } = redact(extraction.text);
    // Belt and braces, exactly as the JD path does it.
    assertClean(clean);

    const outcome = await runCompletion(
      service,
      userId,
      {
        feature: "parse_cv",
        system:
          "You read CVs and extract what is in them. Reply with JSON only. " +
          "Record only what the CV states; do not infer a skill it does not name " +
          "and do not improve the wording.",
        user: clean,
        schema: cvParseSchema,
      },
      cvParseShape,
      ["skills", "quality_score"],
      // The student was charged when they submitted.
      { consumeQuota: false },
    );

    const parsed = outcome.data as { skills?: string[]; warnings?: unknown };

    // quality_score is deliberately not written from the model's reply: the
    // column belongs to score_cv_fit, which computes it deterministically.
    // The model's own opinion stays inside `parsed` and is advisory.
    const { data: parseRow, error: parseError } = await service
      .from("cv_parse_results")
      .insert({
        document_id: documentId,
        user_id: userId,
        parsed,
        metrics,
        warnings: Array.isArray(parsed.warnings) ? parsed.warnings : [],
      })
      .select("id")
      .single();
    if (parseError) throw parseError;

    const merged = await mergeCvSkills(service, userId, parsed.skills ?? []);

    await service
      .from("documents")
      .update({ status: "ready", failure_reason: null })
      .eq("id", documentId);

    const { error: scoreError } = await service.rpc("score_cv_fit", {
      p_user_id: userId,
      p_document_id: documentId,
    });
    if (scoreError) throw scoreError;

    const { data: score } = await service
      .from("cv_scores")
      .select("score_10, basis")
      .eq("document_id", documentId)
      .order("computed_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    await service.rpc("notify", {
      p_user_id: userId,
      p_type: "cv_parsed",
      p_title: "Your CV score is ready",
      p_body: score
        ? `Your CV scores ${score.score_10} out of 10 for the field you are aiming at.`
        : "Tack has read your CV.",
      p_payload: { document_id: documentId },
      p_dedupe_key: `cv_scored:${documentId}`,
    });

    return {
      parseId: parseRow.id,
      skillsMerged: merged,
      score: score?.score_10 ?? null,
    };
  },

  /**
   * Rescore an already-parsed CV.
   *
   * Queued whenever what the student is aiming at changes. Deterministic, so
   * it costs nothing and never touches a model.
   */
  score_cv: async (service, job) => {
    const userId = (job.payload.user_id as string) ?? job.user_id;
    if (!userId) return { skipped: "no user" };

    const { data: docs } = await service
      .from("documents")
      .select("id, is_default, created_at, cv_parse_results!inner(id)")
      .eq("user_id", userId)
      .eq("type", "cv")
      .is("deleted_at", null)
      .order("is_default", { ascending: false })
      .order("created_at", { ascending: false })
      .limit(1);

    const documentId = docs?.[0]?.id;
    if (!documentId) return { skipped: "no parsed cv" };

    const { error } = await service.rpc("score_cv_fit", {
      p_user_id: userId,
      p_document_id: documentId,
    });
    if (error) throw error;

    return { rescored: documentId };
  },

  /**
   * The free CV check.
   *
   * Deliberately never calls runCompletion, so there is no consumeQuota
   * argument to get wrong: it cannot spend a student's allowance because it
   * has no way to. Reading the file and counting what is in it were always
   * free; they were only ever locked behind parse_cv, which is not.
   */
  check_cv: async (service, job) => {
    const userId = job.user_id;
    const documentId = job.payload.document_id as string;
    if (!userId || !documentId) {
      throw new Error("check_cv needs a user and a document");
    }

    const { data: doc } = await service
      .from("documents")
      .select("id, user_id, storage_path, mime_type")
      .eq("id", documentId)
      .maybeSingle();

    // Checked again here rather than trusted from the payload, exactly as
    // parse_cv does it.
    if (!doc || doc.user_id !== userId) {
      throw new Error("document not found for this user");
    }

    const { data: blob, error: readError } = await service.storage
      .from("documents")
      .download(doc.storage_path);
    if (readError || !blob) throw new Error("storage read failed");

    let extraction;
    try {
      extraction = await extractDocument(
        new Uint8Array(await blob.arrayBuffer()),
        doc.mime_type,
      );
    } catch (error) {
      // A photograph Tack cannot read is a fact about the photograph. The
      // student is told in a sentence they can act on rather than the job
      // being retried three times and dead-lettered.
      if (error instanceof UnreadableDocument) {
        await service.from("cv_checks").upsert({
          job_id: job.id,
          user_id: userId,
          document_id: documentId,
          findings: [{
            kind: "unreadable",
            severity: "problem",
            title: "Tack could not read this file",
            detail: error.studentMessage,
          }],
          problems: 1,
        }, { onConflict: "job_id" });
        return { unreadable: true };
      }
      throw error;
    }

    const metrics = measure(extraction.text, {
      pages: extraction.pages,
      truncated: extraction.truncated,
      extractor: extraction.extractor,
      confidence: extraction.confidence,
    });

    // The same extractor that indexes job listings, pointed at a CV. It has
    // never cared what the text was.
    const { data: skills } = await service.rpc("skills_named_in", {
      p_text: extraction.text,
    });
    const recognised = (skills as string[] | null) ?? [];

    const list = sortFindings(findings(metrics, recognised));

    await service.from("cv_checks").upsert({
      job_id: job.id,
      user_id: userId,
      document_id: documentId,
      metrics,
      skills: recognised,
      findings: list,
      problems: list.filter((f) => f.severity === "problem").length,
      suggestions: list.filter((f) => f.severity === "improve").length,
    }, { onConflict: "job_id" });

    return {
      findings: list.length,
      problems: list.filter((f) => f.severity === "problem").length,
      skills: recognised.length,
    };
  },

  /**
   * Turns a claimed repository into a verified one.
   *
   * Never fails the job for a repository that is gone or private — that is a
   * fact about the project, recorded as `missing`, and retrying it three times
   * would not make it exist. Only a transport failure or GitHub's rate limit
   * throws, because those are worth another attempt later.
   */
  verify_project: async (service, job) => {
    const projectId = job.payload.project_id as string;
    const repoUrl = job.payload.repo_url as string;
    if (!projectId || !repoUrl) return { skipped: "no project" };

    const facts = await readRepo(repoUrl);

    await service.from("project_verifications").upsert({
      project_id: projectId,
      provider: "github",
      state: facts.state,
      stars: facts.stars ?? null,
      language: facts.language ?? null,
      last_push_at: facts.lastPushAt ?? null,
      checked_at: new Date().toISOString(),
      error: facts.error ?? null,
    }, { onConflict: "project_id" });

    // Recorded first, then thrown: the row says why it is not verified even
    // while the retry is pending, so the student is never left looking at a
    // silent "pending" with no explanation.
    if (facts.state === "error") {
      throw new Error(facts.error ?? "github failed");
    }

    return { state: facts.state, stars: facts.stars };
  },

  /**
   * Delivers a notification that `notify()` has already written to the inbox.
   *
   * Returns rather than throws in every ordinary "could not send" case. The
   * in-app notification exists either way, so a phone that has uninstalled the
   * app, or a project with no FCM credentials, is not a failure of the work —
   * and treating it as one would retry each digest three times before
   * dead-lettering it, once per student, every night.
   */
  send_push: async (service, job) => {
    const userId = job.user_id;
    if (!userId) return { skipped: "no user" };
    if (!isConfigured()) return { skipped: "fcm not configured" };

    const { data: devices } = await service
      .from("device_tokens")
      .select("token")
      .eq("user_id", userId);

    if (!devices || devices.length === 0) {
      return { skipped: "no devices" };
    }

    const message = {
      title: String(job.payload.title ?? "Tack"),
      body: job.payload.body == null ? null : String(job.payload.body),
      // FCM data values must all be strings.
      data: { type: String(job.payload.type ?? "general") },
    };

    let sent = 0;
    const stale: string[] = [];
    const errors: string[] = [];

    for (const device of devices) {
      const outcome = await sendTo(device.token, message);
      if (outcome.ok) {
        sent++;
      } else if (outcome.stale) {
        stale.push(device.token);
      } else {
        errors.push(outcome.error);
      }
    }

    // A token FCM has rejected as unregistered will never work again. Removing
    // it here is the only thing that stops it being retried nightly forever.
    if (stale.length > 0) {
      await service.from("device_tokens").delete().in("token", stale);
    }

    // Every device failed for a reason that might not repeat — rate limiting,
    // FCM being briefly unavailable. That is worth the queue's backoff.
    if (sent === 0 && errors.length > 0) {
      throw new Error(errors[0]);
    }

    return { sent, removed: stale.length };
  },
};

/**
 * Puts skills the CV names into the student's own skill list.
 *
 * Existing rows are left alone: a student who rated themselves 5 at React
 * should not be quietly moved to 3 because their CV mentions it.
 */
async function mergeCvSkills(
  service: SupabaseClient,
  userId: string,
  names: string[],
): Promise<number> {
  const wanted = new Set(
    names.map((n) => String(n).trim().toLowerCase()).filter(Boolean),
  );
  if (wanted.size === 0) return 0;

  const { data: skills } = await service
    .from("skills")
    .select("id, name, aliases")
    .eq("is_active", true);

  const rows = (skills ?? [])
    .filter((s) =>
      [s.name, ...((s.aliases ?? []) as string[])]
        .some((label) => wanted.has(String(label).toLowerCase()))
    )
    .map((s) => ({
      user_id: userId,
      skill_id: s.id,
      source: "cv",
      proficiency: 3,
      evidence: "Named on your CV",
    }));

  if (rows.length === 0) return 0;

  await service
    .from("user_skills")
    .upsert(rows, { onConflict: "user_id,skill_id", ignoreDuplicates: true });

  return rows.length;
}
