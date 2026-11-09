#!/usr/bin/env node
/* Live verification that interview practice is free, from the question pool.

   Owner-only: run after 0096 and 0098 are applied and the interview function
   is deployed. It creates one disposable student and deletes it at the end.

   What it proves:
     1. every active role has its 9 fixed sets, for old app builds;
     2. every role's title resolves to that role, so a typed role finds it;
     3. the interview function serves the bank, and a role it lacks resolves
        to the nearest one, with no model call and no AI action spent;
     4. start_practice_session draws distinct questions, avoids the ones this
        student just saw, writes no ai_usage row, and is closed to anon;
     5. interview_catalog suggests a role;
   and it lists, read-only, every set the worker wrote from a model, so the
   owner can decide about removing them (plan R24, §7).

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
   invoke('interview/questions'). */
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

/* A client RPC, as the app makes it: PostgREST with the caller's own token. */
const rpc = (token, name, params = {}) =>
  fetch(`${URL}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: {
      apikey: ANON,
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(params),
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
    console.log('\n1. every active role has its 9 fixed sets');

    const { rows: [roles] } = await pg.query(
      `select count(*)::int n from public.interview_roles where is_active`);
    ok('the pool has roles', roles.n > 0, `found ${roles.n}`);

    const { rows: [sets] } = await pg.query(
      `select count(*)::int n
         from public.interview_question_bank b
         join public.interview_roles r on r.slug = b.role_slug and r.is_active
        where b.source = 'seed' and jsonb_array_length(b.questions) >= 5`);
    ok(`${roles.n} roles x 9 seed sets of at least five`, sets.n === roles.n * 9,
      `found ${sets.n}, expected ${roles.n * 9}`);

    // ---------------------------------------------------------------------
    console.log('\n2. every role title finds its role');

    const { rows: unresolved } = await pg.query(
      `select r.slug, r.title, f.role_slug got
         from public.interview_roles r
         left join lateral public.interview_role_from_text(r.title) f on true
        where r.is_active and f.role_slug is distinct from r.slug`);
    ok('interview_role_from_text(title) returns the role for all of them',
      unresolved.length === 0, JSON.stringify(unresolved.slice(0, 5)));

    // ---------------------------------------------------------------------
    console.log('\n3. the interview function serves the bank, for free');

    const paidCalls = async () => {
      const { rows: [r] } = await pg.query(
        `select count(*)::int n from public.ai_usage
          where user_id = $1 and not cached`, [student.id]);
      return r.n;
    };
    const usageRows = async () => {
      const { rows: [r] } = await pg.query(
        `select count(*)::int n from public.ai_usage where user_id = $1`,
        [student.id]);
      return r.n;
    };
    const { rows: [{ limit }] } = await pg.query(
      `select public.ai_daily_limit() as limit`);

    const res = await askFor(student.token, 'Backend developer', 'technical', 'medium');
    const body = await res.json();
    ok('the endpoint answers', res.ok, `${res.status} ${JSON.stringify(body)}`);
    ok('with five questions', (body.questions ?? []).length === 5,
      `got ${(body.questions ?? []).length}`);
    ok('served from the bank for that exact role',
      body.cached === true && body.role === 'backend-developer' && body.resolvedFrom === 'exact',
      JSON.stringify({ cached: body.cached, role: body.role, resolvedFrom: body.resolvedFrom }));
    ok('and the student still has their full allowance',
      body.quotaRemaining === limit, `quotaRemaining ${body.quotaRemaining}, limit ${limit}`);

    // A role the bank does not have, and one written in Bangla: both used to
    // reach a model (or crash). Now they resolve to the nearest role.
    for (const role of ['Structural engineer', 'সফটওয়্যার প্রকৌশলী']) {
      const r = await askFor(student.token, role, 'mixed', 'easy');
      const b = await r.json();
      ok(`"${role}" gets the nearest role's questions`,
        r.ok && (b.questions ?? []).length === 5 && typeof b.resolvedFrom === 'string',
        `${r.status} ${JSON.stringify(b).slice(0, 160)}`);
    }
    ok('nothing reached a model', (await paidCalls()) === 0,
      `${await paidCalls()} paid calls`);

    // ---------------------------------------------------------------------
    console.log('\n4. start_practice_session: free, fresh, and closed to anon');

    const { rows: [pick] } = await pg.query(
      `select slug from public.interview_roles
        where is_active order by sort_order limit 1`);
    const usageBefore = await usageRows();

    const first = await rpc(student.token, 'start_practice_session', {
      p_role_slug: pick.slug, p_session_type: 'technical',
      p_difficulty: 'medium', p_count: 5, p_timer: false,
    });
    const firstBody = await first.json();
    ok('a session starts', first.ok && typeof firstBody.session_id === 'string',
      `${first.status} ${JSON.stringify(firstBody)}`);
    ok('with five questions', firstBody.question_count === 5,
      JSON.stringify(firstBody));

    const poolIds = async (sessionId) => (await pg.query(
      `select pool_question_id id from public.interview_questions
        where session_id = $1 order by order_index`, [sessionId])).rows.map((r) => r.id);
    const firstIds = await poolIds(firstBody.session_id);
    ok('five distinct pool questions, each with its key points',
      firstIds.length === 5 && new Set(firstIds).size === 5 && !firstIds.includes(null),
      JSON.stringify(firstIds));
    const { rows: [kp] } = await pg.query(
      `select count(*)::int n from public.interview_questions
        where session_id = $1 and jsonb_array_length(key_points) between 2 and 4`,
      [firstBody.session_id]);
    ok('key points were copied onto the questions', kp.n === 5, `${kp.n} of 5`);

    // Medium with three questions is one easy, one medium and one hard, and
    // the pool has five of each: none needs to repeat.
    const second = await rpc(student.token, 'start_practice_session', {
      p_role_slug: pick.slug, p_session_type: 'technical',
      p_difficulty: 'medium', p_count: 3, p_timer: false,
    });
    const secondBody = await second.json();
    const secondIds = second.ok ? await poolIds(secondBody.session_id) : [];
    ok('a second session avoids the first one\'s questions',
      secondIds.length === 3 && secondIds.every((id) => !firstIds.includes(id)),
      JSON.stringify({ firstIds, secondIds }));

    ok('and writes no ai_usage row', (await usageRows()) === usageBefore,
      `ai_usage went ${usageBefore} -> ${await usageRows()}`);

    const anon = await rpc(ANON, 'start_practice_session', { p_role_slug: pick.slug });
    ok('anon cannot start one', !anon.ok, `${anon.status}`);

    // ---------------------------------------------------------------------
    console.log('\n5. the catalog');

    const cat = await rpc(student.token, 'interview_catalog');
    const catBody = await cat.json();
    ok('a student gets a catalog', cat.ok && Array.isArray(catBody.fields),
      `${cat.status} ${JSON.stringify(catBody).slice(0, 160)}`);
    ok('with a suggested role, even with no path chosen',
      catBody.suggested != null && typeof catBody.suggested.slug === 'string',
      JSON.stringify(catBody.suggested));
    const anonCat = await rpc(ANON, 'interview_catalog');
    ok('anon cannot read it', !anonCat.ok, `${anonCat.status}`);

    // ---------------------------------------------------------------------
    console.log('\n6. sets a model wrote (read-only; the owner decides)');

    const { rows: model } = await pg.query(
      `select role_slug, session_type::text t, difficulty::text d,
              jsonb_array_length(questions) n, created_at
         from public.interview_question_bank
        where source = 'model'
        order by role_slug, session_type, difficulty`);
    if (model.length === 0) {
      console.log('  none');
    } else {
      for (const m of model) {
        console.log(`  ${m.role_slug} / ${m.t} / ${m.d}: ${m.n} questions, ${m.created_at.toISOString()}`);
      }
      console.log(`  ${model.length} model-written sets. Removal is an owner decision (plan §7).`);
    }
  } finally {
    await admin(`/auth/v1/admin/users/${student.id}`, { method: 'DELETE' });
    await pg.end();
  }

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail === 0 ? 0 : 1);
})().catch((e) => { console.error('ERROR:', e.message); process.exit(1); });
