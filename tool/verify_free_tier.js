#!/usr/bin/env node
/* Live proof that the free tier is actually free.

   Tack gives a student a daily allowance of AI actions shared across the
   coach, CV scoring, job-description analysis and interview feedback. Most of
   what those were spent on is arithmetic — counting bullet points, matching
   skill names against a taxonomy — which needs no model and should never have
   cost anything.

   This drives the free paths as a real student and then asserts the thing that
   matters: `ai_usage` gained no row that reached a model, and the allowance
   has not moved.

     node tool/verify_free_tier.js */
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
const asUser = (t, p, o = {}) => fetch(`${URL}${p}`, {
  ...o,
  headers: { apikey: ANON, Authorization: `Bearer ${t}`, 'Content-Type': 'application/json', ...(o.headers || {}) },
});

async function makeStudent() {
  const email = `free_${Date.now()}@tack.test`;
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
  return { id: u.id, token };
}

/* A CV with deliberate problems: template text left in, no numbers anywhere,
   duties rather than results, and no Projects section. */
const CV_LINES = [
  'Rafiq Hossain',
  'rafiq@example.com | +880 1711111111',
  '',
  'EDUCATION',
  'BUET, BSc Computer Science, 2022 - 2026',
  '',
  'EXPERIENCE',
  'Pathao, Backend intern',
  '- Responsible for the API',
  '- Responsible for fixing bugs',
  '- Worked on the database',
  '',
  'SKILLS',
  'Python, SQL, Excel, Figma',
  '',
  'Lorem ipsum dolor sit amet',
];

/* A real PDF, because the documents bucket accepts PDFs, Word files and
   images and nothing else — a text/plain upload is rejected with a 400. Built
   here rather than using the checked-in fixture so the CV can carry the exact
   defects this check is looking for. */
function makePdf(lines) {
  const esc = (l) => l.replace(/([\\()])/g, '\\$1');
  const text = ['BT', '/F1 11 Tf', '50 750 Td', '14 TL']
    .concat(lines.map((l) => `(${esc(l)}) Tj T*`))
    .concat(['ET'])
    .join('\n');

  const objects = [
    '<</Type/Catalog/Pages 2 0 R>>',
    '<</Type/Pages/Kids[3 0 R]/Count 1>>',
    '<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]/Contents 4 0 R' +
      '/Resources<</Font<</F1 5 0 R>>>>>>',
    `<</Length ${text.length}>>\nstream\n${text}\nendstream`,
    '<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>',
  ];

  let pdf = '%PDF-1.4\n';
  const offsets = [];
  objects.forEach((body, i) => {
    offsets.push(pdf.length);
    pdf += `${i + 1} 0 obj\n${body}\nendobj\n`;
  });

  const xref = pdf.length;
  pdf += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  for (const off of offsets) {
    pdf += `${String(off).padStart(10, '0')} 00000 n \n`;
  }
  pdf += `trailer\n<</Size ${objects.length + 1}/Root 1 0 R>>\n` +
    `startxref\n${xref}\n%%EOF\n`;

  return new Uint8Array([...pdf].map((c) => c.charCodeAt(0)));
}

(async () => {
  for (const v of ['SUPABASE_URL', 'SUPABASE_ANON_KEY', 'SUPABASE_SERVICE_ROLE_KEY', 'DATABASE_URL']) {
    if (!process.env[v]) throw new Error(`${v} must be set in supabase/.env`);
  }

  const pg = new Client({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false },
  });
  await pg.connect();

  const student = await makeStudent();
  try {
    const paid = async () => {
      const { rows: [r] } = await pg.query(
        `select count(*)::int n from public.ai_usage
          where user_id = $1 and not cached`, [student.id]);
      return r.n;
    };
    const allowance = async () => {
      const { rows: [r] } = await pg.query(
        `select coalesce((select count from public.rate_limits
           where user_id = $1 and bucket = 'ai'
             and window_start = (now() at time zone 'utc')::date), 0)::int n`,
        [student.id]);
      return r.n;
    };

    // ---------------------------------------------------------------------
    console.log('\n1. one definition of the limit');

    const { rows: [lim] } = await pg.query(
      `select public.ai_daily_limit() as sql_limit,
              (public.coach_allowance()->>'limit')::int as shown`);
    ok('ai_daily_limit and coach_allowance agree',
      lim.sql_limit === lim.shown, `${lim.sql_limit} vs ${lim.shown}`);
    ok('and it is the raised number', lim.sql_limit === 10, `${lim.sql_limit}`);

    // A caller passing the old 3 must not be able to hold the allowance down.
    const { rows: [forced] } = await pg.query(
      `select public.consume_quota($1, 'probe_free', 3) as left_after`,
      [student.id]);
    ok('the database ignores a limit the caller made up',
      forced.left_after === lim.sql_limit - 1,
      `got ${forced.left_after}, expected ${lim.sql_limit - 1}`);
    await pg.query(
      `delete from public.rate_limits where user_id = $1 and bucket = 'probe_free'`,
      [student.id]);

    // ---------------------------------------------------------------------
    console.log('\n2. a CV check, for nothing');

    const before = await paid();
    const beforeAllowance = await allowance();

    const key = `users/${student.id}/cv/${crypto.randomUUID()}.pdf`;
    const up = await fetch(`${URL}/storage/v1/object/documents/${key}`, {
      method: 'POST',
      headers: {
        apikey: ANON,
        Authorization: `Bearer ${student.token}`,
        'Content-Type': 'application/pdf',
      },
      body: makePdf(CV_LINES),
    });
    ok('the CV uploaded', up.ok, `${up.status}`);

    const { rows: [doc] } = await pg.query(
      `insert into public.documents (user_id, type, title, storage_path, mime_type, status)
       values ($1, 'cv', 'Test CV', $2, 'application/pdf', 'ready') returning id`,
      [student.id, key]);

    const res = await asUser(student.token, '/functions/v1/cv-check', {
      method: 'POST',
      body: JSON.stringify({ documentId: doc.id }),
    });
    const body = await res.json();
    ok('the check is accepted', res.status === 202, `${res.status} ${JSON.stringify(body)}`);
    ok('and says so plainly', body.free === true, JSON.stringify(body));

    const { rows: [s] } = await pg.query(
      `select decrypted_secret x from vault.decrypted_secrets
        where name = 'tack_cron_secret'`);
    await fetch(`${URL}/functions/v1/worker`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${s.x}`, 'Content-Type': 'application/json' },
      body: '{}',
    });

    const { rows: [check] } = await pg.query(
      `select findings, skills, problems, suggestions from public.cv_checks
        where user_id = $1 order by created_at desc limit 1`, [student.id]);
    ok('the check ran', check !== undefined, 'no cv_checks row');

    const kinds = (check?.findings ?? []).map((f) => f.kind);
    ok('it caught the template text left in', kinds.includes('placeholder'),
      kinds.join(', '));
    ok('it noticed no bullet has a number',
      kinds.includes('no-numbers') || kinds.includes('few-numbers'),
      kinds.join(', '));
    ok('it recognised the skills without a model',
      (check?.skills ?? []).includes('Python'),
      JSON.stringify(check?.skills));

    // The whole point.
    ok('nothing reached a model', (await paid()) === before,
      `paid calls ${before} -> ${await paid()}`);
    ok('and the allowance did not move',
      (await allowance()) === beforeAllowance,
      `used ${beforeAllowance} -> ${await allowance()}`);

    // ---------------------------------------------------------------------
    console.log('\n3. a job-description match, for nothing');

    const { rows: [match] } = await pg.query(
      `select public.skills_named_in($1) as found`,
      ['We are looking for someone with Python, SQL and Docker experience.']);
    ok('the free matcher reads a job description',
      (match.found ?? []).length >= 2, JSON.stringify(match.found));
    ok('still nothing reached a model', (await paid()) === before);

    // ---------------------------------------------------------------------
    console.log('\n4. after all of it');

    ok('the student has their whole allowance',
      (await allowance()) === 0, `${await allowance()} used`);
  } finally {
    await admin(`/auth/v1/admin/users/${student.id}`, { method: 'DELETE' });
    await pg.end();
  }

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail === 0 ? 0 : 1);
})().catch((e) => { console.error('ERROR:', e.message); process.exit(1); });
