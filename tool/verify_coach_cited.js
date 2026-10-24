#!/usr/bin/env node
/* The coach that cites or refuses, end to end against the deployed functions
   and whichever model they use. A throwaway student asks three questions:

   - one Tack's guides answer: it must come back with citations whose quotes
     are word-for-word spans of the chunks they name, and cost one action;
   - one the guides cannot: refused at once, free, with no model call;
   - one about their own numbers: still answered from their data, free.

   Spends at most one AI action, on the throwaway student. */
const path = require('path');
const { Client } = require('pg');
require('dotenv').config({ path: path.join(__dirname, '..', 'supabase', '.env'), quiet: true });

const URL = process.env.SUPABASE_URL;
const ANON = process.env.SUPABASE_ANON_KEY;
const SVC = process.env.SUPABASE_SERVICE_ROLE_KEY;

let pass = 0, fail = 0;
const ok = (n, c, extra = '') => { c ? (pass++, console.log(`  PASS  ${n}`)) : (fail++, console.log(`  FAIL  ${n} ${extra}`)); };
const sleep = ms => new Promise(r => setTimeout(r, ms));
const normalise = t => t.toLowerCase().replace(/\s+/g, ' ').trim();

const admin = (p, opt = {}) => fetch(`${URL}${p}`, {
  ...opt, headers: { apikey: SVC, Authorization: `Bearer ${SVC}`, 'Content-Type': 'application/json', ...(opt.headers || {}) }
});
const ask = (token, question, threadId) => fetch(`${URL}/functions/v1/coach`, {
  method: 'POST',
  headers: { apikey: ANON, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ question, ...(threadId ? { threadId } : {}) }),
}).then(async r => ({ status: r.status, body: await r.json().catch(() => null) }));

(async () => {
  const pg = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await pg.connect();
  const one = async (sql, args) => (await pg.query(sql, args)).rows[0];

  const email = `cited_${Date.now()}@tack.test`;
  const created = await admin('/auth/v1/admin/users', {
    method: 'POST', body: JSON.stringify({ email, password: 'Test-passw0rd!', email_confirm: true })
  }).then(r => r.json());
  const session = await fetch(`${URL}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: 'Test-passw0rd!' })
  }).then(r => r.json());
  const me = { id: created.id, token: session.access_token };
  await pg.query(`update public.profiles set education_stage = 'bachelors', year_of_study = 3, years_total = 4,
    onboarding_step = 99, onboarding_completed_at = now() where id = $1`, [me.id]);

  const used = async () => (await one(
    `select coalesce((select count from public.rate_limits where user_id = $1 and bucket = 'ai'
       and window_start = (now() at time zone 'Asia/Dhaka')::date), 0)::int as n`, [me.id])).n;
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
    console.log('\n1. a question the guides answer');
    const q = 'What does a data analyst do day to day?';
    const first = await ask(me.token, q);
    ok('it is queued for the model', first.status === 202 && !!first.body?.jobId, JSON.stringify(first));
    const job = await waitFor(first.body?.jobId);
    ok('the worker finishes it', job?.status === 'done', JSON.stringify(job));
    const result = job?.result ?? {};
    ok('it answered', typeof result.reply === 'string' && result.reply.length > 20 && !result.skipped,
      JSON.stringify(result).slice(0, 300));
    const cites = result.citations ?? [];
    ok('with at least one citation', cites.length >= 1, JSON.stringify(cites));
    const chunks = (await pg.query(
      `select chunk_id, text from public.career_catalog_chunks where chunk_id = any($1)`,
      [cites.map(c => c.chunk_id)])).rows;
    ok('every quote is a word-for-word span of the chunk it names',
      cites.every(c => chunks.some(ch => ch.chunk_id === c.chunk_id && normalise(ch.text).includes(normalise(c.quote)))),
      JSON.stringify(cites));
    ok('and it cites the data analyst guide', cites.every(c => c.path_slug === 'data-analyst'), JSON.stringify(cites));
    const saved = await one(`select body, citations, answered_by from public.chat_messages
      where user_id = $1 and role = 'coach' order by created_at desc limit 1`, [me.id]);
    ok('the reply is saved with its citations', saved?.answered_by === 'model' && (saved?.citations ?? []).length === cites.length,
      JSON.stringify(saved));
    ok('it cost one AI action', await used() === 1, `${await used()}`);

    console.log('\n2. a question the guides cannot answer');
    const refused = await ask(me.token, 'What is the salary of a marine biologist?', result.threadId);
    ok('it is refused at once', refused.status === 200 && refused.body?.answeredBy === 'data'
      && /career guides do not cover that/.test(refused.body?.reply ?? ''), JSON.stringify(refused.body));
    ok('marked as from the guides, so the app does not call it your numbers',
      Array.isArray(refused.body?.citations) && refused.body.citations.length === 0);
    ok('and free', refused.body?.spent === false && await used() === 1, `${await used()}`);

    console.log('\n2b. an everyday question is not taken over by the guides');
    const everyday = await ask(me.token, 'What does a good CV look like?');
    const everydayJob = everyday.body?.jobId && await one(
      `select type from public.jobs_queue where id = $1`, [everyday.body.jobId]);
    ok('it goes to the ordinary coach, as before', everydayJob?.type === 'coach_reply',
      JSON.stringify(everyday.body).slice(0, 200));
    if (everyday.body?.jobId) await waitFor(everyday.body.jobId);
    const spentBefore = await used();

    console.log('\n3. a question about the student\'s own numbers');
    const own = await ask(me.token, 'What should I do next?');
    ok('still answered from their data, free', own.status === 200 && own.body?.answeredBy === 'data'
      && !/career guides/.test(own.body?.reply ?? ''), JSON.stringify(own.body).slice(0, 200));
    ok('still nothing more spent', await used() === spentBefore);
  } finally {
    await admin(`/auth/v1/admin/users/${me.id}`, { method: 'DELETE' });
    await pg.end();
  }

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error('\nERROR:', e.message); process.exit(1); });
