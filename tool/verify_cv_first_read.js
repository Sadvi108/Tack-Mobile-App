#!/usr/bin/env node
/* The CV first read end to end, against the deployed functions and whichever
   model they use. A throwaway student uploads the sample CV the pipeline tests
   use; the free check still runs; the first read comes back with readers who
   only remember words the CV says; asking again is free; another student can
   see none of it.

   Spends one AI action, on the throwaway student. */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { Client } = require('pg');
require('dotenv').config({ path: path.join(__dirname, '..', 'supabase', '.env'), quiet: true });

const URL = process.env.SUPABASE_URL;
const ANON = process.env.SUPABASE_ANON_KEY;
const SVC = process.env.SUPABASE_SERVICE_ROLE_KEY;

let pass = 0, fail = 0;
const ok = (n, c, extra = '') => { c ? (pass++, console.log(`  PASS  ${n}`)) : (fail++, console.log(`  FAIL  ${n} ${extra}`)); };
const sleep = ms => new Promise(r => setTimeout(r, ms));

const admin = (p, opt = {}) => fetch(`${URL}${p}`, {
  ...opt, headers: { apikey: SVC, Authorization: `Bearer ${SVC}`, ...(opt.headers || {}) }
});
const call = (token, fn, body) => fetch(`${URL}/functions/v1/${fn}`, {
  method: 'POST',
  headers: { apikey: ANON, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify(body),
}).then(async r => ({ status: r.status, body: await r.json().catch(() => null) }));

// The sample CV from supabase/functions/_shared/cv/fixture_pdf.ts, and the
// lines of text its content stream draws.
const fixture = fs.readFileSync(
  path.join(__dirname, '..', 'supabase', 'functions', '_shared', 'cv', 'fixture_pdf.ts'), 'utf8');
const pdf = Buffer.from([...fixture.matchAll(/"([A-Za-z0-9+/=]+)"/g)].map(m => m[1]).join(''), 'base64');
const cvLines = [...pdf.toString('latin1').matchAll(/\(([^)]*)\) Tj/g)].map(m => m[1]).filter(Boolean);
const normalise = t => t.toLowerCase().replace(/\s+/g, ' ').trim();
const cvText = normalise(cvLines.join(' '));

(async () => {
  const pg = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await pg.connect();
  const one = async (sql, args) => (await pg.query(sql, args)).rows[0];

  const stamp = Date.now();
  const users = {};
  for (const tag of ['me', 'other']) {
    const email = `firstread_${tag}_${stamp}@tack.test`;
    const created = await admin('/auth/v1/admin/users', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password: 'Test-passw0rd!', email_confirm: true })
    }).then(r => r.json());
    const session = await fetch(`${URL}/auth/v1/token?grant_type=password`, {
      method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password: 'Test-passw0rd!' })
    }).then(r => r.json());
    users[tag] = { id: created.id, token: session.access_token };
  }
  const Me = users.me, Other = users.other;
  const storagePath = `users/${Me.id}/cv/first-read-${stamp}.pdf`;

  const used = async uid => (await one(
    `select coalesce((select count from public.rate_limits where user_id = $1 and bucket = 'ai'
       and window_start = (now() at time zone 'Asia/Dhaka')::date), 0)::int as n`, [uid])).n;
  const waitFor = async jobId => {
    await pg.query(`select public.dispatch_worker()`).catch(() => {});
    for (let i = 0; i < 60; i++) {
      const job = await one(`select status, result from public.jobs_queue where id = $1`, [jobId]);
      if (job && ['done', 'dead'].includes(job.status)) return job;
      if (i % 10 === 9) await pg.query(`select public.dispatch_worker()`).catch(() => {});
      await sleep(3000);
    }
    return null;
  };

  try {
    ok('the sample CV decodes to text', cvLines.length > 5 && cvText.includes('page load time'), `${cvLines.length}`);

    const up = await admin(`/storage/v1/object/documents/${storagePath}`, {
      method: 'POST', headers: { 'Content-Type': 'application/pdf' }, body: pdf,
    });
    ok('the CV uploads', up.ok, `${up.status}`);
    const doc = (await one(
      `insert into public.documents (user_id, type, title, storage_path, mime_type, size_bytes, status, checksum)
       values ($1, 'cv', 'Sample CV', $2, 'application/pdf', $3, 'ready', $4) returning id`,
      [Me.id, storagePath, pdf.length, crypto.createHash('sha256').update(pdf).digest('hex')])).id;

    console.log('\n1. the free check still works');
    const check = await call(Me.token, 'cv-check', { documentId: doc });
    const checkJob = await waitFor(check.body?.jobId);
    ok('the check finishes', checkJob?.status === 'done', JSON.stringify(checkJob));
    const row = await one(`select findings from public.cv_checks where document_id = $1`, [doc]);
    ok('and writes findings', Array.isArray(row?.findings) && row.findings.length > 0);
    ok('and it cost nothing', await used(Me.id) === 0);

    console.log('\n2. the first read');
    const first = await call(Me.token, 'cv-first-read', { documentId: doc });
    ok('the read is queued', first.status === 202 && !!first.body?.jobId, JSON.stringify(first));
    const job = await waitFor(first.body?.jobId);
    ok('the worker finishes it', job?.status === 'done', JSON.stringify(job));
    const result = job?.result ?? {};
    const sections = (result.chunks ?? []).map(c => c.section);
    ok('the CV is read section by section', sections.includes('Experience') && sections.includes('Education'),
      JSON.stringify(sections));
    ok('at least two readers come back', (result.readers ?? []).length >= 2, JSON.stringify(result.readers?.map(r => r.persona)));
    ok('each one is a cast reader', (result.readers ?? []).every(r => ['recruiter', 'hiring_manager', 'hr_officer'].includes(r.persona)));
    const n = (result.chunks ?? []).length;
    ok('quit points are inside the CV or the end', (result.readers ?? []).every(r => r.quit_chunk >= 0 && r.quit_chunk <= n));
    ok('needles stay between -2 and +2',
      (result.readers ?? []).every(r => r.needle.every(x => x.value >= -2 && x.value <= 2)));
    const quotes = (result.readers ?? []).flatMap(r => r.remembered);
    ok('everything remembered is in the CV, word for word',
      quotes.every(q => cvText.includes(normalise(q))), JSON.stringify(quotes));
    ok('every reader names one thing to change', (result.readers ?? []).every(r => r.one_action.length > 10));
    ok('it cost one AI action', await used(Me.id) === 1, `${await used(Me.id)}`);

    const again = await call(Me.token, 'cv-first-read', { documentId: doc });
    ok('asking again is instant', again.status === 200 && again.body?.cached === true, JSON.stringify(again).slice(0, 160));
    ok('and free', await used(Me.id) === 1);

    console.log('\n3. only the owner');
    const theirs = await call(Other.token, 'cv-first-read', { documentId: doc });
    ok('another student cannot ask for it', theirs.status === 404, JSON.stringify(theirs));
    const peek = await fetch(`${URL}/rest/v1/cv_first_reads?document_id=eq.${doc}&select=id`, {
      headers: { apikey: ANON, Authorization: `Bearer ${Other.token}` } }).then(r => r.json());
    ok('nor read the stored result', Array.isArray(peek) && peek.length === 0, JSON.stringify(peek));
    const mine = await fetch(`${URL}/rest/v1/cv_first_reads?document_id=eq.${doc}&select=id`, {
      headers: { apikey: ANON, Authorization: `Bearer ${Me.token}` } }).then(r => r.json());
    ok('while the owner can', Array.isArray(mine) && mine.length === 1);
  } finally {
    await admin(`/storage/v1/object/documents/${storagePath}`, { method: 'DELETE' }).catch(() => {});
    for (const u of Object.values(users)) await admin(`/auth/v1/admin/users/${u.id}`, { method: 'DELETE' });
    await pg.end();
  }

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error('\nERROR:', e.message); process.exit(1); });
