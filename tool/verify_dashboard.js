#!/usr/bin/env node
/* Live verification of public.dashboard_feed().

   Everything a student sees on the home screen now comes from one function, so
   this checks that function the way the app calls it: over PostgREST, with a
   real student's token, against the real database.

   The direct database connection is used only to seed and to clean up. It is
   the owner and bypasses row level security, so nothing is *asserted* through
   it — a check that passed as the owner would prove nothing about what a
   student can actually reach. */
const path = require('path');
const { Client } = require('pg');
require('dotenv').config({ path: path.join(__dirname, '..', 'supabase', '.env'), quiet: true });

const URL = process.env.SUPABASE_URL;
const ANON = process.env.SUPABASE_ANON_KEY;
const SVC = process.env.SUPABASE_SERVICE_ROLE_KEY;
const PASSWORD = 'Test-passw0rd!';

let pass = 0, fail = 0;
const ok = (n, c, extra = '') => { c ? (pass++, console.log(`  PASS  ${n}`)) : (fail++, console.log(`  FAIL  ${n} ${extra}`)); };

const admin = (p, opt = {}) => fetch(`${URL}${p}`, {
  ...opt, headers: { apikey: SVC, Authorization: `Bearer ${SVC}`, 'Content-Type': 'application/json', ...(opt.headers || {}) }
});
const asUser = (tok, p, opt = {}) => fetch(`${URL}${p}`, {
  ...opt, headers: { apikey: ANON, Authorization: `Bearer ${tok}`, 'Content-Type': 'application/json', ...(opt.headers || {}) }
});
const feedFor = (tok) => asUser(tok, '/rest/v1/rpc/dashboard_feed', { method: 'POST', body: '{}' });

async function makeStudent(label) {
  const email = `dash_${label}_${Date.now()}@tack.test`;
  const created = await admin('/auth/v1/admin/users', {
    method: 'POST',
    body: JSON.stringify({ email, password: PASSWORD, email_confirm: true, user_metadata: { full_name: 'Dashboard Check' } })
  }).then(r => r.json());
  if (!created.id) throw new Error(`could not create user: ${JSON.stringify(created)}`);
  const token = (await fetch(`${URL}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: PASSWORD })
  }).then(r => r.json())).access_token;
  return { id: created.id, email, token };
}

/* Dhaka dates, because the function counts Dhaka days. Seeding in UTC and
   asserting in Dhaka is how you write a streak test that passes in London and
   fails in Dhaka at six in the evening. */
const dhakaToday = () => {
  const d = new Date(Date.now() + 6 * 3600 * 1000);
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
};
const dayOffset = (n) => {
  const d = new Date(dhakaToday().getTime() + n * 86400000);
  return d.toISOString().slice(0, 10);
};
/* Mid-afternoon Dhaka, so a seeded timestamp lands on the day intended
   whatever hour this script happens to run at. */
const stampOffset = (n) => `${dayOffset(n)}T09:00:00+06:00`;

(async () => {
  if (!URL || !ANON || !SVC || !process.env.DATABASE_URL) {
    throw new Error('SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY and DATABASE_URL must be set in supabase/.env');
  }

  const pg = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await pg.connect();

  const student = await makeStudent('a');
  let other = null;

  try {
    console.log('\n1. who may call it at all');

    const anonCall = await fetch(`${URL}/rest/v1/rpc/dashboard_feed`, {
      method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' }, body: '{}'
    });
    ok('the anon key alone cannot call it', anonCall.status === 401 || anonCall.status === 403 || anonCall.status === 404,
      `status ${anonCall.status}`);

    for (const [fn, body] of [
      ['tack_week_summary', { p_user_id: student.id, p_from: dayOffset(-7), p_to: dayOffset(0) }],
      ['tack_activity', { p_user_id: student.id }],
    ]) {
      const helper = await asUser(student.token, `/rest/v1/rpc/${fn}`, {
        method: 'POST', body: JSON.stringify(body),
      });
      ok(`a student cannot call ${fn}, which takes a user id`, helper.status >= 400, `status ${helper.status}`);
    }

    const first = await feedFor(student.token);
    ok('a signed-in student can call the feed', first.status === 200, `status ${first.status} ${(await first.clone().text()).slice(0, 200)}`);

    console.log('\n2. a student with nothing yet');
    const empty = await first.json();
    ok('the feed is not an error for a brand-new account', empty !== undefined);
    if (empty) {
      ok('the score starts at zero rather than missing', empty.score?.total === 0, JSON.stringify(empty.score).slice(0, 120));
      ok('the streak starts at zero', empty.streak?.current === 0, JSON.stringify(empty.streak));
      ok('nothing is on the timeline', Array.isArray(empty.timeline) && empty.timeline.length === 0, JSON.stringify(empty.timeline).slice(0, 120));
      ok('no CV is reported', empty.documents?.has_cv === false, JSON.stringify(empty.documents));
      ok('every section the client reads is present', [
        'profile', 'score', 'streak', 'this_week', 'last_week', 'trend',
        'roadmap', 'applications', 'timeline', 'skill_gap', 'skill_fit',
        'paths', 'documents', 'unread_notifications', 'today',
      ].every(k => k in empty), Object.keys(empty).join(','));
    }

    console.log('\n3. real activity, seeded as the student would create it');

    /* A path, a roadmap, a milestone and three tasks: two done on consecutive
       days and one due tomorrow. */
    const { rows: [pathRow] } = await pg.query(
      `select id, title from public.career_paths where is_active order by sort_order limit 1`);
    await pg.query(
      `insert into public.user_career_paths (user_id, path_id, is_primary) values ($1, $2, true)`,
      [student.id, pathRow.id]);

    const { rows: [roadmap] } = await pg.query(
      `insert into public.roadmaps (user_id, path_id, title, origin)
       values ($1, $2, 'Check', 'template') returning id`, [student.id, pathRow.id]);
    const { rows: [milestone] } = await pg.query(
      `insert into public.roadmap_milestones (roadmap_id, user_id, order_index, title, state)
       values ($1, $2, 0, 'Learn the tools', 'active') returning id`, [roadmap.id, student.id]);

    /* done_at cannot be seeded directly: stamp_task_done fires BEFORE INSERT OR
       UPDATE OF is_done and rewrites it to now(), on purpose — a client must
       not be able to claim it finished something last Tuesday. The trigger is
       column-scoped, so a plain update of done_at alone does not re-fire it,
       which is how a test backdates one honestly. */
    const { rows: ticked } = await pg.query(
      `insert into public.roadmap_tasks (milestone_id, user_id, order_index, title, points, est_minutes, is_done)
       values ($1, $2, 0, 'Ticked yesterday', 5, 60, true),
              ($1, $2, 1, 'Ticked today',      4, 30, true)
       returning id, order_index`,
      [milestone.id, student.id]);
    ok('a client cannot stamp its own done_at',
      (await pg.query(`select count(*)::int n from public.roadmap_tasks
                        where id = any($1)
                          and (done_at at time zone 'Asia/Dhaka')::date = (now() at time zone 'Asia/Dhaka')::date`,
        [ticked.map(t => t.id)])).rows[0].n === 2,
      'the done_at trigger did not stamp both rows');

    const yesterday = ticked.find(t => t.order_index === 0).id;
    await pg.query(`update public.roadmap_tasks set done_at = $2 where id = $1`,
      [yesterday, stampOffset(-1)]);
    await pg.query(
      `insert into public.roadmap_tasks (milestone_id, user_id, order_index, title, points, est_minutes, due_date)
       values ($1, $2, 2, 'Due tomorrow', 6, 45, $3),
              ($1, $2, 3, 'Late already', 7, 45, $4)`,
      [milestone.id, student.id, dayOffset(1), dayOffset(-3)]);

    /* An application with a follow-up date, and a job that closes soon. */
    const { rows: [job] } = await pg.query(
      `insert into public.jobs (user_id, company_name, title, closes_at)
       values ($1, 'bKash', 'Data analyst', $2) returning id`, [student.id, dayOffset(5)]);
    await pg.query(
      `insert into public.job_applications (user_id, job_id, status, next_action, next_action_date)
       values ($1, $2, 'applied', 'Send the portfolio', $3)`, [student.id, job.id, dayOffset(2)]);

    /* A skill, added yesterday. This is the exact shape of the bug 0048 fixed:
       the streak counted user_skills and the week summary did not, so the same
       snapshot lit up a day on the strip and said "nothing last week". */
    const { rows: [skill] } = await pg.query(
      `select id from public.skills where is_active order by name limit 1`);
    await pg.query(
      `insert into public.user_skills (user_id, skill_id, proficiency, source, created_at)
       values ($1, $2, 3, 'self', $3)`, [student.id, skill.id, stampOffset(-1)]);

    /* A CV, so has_cv flips and the set-up step drops. */
    await pg.query(
      `insert into public.documents (user_id, type, title, storage_path, status)
       values ($1, 'cv', 'CV', $2, 'ready')`, [student.id, `users/${student.id}/cv/x.pdf`]);

    await pg.query(`select public.recompute_readiness($1, 'verify')`, [student.id]);

    const loaded = await feedFor(student.token);
    ok('the feed still answers with data on it', loaded.status === 200, `status ${loaded.status}`);
    const feed = await loaded.json();

    console.log('\n4. what it says');
    ok('the chosen path is named', feed.paths?.primary_title === pathRow.title,
      `${feed.paths?.primary_title} vs ${pathRow.title}`);
    ok('the CV is seen', feed.documents?.has_cv === true, JSON.stringify(feed.documents));
    ok('the roadmap counts every step, done and not', feed.roadmap?.total === 4 && feed.roadmap?.done === 2,
      JSON.stringify(feed.roadmap));
    ok('the late step is counted as late', feed.roadmap?.overdue === 1, JSON.stringify(feed.roadmap));
    ok('the next step is the soonest unfinished one', feed.roadmap?.next_task?.title === 'Late already',
      JSON.stringify(feed.roadmap?.next_task));

    ok('two days of activity make a two-day streak', feed.streak?.current === 2, JSON.stringify(feed.streak));
    ok('this week counts the steps ticked', (feed.this_week?.tasks_done ?? 0) >= 1, JSON.stringify(feed.this_week));

    /* The regression that matters most. Every day the streak lights up must be
       a day the week summaries can account for, or two cards on one screen
       contradict each other about whether the student did anything. */
    const weekDays = (feed.this_week?.active_days ?? 0) + (feed.last_week?.active_days ?? 0);
    const streakDays = (feed.streak?.days ?? []).filter(d => d >= feed.last_week.from).length;
    ok('the streak and the week summaries count the same days',
      weekDays === streakDays, `weeks say ${weekDays}, streak says ${streakDays}`);

    const weekMoves = (feed.this_week?.moves ?? 0) + (feed.last_week?.moves ?? 0);
    ok('a week with an active day never reports zero activity',
      !(streakDays > 0 && weekMoves === 0), `${streakDays} active days but ${weekMoves} moves`);
    /* The skill was seeded yesterday, which falls in *this* week six days out
       of seven and in last week only when the script runs on a Monday. Pinning
       the assertion to last_week made this pass on Mondays and fail the rest of
       the week, which says nothing about the code under test. What 0048
       actually promises is that a skill counts as activity in whichever week
       contains the day it was added. */
    const addedOn = dayOffset(-1);
    const bucket = addedOn >= feed.this_week?.from ? feed.this_week : feed.last_week;
    ok('a skill added is activity, not nothing',
      (bucket?.skills_added ?? 0) === 1,
      `added ${addedOn}, looked in ${bucket?.from}..${bucket?.to}: ${JSON.stringify(bucket)}`);

    ok('the path count is read from the database, not written into the copy',
      (feed.paths?.available ?? 0) > 0, JSON.stringify(feed.paths));

    const kinds = (feed.timeline ?? []).map(e => e.kind);
    ok('the timeline merges all three sources', ['task', 'application', 'closing'].every(k => kinds.includes(k)),
      kinds.join(','));
    const dates = (feed.timeline ?? []).map(e => e.on);
    ok('and arrives already sorted by date', dates.join() === [...dates].sort().join(), dates.join(','));
    ok('a past date is flagged as late', (feed.timeline ?? []).some(e => e.overdue === true),
      JSON.stringify(feed.timeline).slice(0, 200));

    ok('the skill gap is scoped to the chosen path',
      Array.isArray(feed.skill_gap) && (feed.skill_fit?.total ?? 0) > 0,
      JSON.stringify(feed.skill_fit));
    ok('and the gap never lists a skill the student already has',
      Array.isArray(feed.skill_gap) &&
      feed.skill_gap.length === (feed.skill_fit.total - feed.skill_fit.have),
      `${feed.skill_gap?.length} listed vs ${feed.skill_fit?.total - feed.skill_fit?.have} missing`);

    console.log('\n5. a target is chosen, never assumed');
    /* The first path a student follows becomes their target, by trigger. A
       second one does not: following is not choosing, and the dashboard must
       not promote a browse into a decision. */
    const { rows: [second] } = await pg.query(
      `select id, title from public.career_paths where is_active and id <> $1
       order by sort_order limit 1`, [pathRow.id]);
    await pg.query(
      `insert into public.user_career_paths (user_id, path_id) values ($1, $2)`,
      [student.id, second.id]);

    const twoPaths = await feedFor(student.token).then(r => r.json());
    ok('the first path followed is the target',
      twoPaths.paths?.primary_title === pathRow.title,
      `${twoPaths.paths?.primary_title} vs ${pathRow.title}`);
    ok('the second is listed as followed, not as a target',
      (twoPaths.paths?.following ?? []).some(p => p.title === second.title),
      JSON.stringify(twoPaths.paths?.following));

    const chosen = await asUser(student.token, '/rest/v1/rpc/set_primary_path', {
      method: 'POST', body: JSON.stringify({ p_path_id: second.id }),
    });
    ok('a student can choose their own target', chosen.status < 300, `status ${chosen.status}`);

    const after = await feedFor(student.token).then(r => r.json());
    ok('choosing swaps the target over', after.paths?.primary_title === second.title,
      `${after.paths?.primary_title}`);
    ok('and leaves exactly one target',
      (await pg.query(`select count(*)::int n from public.user_career_paths
                        where user_id = $1 and deleted_at is null and is_primary`,
        [student.id])).rows[0].n === 1);

    console.log('\n6. it is only ever about the caller');
    other = await makeStudent('b');

    const theirs = await feedFor(other.token).then(r => r.json());
    ok('another student gets their own empty feed, not this one',
      theirs?.roadmap?.total === 0 && theirs?.documents?.has_cv === false,
      JSON.stringify(theirs?.roadmap));
    ok('and nothing of the first student appears in it',
      !JSON.stringify(theirs ?? {}).includes(student.id),
      'the other feed mentioned the first student\'s id');

    /* The important one. There is no argument to poison, but a future edit
       could add one — this fails loudly the day somebody does. */
    const injected = await asUser(other.token, '/rest/v1/rpc/dashboard_feed', {
      method: 'POST', body: JSON.stringify({ p_user_id: student.id, user_id: student.id })
    });
    ok('passing somebody else\'s id changes nothing',
      injected.status >= 400 ||
      (await injected.clone().json())?.roadmap?.total === 0,
      `status ${injected.status}`);

    console.log('\n7. one request, not nine');
    const t0 = Date.now();
    await feedFor(student.token);
    const ms = Date.now() - t0;
    ok(`the whole dashboard loads in one call (${ms}ms)`, ms < 3000, `${ms}ms`);
  } finally {
    await admin(`/auth/v1/admin/users/${student.id}`, { method: 'DELETE' });
    if (other) await admin(`/auth/v1/admin/users/${other.id}`, { method: 'DELETE' });

    const left = await pg.query(
      'select count(*)::int n from public.roadmaps where user_id = $1', [student.id]);
    ok('the throwaway account and everything under it are gone', left.rows[0].n === 0, `${left.rows[0].n} left`);
    await pg.end();

    console.log(`\n${pass} passed, ${fail} failed\n`);
    process.exit(fail === 0 ? 0 : 1);
  }
})().catch(e => { console.error('ERROR:', e.message); process.exit(1); });
