#!/usr/bin/env node
// Asserts that nothing of ours is callable without signing in, and that no
// trigger function is callable by name at all.
//
// This check exists because Supabase's advisor found six SECURITY DEFINER
// functions open to `anon` — reachable by anybody holding the publishable key,
// which ships inside every copy of the app. Nothing in the repo would have
// noticed: the migrations were correct in what they granted and silent about
// what Postgres grants to PUBLIC on its own.
//
// Two layers, on purpose. The catalogue query is the whole truth; the live HTTP
// calls prove PostgREST agrees with it, because it is PostgREST that is
// actually exposed to the internet.
//
//   node tool/verify_rpc_surface.js
const path = require('path');
const { Client } = require('pg');
require('dotenv').config({
  path: path.join(__dirname, '..', 'supabase', '.env'),
  quiet: true,
});

// Ours, as opposed to pg_trgm's operators, which belong to the extension.
const OURS = `
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.prokind = 'f'
   and not exists (
     select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')`;

// Previously open to anon. Called for real over HTTP with the publishable key.
const PROBES = ['recompute_my_readiness', 'enqueue_cv_rescore'];

let failures = 0;
const ok = (m) => console.log(`  ok    ${m}`);
const bad = (m) => {
  failures++;
  console.log(`  FAIL  ${m}`);
};

(async () => {
  for (const v of ['DATABASE_URL', 'SUPABASE_URL', 'SUPABASE_ANON_KEY']) {
    if (!process.env[v]) throw new Error(`${v} missing from supabase/.env`);
  }

  const client = new Client({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false },
  });
  await client.connect();

  const rows = async (q) => (await client.query(q)).rows;

  const anon = await rows(
    `select p.proname ${OURS} and has_function_privilege('anon', p.oid, 'EXECUTE') order by 1`,
  );
  anon.length === 0
    ? ok('no function is executable by anon')
    : bad(`executable by anon: ${anon.map((r) => r.proname).join(', ')}`);

  const triggers = await rows(
    `select p.proname ${OURS} and p.prorettype = 'trigger'::regtype
       and (has_function_privilege('anon', p.oid, 'EXECUTE')
         or has_function_privilege('authenticated', p.oid, 'EXECUTE'))
     order by 1`,
  );
  triggers.length === 0
    ? ok('no trigger function is callable by a client')
    : bad(`trigger functions callable: ${triggers.map((r) => r.proname).join(', ')}`);

  // The worker, the nightly sweep and the quota primitives all run as
  // service_role. A lockdown that caught them would stop the job queue draining
  // and nothing in the app would report it.
  const worker = [
    'claim_jobs', 'fail_job', 'reap_stuck_jobs', 'dispatch_worker',
    'nightly_maintenance', 'consume_quota', 'refund_quota',
    'recompute_readiness', 'score_cv_fit', 'reindex_listings',
  ];
  const missing = await rows(
    `select p.proname ${OURS} and p.proname = any(array[${worker
      .map((w) => `'${w}'`)
      .join(',')}])
       and not has_function_privilege('service_role', p.oid, 'EXECUTE') order by 1`,
  );
  missing.length === 0
    ? ok(`service_role keeps EXECUTE on all ${worker.length} worker functions`)
    : bad(`service_role lost: ${missing.map((r) => r.proname).join(', ')}`);

  await client.end();

  // What the catalogue says is one thing; what the internet can reach is the
  // thing that matters.
  const base = process.env.SUPABASE_URL.replace(/\/$/, '');
  const key = process.env.SUPABASE_ANON_KEY;
  for (const fn of PROBES) {
    const res = await fetch(`${base}/rest/v1/rpc/${fn}`, {
      method: 'POST',
      headers: {
        apikey: key,
        Authorization: `Bearer ${key}`,
        'Content-Type': 'application/json',
      },
      body: '{}',
    });
    // 401/403 is the lockdown working. 404 means PostgREST will not expose it
    // to this role at all, which is equally fine.
    [401, 403, 404].includes(res.status)
      ? ok(`POST /rpc/${fn} as anon -> ${res.status}`)
      : bad(`POST /rpc/${fn} as anon -> ${res.status}, expected 401/403/404`);
  }

  console.log(
    failures === 0
      ? '\nRPC surface is closed.'
      : `\n${failures} check(s) failed.`,
  );
  process.exit(failures === 0 ? 0 : 1);
})().catch((e) => {
  console.error('ERROR:', e.message);
  process.exit(1);
});
