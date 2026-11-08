#!/usr/bin/env node
/* coach_context() v2 and the chat_messages action checks (0097), against the
   real database, in one transaction that is always rolled back. Nothing it
   writes survives, and it spends no AI action.

   - The actions CHECK, probed with real inserts as the service role: valid
     chips are stored, malformed ones are refused.
   - coach_context()->'roadmap' agrees with dashboard_feed()->'roadmap' for the
     seeded demo student (tool/seed_dashboard_demo.js), so the coach and Home
     never disagree about progress.
   - The same student moved to first year gets empty applications and no
     dates.

     node tool/verify_coach_context.js [student-email]

   Applies 0097 inside the transaction first if it is not applied yet. */
const fs = require('fs');
const path = require('path');
const assert = require('node:assert/strict');
const { Client } = require('pg');
require('dotenv').config({ path: path.join(__dirname, '../supabase/.env'), quiet: true });

const MIGRATION = '0097_coach_context_v2.sql';

let pass = 0;
const ok = (name) => { pass++; console.log(`  PASS  ${name}`); };

(async () => {
  const db = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await db.connect();
  const one = async (sql, args) => (await db.query(sql, args)).rows[0];
  try {
    await db.query('begin');
    if (!(await db.query('select 1 from public.schema_migrations where version=$1', [MIGRATION])).rowCount) {
      await db.query(fs.readFileSync(path.join(__dirname, '../supabase/migrations', MIGRATION), 'utf8'));
      console.log(`  (${MIGRATION} applied inside the transaction only)`);
    }

    const email = process.argv[2];
    const student = await one(
      email
        ? `select p.id from public.profiles p join auth.users u on u.id = p.id
            where u.email = $1 and p.deleted_at is null`
        : `select p.id from public.profiles p join auth.users u on u.id = p.id
            where u.email like 'demo_dash_%@tack.test' and p.deleted_at is null
            order by u.created_at desc limit 1`,
      email ? [email] : []);
    assert.ok(student, 'no demo student: run tool/seed_dashboard_demo.js launch first, or pass an email');
    const uid = student.id;

    console.log('\n1. the actions check, with real inserts');
    const thread = (await one(
      `insert into public.chat_threads(user_id, title) values ($1, 'verify 0097') returning id`, [uid])).id;
    await db.query('set local role service_role');
    const insert = (actions, intent = 'model') => db.query(
      `insert into public.chat_messages(thread_id, user_id, role, body, answered_by, actions, intent)
       values ($1, $2, 'coach', 'verify', 'data', $3, $4)`,
      [thread, uid, actions === null ? null : JSON.stringify(actions), intent]);
    await insert([
      { label: 'Practise an interview', route: 'interview' },
      { label: 'Read about Data analyst', route: 'path', slug: 'data-analyst' },
    ]);
    ok('two valid actions are stored');
    const refused = [
      ['an unknown route', [{ label: 'Go somewhere', route: 'nowhere' }]],
      ['path without a slug', [{ label: 'Read about it', route: 'path' }]],
      ['a slug on another route', [{ label: 'Open your roadmap', route: 'roadmap', slug: 'x' }]],
      ['an extra key', [{ label: 'Open your roadmap', route: 'roadmap', extra: 1 }]],
      ['a one-letter label', [{ label: 'A', route: 'roadmap' }]],
      ['a string element', ['roadmap']],
      ['four actions', ['roadmap', 'score', 'paths', 'profile'].map((route) => ({ label: 'Open it', route }))],
      ['an object instead of a list', { label: 'Open your roadmap', route: 'roadmap' }],
    ];
    for (const [what, actions] of refused) {
      await db.query('savepoint probe');
      await assert.rejects(() => insert(actions), /chat_messages_actions_shape/, what);
      await db.query('rollback to savepoint probe');
      ok(`refused: ${what}`);
    }
    await db.query('savepoint probe');
    await assert.rejects(() => insert(null, 'Not An Intent'), /chat_messages_intent_shape/);
    await db.query('rollback to savepoint probe');
    ok('refused: a malformed intent');
    await db.query('reset role');

    console.log('\n2. the coach and Home count the roadmap the same way');
    await db.query(`select set_config('request.jwt.claims', $1, true)`,
      [JSON.stringify({ sub: uid, role: 'authenticated' })]);
    const { ctx, feed } = await one(
      'select public.coach_context() as ctx, public.dashboard_feed() as feed');
    assert.equal(ctx.version, 2);
    ok('version 2');
    for (const key of ['done', 'total', 'overdue']) {
      assert.equal(ctx.roadmap[key], feed.roadmap[key], `roadmap.${key}`);
    }
    assert.equal(ctx.roadmap.next, feed.roadmap.next_task?.title ?? null);
    assert.equal(ctx.roadmap.next_points, feed.roadmap.next_task?.points ?? null);
    ok(`roadmap agrees: ${ctx.roadmap.done} of ${ctx.roadmap.total}, ${ctx.roadmap.overdue} overdue`);
    assert.deepEqual(ctx.cohort, feed.cohort ?? null);
    ok('cohort agrees');
    const text = JSON.stringify(ctx);
    const notes = (await db.query(
      `select next_action, notes from public.job_applications where user_id = $1 and deleted_at is null`,
      [uid])).rows;
    for (const row of notes) {
      for (const typed of [row.next_action, row.notes]) {
        if (typed && typed.length > 3) assert.ok(!text.includes(typed), 'free text leaked into the context');
      }
    }
    ok('no application note or next action text in the context');

    console.log('\n3. a first-year gets no applications and no dates');
    await db.query('reset role');
    await db.query(
      `update public.profiles set education_stage = 'bachelors', year_of_study = 1, years_total = 4
        where id = $1`, [uid]);
    const early = (await one('select public.coach_context() as ctx')).ctx;
    assert.ok(['discover', 'explore'].includes(early.mode), `mode is ${early.mode}`);
    assert.deepEqual(early.applications, {});
    assert.deepEqual(early.upcoming, []);
    ok(`${early.mode}: applications {} and upcoming []`);

    console.log(`\nPASS: ${pass} checks. Everything above is rolled back.`);
  } finally {
    await db.query('rollback');
    await db.end();
  }
})().catch((e) => { console.error('FAIL:', e.message); process.exitCode = 1; });
