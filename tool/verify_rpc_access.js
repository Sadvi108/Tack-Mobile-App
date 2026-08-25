#!/usr/bin/env node
/* Functions that take a user id are the one place Row Level Security cannot
   help: RLS protects tables, not a SECURITY DEFINER function handed the
   caller's choice of id. This checks that a signed-in student can reach the
   short list the app needs and nothing else — including against another
   student, not just against an anonymous caller. */
const path = require('path');
const { Client } = require('pg');
require('dotenv').config({ path: path.join(__dirname, '..', 'supabase', '.env'), quiet: true });

const URL = process.env.SUPABASE_URL, ANON = process.env.SUPABASE_ANON_KEY, SVC = process.env.SUPABASE_SERVICE_ROLE_KEY;
const admin = (p, o = {}) => fetch(`${URL}${p}`, { ...o, headers: { apikey: SVC, Authorization: `Bearer ${SVC}`, 'Content-Type': 'application/json', ...(o.headers || {}) } });

let pass = 0, fail = 0;
const ok = (n, c, e = '') => { c ? (pass++, console.log(`  PASS  ${n}`)) : (fail++, console.log(`  FAIL  ${n} ${e}`)); };

const rpc = (token, fn, params) => fetch(`${URL}/rest/v1/rpc/${fn}`, {
  method: 'POST',
  headers: { apikey: ANON, ...(token ? { Authorization: `Bearer ${token}` } : {}), 'Content-Type': 'application/json' },
  body: JSON.stringify(params),
});

(async () => {
  const pg = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await pg.connect();

  const stamp = Date.now();
  const users = [];
  for (const tag of ['attacker', 'victim']) {
    const u = await admin('/auth/v1/admin/users', {
      method: 'POST',
      body: JSON.stringify({ email: `rpc_${tag}_${stamp}@tack.test`, password: 'Test-passw0rd!', email_confirm: true }),
    }).then((r) => r.json());
    const s = await fetch(`${URL}/auth/v1/token?grant_type=password`, {
      method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: `rpc_${tag}_${stamp}@tack.test`, password: 'Test-passw0rd!' }),
    }).then((r) => r.json());
    users.push({ id: u.id, token: s.access_token });
  }
  const [attacker, victim] = users;
  await pg.query('select public.recompute_readiness($1, $2)', [victim.id, 'setup']);

  const privileged = [
    ['readiness_ratios', { p_user_id: victim.id }],
    ['recompute_readiness', { p_user_id: victim.id, p_reason: 'x' }],
    ['consume_quota', { p_user_id: victim.id, p_bucket: 'ai_actions', p_limit: 3 }],
    ['quota_remaining', { p_user_id: victim.id, p_bucket: 'ai_actions', p_limit: 3 }],
    ['claim_jobs', { p_limit: 5, p_worker: 'x' }],
    ['fail_job', { p_id: '00000000-0000-0000-0000-000000000000', p_error: 'x' }],
    ['drain_local_jobs', { p_limit: 5 }],
    ['nightly_maintenance', {}],
    ['dispatch_worker', {}],
  ];

  console.log('\n1. an anonymous caller reaches none of it');
  for (const [fn, params] of privileged) {
    const res = await rpc(null, fn, params);
    ok(`${fn} is refused`, res.status === 401 || res.status === 403, `status ${res.status}`);
  }

  console.log('\n2. a signed-in student cannot use them against another student');
  for (const [fn, params] of privileged) {
    const res = await rpc(attacker.token, fn, params);
    ok(`${fn} is refused`, res.status === 401 || res.status === 403, `status ${res.status}`);
  }

  console.log("\n3. the victim's data and quota are untouched");
  const quota = (await pg.query('select coalesce(sum(count),0)::int c from public.rate_limits where user_id=$1', [victim.id])).rows[0].c;
  ok('no quota was consumed', quota === 0, `${quota}`);
  const snapshots = (await pg.query('select count(*)::int n from public.readiness_scores where user_id=$1', [victim.id])).rows[0].n;
  ok('no extra score snapshot was written', snapshots === 1, `${snapshots}`);

  console.log('\n4. the app can still do its job');
  const cv = (await pg.query(
    `insert into public.documents (user_id, type, title, storage_path, status)
     values ($1,'cv','CV','users/'||$2::text||'/cv/'||gen_random_uuid(),'ready') returning id`,
    [attacker.id, attacker.id])).rows[0].id;

  const setDefault = await rpc(attacker.token, 'set_default_cv', { p_document_id: cv });
  ok('a student can set their own default CV', setDefault.status < 400, `status ${setDefault.status}`);

  const company = await rpc(attacker.token, 'upsert_company', { raw_name: 'bKash Ltd.' });
  ok('a student can add a company when saving a job', company.status < 400, `status ${company.status}`);

  const readiness = await rpc(attacker.token, 'current_readiness', {});
  ok('a student can read their own score', readiness.status < 400, `status ${readiness.status}`);

  console.log("\n5. and still cannot promote someone else's CV");
  const victimCv = (await pg.query(
    `insert into public.documents (user_id, type, title, storage_path, status)
     values ($1,'cv','Victim CV','users/'||$2::text||'/cv/'||gen_random_uuid(),'ready') returning id`,
    [victim.id, victim.id])).rows[0].id;
  const cross = await rpc(attacker.token, 'set_default_cv', { p_document_id: victimCv });
  const promoted = (await pg.query('select is_default from public.documents where id=$1', [victimCv])).rows[0].is_default;
  ok("another student's CV is not promoted", promoted === false, `status ${cross.status}, is_default ${promoted}`);

  for (const u of users) await admin(`/auth/v1/admin/users/${u.id}`, { method: 'DELETE' });
  await pg.end();
  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error('\nERROR:', e.message); process.exit(1); });
