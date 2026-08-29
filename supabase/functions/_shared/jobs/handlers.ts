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
import { measure } from "../cv/metrics.ts";

export type Handler = (
  service: SupabaseClient,
  job: { id: string; user_id: string | null; payload: Record<string, unknown> },
) => Promise<unknown>;

export const handlers: Record<string, Handler> = {
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

    await service.from("notifications").insert({
      user_id: userId,
      type: "analysis_ready",
      title: "Your job analysis is ready",
      body: `You match ${match.matchPercent}% of what this role asks for.`,
      payload: { analysis_id: analysisId },
    });

    return { analysisId, matchPercent: match.matchPercent };
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
      if (error instanceof UnreadableDocument) {
        await service
          .from("documents")
          .update({ status: "failed", failure_reason: error.studentMessage })
          .eq("id", documentId);
        await service.from("notifications").insert({
          user_id: userId,
          type: "cv_parsed",
          title: "Tack could not read that CV",
          body: error.studentMessage,
          payload: { document_id: documentId },
        });
        return { unreadable: true };
      }
      throw error;
    }

    const metrics = measure(extraction.text, {
      pages: extraction.pages,
      truncated: extraction.truncated,
      extractor: extraction.extractor,
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

    await service.from("notifications").insert({
      user_id: userId,
      type: "cv_parsed",
      title: "Your CV score is ready",
      body: score
        ? `Your CV scores ${score.score_10} out of 10 for the field you are aiming at.`
        : "Tack has read your CV.",
      payload: { document_id: documentId },
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
