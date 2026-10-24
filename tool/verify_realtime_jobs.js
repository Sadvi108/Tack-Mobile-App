#!/usr/bin/env node
/* Proves that following a job over Realtime leaks nothing: the owner hears
   their job change, another student listening for the same job id hears
   nothing, and neither does a caller with only the anon key. Creates two
   throwaway users, gives A a job, changes it, and deletes them again.

   Speaks the Realtime socket protocol directly with Node's built-in
   WebSocket, so it needs no client library. */
const path = require('path');
const { Client } = require('pg');
require('dotenv').config({ path: path.join(__dirname, '..', 'supabase', '.env'), quiet: true });

const URL = process.env.SUPABASE_URL;
const ANON = process.env.SUPABASE_ANON_KEY;
const SVC = process.env.SUPABASE_SERVICE_ROLE_KEY;

let pass = 0, fail = 0;
const ok = (n, c, extra = '') => { c ? (pass++, console.log(`  PASS  ${n}`)) : (fail++, console.log(`  FAIL  ${n} ${extra}`)); };
const sleep = ms => new Promise(r => setTimeout(r, ms));

const admin = (p, opt = {}) => fetch(`${URL}${p}`, {
  ...opt, headers: { apikey: SVC, Authorization: `Bearer ${SVC}`, 'Content-Type': 'application/json', ...(opt.headers || {}) }
});

/* Joins one channel listening for UPDATEs to one job row. Resolves once the
   server says the Postgres listener is live, or after 15s regardless. */
function listen(label, jobId, token) {
  const socket = new WebSocket(
    `${URL.replace(/^http/, 'ws')}/realtime/v1/websocket?apikey=${ANON}&vsn=1.0.0`);
  const heard = [];
  let joined = null;
  const ready = new Promise(resolve => {
    const timer = setTimeout(() => resolve(false), 15000);
    socket.addEventListener('open', () => {
      socket.send(JSON.stringify({
        topic: `realtime:verify-${label}`, event: 'phx_join', ref: '1', join_ref: '1',
        payload: {
          config: {
            broadcast: { ack: false, self: false }, presence: { key: '' }, private: false,
            postgres_changes: [{ event: 'UPDATE', schema: 'public', table: 'jobs_queue', filter: `id=eq.${jobId}` }],
          },
          ...(token ? { access_token: token } : {}),
        },
      }));
    });
    socket.addEventListener('message', ({ data }) => {
      const msg = JSON.parse(data);
      if (msg.event === 'phx_reply' && msg.ref === '1') joined = msg.payload.status;
      if (msg.event === 'system' && msg.payload?.extension === 'postgres_changes') {
        clearTimeout(timer);
        resolve(msg.payload.status === 'ok');
      }
      if (msg.event === 'postgres_changes') heard.push({ ...msg.payload.data, at: Date.now() });
    });
  });
  return { ready, heard, joined: () => joined, close: () => socket.close() };
}

(async () => {
  const pg = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await pg.connect();

  const stamp = Date.now();
  const users = [];
  for (const tag of ['a', 'b']) {
    const email = `realtime_${tag}_${stamp}@tack.test`;
    const created = await admin('/auth/v1/admin/users', {
      method: 'POST',
      body: JSON.stringify({ email, password: 'Test-passw0rd!', email_confirm: true })
    }).then(r => r.json());
    const session = await fetch(`${URL}/auth/v1/token?grant_type=password`, {
      method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password: 'Test-passw0rd!' })
    }).then(r => r.json());
    users.push({ id: created.id, token: session.access_token });
  }
  const [A, B] = users;

  try {
    console.log('\n1. publication');
    const published = (await pg.query(
      `select 1 from pg_publication_tables
        where pubname='supabase_realtime' and schemaname='public' and tablename='jobs_queue'`)).rowCount;
    ok('jobs_queue is published to Realtime', published === 1);

    // 'done' and an unknown type, so the worker never claims it mid-test.
    const jobId = (await pg.query(
      `insert into public.jobs_queue (user_id, type, status, result)
       values ($1, 'verify_realtime', 'done', '{}'::jsonb) returning id`, [A.id])).rows[0].id;

    console.log('\n2. listeners');
    const owner = listen('owner', jobId, A.token);
    const other = listen('other', jobId, B.token);
    const anon = listen('anon', jobId, null);
    const [ownerReady, otherReady, anonReady] = await Promise.all([owner.ready, other.ready, anon.ready]);
    ok('the owner\'s listener goes live', ownerReady, `joined=${owner.joined()}`);
    console.log(`        other student live: ${otherReady} (joined=${other.joined()}), anon live: ${anonReady} (joined=${anon.joined()})`);

    console.log('\n3. the job changes');
    const changedAt = Date.now();
    await pg.query(`update public.jobs_queue set result = '{"verified":true}'::jsonb where id = $1`, [jobId]);
    await sleep(8000);

    ok('the owner hears the change', owner.heard.length === 1, `heard ${owner.heard.length}`);
    if (owner.heard[0]) console.log(`        heard ${owner.heard[0].at - changedAt}ms after the update was sent`);
    ok('the change is about their job', owner.heard[0]?.record?.id === jobId);
    ok('another student listening for the same id hears nothing', other.heard.length === 0, `heard ${other.heard.length}`);
    ok('the anon key alone hears nothing', anon.heard.length === 0, `heard ${anon.heard.length}`);

    for (const l of [owner, other, anon]) l.close();
  } finally {
    for (const u of users) await admin(`/auth/v1/admin/users/${u.id}`, { method: 'DELETE' });
    const left = (await pg.query(`select count(*)::int n from public.jobs_queue where type='verify_realtime'`)).rows[0].n;
    ok('no test jobs are left behind', left === 0, `${left}`);
    await pg.end();
  }

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error('\nERROR:', e.message); process.exit(1); });
