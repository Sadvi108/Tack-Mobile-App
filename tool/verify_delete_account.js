#!/usr/bin/env node
/* Live verification that deleting an account really deletes it.

   Google Play requires an in-app route to this, but the reason to check it
   properly is simpler: a student who asks to be forgotten and is not is the
   one failure you cannot apologise your way out of.

   Three things have to be true, and only the first is obvious:

     1. the auth user and every row that hangs off it are gone;
     2. the *files* are gone too — storage.objects has no foreign key to
        auth.users, so nothing in the database cascade touches a CV;
     3. one student cannot use it to delete another.

     node tool/verify_delete_account.js */
const path = require('path');
const { Client } = require('pg');
require('dotenv').config({
  path: path.join(__dirname, '..', 'supabase', '.env'),
  quiet: true,
});

const URL = process.env.SUPABASE_URL;
const ANON = process.env.SUPABASE_ANON_KEY;
const SVC = process.env.SUPABASE_SERVICE_ROLE_KEY;
const PASSWORD = 'Test-passw0rd!';

let pass = 0, fail = 0;
const ok = (n, c, extra = '') => {
  c ? (pass++, console.log(`  PASS  ${n}`))
    : (fail++, console.log(`  FAIL  ${n} ${extra}`));
};

const admin = (p, o = {}) => fetch(`${URL}${p}`, {
  ...o,
  headers: { apikey: SVC, Authorization: `Bearer ${SVC}`, 'Content-Type': 'application/json', ...(o.headers || {}) },
});

async function makeStudent(label) {
  const email = `delete_${label}_${Date.now()}@tack.test`;
  const u = await admin('/auth/v1/admin/users', {
    method: 'POST',
    body: JSON.stringify({ email, password: PASSWORD, email_confirm: true }),
  }).then((r) => r.json());
  if (!u.id) throw new Error(`could not create user: ${JSON.stringify(u)}`);
  const token = (await fetch(`${URL}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: ANON, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: PASSWORD }),
  }).then((r) => r.json())).access_token;
  return { id: u.id, email, token };
}

/* A real object in the real private bucket, at the path the app uses. */
async function uploadCv(student) {
  const key = `users/${student.id}/cv/${crypto.randomUUID()}.pdf`;
  const res = await fetch(`${URL}/storage/v1/object/documents/${key}`, {
    method: 'POST',
    headers: {
      apikey: ANON,
      Authorization: `Bearer ${student.token}`,
      'Content-Type': 'application/pdf',
    },
    body: new Uint8Array([0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x34]),
  });
  if (!res.ok) throw new Error(`upload failed: ${res.status} ${await res.text()}`);
  return key;
}

const objectsUnder = async (pg, uid) => Number((await pg.query(
  `select count(*)::int n from storage.objects where name like $1`,
  [`users/${uid}/%`])).rows[0].n);

(async () => {
  for (const v of ['SUPABASE_URL', 'SUPABASE_ANON_KEY', 'SUPABASE_SERVICE_ROLE_KEY', 'DATABASE_URL']) {
    if (!process.env[v]) throw new Error(`${v} must be set in supabase/.env`);
  }

  const pg = new Client({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false },
  });
  await pg.connect();

  const strays = [];
  try {
    // ---------------------------------------------------------------------
    console.log('\n1. a student with something to lose');

    const student = await makeStudent('owner');
    strays.push(student.id);
    const key = await uploadCv(student);

    await pg.query(
      `insert into public.documents (user_id, type, title, storage_path, status)
       values ($1, 'cv', 'My CV', $2, 'ready')`, [student.id, key]);
    await pg.query(
      `insert into public.jobs (user_id, company_name, title)
       values ($1, 'bKash', 'Data analyst')`, [student.id]);

    ok('their file is in the bucket', await objectsUnder(pg, student.id) === 1);
    ok('and their rows are in the database',
      (await pg.query(`select count(*)::int n from public.documents where user_id = $1`,
        [student.id])).rows[0].n === 1);

    // ---------------------------------------------------------------------
    console.log('\n2. one student cannot delete another');

    const bystander = await makeStudent('bystander');
    strays.push(bystander.id);

    // The function takes no user id at all, which is the point — but a body
    // carrying one must not change whose account goes.
    const attack = await fetch(`${URL}/functions/v1/delete-account`, {
      method: 'POST',
      headers: {
        apikey: ANON,
        Authorization: `Bearer ${bystander.token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ userId: student.id, user_id: student.id }),
    });
    ok('the call is accepted for the caller themselves', attack.ok,
      `${attack.status} ${await attack.clone().text()}`);

    const victim = await pg.query(
      `select count(*)::int n from public.profiles where id = $1`, [student.id]);
    ok('but it deleted the caller, not the id in the body', victim.rows[0].n === 1);
    ok('the caller is the one who is gone',
      (await pg.query(`select count(*)::int n from public.profiles where id = $1`,
        [bystander.id])).rows[0].n === 0);

    // ---------------------------------------------------------------------
    console.log('\n3. signed out, nothing happens');

    const anon = await fetch(`${URL}/functions/v1/delete-account`, {
      method: 'POST',
      headers: { apikey: ANON, Authorization: `Bearer ${ANON}`, 'Content-Type': 'application/json' },
      body: '{}',
    });
    ok('an unauthenticated call is refused', anon.status === 401,
      `got ${anon.status}`);

    // ---------------------------------------------------------------------
    console.log('\n4. the student deletes their own account');

    const res = await fetch(`${URL}/functions/v1/delete-account`, {
      method: 'POST',
      headers: {
        apikey: ANON,
        Authorization: `Bearer ${student.token}`,
        'Content-Type': 'application/json',
      },
      body: '{}',
    });
    const body = await res.json();
    ok('the call succeeds', res.ok, `${res.status} ${JSON.stringify(body)}`);
    ok('and reports the file it removed', body.files?.documents === 1,
      JSON.stringify(body.files));

    ok('the auth user is gone',
      (await pg.query(`select count(*)::int n from auth.users where id = $1`,
        [student.id])).rows[0].n === 0);
    ok('the profile cascaded away',
      (await pg.query(`select count(*)::int n from public.profiles where id = $1`,
        [student.id])).rows[0].n === 0);
    ok('so did the rows hanging off it',
      (await pg.query(`select count(*)::int n from public.documents where user_id = $1`,
        [student.id])).rows[0].n === 0);

    // The one the database cascade cannot do for you.
    ok('and the file is out of the bucket, not orphaned',
      await objectsUnder(pg, student.id) === 0,
      `${await objectsUnder(pg, student.id)} object(s) left`);
  } finally {
    for (const id of strays) {
      await admin(`/auth/v1/admin/users/${id}`, { method: 'DELETE' });
    }
    await pg.end();
  }

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail === 0 ? 0 : 1);
})().catch((e) => { console.error('ERROR:', e.message); process.exit(1); });
