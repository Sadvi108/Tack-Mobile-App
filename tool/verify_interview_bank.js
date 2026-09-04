#!/usr/bin/env node
/* Live verification that interview practice is free.

   `interview_question_bank` is a cache keyed on (role, session_type,
   difficulty). The first student to ask for a combination pays one of their
   three daily AI actions and everybody after gets it free — but it was empty
   from the day it was created, so every student paid for questions the last
   one had already generated.

   The check that matters is not "does it return questions" but "did it cost
   anything". `ai_usage` is read before and after and must not move.

     node tool/verify_interview_bank.js */
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

const ROLES = [
  'Frontend developer', 'Backend developer', 'Data analyst',
  'Digital marketer', 'HR executive', 'Business analyst',
  'Graphic designer', 'QA engineer', 'Accountant', 'Content writer',
];
const TYPES = ['behavioural', 'technical', 'mixed'];
const LEVELS = ['easy', 'medium', 'hard'];

let pass = 0, fail = 0;
const ok = (n, c, extra = '') => {
  c ? (pass++, console.log(`  PASS  ${n}`))
    : (fail++, console.log(`  FAIL  ${n} ${extra}`));
};

const admin = (p, o = {}) => fetch(`${URL}${p}`, {
  ...o,
  headers: { apikey: SVC, Authorization: `Bearer ${SVC}`, 'Content-Type': 'application/json', ...(o.headers || {}) },
});

async function makeStudent() {
  const email = `iv_${Date.now()}@tack.test`;
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

/* The action is the last path segment, not a body field — the app calls
   invoke('interview/questions'). Worth stating because docs/API.md had it as a
   body field and this check is what caught that. */
const askFor = (token, role, sessionType, difficulty) =>
  fetch(`${URL}/functions/v1/interview/questions`, {
    method: 'POST',
    headers: {
      apikey: ANON,
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ role, sessionType, difficulty, count: 5 }),
  });

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
    // ---------------------------------------------------------------------
    console.log('\n1. every combination the app can ask for');

    const { rows: [seeded] } = await pg.query(
      `select count(*)::int n from public.interview_question_bank`);
    ok('all 90 sets are seeded', seeded.n >= 90, `found ${seeded.n}`);

    const { rows: thin } = await pg.query(
      `select role_slug, session_type::text t, difficulty::text d
         from public.interview_question_bank
        where jsonb_array_length(questions) < 5`);
    ok('none is shorter than the five the app asks for', thin.length === 0,
      JSON.stringify(thin.slice(0, 3)));

    // The app slugifies exactly as the endpoint does; a mismatch means every
    // request misses the cache and pays, which is the bug this feature exists
    // to remove.
    const missing = [];
    for (const role of ROLES) {
      const slug = role.toLowerCase().replace(/[^a-z0-9]+/g, '-');
      for (const t of TYPES) {
        for (const d of LEVELS) {
          const { rows } = await pg.query(
            `select 1 from public.interview_question_bank
              where role_slug = $1 and session_type = $2::interview_type
                and difficulty = $3::difficulty_level`, [slug, t, d]);
          if (rows.length === 0) missing.push(`${slug}/${t}/${d}`);
        }
      }
    }
    ok('every role the app offers resolves, for all 9 combinations',
      missing.length === 0, `missing ${missing.slice(0, 5).join(', ')}`);

    // ---------------------------------------------------------------------
    console.log('\n2. and it costs nothing');

    /* ai_usage logs cache hits too — recordCacheHit writes a row with
       provider 'cache' so the saving is visible in the data. So counting rows
       measures the wrong thing; what costs money and quota is a row that
       actually reached a model. */
    const paidCalls = async () => {
      const { rows: [r] } = await pg.query(
        `select count(*)::int n from public.ai_usage
          where user_id = $1 and not cached`, [student.id]);
      return r.n;
    };
    const cacheHits = async () => {
      const { rows: [r] } = await pg.query(
        `select count(*)::int n from public.ai_usage
          where user_id = $1 and cached`, [student.id]);
      return r.n;
    };

    const before = await paidCalls();

    const res = await askFor(student.token, 'Backend developer', 'technical', 'medium');
    const body = await res.json();
    ok('the endpoint answers', res.ok, `${res.status} ${JSON.stringify(body)}`);
    ok('with five questions', (body.questions ?? []).length === 5,
      `got ${(body.questions ?? []).length}`);
    ok('served from the bank, not generated', body.cached === true,
      JSON.stringify({ cached: body.cached }));

    const after = await paidCalls();
    ok('nothing reached a model', after === before && after === 0,
      `paid calls went ${before} -> ${after}`);
    ok('and the saving is recorded as a cache hit', (await cacheHits()) === 1,
      'recordCacheHit did not log it');
    ok('and the student still has their full allowance',
      body.quotaRemaining === 3, `quotaRemaining ${body.quotaRemaining}`);

    // ---------------------------------------------------------------------
    console.log('\n3. ten sessions in a row, still free');

    for (const [role, t, d] of [
      ['Frontend developer', 'mixed', 'easy'],
      ['Data analyst', 'technical', 'hard'],
      ['HR executive', 'behavioural', 'medium'],
      ['Accountant', 'technical', 'easy'],
      ['QA engineer', 'mixed', 'hard'],
    ]) {
      await askFor(student.token, role, t, d);
    }
    const afterMany = await paidCalls();
    ok('six sessions still reached no model', afterMany === 0,
      `paid calls went ${before} -> ${afterMany}`);
    ok('all six are logged as cache hits', (await cacheHits()) === 6,
      `${await cacheHits()} hits logged`);

    // ---------------------------------------------------------------------
    console.log('\n4. the company packs');

    const packs = await fetch(
      `${URL}/rest/v1/company_interview_packs?select=slug,name,questions`,
      { headers: { apikey: ANON, Authorization: `Bearer ${student.token}` } },
    ).then((r) => r.json());
    ok('a signed-in student can read them', Array.isArray(packs) && packs.length >= 6,
      JSON.stringify(packs).slice(0, 120));
    ok('and each carries questions',
      Array.isArray(packs) && packs.every((p) => (p.questions ?? []).length >= 4));

    const anon = await fetch(
      `${URL}/rest/v1/company_interview_packs?select=slug`,
      { headers: { apikey: ANON, Authorization: `Bearer ${ANON}` } },
    ).then((r) => r.json());
    ok('a signed-out visitor cannot', !Array.isArray(anon) || anon.length === 0,
      JSON.stringify(anon).slice(0, 120));
  } finally {
    await admin(`/auth/v1/admin/users/${student.id}`, { method: 'DELETE' });
    await pg.end();
  }

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail === 0 ? 0 : 1);
})().catch((e) => { console.error('ERROR:', e.message); process.exit(1); });
