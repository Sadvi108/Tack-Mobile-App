#!/usr/bin/env node
/* The interview prep brief end to end, against the deployed functions and
   whichever model they are configured with. Two throwaway students at the
   interview stage: one with skills and a project to cite, one with nothing,
   whose brief the evidence gate must refuse and whose action must come back.

   Spends at most two AI actions, both on the throwaway students. */
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
const call = (token, fn, body) => fetch(`${URL}/functions/v1/${fn}`, {
  method: 'POST',
  headers: { apikey: ANON, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify(body),
}).then(async r => ({ status: r.status, body: await r.json().catch(() => null) }));

(async () => {
  const pg = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await pg.connect();
  const one = async (sql, args) => (await pg.query(sql, args)).rows[0];

  const stamp = Date.now();
  const users = {};
  for (const tag of ['ready', 'empty']) {
    const email = `prep_${tag}_${stamp}@tack.test`;
    const created = await admin('/auth/v1/admin/users', {
      method: 'POST', body: JSON.stringify({ email, password: 'Test-passw0rd!', email_confirm: true })
    }).then(r => r.json());
    const session = await fetch(`${URL}/auth/v1/token?grant_type=password`, {
      method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password: 'Test-passw0rd!' })
    }).then(r => r.json());
    users[tag] = { id: created.id, token: session.access_token };
    await pg.query(
      `update public.profiles set education_stage = 'bachelors', year_of_study = 4, years_total = 4,
         onboarding_step = 99, onboarding_completed_at = now() where id = $1`, [created.id]);
  }
  const R = users.ready, X = users.empty;

  const used = async uid => (await one(
    `select coalesce((select count from public.rate_limits where user_id = $1 and bucket = 'ai'
       and window_start = (now() at time zone 'Asia/Dhaka')::date), 0)::int as n`, [uid])).n;

  const waitFor = async jobId => {
    // The worker drains on a two-minute cron; nudging it keeps this quick.
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
    const application = async (uid, desc) => {
      const job = (await one(
        `insert into public.jobs (user_id, company_name, title, description)
         values ($1, 'Meghna Foods', 'Junior data analyst', $2) returning id`, [uid, desc])).id;
      return (await one(
        `insert into public.job_applications (user_id, job_id, status, applied_at)
         values ($1, $2, 'interview', now() - interval '5 days') returning id`, [uid, job])).id;
    };
    const description = 'Junior data analyst. You will clean sales data in Excel, write SQL queries '
      + 'against our warehouse, and build weekly dashboards for the operations team. '
      + 'Requirements: SQL, Excel, Power BI, clear written English.';

    const skillIds = (await pg.query(
      `select id, name from public.skills where lower(name) in ('sql', 'excel') and is_active`)).rows;
    for (const s of skillIds) {
      await pg.query(`insert into public.user_skills (user_id, skill_id, proficiency, source)
        values ($1, $2, 3, 'self')`, [R.id, s.id]);
    }
    await pg.query(`insert into public.projects (user_id, title, summary)
      values ($1, 'Shop sales dashboard', 'A dashboard of a family shop''s monthly sales, built from a spreadsheet.')`, [R.id]);

    console.log('\n1. a student with something to cite');
    const appR = await application(R.id, description);
    const before = await used(R.id);
    const first = await call(R.token, 'interview-prep', { applicationId: appR });
    ok('the request is queued', first.status === 202 && !!first.body?.jobId, JSON.stringify(first));
    const job = await waitFor(first.body?.jobId);
    ok('the worker finishes it', job?.status === 'done', JSON.stringify(job));
    const brief = job?.result?.brief;
    ok('a brief comes back', !!brief, JSON.stringify(job?.result));
    const names = [...skillIds.map(s => s.name), 'Shop sales dashboard'].map(n => n.toLowerCase());
    ok('at least two talking points', (brief?.talking_points ?? []).length >= 2, JSON.stringify(brief?.talking_points));
    ok('every point cites something the student has',
      (brief?.talking_points ?? []).every(p => names.some(n => p.evidence.toLowerCase().includes(n))),
      JSON.stringify(brief?.talking_points));
    ok('likely questions and questions to ask are there',
      (brief?.likely_questions ?? []).length > 0 && (brief?.questions_to_ask ?? []).length > 0);
    ok('no gap is a skill the student already has',
      !(brief?.gaps ?? []).some(g => ['sql', 'excel'].includes(g.skill.toLowerCase())), JSON.stringify(brief?.gaps));
    ok('it cost one AI action', await used(R.id) === before + 1, `${before} -> ${await used(R.id)}`);
    ok('it is stored', !!(await one(`select id from public.interview_prep_briefs where application_id = $1`, [appR])));

    const again = await call(R.token, 'interview-prep', { applicationId: appR });
    ok('asking again returns it at once', again.status === 200 && again.body?.status === 'ready' && again.body?.cached === true,
      JSON.stringify(again).slice(0, 200));
    ok('and free', await used(R.id) === before + 1);
    const cl = await fetch(`${URL}/rest/v1/rpc/application_checklist`, {
      method: 'POST', headers: { apikey: ANON, Authorization: `Bearer ${R.token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_application: appR }),
    }).then(r => r.json());
    ok('the checklist no longer asks for a brief', !(cl.items ?? []).some(i => i.id === 'APP-PREP'), JSON.stringify(cl));

    console.log('\n2. a student with nothing to cite');
    const appX = await application(X.id, description);
    const beforeX = await used(X.id);
    const queued = await call(X.token, 'interview-prep', { applicationId: appX });
    ok('the request is queued', queued.status === 202, JSON.stringify(queued));
    const jobX = await waitFor(queued.body?.jobId);
    ok('the gate refuses an unbacked brief', jobX?.status === 'done' && jobX?.result?.skipped === 'ungrounded',
      JSON.stringify(jobX?.result));
    ok('nothing is stored', !(await one(`select id from public.interview_prep_briefs where application_id = $1`, [appX])));
    ok('and the AI action comes back', await used(X.id) === beforeX, `${beforeX} -> ${await used(X.id)}`);

    console.log('\n3. not before the interview');
    await pg.query(`update public.job_applications set status = 'offer' where id = $1`, [appX]);
    const late = await call(X.token, 'interview-prep', { applicationId: appX });
    ok('an application past the interview stage is turned away', late.status === 409, JSON.stringify(late));
  } finally {
    for (const u of Object.values(users)) await admin(`/auth/v1/admin/users/${u.id}`, { method: 'DELETE' });
    await pg.end();
  }

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error('\nERROR:', e.message); process.exit(1); });
