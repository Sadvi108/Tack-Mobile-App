/**
 * Does the supported CV flow work against the deployed functions?
 *
 * Everything else verifies the pipeline by calling the handlers directly,
 * which proves the logic and proves nothing about the runtime they will
 * actually run in. This checks text-PDF reading in Supabase's runtime, plus deployed
 * request contracts, photo fallback and private downloads.
 *
 * Run it straight after `supabase functions deploy`:
 *
 *   deno run --allow-all --config supabase/functions/deno.json tool/verify_deployed.ts
 *
 * It creates a throwaway student, uploads a synthetic text PDF through the
 * real endpoint, waits for the worker's cron to pick it up, and checks a score
 * came back. Then it deletes the account.
 */
import { createClient } from "@supabase/supabase-js";
import { SAMPLE_CV_PDF_BASE64 } from "../supabase/functions/_shared/cv/fixture_pdf.ts";

for (const line of (await Deno.readTextFile("supabase/.env")).split("\n")) {
  const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
  if (m) Deno.env.set(m[1], m[2].replace(/^["']|["']$/g, ""));
}

const URL_ = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
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

const stamp = Date.now();
const email = `deployed_${stamp}@tack.test`;
const created = await admin("/auth/v1/admin/users", {
  method: "POST",
  body: JSON.stringify({
    email,
    password: "Test-passw0rd!",
    email_confirm: true,
    user_metadata: { full_name: "Deploy Check" },
  }),
}).then((r) => r.json());
if (!created.id) {
  throw new Error(`could not create user: ${JSON.stringify(created)}`);
}
const userId: string = created.id;

const session = await fetch(`${URL_}/auth/v1/token?grant_type=password`, {
  method: "POST",
  headers: { apikey: ANON, "Content-Type": "application/json" },
  body: JSON.stringify({ email, password: "Test-passw0rd!" }),
}).then((r) => r.json());
const token: string = session.access_token;
const student = createClient(URL_, ANON, {
  auth: { persistSession: false },
  global: { headers: { Authorization: `Bearer ${token}` } },
});
let uploadedKey: string | null = null;
const ask = (fn: string, body: unknown) =>
  fetch(`${URL_}/functions/v1/${fn}`, {
    method: "POST",
    headers: {
      apikey: ANON,
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

try {
  console.log("\n0. deployed validation, policy pages and catalogue");
  for (
    const [fn, body] of [
      ["coach", { question: 42 }],
      ["analyze-jd", { text: 42 }],
      ["cv-check", null],
      ["score-cv", null],
      ["interview/questions", { role: 42 }],
      ["radar", { remote: "true" }],
    ] as const
  ) {
    const response = await ask(fn, body);
    await response.arrayBuffer();
    ok(
      `${fn} rejects malformed requests`,
      response.status === 400,
      `status ${response.status}`,
    );
  }
  for (const page of ["privacy", "terms", "support"]) {
    const response = await fetch(`${URL_}/functions/v1/policies/${page}`);
    const content = await response.text();
    ok(
      `${page} is public and readable`,
      response.status === 200 && content.length > 100,
    );
  }
  const { data: catalog, error: catalogError } = await student.from(
    "career_paths",
  )
    .select("id, career_fields(slug,name)");
  ok(
    "students can read all 139 career paths",
    !catalogError && (catalog?.length ?? 0) >= 139,
  );
  const { data: before, error: allowanceError } = await student.rpc(
    "coach_allowance",
  );
  if (allowanceError) throw new Error("The allowance could not be read.");
  console.log("\n1. the functions are actually there");
  for (const fn of ["score-cv", "worker"]) {
    const probe = await fetch(`${URL_}/functions/v1/${fn}`, {
      method: "POST",
      headers: {
        apikey: ANON,
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: "{}",
    });
    // 404 means not deployed. Anything else means the function answered, even
    // if it answered "no".
    ok(`${fn} responds`, probe.status !== 404, `status ${probe.status}`);
  }

  console.log("\n2. a final-year student with a path to be scored against");
  await service.from("profiles")
    .update({ year_of_study: 4, years_total: 4 }).eq("id", userId);
  const { data: path } = await service.from("career_paths")
    .select("id").eq("slug", "frontend-developer").single();
  await service.from("user_career_paths").insert({
    user_id: userId,
    path_id: path!.id,
    is_primary: true,
    selected_at: new Date().toISOString(),
  });

  console.log(
    "\n3. a text PDF, uploaded and downloaded privately",
  );
  const pdfBytes = Uint8Array.from(
    atob(SAMPLE_CV_PDF_BASE64),
    (c) => c.charCodeAt(0),
  );
  const { data: doc } = await service.from("documents").insert({
    user_id: userId,
    type: "cv",
    title: "Synthetic text CV",
    storage_path: `pending-${crypto.randomUUID()}`,
    mime_type: "application/pdf",
    size_bytes: pdfBytes.length,
    status: "processing",
  }).select("id").single();

  const key = `users/${userId}/cv/${doc!.id}`;
  uploadedKey = key;
  const up = await service.storage.from("documents")
    .upload(key, pdfBytes, { contentType: "application/pdf", upsert: true });
  ok("the file reached storage", !up.error, JSON.stringify(up.error));
  await service.from("documents").update({ storage_path: key }).eq(
    "id",
    doc!.id,
  );

  const { data: owned } = await student.from("documents").select("storage_path")
    .eq("user_id", userId).eq("id", doc!.id).single();
  const { data: signed, error: signError } = await student.storage.from(
    "documents",
  )
    .createSignedUrl(owned!.storage_path, 300);
  if (signError) {
    throw new Error("the owner could not sign the uploaded document");
  }
  const downloaded = await fetch(signed!.signedUrl);
  const downloadedBytes = new Uint8Array(await downloaded.arrayBuffer());
  ok(
    "the private file downloads intact for a device reader",
    downloaded.ok &&
      downloadedBytes.length === pdfBytes.length &&
      downloadedBytes.every((b, i) => b === pdfBytes[i]),
  );

  const freeResponse = await ask("cv-check", { documentId: doc!.id });
  const free = await freeResponse.json();
  const freeRepeat = await ask("cv-check", { documentId: doc!.id });
  const freeRepeated = await freeRepeat.json();
  ok(
    "a text PDF can start its free check",
    freeResponse.status === 202 && Boolean(free.jobId),
  );
  ok(
    "duplicate free checks return the same job",
    freeRepeat.status === 202 && freeRepeated.jobId === free.jobId,
  );
  const { data: afterFree } = await student.rpc("coach_allowance");
  ok("the free check reserves no AI action", afterFree?.used === before?.used);

  const asked = await fetch(`${URL_}/functions/v1/score-cv`, {
    method: "POST",
    headers: {
      apikey: ANON,
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ documentId: doc!.id }),
  });
  const askedBody = await asked.json();
  ok(
    "score-cv accepted it",
    asked.status === 202 || asked.status === 200,
    `status ${asked.status} ${JSON.stringify(askedBody).slice(0, 200)}`,
  );
  const repeat = await ask("score-cv", { documentId: doc!.id });
  const repeated = await repeat.json();
  ok(
    "retry returns the same pending job",
    asked.status === 202 && repeat.status === 202 &&
      Boolean(askedBody.jobId) && repeated.jobId === askedBody.jobId &&
      repeated.duplicate === true,
  );
  const { data: after } = await student.rpc("coach_allowance");
  ok(
    "one action is reserved for both submissions",
    after?.used === before?.used + 1 &&
      after?.limit === before?.limit,
  );

  console.log("\n4. waiting for the worker (cron runs every two minutes)");
  const deadline = Date.now() + 5 * 60_000;
  let score: Record<string, unknown> | null = null;
  let freeCheckSaved = false;
  let lastStatus = "";

  while (Date.now() < deadline) {
    const { data: row } = await service.from("cv_scores")
      .select("score_10, basis, fixes")
      .eq("document_id", doc!.id)
      .order("computed_at", { ascending: false }).limit(1).maybeSingle();
    if (row) score = row;
    const { data: checks } = await student.from("cv_checks").select("id")
      .eq("document_id", doc!.id).eq("user_id", userId);
    freeCheckSaved = checks?.length === 1;
    if (score && freeCheckSaved) break;

    const { data: d } = await service.from("documents")
      .select("status, failure_reason").eq("id", doc!.id).single();
    if (d!.status === "failed") {
      lastStatus = `document failed: ${d!.failure_reason}`;
      break;
    }

    const { data: jobs } = await service.from("jobs_queue")
      .select("status, last_error").eq("user_id", userId).eq(
        "type",
        "parse_cv",
      );
    const job = jobs?.[0];
    if (job && job.status !== lastStatus) {
      lastStatus = job.status;
      console.log(
        `     job ${job.status}${job.last_error ? ` — ${job.last_error}` : ""}`,
      );
      if (job.status === "dead") break;
    }
    await new Promise((r) => setTimeout(r, 10_000));
  }

  ok(
    "a score came back from the deployed pipeline",
    score !== null,
    lastStatus || "timed out after five minutes",
  );
  ok("the free PDF check completes and is saved once", freeCheckSaved);

  if (score) {
    ok(
      "it is a number out of ten",
      Number(score.score_10) > 0 && Number(score.score_10) <= 10,
      `${score.score_10}`,
    );
    ok(
      "scored against the chosen path",
      score.basis === "path",
      `${score.basis}`,
    );
    ok("with something to fix", (score.fixes as unknown[]).length > 0);
    console.log(`\n     the text PDF scored ${score.score_10} out of 10`);
  }

  console.log("\n5. photos remain files without starting unsupported feedback");
  const photoId = crypto.randomUUID();
  const photoKey = `users/${userId}/cv/${photoId}`;
  const photoBytes = await Deno.readFile(
    "supabase/functions/_shared/cv/fixture_cv_photo.jpg",
  );
  const photoRow = await student.from("documents").insert({
    id: photoId,
    user_id: userId,
    type: "cv",
    title: "Synthetic photo CV",
    storage_path: photoKey,
    mime_type: "image/jpeg",
    size_bytes: photoBytes.length,
    status: "ready",
  });
  if (photoRow.error) throw new Error("Synthetic photo row failed");
  const photoUpload = await student.storage.from("documents").upload(
    photoKey,
    photoBytes,
    { contentType: "image/jpeg" },
  );
  if (photoUpload.error) throw new Error("Synthetic photo upload failed");
  const { data: beforePhoto } = await student.rpc("coach_allowance");
  for (const endpoint of ["score-cv", "cv-check"]) {
    const response = await ask(endpoint, { documentId: photoId });
    const body = await response.json();
    ok(
      `${endpoint} gives photos a text-file fallback`,
      response.status === 400 && JSON.stringify(body).includes("text PDF"),
    );
  }
  const { data: afterPhoto } = await student.rpc("coach_allowance");
  ok(
    "unsupported photo feedback consumes no allowance",
    beforePhoto.used === afterPhoto.used,
  );
  const { data: photoJobs, error: photoJobsError } = await student.from(
    "jobs_queue",
  ).select("id")
    .eq("user_id", userId).contains("payload", { document_id: photoId });
  ok(
    "photo feedback never enters the queue",
    !photoJobsError && photoJobs?.length === 0,
  );
} finally {
  console.log("\ncleanup");
  const { data: paths } = await service.from("documents")
    .select("storage_path").eq("user_id", userId);
  const keys = [
    ...new Set([
      ...(paths ?? []).map((p) => p.storage_path),
      ...(uploadedKey ? [uploadedKey] : []),
    ]),
  ];
  if (keys.length) {
    const removed = await service.storage.from("documents").remove(keys);
    if (removed.error) {
      fail++;
      console.error("Test file cleanup failed.");
    }
  }
  const deleted = await admin(`/auth/v1/admin/users/${userId}`, {
    method: "DELETE",
  });
  if (!deleted.ok) {
    fail++;
    console.error("Test account cleanup failed.");
  }
  console.log("  throwaway account removed");
}

console.log(`\n${pass} passed, ${fail} failed.`);
Deno.exit(fail === 0 ? 0 : 1);
