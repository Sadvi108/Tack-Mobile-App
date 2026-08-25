#!/usr/bin/env node
/* Proves analytics stay inside the project and inside the student's own row. */
const path = require('path');
const { Client } = require('pg');
require('dotenv').config({ path: path.join(__dirname, '..', 'supabase', '.env'), quiet: true });

const URL = process.env.SUPABASE_URL;
const ANON = process.env.SUPABASE_ANON_KEY;
const SVC = process.env.SUPABASE_SERVICE_ROLE_KEY;
const admin = (p, o = {}) => fetch(`${URL}${p}`, { ...o, headers: { apikey: SVC, Authorization: `Bearer ${SVC}`, 'Content-Type': 'application/json', ...(o.headers || {}) } });
const asUser = (t, p, o = {}) => fetch(`${URL}${p}`, { ...o, headers: { apikey: ANON, Authorization: `Bearer ${t}`, 'Content-Type': 'application/json', ...(o.headers || {}) } });

let pass = 0, fail = 0;
const ok = (n, c, e = '') => { c ? (pass++, console.log(`  PASS  ${n}`)) : (fail++, console.log(`  FAIL  ${n} ${e}`)); };

(async () => {
  const pg = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await pg.connect();

  const stamp = Date.now();
  const users = [];
  for (const tag of ['a', 'b']) {
    const email = `analytics_${tag}_${stamp}@tack.test`;
    const u = await admin('/auth/v1/admin/users', {
      method: 'POST', body: JSON.stringify({ email, password: 'Test-passw0rd!', email_confirm: true }),
    }).then((r) => r.json());
    const s = await fetch(`${URL}/auth/v1/token?grant_type=password`, {
      method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password: 'Test-passw0rd!' }),
    }).then((r) => r.json());
    users.push({ id: u.id, token: s.access_token });
  }
  const [A, B] = users;

  console.log('\n1. a student records their own events');
  const insert = await asUser(A.token, '/rest/v1/analytics_events', {
    method: 'POST',
    body: JSON.stringify({ user_id: A.id, name: 'screen_view', properties: { screen: 'dashboard' } }),
  });
  ok('an event is accepted', insert.status < 400, `status ${insert.status}`);

  const own = await asUser(A.token, '/rest/v1/analytics_events?select=name').then((r) => r.json());
  ok('and readable by the student who made it', Array.isArray(own) && own.length === 1);

  console.log('\n2. nobody else can reach it');
  const seenByB = await asUser(B.token, '/rest/v1/analytics_events?select=*').then((r) => r.json());
  ok("another student sees nothing", Array.isArray(seenByB) && seenByB.length === 0, JSON.stringify(seenByB).slice(0, 80));

  const forged = await asUser(B.token, '/rest/v1/analytics_events', {
    method: 'POST', body: JSON.stringify({ user_id: A.id, name: 'forged' }),
  });
  ok('and cannot write an event as someone else', forged.status >= 400, `status ${forged.status}`);

  console.log('\n3. the log cannot be rewritten');
  const update = await asUser(A.token, `/rest/v1/analytics_events?user_id=eq.${A.id}`, {
    method: 'PATCH', body: JSON.stringify({ name: 'changed' }),
  });
  const del = await asUser(A.token, `/rest/v1/analytics_events?user_id=eq.${A.id}`, { method: 'DELETE' });
  const stillThere = await asUser(A.token, '/rest/v1/analytics_events?select=name').then((r) => r.json());
  ok('events cannot be edited or deleted by the client',
    stillThere.length === 1 && stillThere[0].name === 'screen_view',
    `patch ${update.status}, delete ${del.status}`);

  console.log('\n4. closing an account takes the history with it');
  await admin(`/auth/v1/admin/users/${A.id}`, { method: 'DELETE' });
  const left = (await pg.query('select count(*)::int n from public.analytics_events where user_id = $1', [A.id])).rows[0].n;
  ok('no events survive the account', left === 0, `${left}`);

  await admin(`/auth/v1/admin/users/${B.id}`, { method: 'DELETE' });
  await pg.end();
  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error('\nERROR:', e.message); process.exit(1); });
