/**
 * Does the CV score work against the *deployed* functions?
 *
 * Everything else verifies the pipeline by calling the handlers directly,
 * which proves the logic and proves nothing about the runtime they will
 * actually run in. Supabase's Edge Runtime is not plain Deno, and the OCR
 * engine wants Node worker threads — whether it gets them there could not be
 * tested without Docker. This is the test that answers it.
 *
 * Run it straight after `supabase functions deploy`:
 *
 *   deno run --allow-all --config supabase/functions/deno.json tool/verify_deployed.ts
 *
 * It creates a throwaway student, uploads a photograph of a CV through the
 * real endpoint, waits for the worker's cron to pick it up, and checks a score
 * came back. Then it deletes the account.
 */
import { createClient } from "@supabase/supabase-js";

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
if (!created.id) throw new Error(`could not create user: ${JSON.stringify(created)}`);
const userId: string = created.id;

const session = await fetch(`${URL_}/auth/v1/token?grant_type=password`, {
  method: "POST",
  headers: { apikey: ANON, "Content-Type": "application/json" },
  body: JSON.stringify({ email, password: "Test-passw0rd!" }),
}).then((r) => r.json());
const token: string = session.access_token;

try {
  console.log("\n1. the functions are actually there");
  for (const fn of ["score-cv", "worker"]) {
    const probe = await fetch(`${URL_}/functions/v1/${fn}`, {
      method: "POST",
      headers: { apikey: ANON, Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
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
    user_id: userId, path_id: path!.id, is_primary: true,
    selected_at: new Date().toISOString(),
  });

  console.log("\n3. a photograph of a CV, uploaded the way the app uploads one");
  const photo = await Deno.readFile("supabase/functions/_shared/cv/fixture_cv_photo.jpg");
  const { data: doc } = await service.from("documents").insert({
    user_id: userId,
    type: "cv",
    title: "CV photo",
    storage_path: `pending-${crypto.randomUUID()}`,
    mime_type: "image/jpeg",
    size_bytes: photo.length,
    status: "processing",
  }).select("id").single();

  const key = `users/${userId}/cv/${doc!.id}`;
  const up = await service.storage.from("documents")
    .upload(key, photo, { contentType: "image/jpeg", upsert: true });
  ok("the file reached storage", !up.error, JSON.stringify(up.error));
  await service.from("documents").update({ storage_path: key }).eq("id", doc!.id);

  const asked = await fetch(`${URL_}/functions/v1/score-cv`, {
    method: "POST",
    headers: { apikey: ANON, Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ documentId: doc!.id }),
  });
  const askedBody = await asked.json();
  ok("score-cv accepted it", asked.status === 202 || asked.status === 200,
    `status ${asked.status} ${JSON.stringify(askedBody).slice(0, 200)}`);

  console.log("\n4. waiting for the worker (cron runs every two minutes)");
  const deadline = Date.now() + 5 * 60_000;
  let score: Record<string, unknown> | null = null;
  let lastStatus = "";

  while (Date.now() < deadline) {
    const { data: row } = await service.from("cv_scores")
      .select("score_10, basis, fixes")
      .eq("document_id", doc!.id)
      .order("computed_at", { ascending: false }).limit(1).maybeSingle();
    if (row) { score = row; break; }

    const { data: d } = await service.from("documents")
      .select("status, failure_reason").eq("id", doc!.id).single();
    if (d!.status === "failed") {
      lastStatus = `document failed: ${d!.failure_reason}`;
      break;
    }

    const { data: jobs } = await service.from("jobs_queue")
      .select("status, last_error").eq("user_id", userId).eq("type", "parse_cv");
    const job = jobs?.[0];
    if (job && job.status !== lastStatus) {
      lastStatus = job.status;
      console.log(`     job ${job.status}${job.last_error ? ` — ${job.last_error}` : ""}`);
      if (job.status === "dead") break;
    }
    await new Promise((r) => setTimeout(r, 10_000));
  }

  ok("a score came back from the deployed pipeline", score !== null,
    lastStatus || "timed out after five minutes");

  if (score) {
    ok("it is a number out of ten",
      Number(score.score_10) > 0 && Number(score.score_10) <= 10, `${score.score_10}`);
    ok("scored against the chosen path", score.basis === "path", `${score.basis}`);
    ok("with something to fix", (score.fixes as unknown[]).length > 0);
    console.log(`\n     the photograph scored ${score.score_10} out of 10`);
  }

  // Only meaningful if the worker actually tried. Asserting it when nothing
  // ran is a pass that means nothing, which is worse than no check.
  const { data: attempts } = await service.from("jobs_queue")
    .select("status").eq("user_id", userId).eq("type", "parse_cv");
  if ((attempts ?? []).length > 0) {
    const { data: ocrTrouble } = await service.from("audit_log")
      .select("meta").eq("user_id", userId).eq("action", "ocr_unavailable");
    ok("the OCR engine started in the Edge Runtime",
      (ocrTrouble ?? []).length === 0, JSON.stringify(ocrTrouble));
  } else {
    console.log("  SKIP  the OCR engine — the worker never ran, so nothing was tried");
  }
} finally {
  console.log("\ncleanup");
  const { data: paths } = await service.from("documents")
    .select("storage_path").eq("user_id", userId);
  if (paths?.length) {
    await service.storage.from("documents").remove(paths.map((p) => p.storage_path));
  }
  await admin(`/auth/v1/admin/users/${userId}`, { method: "DELETE" });
  console.log("  throwaway account removed");
}

console.log(`\n${pass} passed, ${fail} failed.`);
Deno.exit(fail === 0 ? 0 : 1);
