#!/usr/bin/env node
/* The application checklist and the prep brief's plumbing, against live SQL.
   Two throwaway students: L, in their final year, with four applications in
   different states, and E, who tries to read L's. Anything that would spend
   an AI action runs inside a transaction that is rolled back. */
const path = require('path');
const crypto = require('crypto');
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
const rpc = (token, fn, args) => fetch(`${URL}/rest/v1/rpc/${fn}`, {
  method: 'POST',
  headers: { apikey: ANON, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify(args),
}).then(async r => ({ status: r.status, body: await r.json().catch(() => null) }));
const rest = (token, p) => fetch(`${URL}/rest/v1/${p}`, {
  headers: { apikey: ANON, Authorization: `Bearer ${token}` },
}).then(r => r.json());

// The TypeScript twin, from supabase/functions/_shared/ai/gateway.ts.
const hashText = t => crypto.createHash('sha256')
  .update(t.trim().toLowerCase().replace(/\s+/g, ' '), 'utf8').digest('hex');

(async () => {
  const pg = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await pg.connect();
  const one = async (sql, args) => (await pg.query(sql, args)).rows[0];
  const today = (await one(`select public.tack_today()::text as d`)).d;
  const day = n => (new Date(Date.parse(today) + n * 86400000)).toISOString().slice(0, 10);

  const stamp = Date.now();
  const users = {};
  for (const tag of ['l', 'e']) {
    const email = `checklist_${tag}_${stamp}@tack.test`;
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
         onboarding_step = 99, onboarding_completed_at = now() - interval '30 days' where id = $1`, [created.id]);
  }
  const L = users.l, E = users.e;
  const description = '  Junior analyst at Meghna Foods.\n\nYou will build   dashboards in SQL and Excel '
    + 'for the sales team, every week.  ';

  try {
    const job = async (company, closes, desc) => (await one(
      `insert into public.jobs (user_id, company_name, title, closes_at, description)
       values ($1, $2, 'Junior analyst', $3, $4) returning id`, [L.id, company, closes, desc])).id;
    const cv = (await one(
      `insert into public.documents (user_id, type, title, storage_path, mime_type, size_bytes, status)
       values ($1::uuid, 'cv', 'My CV', 'users/' || $2 || '/cv/' || gen_random_uuid(), 'application/pdf', 1024, 'ready')
       returning id`, [L.id, L.id])).id;

    const jobA = await job('Meghna Foods', day(2), description);
    const A = (await one(`insert into public.job_applications (user_id, job_id, status)
      values ($1, $2, 'saved') returning id`, [L.id, jobA])).id;
    const B = (await one(`insert into public.job_applications (user_id, job_id, status, applied_at, cv_document_id)
      values ($1, $2, 'interview', now() - interval '10 days', $3) returning id`,
      [L.id, await job('Padma Textiles', null, null), cv])).id;
    const C = (await one(`insert into public.job_applications (user_id, job_id, status, applied_at, cv_document_id, created_at)
      values ($1, $2, 'applied', now() - interval '30 days', $3, now() - interval '31 days') returning id`,
      [L.id, await job('Surma Tea', null, null), cv])).id;
    await pg.query(`update public.application_status_history set changed_at = now() - interval '30 days'
      where application_id = $1`, [C]);
    const D = (await one(`insert into public.job_applications (user_id, job_id, status, applied_at)
      values ($1, $2, 'rejected', now() - interval '40 days') returning id`,
      [L.id, await job('Jamuna Group', null, null)])).id;

    const checklist = async id => (await rpc(L.token, 'application_checklist', { p_application: id })).body;
    const ids = c => (c?.items ?? []).map(i => i.id);

    console.log('\n1. the rules');
    const a = await checklist(A);
    ok('a saved application closing soon, no CV, unchecked job: DATE, CV, JD',
      JSON.stringify(ids(a)) === JSON.stringify(['APP-DATE', 'APP-CV', 'APP-JD']), JSON.stringify(ids(a)));
    ok('the closing date is the next step', a?.next_step?.id === 'APP-DATE', JSON.stringify(a?.next_step));
    ok('every item has a title and an action',
      (a?.items ?? []).every(i => typeof i.title === 'string' && i.title.length > 5 && typeof i.action === 'string'));
    ok('the closing item says the day', /Closes \w{3} \d{2} \w{3}/.test(a?.items?.[0]?.title ?? ''), a?.items?.[0]?.title);

    const b = await checklist(B);
    ok('an interview with no practice and no brief: PRACTICE, PREP',
      JSON.stringify(ids(b)) === JSON.stringify(['APP-PRACTICE', 'APP-PREP']), JSON.stringify(ids(b)));
    ok('practice comes first', b?.next_step?.id === 'APP-PRACTICE');

    const c = await checklist(C);
    ok('sent a month ago with no change: FOLLOW', JSON.stringify(ids(c)) === JSON.stringify(['APP-FOLLOW']), JSON.stringify(ids(c)));

    const d = await checklist(D);
    ok('a closed application has nothing to do', ids(d).length === 0 && d?.next_step === null, JSON.stringify(d));

    console.log('\n2. doing the thing clears it');
    const session = (await one(`insert into public.interview_sessions (user_id, role) values ($1, 'Analyst') returning id`, [L.id])).id;
    await pg.query(`insert into public.interview_questions (session_id, user_id, order_index, question, answer_text, answered_at)
      values ($1, $2, 0, 'Why this role?', 'Because.', now())`, [session, L.id]);
    const b2 = await checklist(B);
    ok('practising this week clears PRACTICE', !ids(b2).includes('APP-PRACTICE'), JSON.stringify(ids(b2)));
    ok('so the brief becomes the next step', b2?.next_step?.id === 'APP-PREP');

    ok('the SQL hash is the TypeScript hash',
      (await one(`select public.tack_text_hash($1) as h`, [description])).h === hashText(description));
    // Pasted descriptions carry no-break spaces, byte-order marks and wide
    // spaces. JavaScript's trim and \s count all of them; Postgres's do not.
    for (const [label, text] of [
      ['a no-break space', 'Junior analyst  role'],
      ['a byte-order mark', '﻿Junior analyst role﻿'],
      ['an ideographic space and a line separator', 'Junior　analyst role'],
      ['tabs and vertical tabs', '\tJunior\x0banalyst\t\trole '],
      ['Greek capitals', 'ΣΑΣ analyst'],
    ]) {
      ok(`the hashes agree on ${label}`,
        (await one(`select public.tack_text_hash($1) as h`, [text])).h === hashText(text));
    }
    const analysis = (await one(`insert into public.job_analyses (raw_text_hash, job_title, extracted)
      values ($1, 'Junior analyst', '{}'::jsonb)
      on conflict (raw_text_hash) do update set job_title = excluded.job_title returning id`, [hashText(description)])).id;
    await pg.query(`insert into public.job_match_scores (user_id, analysis_id, match_percent, matched_skills, missing_skills)
      values ($1, $2, 50, '[]', '[]')`, [L.id, analysis]);
    ok('checking this job\'s description clears JD, even from the shared cache',
      !ids(await checklist(A)).includes('APP-JD'), JSON.stringify(ids(await checklist(A))));

    console.log('\n2b. what the student cannot see is not done');
    // A CV deleted from the vault is not attached, whatever the row says.
    await pg.query(`update public.documents set deleted_at = now() where id = $1`, [cv]);
    ok('a deleted CV counts as no CV', ids(await checklist(C)).includes('APP-CV'), JSON.stringify(ids(await checklist(C))));
    await pg.query(`update public.documents set deleted_at = null where id = $1`, [cv]);
    // Practice in a deleted session is gone from the practice screen.
    await pg.query(`update public.interview_sessions set deleted_at = now() where id = $1`, [session]);
    ok('practice in a deleted session does not count', ids(await checklist(B)).includes('APP-PRACTICE'),
      JSON.stringify(ids(await checklist(B))));
    await pg.query(`update public.interview_sessions set deleted_at = null where id = $1`, [session]);
    // The analyser refuses under 80 characters, so the checklist must not ask.
    const shortApp = (await one(`insert into public.job_applications (user_id, job_id, status)
      values ($1, $2, 'saved') returning id`, [L.id, await job('Short Co', null, '  Analyst.\n\n  Excel.  ')])).id;
    ok('a description too short to check is not asked for',
      !ids(await checklist(shortApp)).includes('APP-JD'), JSON.stringify(ids(await checklist(shortApp))));

    console.log('\n3. only the owner');
    const theirs = await rpc(E.token, 'application_checklist', { p_application: A });
    ok('another student cannot read it', theirs.status >= 400 || theirs.body === null, JSON.stringify(theirs));
    const anon = await fetch(`${URL}/rest/v1/rpc/application_checklist`, {
      method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_application: A }),
    });
    ok('nor can the public', anon.status >= 400, `${anon.status}`);

    console.log('\n4. the new job types');
    const enqueue = async (uid, type, payload) => {
      await pg.query('begin');
      try {
        const r = await one(`select public.enqueue_student_job($1, $2, $3::jsonb, $4) as r`,
          [uid, type, JSON.stringify(payload), `${type}:verify:${stamp}:${Math.random()}`]);
        return { ok: true, r: r.r };
      } catch (e) {
        return { ok: false, error: e.message };
      } finally {
        await pg.query('rollback');
      }
    };
    ok('a prep brief for an interview-stage application is accepted',
      (await enqueue(L.id, 'interview_prep', { application_id: B })).ok);
    const notYet = await enqueue(L.id, 'interview_prep', { application_id: A });
    ok('but not before the interview stage', !notYet.ok && /application_not_interview/.test(notYet.error), notYet.error);
    const stolen = await enqueue(E.id, 'interview_prep', { application_id: B });
    ok('and never for somebody else\'s application', !stolen.ok && /application_not_owned/.test(stolen.error), stolen.error);
    const read = await enqueue(E.id, 'cv_first_read', { document_id: cv });
    ok('a first read only of your own CV', !read.ok && /document_not_owned/.test(read.error), read.error);
    ok('a first read of your own CV is accepted', (await enqueue(L.id, 'cv_first_read', { document_id: cv })).ok);
    ok('a cited coach question is accepted', (await enqueue(L.id, 'coach_cited', { question: 'What does an analyst do?' })).ok);

    console.log('\n5. briefs are private');
    await pg.query(`insert into public.interview_prep_briefs (user_id, application_id, input_hash, brief)
      values ($1, $2, 'h1', '{"talking_points": []}'::jsonb)`, [L.id, B]);
    ok('the owner sees their brief', (await rest(L.token, `interview_prep_briefs?application_id=eq.${B}&select=id`)).length === 1);
    ok('another student sees nothing', (await rest(E.token, `interview_prep_briefs?application_id=eq.${B}&select=id`)).length === 0);
    const b3 = await checklist(B);
    ok('having a brief clears PREP', !ids(b3).includes('APP-PREP') && b3?.next_step === null, JSON.stringify(b3));

    const grants = await one(
      `select has_function_privilege('anon', 'public.application_checklist(uuid)', 'execute') as anon_cl,
              has_function_privilege('authenticated', 'public.tack_text_hash(text)', 'execute') as auth_hash`);
    ok('the checklist is not callable anonymously', grants.anon_cl === false);
    ok('the hash helper stays internal', grants.auth_hash === false);
    const table = await one(
      `select has_table_privilege('authenticated', 'public.interview_prep_briefs', 'select') as sel,
              has_table_privilege('authenticated', 'public.interview_prep_briefs', 'insert') as ins,
              has_table_privilege('authenticated', 'public.interview_prep_briefs', 'truncate') as trunc,
              has_table_privilege('anon', 'public.interview_prep_briefs', 'select') as anon_sel`);
    ok('students may read briefs and nothing else',
      table.sel && !table.ins && !table.trunc && !table.anon_sel, JSON.stringify(table));
  } finally {
    await pg.query('rollback').catch(() => {});
    await pg.query(`delete from public.job_analyses where job_title = 'Junior analyst'
      and raw_text_hash = $1 and not exists (select 1 from public.job_match_scores m
        where m.analysis_id = job_analyses.id and m.user_id <> all($2::uuid[]))`,
      [hashText(description),
       [L.id, E.id]]).catch(() => {});
    for (const u of Object.values(users)) await admin(`/auth/v1/admin/users/${u.id}`, { method: 'DELETE' });
    await pg.end();
  }

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error('\nERROR:', e.message); process.exit(1); });
