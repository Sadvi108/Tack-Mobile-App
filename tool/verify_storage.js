#!/usr/bin/env node
/* Proves the document vault's core promise: one student cannot reach another
   student's file, by row id or by storage path. Creates two throwaway users,
   uploads a file as A, then attacks it as B. */
const path = require('path');
const { Client } = require('pg');
require('dotenv').config({ path: path.join(__dirname, '..', 'supabase', '.env'), quiet: true });

const URL = process.env.SUPABASE_URL;
const ANON = process.env.SUPABASE_ANON_KEY;
const SVC = process.env.SUPABASE_SERVICE_ROLE_KEY;

let pass = 0, fail = 0;
const ok = (n, c, extra = '') => { c ? (pass++, console.log(`  PASS  ${n}`)) : (fail++, console.log(`  FAIL  ${n} ${extra}`)); };

const admin = (p, opt = {}) => fetch(`${URL}${p}`, {
  ...opt, headers: { apikey: SVC, Authorization: `Bearer ${SVC}`, 'Content-Type': 'application/json', ...(opt.headers || {}) }
});
const asUser = (tok, p, opt = {}) => fetch(`${URL}${p}`, {
  ...opt, headers: { apikey: ANON, Authorization: `Bearer ${tok}`, ...(opt.headers || {}) }
});

(async () => {
  const pg = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await pg.connect();

  const stamp = Date.now();
  const users = [];
  for (const tag of ['a', 'b']) {
    const email = `storage_${tag}_${stamp}@tack.test`;
    const created = await admin('/auth/v1/admin/users', {
      method: 'POST',
      body: JSON.stringify({ email, password: 'Test-passw0rd!', email_confirm: true })
    }).then(r => r.json());
    const session = await fetch(`${URL}/auth/v1/token?grant_type=password`, {
      method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password: 'Test-passw0rd!' })
    }).then(r => r.json());
    users.push({ id: created.id, email, token: session.access_token });
  }
  const [A, B] = users;

  console.log('\n1. bucket configuration');
  const bucket = (await pg.query(`select public, file_size_limit, allowed_mime_types from storage.buckets where id='documents'`)).rows[0];
  ok('the documents bucket is private', bucket.public === false);
  ok('a 10MB object limit is enforced server-side', Number(bucket.file_size_limit) === 10485760, `${bucket.file_size_limit}`);
  ok('only document and image types are allowed', bucket.allowed_mime_types.includes('application/pdf'));
  ok('archives and executables are not allowed', !bucket.allowed_mime_types.includes('application/zip'));

  console.log('\n2. user A uploads a file');
  const docId = (await pg.query(
    `insert into public.documents (user_id, type, title, storage_path, mime_type, size_bytes, status)
     values ($1,'cv','A private CV','users/'||$2::text||'/cv/'||gen_random_uuid(),'application/pdf',1024,'ready')
     returning id`, [A.id, A.id])).rows[0].id;
  const storagePath = (await pg.query(`select storage_path from public.documents where id=$1`, [docId])).rows[0].storage_path;

  const body = Buffer.from('%PDF-1.4 a private cv');
  const up = await asUser(A.token, `/storage/v1/object/documents/${storagePath}`, {
    method: 'POST', headers: { 'Content-Type': 'application/pdf' }, body
  });
  ok('user A can upload to their own path', up.status < 400, `status ${up.status} ${(await up.clone().text()).slice(0,120)}`);

  console.log('\n3. user B attacks it');
  const rowRead = await asUser(B.token, `/rest/v1/documents?id=eq.${docId}&select=*`).then(r => r.json());
  ok("user B cannot read user A's document row", Array.isArray(rowRead) && rowRead.length === 0, JSON.stringify(rowRead).slice(0, 120));

  const objRead = await asUser(B.token, `/storage/v1/object/documents/${storagePath}`);
  ok("user B cannot download user A's object", objRead.status >= 400, `status ${objRead.status}`);

  const signAttempt = await asUser(B.token, `/storage/v1/object/sign/documents/${storagePath}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ expiresIn: 300 })
  });
  ok("user B cannot sign a URL for user A's object", signAttempt.status >= 400, `status ${signAttempt.status}`);

  const overwrite = await asUser(B.token, `/storage/v1/object/documents/${storagePath}`, {
    method: 'PUT', headers: { 'Content-Type': 'application/pdf' }, body: Buffer.from('overwritten')
  });
  ok("user B cannot overwrite user A's object", overwrite.status >= 400, `status ${overwrite.status}`);

  const del = await asUser(B.token, `/storage/v1/object/documents/${storagePath}`, { method: 'DELETE' });
  ok("user B cannot delete user A's object", del.status >= 400, `status ${del.status}`);

  const writeIntoAPath = await asUser(B.token, `/storage/v1/object/documents/users/${A.id}/cv/forged.pdf`, {
    method: 'POST', headers: { 'Content-Type': 'application/pdf' }, body: Buffer.from('forged')
  });
  ok("user B cannot write into user A's folder", writeIntoAPath.status >= 400, `status ${writeIntoAPath.status}`);

  console.log('\n4. user A can still reach their own file');
  const ownRead = await asUser(A.token, `/storage/v1/object/documents/${storagePath}`);
  ok('user A can download their own object', ownRead.status < 400, `status ${ownRead.status}`);

  const sign = await asUser(A.token, `/storage/v1/object/sign/documents/${storagePath}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ expiresIn: 300 })
  });
  ok('user A can sign a short-lived URL for their own object', sign.status < 400, `status ${sign.status}`);

  console.log('\n5. the default CV rule holds through the API');
  const second = (await pg.query(
    `insert into public.documents (user_id, type, title, storage_path, status)
     values ($1,'cv','CV v2','users/'||$2::text||'/cv/'||gen_random_uuid(),'ready') returning id`,
    [A.id, A.id])).rows[0].id;
  await pg.query(`select public.set_default_cv($1)`, [docId]);
  await pg.query(`select public.set_default_cv($1)`, [second]);
  const defaults = (await pg.query(
    `select count(*)::int n from public.documents where user_id=$1 and type='cv' and is_default and deleted_at is null`,
    [A.id])).rows[0].n;
  ok('only one CV is ever the default', defaults === 1, `${defaults}`);

  let crossPromote = false;
  try {
    await pg.query(`select public.set_default_cv($1)`, ['00000000-0000-0000-0000-000000000000']);
  } catch { crossPromote = true; }
  ok('promoting a CV that does not exist fails loudly', crossPromote);

  // Deleting the auth user cascades the rows but not the bytes, so the
  // objects have to go explicitly or the bucket accumulates test files.
  for (const u of users) {
    const objects = (await pg.query(
      `select name from storage.objects where bucket_id='documents' and name like 'users/' || $1 || '%'`,
      [u.id])).rows;
    for (const o of objects) {
      await asUser(u.token, `/storage/v1/object/documents/${o.name}`, { method: 'DELETE' });
    }
    await admin(`/auth/v1/admin/users/${u.id}`, { method: 'DELETE' });
  }

  const orphans = (await pg.query(
    `select count(*)::int n from storage.objects o
       where o.bucket_id='documents'
         and not exists (select 1 from public.documents d where d.storage_path = o.name)`)).rows[0].n;
  ok('no orphaned objects are left in the bucket', orphans === 0, `${orphans}`);

  await pg.end();
  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error('\nERROR:', e.message); process.exit(1); });
