#!/usr/bin/env node
/* Live verification of notifications and the daily digest.

   `public.notifications` has existed since 0009 with a screen, a repository
   and an unread badge reading it — and nothing had ever written a row. This
   checks the thing that now does, and the three properties that make it safe
   to point at real students:

     1. one call writes the inbox row *and* enqueues the push, so the phone
        never announces something the app cannot show, and vice versa;
     2. the same dedupe key twice does nothing the second time, which is what
        stops a retried job or a re-run sweep saying it twice;
     3. the digest is capped at one per student per day and arrives at a civil
        hour rather than at 00:20, when the nightly sweep actually runs.

     node tool/verify_notifications.js */
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

async function makeStudent(label) {
  const email = `notify_${label}_${Date.now()}@tack.test`;
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

(async () => {
  for (const v of ['SUPABASE_URL', 'SUPABASE_ANON_KEY', 'SUPABASE_SERVICE_ROLE_KEY', 'DATABASE_URL']) {
    if (!process.env[v]) throw new Error(`${v} must be set in supabase/.env`);
  }

  const pg = new Client({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false },
  });
  await pg.connect();

  const students = [];
  try {
    const student = await makeStudent('digest');
    students.push(student.id);
    await pg.query(
      `update public.profiles set onboarding_completed_at = now(),
              full_name = 'Digest Tester', education_stage = 'bachelors'
        where id = $1`, [student.id]);

    // ---------------------------------------------------------------------
    console.log('\n1. registering a device');

    const res = await asUser(student.token, '/rest/v1/rpc/register_device', {
      method: 'POST',
      body: JSON.stringify({ p_token: `tok_${student.id}`, p_platform: 'android' }),
    });
    ok('a student can register their own device', res.ok,
      `${res.status} ${await res.clone().text()}`);

    const { rows: [device] } = await pg.query(
      `select user_id, platform from public.device_tokens where token = $1`,
      [`tok_${student.id}`]);
    ok('and it is recorded against them', device?.user_id === student.id);

    // The same token arriving for a different account must move, not
    // duplicate: a shared phone otherwise sends one student's reminders to
    // the other.
    const second = await makeStudent('shared');
    students.push(second.id);
    await asUser(second.token, '/rest/v1/rpc/register_device', {
      method: 'POST',
      body: JSON.stringify({ p_token: `tok_${student.id}`, p_platform: 'android' }),
    });
    const { rows: moved } = await pg.query(
      `select user_id from public.device_tokens where token = $1`,
      [`tok_${student.id}`]);
    ok('a shared handset reassigns the token rather than duplicating it',
      moved.length === 1 && moved[0].user_id === second.id,
      JSON.stringify(moved));

    // ---------------------------------------------------------------------
    console.log('\n2. one call, both rails');

    await pg.query(
      `select public.notify($1, 'general', 'Probe', 'Body', '{}'::jsonb, 'verify:one')`,
      [student.id]);

    const inbox = await pg.query(
      `select id, type, title from public.notifications where user_id = $1`,
      [student.id]);
    ok('the in-app notification exists', inbox.rows.length === 1,
      JSON.stringify(inbox.rows));

    const queued = await pg.query(
      `select type, status, payload from public.jobs_queue
        where idempotency_key = 'push:verify:one'`);
    ok('and a push job was enqueued with it',
      queued.rows.length === 1 && queued.rows[0].type === 'send_push',
      JSON.stringify(queued.rows));
    ok('carrying the title the inbox row shows',
      queued.rows[0]?.payload?.title === 'Probe',
      JSON.stringify(queued.rows[0]?.payload));

    // ---------------------------------------------------------------------
    console.log('\n3. saying it twice');

    await pg.query(
      `select public.notify($1, 'general', 'Probe', 'Body', '{}'::jsonb, 'verify:one')`,
      [student.id]);
    const again = await pg.query(
      `select count(*)::int n from public.notifications where user_id = $1`,
      [student.id]);
    ok('the same dedupe key writes one notification, not two',
      again.rows[0].n === 1, `${again.rows[0].n} rows`);

    // ---------------------------------------------------------------------
    console.log('\n4. the digest');

    // A roadmap with one late step and one due tomorrow.
    const { rows: [pathRow] } = await pg.query(
      `select id from public.career_paths limit 1`);
    const { rows: [roadmap] } = await pg.query(
      `insert into public.roadmaps (user_id, path_id, title, origin)
       values ($1, $2, 'Check', 'template') returning id`,
      [student.id, pathRow.id]);
    const { rows: [milestone] } = await pg.query(
      `insert into public.roadmap_milestones (roadmap_id, user_id, order_index, title, state)
       values ($1, $2, 0, 'Start', 'active') returning id`,
      [roadmap.id, student.id]);
    await pg.query(
      `insert into public.roadmap_tasks (milestone_id, user_id, order_index, title, points, due_date)
       values ($1, $2, 0, 'Late one',  5, public.tack_today() - 2),
              ($1, $2, 1, 'Due one',   5, public.tack_today() + 1)`,
      [milestone.id, student.id]);

    const { rows: [count] } = await pg.query(
      `select public.enqueue_daily_digest() as n`);
    ok('the digest runs and enqueues for the student', count.n >= 1,
      `enqueued ${count.n}`);

    const digest = await pg.query(
      `select title, body, payload from public.notifications
        where user_id = $1 and type = 'step_due'`, [student.id]);
    ok('one digest, not one notification per step', digest.rows.length === 1,
      JSON.stringify(digest.rows));
    ok('it counts both the late and the upcoming',
      digest.rows[0]?.payload?.overdue === 1 &&
      digest.rows[0]?.payload?.due_soon === 1,
      JSON.stringify(digest.rows[0]?.payload));

    const when = await pg.query(
      `select run_after,
              (run_after at time zone 'Asia/Dhaka')::time as dhaka_time
         from public.jobs_queue
        where idempotency_key like 'push:digest:' || $1 || '%'`, [student.id]);
    ok('and is scheduled for 09:00 Dhaka, not the 00:20 the sweep runs at',
      when.rows[0]?.dhaka_time === '09:00:00',
      `scheduled ${when.rows[0]?.dhaka_time}`);

    // ---------------------------------------------------------------------
    console.log('\n5. running it twice in one day');

    await pg.query(`select public.enqueue_daily_digest()`);
    const capped = await pg.query(
      `select count(*)::int n from public.notifications
        where user_id = $1 and type = 'step_due'`, [student.id]);
    ok('the cap holds: still one digest today', capped.rows[0].n === 1,
      `${capped.rows[0].n} digests`);

    // ---------------------------------------------------------------------
    console.log('\n6. nothing to say');

    const quiet = await makeStudent('quiet');
    students.push(quiet.id);
    await pg.query(
      `update public.profiles set onboarding_completed_at = now() where id = $1`,
      [quiet.id]);
    await pg.query(`select public.enqueue_daily_digest()`);
    const none = await pg.query(
      `select count(*)::int n from public.notifications where user_id = $1`,
      [quiet.id]);
    ok('a student with no due steps is left alone', none.rows[0].n === 0,
      `${none.rows[0].n} sent`);
  } finally {
    for (const id of students) {
      await admin(`/auth/v1/admin/users/${id}`, { method: 'DELETE' });
    }
    const { rows: [left] } = await pg.query(
      `select count(*)::int n from public.device_tokens where user_id = any($1)`,
      [students]);
    ok('device tokens cascade away with the account', left.n === 0, `${left.n} left`);
    await pg.end();
  }

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail === 0 ? 0 : 1);
})().catch((e) => { console.error('ERROR:', e.message); process.exit(1); });
