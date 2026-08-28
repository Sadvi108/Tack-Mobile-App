#!/usr/bin/env node
/* Supabase will not confirm or deny that an address is registered: signing up
   with an existing confirmed email returns an ordinary-looking 200 and sends
   nothing. This checks the one signal that distinguishes the two, so the app
   never tells a student to check an inbox that will stay empty. */
const path = require('path');
const { Client } = require('pg');
require('dotenv').config({ path: path.join(__dirname, '..', 'supabase', '.env'), quiet: true });

const URL = process.env.SUPABASE_URL, ANON = process.env.SUPABASE_ANON_KEY, SVC = process.env.SUPABASE_SERVICE_ROLE_KEY;
const admin = (p, o = {}) => fetch(`${URL}${p}`, { ...o, headers: { apikey: SVC, Authorization: `Bearer ${SVC}`, 'Content-Type': 'application/json', ...(o.headers || {}) } });
const signup = (email) => fetch(`${URL}/auth/v1/signup`, {
  method: 'POST',
  headers: { apikey: ANON, 'Content-Type': 'application/json' },
  body: JSON.stringify({ email, password: 'Test-passw0rd!' }),
}).then(async (r) => ({ status: r.status, body: await r.json() }));

let pass = 0, fail = 0;
const ok = (n, c, e = '') => { c ? (pass++, console.log(`  PASS  ${n}`)) : (fail++, console.log(`  FAIL  ${n} ${e}`)); };

(async () => {
  const pg = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await pg.connect();

  const email = `signup_${Date.now()}@tack.test`;

  console.log('\n1. a genuinely new address');
  const first = await signup(email);
  ok('is accepted', first.status === 200, `status ${first.status}`);
  ok('comes back with an identity', (first.body.identities ?? []).length === 1,
    JSON.stringify(first.body.identities).slice(0, 80));
  ok('records that a confirmation was sent', !!first.body.confirmation_sent_at);
  ok('is not signed in until they confirm', !first.body.access_token);

  const row = (await pg.query(
    'select confirmation_sent_at, email_confirmed_at from auth.users where email = $1', [email])).rows[0];
  ok('the server really did try to send one', !!row?.confirmation_sent_at);
  ok('and the account is still unconfirmed', !row?.email_confirmed_at);

  console.log('\n2. the same address again, still unconfirmed');
  const second = await signup(email);
  ok('is accepted and resends', second.status === 200, `status ${second.status}`);
  ok('still shows an identity, because it is genuinely pending',
    (second.body.identities ?? []).length === 1,
    JSON.stringify(second.body.identities).slice(0, 80));

  console.log('\n3. once confirmed, the same address goes quiet');
  const id = (await pg.query('select id from auth.users where email = $1', [email])).rows[0].id;
  await admin(`/auth/v1/admin/users/${id}`, {
    method: 'PUT', body: JSON.stringify({ email_confirm: true }),
  });

  const before = (await pg.query('select confirmation_sent_at from auth.users where id = $1', [id])).rows[0];
  const third = await signup(email);

  ok('still returns 200, giving nothing away', third.status === 200, `status ${third.status}`);
  ok('but the identities list is empty — the one usable signal',
    (third.body.identities ?? []).length === 0,
    JSON.stringify(third.body.identities).slice(0, 80));
  ok('and the id is fabricated, not the real account',
    third.body.id !== id, `${third.body.id}`);

  const after = (await pg.query('select confirmation_sent_at from auth.users where id = $1', [id])).rows[0];
  ok('no new email was actually sent',
    String(after.confirmation_sent_at) === String(before.confirmation_sent_at),
    `${before.confirmation_sent_at} -> ${after.confirmation_sent_at}`);

  await admin(`/auth/v1/admin/users/${id}`, { method: 'DELETE' });
  await pg.end();
  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error('\nERROR:', e.message); process.exit(1); });
