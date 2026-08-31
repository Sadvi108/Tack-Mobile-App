/**
 * Live verification of the CV pipeline (slice 2).
 *
 * Drives the queue handlers directly against the real database and the real
 * storage bucket, so extraction, measurement, redaction, the model gateway,
 * the skill merge and the deterministic score are all exercised end to end.
 * The Edge Functions themselves are not deployed yet — see docs/DEPLOY.md —
 * and this is what stands in for that until they are.
 *
 *   deno run --allow-all --config supabase/functions/deno.json \
 *     tool/verify_cv_pipeline.ts
 */
import { createClient } from "@supabase/supabase-js";

import { handlers } from "../supabase/functions/_shared/jobs/handlers.ts";
import { SAMPLE_CV_PDF_BASE64 } from "../supabase/functions/_shared/cv/fixture_pdf.ts";

// supabase/.env holds the keys. Loaded into the process so the shared modules
// find them exactly as they would inside a deployed function.
for (const line of (await Deno.readTextFile("supabase/.env")).split("\n")) {
  const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
  if (m) Deno.env.set(m[1], m[2].replace(/^["']|["']$/g, ""));
}

const URL_ = Deno.env.get("SUPABASE_URL")!;
const SVC = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const service = createClient(URL_, SVC, { auth: { persistSession: false } });

let pass = 0, fail = 0;
const ok = (name: string, cond: boolean, extra = "") =>
  cond
    ? (pass++, console.log(`  PASS  ${name}`))
    : (fail++, console.log(`  FAIL  ${name} ${extra}`));

const admin = (p: string, opt: RequestInit = {}) =>
  fetch(`${URL_}${p}`, {
    ...opt,
    headers: {
      apikey: SVC,
      Authorization: `Bearer ${SVC}`,
      "Content-Type": "application/json",
      ...(opt.headers ?? {}),
    },
  });

const pdf = Uint8Array.from(atob(SAMPLE_CV_PDF_BASE64), (c) => c.charCodeAt(0));
const stamp = Date.now();

const email = `cvpipe_${stamp}@tack.test`;
const created = await admin("/auth/v1/admin/users", {
  method: "POST",
  body: JSON.stringify({
    email,
    password: "Test-passw0rd!",
    email_confirm: true,
    user_metadata: { full_name: "CV Pipeline" },
  }),
}).then((r) => r.json());
if (!created.id) throw new Error(`could not create user: ${JSON.stringify(created)}`);
const userId: string = created.id;

// A final-year aiming at frontend, so the score has a path to measure against.
await service.from("profiles").update({ year_of_study: 4, years_total: 4 }).eq("id", userId);
const { data: path } = await service
  .from("career_paths").select("id").eq("slug", "frontend-developer").single();
await service.from("user_career_paths")
  .insert({ user_id: userId, path_id: path!.id, is_primary: true, selected_at: new Date().toISOString() });

async function addDocument(mime: string, bytes: Uint8Array, title: string) {
  const { data: doc, error } = await service.from("documents").insert({
    user_id: userId,
    type: "cv",
    title,
    storage_path: `pending-${crypto.randomUUID()}`,
    mime_type: mime,
    size_bytes: bytes.length,
    status: "processing",
  }).select("id").single();
  if (error) throw error;

  const key = `users/${userId}/cv/${doc.id}`;
  const up = await service.storage.from("documents")
    .upload(key, bytes, { contentType: mime, upsert: true });
  if (up.error) throw up.error;

  await service.from("documents").update({ storage_path: key }).eq("id", doc.id);
  return doc.id as string;
}

const job = (payload: Record<string, unknown>) => ({
  id: crypto.randomUUID(),
  user_id: userId,
  payload,
});

try {
  console.log("\n1. a readable CV goes all the way through");
  const docId = await addDocument("application/pdf", pdf, "CV");
  const result = await handlers.parse_cv(service, job({ document_id: docId })) as
    Record<string, unknown>;
  ok("the handler reports a parse", Boolean(result.parseId), JSON.stringify(result));

  const { data: parse } = await service.from("cv_parse_results")
    .select("parsed, metrics, quality_score").eq("document_id", docId).single();

  ok("the model's extraction is stored", Array.isArray(parse!.parsed.skills),
    JSON.stringify(parse!.parsed).slice(0, 120));

  const m = parse!.metrics;
  ok("metrics were measured from the real PDF", m.words > 20 && m.chars > 200,
    JSON.stringify(m).slice(0, 160));
  ok("the extractor is recorded", m.extractor === "unpdf", m.extractor);
  ok("contact details were seen before redaction ran", m.has_contact === true);
  ok("sections were found", m.sections.includes("experience") && m.sections.includes("skills"),
    m.sections.join(","));
  ok("bullets were counted", m.bullets >= 2, `${m.bullets}`);
  ok("a quantified bullet was recognised", m.bullets_quantified >= 1, `${m.bullets_quantified}`);
  ok("the newest date on the CV was found", /^\d{4}-\d{2}$/.test(m.latest_entry_date ?? ""),
    `${m.latest_entry_date}`);
  ok("the page count is real", m.pages === 1, `${m.pages}`);

  console.log("\n2. nothing personal reached the model");
  const parsedText = JSON.stringify(parse!.parsed);
  ok("no email address is in the stored extraction", !parsedText.includes("@example.com"));
  ok("no phone number is in the stored extraction", !parsedText.includes("8801712345678"));

  console.log("\n3. the score follows on its own");
  ok("quality_score was written back by the scorer",
    typeof parse!.quality_score === "number", `${parse!.quality_score}`);
  const { data: score } = await service.from("cv_scores")
    .select("score_10, score_raw, basis, components, fixes")
    .eq("document_id", docId).order("computed_at", { ascending: false }).limit(1).single();
  ok("a score row exists", Boolean(score));
  ok("it scored against the chosen path", score!.basis === "path", score!.basis);
  ok("the score is out of 10 to one decimal",
    Number(score!.score_10) >= 0 && Number(score!.score_10) <= 10 &&
      Number(score!.score_10) === Math.round(score!.score_raw) / 10,
    `${score!.score_10} / ${score!.score_raw}`);
  ok("all eight components were scored", Object.keys(score!.components).length === 8);
  ok("the student is told what to fix", (score!.fixes as unknown[]).length > 0);

  console.log("\n4. the document is no longer stuck");
  const { data: doc } = await service.from("documents")
    .select("status, failure_reason, checksum").eq("id", docId).single();
  ok("status moved off processing", doc!.status === "ready", doc!.status);
  ok("no failure reason is left behind", doc!.failure_reason === null);

  console.log("\n5. skills the CV names join the student's own list");
  const { data: skills } = await service.from("user_skills")
    .select("source, skills(name)").eq("user_id", userId);
  ok("at least one skill was merged from the CV",
    (skills ?? []).some((s) => s.source === "cv"), JSON.stringify(skills));

  console.log("\n6. the student is told");
  const { data: notes } = await service.from("notifications")
    .select("type, title, body").eq("user_id", userId);
  const ready = (notes ?? []).find((n) => n.type === "cv_parsed");
  ok("a notification was written", Boolean(ready), JSON.stringify(notes));
  ok("it names the score", /out of 10/.test(ready?.body ?? ""), ready?.body ?? "");

  console.log("\n7. rescoring is free and deterministic");
  const before = score!.score_raw;
  await handlers.score_cv(service, job({ user_id: userId }));
  const { data: again } = await service.from("cv_scores")
    .select("score_raw, delta").eq("document_id", docId)
    .order("computed_at", { ascending: false }).limit(1).single();
  ok("the same inputs give the same score", again!.score_raw === before,
    `${before} then ${again!.score_raw}`);
  const { count: aiCalls } = await service.from("ai_usage")
    .select("id", { count: "exact", head: true }).eq("user_id", userId);
  ok("rescoring made no second model call", aiCalls === 1, `${aiCalls} call(s)`);

  console.log("\n8. a file with no text layer fails readably");
  const scan = new Uint8Array(2048).fill(0x41);
  const badId = await addDocument("image/png", scan, "A photo of my CV");
  const badResult = await handlers.parse_cv(service, job({ document_id: badId })) as
    Record<string, unknown>;
  ok("the handler reports it as unreadable", badResult.unreadable === true,
    JSON.stringify(badResult));
  const { data: badDoc } = await service.from("documents")
    .select("status, failure_reason").eq("id", badId).single();
  ok("the document is marked failed, not left processing", badDoc!.status === "failed",
    badDoc!.status);
  ok("the reason tells the student what to do",
    /PDF/.test(badDoc!.failure_reason ?? ""), badDoc!.failure_reason ?? "");
  const { count: afterBad } = await service.from("ai_usage")
    .select("id", { count: "exact", head: true }).eq("user_id", userId);
  ok("an unreadable file costs no model call", afterBad === 1, `${afterBad}`);

  console.log("\n9. a dead job never leaves a document spinning");
  const deadDocId = await addDocument("application/pdf", pdf, "CV that dies");
  const { data: deadJob } = await service.from("jobs_queue").insert({
    user_id: userId,
    type: "parse_cv",
    payload: { document_id: deadDocId },
    status: "running",
    attempts: 3,
    max_attempts: 3,
  }).select("id").single();
  await service.from("jobs_queue").update({ status: "dead", last_error: "verify" })
    .eq("id", deadJob!.id);
  const { data: deadDoc } = await service.from("documents")
    .select("status, failure_reason").eq("id", deadDocId).single();
  ok("the trigger marked the document failed", deadDoc!.status === "failed", deadDoc!.status);
  ok("with a sentence the student can act on",
    (deadDoc!.failure_reason ?? "").length > 20, deadDoc!.failure_reason ?? "");

  console.log("\n10. a worker that dies hands its job back");
  // analyse_jd on purpose: it carries no coalescing index, so this is the
  // ordinary hand-back path with nothing else in the way.
  const { data: stuck } = await service.from("jobs_queue").insert({
    user_id: userId,
    type: "analyse_jd",
    payload: { probe: "plain" },
    status: "running",
    attempts: 1,
    max_attempts: 3,
    locked_at: new Date(Date.now() - 30 * 60_000).toISOString(),
    locked_by: "worker-gone",
  }).select("id").single();
  ok("a stuck job could be set up", Boolean(stuck));

  // The error is asserted, not ignored. Swallowing it is how a 23505 from this
  // call stayed invisible long enough to reach a migration.
  const reap = await service.rpc("reap_stuck_jobs");
  ok("the reaper ran without error", !reap.error, JSON.stringify(reap.error));
  const { data: reaped } = await service.from("jobs_queue")
    .select("status, last_error").eq("id", stuck!.id).single();
  ok("it is pending again", reaped!.status === "pending", reaped!.status);
  ok("and says why", reaped!.last_error === "worker did not finish", reaped!.last_error ?? "");

  console.log("\n10b. a coalesced job is retired, not resurrected onto its own index");
  // score_cv and recompute_readiness each carry a partial unique index keeping
  // one pending job per student. Handing a stuck one back on top of a waiting
  // one used to throw 23505 and abort the whole sweep for every student.
  //
  // The skill merge in step 1 already left a pending score_cv behind — which
  // is coalescing working — so the scenario is set up from a known state.
  await service.from("jobs_queue").delete()
    .eq("user_id", userId).eq("type", "score_cv").eq("status", "pending");

  const { data: waiting } = await service.from("jobs_queue").insert({
    user_id: userId,
    type: "score_cv",
    payload: { user_id: userId },
    status: "pending",
  }).select("id").single();
  ok("a pending coalesced job could be set up", Boolean(waiting));

  const { data: doomed } = await service.from("jobs_queue").insert({
    user_id: userId,
    type: "score_cv",
    payload: { user_id: userId },
    status: "running",
    attempts: 1,
    max_attempts: 3,
    locked_at: new Date(Date.now() - 30 * 60_000).toISOString(),
    locked_by: "worker-gone",
  }).select("id").single();
  const { data: neighbourJob } = await service.from("jobs_queue").insert({
    user_id: userId,
    type: "analyse_jd",
    payload: { probe: "neighbour" },
    status: "running",
    attempts: 1,
    max_attempts: 3,
    locked_at: new Date(Date.now() - 30 * 60_000).toISOString(),
    locked_by: "worker-gone",
  }).select("id").single();
  ok("the colliding pair could be set up", Boolean(doomed) && Boolean(neighbourJob));

  const reap2 = await service.rpc("reap_stuck_jobs");
  ok("the sweep survives a job that cannot be handed back", !reap2.error,
    JSON.stringify(reap2.error));

  const { data: retired } = await service.from("jobs_queue")
    .select("status, result").eq("id", doomed!.id).single();
  ok("the superseded job is retired", retired!.status === "done", retired!.status);
  ok("and says it was superseded", retired!.result?.superseded === true,
    JSON.stringify(retired!.result));
  const { data: stillWaiting } = await service.from("jobs_queue")
    .select("status").eq("id", waiting!.id).single();
  ok("the job that was already waiting is untouched", stillWaiting!.status === "pending",
    stillWaiting!.status);
  const { data: neighbour } = await service.from("jobs_queue")
    .select("status").eq("id", neighbourJob!.id).single();
  ok("one poisoned row no longer blocks every other job", neighbour!.status === "pending",
    neighbour!.status);

  // fail_job takes the same route from a live worker, and threw the same 23505.
  await service.from("jobs_queue").update({ status: "running" }).eq("id", doomed!.id);
  const failed = await service.rpc("fail_job", { p_id: doomed!.id, p_error: "probe" });
  ok("fail_job survives the same collision", !failed.error, JSON.stringify(failed.error));
  const { data: afterFail } = await service.from("jobs_queue")
    .select("status").eq("id", doomed!.id).single();
  ok("and retires it rather than leaving it running", afterFail!.status === "done",
    afterFail!.status);

  console.log("\n11b. a photographed CV is read, not refused");
  // The common case in this market: a paper CV and a phone camera, no scanner.
  const photo = await Deno.readFile(
    "supabase/functions/_shared/cv/fixture_cv_photo.jpg",
  );
  const photoId = await addDocument("image/jpeg", photo, "CV photo");
  const photoResult = await handlers.parse_cv(
    service,
    job({ document_id: photoId }),
  ) as Record<string, unknown>;
  ok("the photo was parsed rather than refused", Boolean(photoResult.parseId),
    JSON.stringify(photoResult));

  const { data: photoParse } = await service.from("cv_parse_results")
    .select("parsed, metrics").eq("document_id", photoId).single();
  const pm = photoParse!.metrics;
  ok("it went through OCR", pm.extractor === "ocr", pm.extractor);
  ok("and recorded how confident the reading was",
    typeof pm.ocr_confidence === "number" && pm.ocr_confidence > 55,
    `${pm.ocr_confidence}`);
  ok("the sections were still found", pm.sections.includes("experience"),
    pm.sections.join(","));
  ok("and the contact details were seen", pm.has_contact === true);

  // The reason OCR could not simply be handed to a multimodal model: the
  // redaction step operates on text, and it has to still work on text a
  // scanner produced.
  const photoText = JSON.stringify(photoParse!.parsed);
  ok("no email reached the model", !photoText.includes("@example.com"),
    photoText.slice(0, 160));
  ok("no phone number reached the model", !photoText.includes("8801712345678"));

  const { data: photoScore } = await service.from("cv_scores")
    .select("score_10, basis").eq("document_id", photoId)
    .order("computed_at", { ascending: false }).limit(1).single();
  ok("a photographed CV gets a score like any other",
    photoScore !== null && Number(photoScore.score_10) > 0,
    JSON.stringify(photoScore));

  console.log("\n11c. an unreadable photo says so instead of scoring noise");
  const noise = new Uint8Array(4096);
  crypto.getRandomValues(noise);
  const noiseId = await addDocument("image/jpeg", noise, "Not a photo");
  const noiseResult = await handlers.parse_cv(
    service,
    job({ document_id: noiseId }),
  ) as Record<string, unknown>;
  ok("it is reported unreadable", noiseResult.unreadable === true,
    JSON.stringify(noiseResult));
  const { data: noiseDoc } = await service.from("documents")
    .select("status, failure_reason").eq("id", noiseId).single();
  ok("the document is failed, not left processing", noiseDoc!.status === "failed",
    noiseDoc!.status);
  ok("with something the student can act on",
    /photo|PDF/i.test(noiseDoc!.failure_reason ?? ""), noiseDoc!.failure_reason ?? "");

  console.log("\n11. the nightly sweep clears anything still stuck");
  const orphanId = await addDocument("application/pdf", pdf, "Orphan");

  // documents carries a set_updated_at trigger, so the row cannot be backdated
  // from here. The threshold is passed in instead, which walks the same path
  // the nightly run walks. First with the real default, to prove a CV that is
  // merely still being read is left alone.
  const sweep1 = await service.rpc("sweep_stuck_documents");
  ok("the sweep ran without error", !sweep1.error, JSON.stringify(sweep1.error));
  const { data: young } = await service.from("documents")
    .select("status").eq("id", orphanId).single();
  ok("a CV that is still being read is not swept up", young!.status === "processing",
    young!.status);

  await service.rpc("sweep_stuck_documents", { p_older: "00:00:00" });
  const { data: swept } = await service.from("documents")
    .select("status").eq("id", orphanId).single();
  ok("a processing document with no job and no parse is failed", swept!.status === "failed",
    swept!.status);
  const { data: intact } = await service.from("documents")
    .select("status").eq("id", docId).single();
  ok("a document that finished properly is left alone", intact!.status === "ready", intact!.status);
} finally {
  console.log("\ncleanup");
  const { data: paths } = await service.from("documents")
    .select("storage_path").eq("user_id", userId);
  if (paths?.length) {
    await service.storage.from("documents").remove(paths.map((p) => p.storage_path));
  }
  await admin(`/auth/v1/admin/users/${userId}`, { method: "DELETE" });
  const { count } = await service.from("documents")
    .select("id", { count: "exact", head: true }).eq("user_id", userId);
  ok("the account and everything under it is gone", count === 0, `${count} left`);
}

console.log(`\n${pass} passed, ${fail} failed.`);
Deno.exit(fail === 0 ? 0 : 1);
