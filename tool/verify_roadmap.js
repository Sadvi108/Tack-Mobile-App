#!/usr/bin/env node
/* Live verification of the roadmap.

   Generation moved into Postgres, so this checks the function the way the app
   calls it — over PostgREST, with a real student's token — and then checks the
   things that used to be wrong: that a second career path does not cost score,
   that unfollowing gives it back, and that un-ticking a task re-locks the
   milestone it had unlocked. */
const path = require('path');
const { Client } = require('pg');
require('dotenv').config({ path: path.join(__dirname, '..', 'supabase', '.env'), quiet: true });

const URL = process.env.SUPABASE_URL;
const ANON = process.env.SUPABASE_ANON_KEY;
const SVC = process.env.SUPABASE_SERVICE_ROLE_KEY;
const PASSWORD = 'Test-passw0rd!';

let pass = 0, fail = 0;
const ok = (n, c, extra = '') => { c ? (pass++, console.log(`  PASS  ${n}`)) : (fail++, console.log(`  FAIL  ${n} ${extra}`)); };

const admin = (p, o = {}) => fetch(`${URL}${p}`, { ...o, headers: { apikey: SVC, Authorization: `Bearer ${SVC}`, 'Content-Type': 'application/json', ...(o.headers || {}) } });
const asUser = (t, p, o = {}) => fetch(`${URL}${p}`, { ...o, headers: { apikey: ANON, Authorization: `Bearer ${t}`, 'Content-Type': 'application/json', ...(o.headers || {}) } });

async function makeStudent(label) {
  const email = `roadmap_${label}_${Date.now()}@tack.test`;
  const u = await admin('/auth/v1/admin/users', {
    method: 'POST',
    body: JSON.stringify({ email, password: PASSWORD, email_confirm: true }),
  }).then(r => r.json());
  if (!u.id) throw new Error(`could not create user: ${JSON.stringify(u)}`);
  const token = (await fetch(`${URL}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: PASSWORD }),
  }).then(r => r.json())).access_token;
  return { id: u.id, token };
}

const ratio = async (pg, uid) => Number(
  (await pg.query(
    `select ratio from public.readiness_ratios($1) where component = 'roadmap_progress'`,
    [uid])).rows[0].ratio);

const states = async (pg, roadmapId) =>
  (await pg.query(
    `select order_index i, state::text s from public.roadmap_milestones
      where roadmap_id = $1 order by order_index`, [roadmapId])).rows
    .map(r => `${r.i}:${r.s}`).join(' ');

(async () => {
  const pg = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await pg.connect();

  const a = await makeStudent('a');
  const b = await makeStudent('b');

  try {
    const { rows: [front] } = await pg.query(
      `select id, title from public.career_paths where slug = 'frontend-developer'`);
    const { rows: [qa] } = await pg.query(
      `select id, title from public.career_paths where slug = 'qa-engineer'`);

    console.log('\n1. who may generate a roadmap');
    const anon = await fetch(`${URL}/rest/v1/rpc/generate_roadmap`, {
      method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_path_id: front.id }),
    });
    ok('the anon key alone cannot', anon.status >= 400, `status ${anon.status}`);

    console.log('\n2. it is shaped by what the student already has');
    // Student A knows HTML and CSS well; student B knows nothing.
    const { rows: known } = await pg.query(
      `select id, name from public.skills where slug in ('html','css')`);
    for (const s of known) {
      await pg.query(
        `insert into public.user_skills (user_id, skill_id, proficiency, source)
         values ($1,$2,4,'self') on conflict (user_id, skill_id) do update set proficiency = 4`,
        [a.id, s.id]);
    }
    await pg.query(
      `update public.profiles set expected_graduation = current_date + 240 where id = $1`, [a.id]);

    const genA = await asUser(a.token, '/rest/v1/rpc/generate_roadmap', {
      method: 'POST', body: JSON.stringify({ p_path_id: front.id }),
    });
    ok('a signed-in student can', genA.status === 200, `status ${genA.status}`);
    const roadmapA = await genA.json();

    const genB = await asUser(b.token, '/rest/v1/rpc/generate_roadmap', {
      method: 'POST', body: JSON.stringify({ p_path_id: front.id }),
    }).then(r => r.json());

    const count = async (rid) => (await pg.query(
      `select count(*)::int n from public.roadmap_tasks t
        join public.roadmap_milestones m on m.id = t.milestone_id
       where m.roadmap_id = $1 and t.deleted_at is null`, [rid])).rows[0].n;
    const nA = await count(roadmapA), nB = await count(genB);
    ok('a student with the skills gets a shorter roadmap', nA < nB, `${nA} vs ${nB}`);

    const { rows: [sk] } = await pg.query(
      `select skipped_count from public.roadmaps where id = $1`, [roadmapA]);
    ok('and is told how many steps were left out',
      sk.skipped_count === nB - nA, `skipped_count ${sk.skipped_count}, difference ${nB - nA}`);

    // The distinction the rule turns on: knowing a skill cancels a "learn it"
    // step, never a "build something with it" step.
    const { rows: [proj] } = await pg.query(
      `select count(*)::int n from public.roadmap_tasks t
         join public.roadmap_milestones m on m.id = t.milestone_id
        where m.roadmap_id = $1 and t.type = 'project'
          and t.skill_id in (select skill_id from public.user_skills
                              where user_id = $2 and proficiency >= 3)`, [roadmapA, a.id]);
    ok('a project step survives even when the skill is known', proj.n > 0, `${proj.n} kept`);

    console.log('\n3. dates come from their real graduation');
    const { rows: [d] } = await pg.query(
      `select count(*)::int total, count(due_date)::int dated,
              min(due_date) mn, max(due_date) mx
         from public.roadmap_tasks t join public.roadmap_milestones m on m.id = t.milestone_id
        where m.roadmap_id = $1 and t.deleted_at is null`, [roadmapA]);
    ok('every step has one', d.dated === d.total, `${d.dated}/${d.total}`);
    const { rows: [w] } = await pg.query(
      `select (select expected_graduation from public.profiles where id = $1) grad,
              current_date today`, [a.id]);
    ok('and they all land between today and graduation',
      new Date(d.mn) >= new Date(w.today) && new Date(d.mx) <= new Date(w.grad),
      `${d.mn} .. ${d.mx} vs graduation ${w.grad}`);

    // Student B has no graduation date, so inventing one would be a deadline
    // they would miss for no reason.
    const { rows: [nb] } = await pg.query(
      `select count(due_date)::int dated from public.roadmap_tasks t
         join public.roadmap_milestones m on m.id = t.milestone_id where m.roadmap_id = $1`, [genB]);
    ok('a student with no graduation date gets no invented deadlines',
      nb.dated === 0, `${nb.dated} dated`);

    console.log('\n4. exactly one milestone is open');
    const s0 = await states(pg, roadmapA);
    ok('at generation', (s0.match(/active/g) || []).length === 1, s0);

    console.log('\n5. un-ticking re-locks what it unlocked');
    const { rows: firstTasks } = await pg.query(
      `select t.id from public.roadmap_tasks t join public.roadmap_milestones m on m.id = t.milestone_id
        where m.roadmap_id = $1 and m.order_index = 0 and t.deleted_at is null`, [roadmapA]);
    for (const t of firstTasks) {
      await pg.query('update public.roadmap_tasks set is_done = true where id = $1', [t.id]);
    }
    const s1 = await states(pg, roadmapA);
    ok('completing the first opens the second', s1.startsWith('0:completed 1:active'), s1);

    await pg.query('update public.roadmap_tasks set is_done = false where id = $1', [firstTasks[0].id]);
    const s2 = await states(pg, roadmapA);
    ok('un-ticking one re-locks the second', s2.startsWith('0:active 1:locked'), s2);
    ok('and never leaves two open at once',
      (s2.match(/active/g) || []).length === 1, s2);

    console.log('\n6. a second path must not cost readiness points');
    for (const t of firstTasks) {
      await pg.query('update public.roadmap_tasks set is_done = true where id = $1', [t.id]);
    }
    await pg.query(
      `insert into public.user_career_paths (user_id, path_id, is_primary) values ($1,$2,true)
       on conflict (user_id, path_id) do update set deleted_at = null`, [a.id, front.id]);
    const before = await ratio(pg, a.id);
    ok('the student has real progress to protect', before > 0, `${before}`);

    await pg.query(
      `insert into public.user_career_paths (user_id, path_id, is_primary) values ($1,$2,false)
       on conflict (user_id, path_id) do update set deleted_at = null`, [a.id, qa.id]);
    await asUser(a.token, '/rest/v1/rpc/generate_roadmap', {
      method: 'POST', body: JSON.stringify({ p_path_id: qa.id }),
    });
    const after = await ratio(pg, a.id);
    ok('following a second path did not lower it', after >= before, `${before} -> ${after}`);

    console.log('\n7. unfollowing retires the roadmap it made');
    await pg.query(
      `update public.user_career_paths set deleted_at = now() where user_id = $1 and path_id = $2`,
      [a.id, qa.id]);
    const { rows: [retired] } = await pg.query(
      `select count(*)::int n from public.roadmaps
        where user_id = $1 and path_id = $2 and deleted_at is not null`, [a.id, qa.id]);
    ok('its roadmap was retired automatically', retired.n === 1, `${retired.n}`);
    const back = await ratio(pg, a.id);
    ok('and the score returned to where it was',
      Math.abs(back - before) < 1e-9, `${before} -> ${back}`);

    console.log('\n8. a half-built roadmap cannot be handed back forever');
    // The wreckage the old four-round-trip generator left: a roadmaps row with
    // nothing underneath it, cached by the idempotency guard.
    const { rows: [shell] } = await pg.query(
      `insert into public.roadmaps (user_id, path_id, title, origin)
       values ($1,$2,'Broken','template') returning id`, [b.id, qa.id]);
    const regen = await asUser(b.token, '/rest/v1/rpc/generate_roadmap', {
      method: 'POST', body: JSON.stringify({ p_path_id: qa.id }),
    }).then(r => r.json());
    ok('an empty roadmap is replaced, not returned', regen !== shell.id, `${regen} vs ${shell.id}`);
    ok('and the replacement actually has milestones',
      (await pg.query(`select count(*)::int n from public.roadmap_milestones where roadmap_id = $1`,
        [regen])).rows[0].n > 0);
  } finally {
    await admin(`/auth/v1/admin/users/${a.id}`, { method: 'DELETE' });
    await admin(`/auth/v1/admin/users/${b.id}`, { method: 'DELETE' });
    const { rows: [left] } = await pg.query(
      'select count(*)::int n from public.roadmaps where user_id in ($1,$2)', [a.id, b.id]);
    ok('the throwaway accounts and their roadmaps are gone', left.n === 0, `${left.n} left`);
    await pg.end();
    console.log(`\n${pass} passed, ${fail} failed\n`);
    process.exit(fail === 0 ? 0 : 1);
  }
})().catch(e => { console.error('ERROR:', e.message); process.exit(1); });
