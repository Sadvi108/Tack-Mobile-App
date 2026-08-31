#!/usr/bin/env node
/* End-to-end database verification: signup trigger, ownership isolation,
   the application status machine, milestone advance, and the score engine.
   Creates two throwaway auth users and deletes them at the end. */
const path = require('path');
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
const asUser = (tok, p, opt = {}) => fetch(`${URL}${p}`, {
  ...opt, headers: { apikey: ANON, Authorization: `Bearer ${tok}`, 'Content-Type': 'application/json', ...(opt.headers || {}) }
});

(async () => {
  const pg = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await pg.connect();

  const stamp = Date.now();
  const users = [];
  for (const tag of ['a', 'b']) {
    const email = `verify_${tag}_${stamp}@tack.test`;
    const r = await admin('/auth/v1/admin/users', {
      method: 'POST',
      body: JSON.stringify({ email, password: 'Test-passw0rd!', email_confirm: true, user_metadata: { full_name: `Verify ${tag.toUpperCase()}` } })
    });
    const j = await r.json();
    if (!j.id) throw new Error(`could not create user: ${JSON.stringify(j)}`);
    const s = await fetch(`${URL}/auth/v1/token?grant_type=password`, {
      method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password: 'Test-passw0rd!' })
    }).then(x => x.json());
    users.push({ id: j.id, email, token: s.access_token });
  }
  const [A, B] = users;

  console.log('\n1. signup trigger');
  const prof = await pg.query('select id, full_name, mode, onboarding_step from public.profiles where id = any($1)', [[A.id, B.id]]);
  ok('profile row created for both users', prof.rows.length === 2, `got ${prof.rows.length}`);
  ok('full_name copied from user metadata', prof.rows.every(r => r.full_name?.startsWith('Verify')));
  ok('mode defaults to explore when year is unknown', prof.rows.every(r => r.mode === 'explore'));

  console.log('\n2. mode is derived, not settable');
  await pg.query('update public.profiles set year_of_study = 4, years_total = 4 where id = $1', [A.id]);
  const m = await pg.query('select mode from public.profiles where id = $1', [A.id]);
  ok('year 4 of 4 becomes launch mode', m.rows[0].mode === 'launch', m.rows[0].mode);
  await pg.query('update public.profiles set year_of_study = 2, years_total = 4 where id = $1', [B.id]);
  const m2 = await pg.query('select mode from public.profiles where id = $1', [B.id]);
  ok('year 2 of 4 becomes build mode', m2.rows[0].mode === 'build', m2.rows[0].mode);
  let generatedBlocked = false;
  try { await pg.query(`update public.profiles set mode = 'launch' where id = $1`, [B.id]); }
  catch { generatedBlocked = true; }
  ok('mode cannot be written directly', generatedBlocked);

  console.log('\n3. ownership isolation (RLS)');
  const projA = await asUser(A.token, '/rest/v1/projects', {
    method: 'POST', headers: { Prefer: 'return=representation' },
    body: JSON.stringify({ user_id: A.id, title: 'A private project' })
  }).then(r => r.json());
  ok('user A can insert their own project', Array.isArray(projA) && projA[0]?.id, JSON.stringify(projA).slice(0, 120));

  const seenByB = await asUser(B.token, '/rest/v1/projects?select=*').then(r => r.json());
  ok("user B cannot see user A's project", Array.isArray(seenByB) && seenByB.length === 0, JSON.stringify(seenByB).slice(0, 120));

  const forge = await asUser(B.token, '/rest/v1/projects', {
    method: 'POST', body: JSON.stringify({ user_id: A.id, title: 'forged' })
  });
  ok('user B cannot insert a row owned by user A', forge.status === 403 || forge.status === 401, `status ${forge.status}`);

  const directRead = await asUser(B.token, `/rest/v1/projects?id=eq.${projA[0]?.id}`).then(r => r.json());
  ok('direct id lookup of another user row returns nothing', Array.isArray(directRead) && directRead.length === 0);

  console.log('\n4. reference data is readable, not writable');
  const skills = await asUser(A.token, '/rest/v1/skills?select=slug&limit=3').then(r => r.json());
  ok('authenticated user can read the skill vocabulary', Array.isArray(skills) && skills.length === 3);
  const wSkill = await asUser(A.token, '/rest/v1/skills', { method: 'POST', body: JSON.stringify({ slug: 'hack', name: 'Hack' }) });
  ok('authenticated user cannot write reference skills', wSkill.status >= 400, `status ${wSkill.status}`);
  const anonRead = await fetch(`${URL}/rest/v1/skills?select=slug&limit=1`, { headers: { apikey: ANON } });
  ok('anon key reads nothing from public', anonRead.status >= 400 || (await anonRead.json()).length === 0, `status ${anonRead.status}`);

  console.log('\n5. roadmap generation and milestone advance');
  const pathId = (await pg.query(`select id from public.career_paths where slug = 'frontend-developer'`)).rows[0].id;
  const rm = await pg.query(
    `insert into public.roadmaps (user_id, path_id, title) values ($1,$2,'Frontend developer') returning id`, [A.id, pathId]);
  const roadmapId = rm.rows[0].id;
  await pg.query(`
    insert into public.roadmap_milestones (roadmap_id, user_id, source_milestone_id, order_index, title, description, unlock_text, typical_semester, state)
    select $1, $2, m.id, m.order_index, m.title, m.description, m.unlock_text, m.typical_semester,
           case when m.order_index = 0 then 'active' else 'locked' end::milestone_state
      from public.career_path_milestones m where m.path_id = $3`, [roadmapId, A.id, pathId]);
  await pg.query(`
    insert into public.roadmap_tasks (milestone_id, user_id, order_index, title, type, points, est_minutes, skill_id)
    select rm.id, $1, t.order_index, t.title, t.type, t.points, t.est_minutes, t.skill_id
      from public.roadmap_tasks_src_view rm_dummy_never limit 0`, [A.id]).catch(() => {});
  await pg.query(`
    insert into public.roadmap_tasks (milestone_id, user_id, order_index, title, type, points, est_minutes, skill_id)
    select rmm.id, $1, t.order_index, t.title, t.type, t.points, t.est_minutes, t.skill_id
      from public.roadmap_milestones rmm
      join public.career_path_tasks t on t.milestone_id = rmm.source_milestone_id
      where rmm.roadmap_id = $2`, [A.id, roadmapId]);

  const counts = await pg.query(
    `select (select count(*)::int from public.roadmap_milestones where roadmap_id=$1) ms,
            (select count(*)::int from public.roadmap_tasks where user_id=$2) ts`, [roadmapId, A.id]);
  ok('template copied into a personal roadmap', counts.rows[0].ms === 5 && counts.rows[0].ts === 29,
    `${counts.rows[0].ms} milestones, ${counts.rows[0].ts} tasks`);

  const first = (await pg.query(
    `select id from public.roadmap_milestones where roadmap_id=$1 and order_index=0`, [roadmapId])).rows[0].id;
  await pg.query(`update public.roadmap_tasks set is_done = true where milestone_id = $1`, [first]);
  const states = await pg.query(
    `select order_index, state from public.roadmap_milestones where roadmap_id=$1 order by order_index`, [roadmapId]);
  ok('finishing every task completes the milestone', states.rows[0].state === 'completed', states.rows[0].state);
  ok('the next milestone unlocks', states.rows[1].state === 'active', states.rows[1].state);
  ok('later milestones stay locked', states.rows[2].state === 'locked', states.rows[2].state);
  const stamped = await pg.query(`select count(*)::int n from public.roadmap_tasks where milestone_id=$1 and done_at is null`, [first]);
  ok('done_at stamped by the server', stamped.rows[0].n === 0);

  console.log('\n6. cross-parent forgery');
  const bRoadmap = (await pg.query(
    `insert into public.roadmaps (user_id, path_id, title) values ($1,$2,'B roadmap') returning id`, [B.id, pathId])).rows[0].id;
  const bMilestone = (await pg.query(
    `insert into public.roadmap_milestones (roadmap_id, user_id, order_index, title, state)
     values ($1,$2,0,'B milestone','active') returning id`, [bRoadmap, B.id])).rows[0].id;
  const forgeTask = await asUser(A.token, '/rest/v1/roadmap_tasks', {
    method: 'POST', body: JSON.stringify({ milestone_id: bMilestone, user_id: A.id, title: 'forged task' })
  });
  ok("user A cannot attach a task to user B's milestone", forgeTask.status >= 400, `status ${forgeTask.status}`);

  console.log('\n7. application status machine');
  const companyId = (await pg.query(`select public.upsert_company('bKash Ltd.') as id`)).rows[0].id;
  const companyId2 = (await pg.query(`select public.upsert_company('  bkash limited ') as id`)).rows[0].id;
  ok('company names normalise onto one row', companyId === companyId2);

  const jobId = (await pg.query(
    `insert into public.jobs (user_id, company_id, company_name, title) values ($1,$2,'bKash','Junior frontend developer') returning id`,
    [A.id, companyId])).rows[0].id;
  const appId = (await pg.query(
    `insert into public.job_applications (user_id, job_id, status) values ($1,$2,'saved') returning id`, [A.id, jobId])).rows[0].id;
  await pg.query(`update public.job_applications set status='applied' where id=$1`, [appId]);
  await pg.query(`update public.job_applications set status='interview' where id=$1`, [appId]);
  let badTransition = false;
  try { await pg.query(`update public.job_applications set status='saved' where id=$1`, [appId]); }
  catch { badTransition = true; }
  ok('interview cannot jump back to saved', badTransition);
  await pg.query(`update public.job_applications set status='rejected' where id=$1`, [appId]);
  const hist = await pg.query(
    `select from_status, to_status from public.application_status_history where application_id=$1 order by changed_at`, [appId]);
  ok('every status change is recorded', hist.rows.length === 4, `${hist.rows.length} entries`);
  ok('history records the transition pairs', hist.rows[3].from_status === 'interview' && hist.rows[3].to_status === 'rejected');
  const wHist = await asUser(A.token, '/rest/v1/application_status_history', {
    method: 'POST', body: JSON.stringify({ application_id: appId, user_id: A.id, to_status: 'offer' })
  });
  ok('client cannot forge status history', wHist.status >= 400, `status ${wHist.status}`);

  console.log('\n8. readiness score engine');
  const s1 = (await pg.query(`select * from public.recompute_readiness($1, 'verify')`, [A.id])).rows[0];
  ok('score computed and stored', s1 && s1.total >= 0 && s1.total <= 100, JSON.stringify(s1?.total));
  ok('score uses the launch weight table', s1.mode === 'launch', s1.mode);
  const comps = s1.components;
  ok('all eleven components present', Object.keys(comps).length === 11, `${Object.keys(comps).length}`);
  const weightSum = Object.values(comps).reduce((a, c) => a + c.max, 0);
  ok('weights sum to 100', weightSum === 100, `${weightSum}`);
  ok('roadmap progress reflects the finished milestone',
    comps.roadmap_progress.earned > 0, JSON.stringify(comps.roadmap_progress));
  ok('application activity scores above zero in launch mode',
    comps.application_activity.earned > 0, JSON.stringify(comps.application_activity));

  const before = s1.total;
  for (let i = 0; i < 3; i++) {
    await pg.query(`insert into public.projects (user_id, title) values ($1, $2)`, [A.id, `Project ${i}`]);
  }
  const s2 = (await pg.query(`select * from public.recompute_readiness($1, 'verify projects')`, [A.id])).rows[0];
  ok('adding three projects raises the score', s2.total > before, `${before} -> ${s2.total}`);
  ok('delta records the change', s2.delta === s2.total - before, `${s2.delta}`);
  const projectComp = s2.components.projects;
  ok('projects component maxes out at three', projectComp.earned === projectComp.max, JSON.stringify(projectComp));

  const explore = (await pg.query(`select * from public.recompute_readiness($1, 'verify')`, [B.id])).rows[0];
  ok('a build-mode student gets zero application weight',
    explore.components.application_activity.max === 0, JSON.stringify(explore.components.application_activity));

  console.log('\n9. quota');
  const q1 = (await pg.query(`select public.consume_quota($1,'ai_analysis',3) r`, [A.id])).rows[0].r;
  const q2 = (await pg.query(`select public.consume_quota($1,'ai_analysis',3) r`, [A.id])).rows[0].r;
  const q3 = (await pg.query(`select public.consume_quota($1,'ai_analysis',3) r`, [A.id])).rows[0].r;
  const q4 = (await pg.query(`select public.consume_quota($1,'ai_analysis',3) r`, [A.id])).rows[0].r;
  ok('quota counts down 2, 1, 0', q1 === 2 && q2 === 1 && q3 === 0, `${q1},${q2},${q3}`);
  ok('a fourth call is refused', q4 === -1, `${q4}`);
  const rem = (await pg.query(`select public.quota_remaining($1,'ai_analysis',3) r`, [A.id])).rows[0].r;
  ok('remaining reports zero, not negative', rem === 0, `${rem}`);

  console.log('\n10. queue claim');
  await pg.query(`insert into public.jobs_queue (user_id, type, payload, idempotency_key) values ($1,'test','{}','k-'||$2)`, [A.id, stamp]);
  const claimed = await pg.query(`select * from public.claim_jobs(10, 'verify-worker')`);
  ok('worker claims pending jobs', claimed.rows.length >= 1, `${claimed.rows.length}`);
  ok('claimed jobs move to running', claimed.rows.every(r => r.status === 'running'));
  const again = await pg.query(`select * from public.claim_jobs(10, 'verify-worker-2')`);
  ok('a second worker claims nothing already taken', again.rows.length === 0, `${again.rows.length}`);
  const dupe = await pg.query(
    `insert into public.jobs_queue (user_id, type, idempotency_key) values ($1,'test','k-'||$2)
     on conflict (idempotency_key) do nothing returning id`, [A.id, stamp]);
  ok('idempotency key blocks a duplicate job', dupe.rows.length === 0);

  console.log('\n11. document rules');
  const d1 = (await pg.query(
    `insert into public.documents (user_id, type, title, storage_path, status)
     values ($1,'cv','CV v1','users/'||$2::text||'/cv/'||gen_random_uuid(),'ready') returning id`, [A.id, A.id])).rows[0].id;
  const d2 = (await pg.query(
    `insert into public.documents (user_id, type, title, storage_path, status)
     values ($1,'cv','CV v2','users/'||$2::text||'/cv/'||gen_random_uuid(),'ready') returning id`, [A.id, A.id])).rows[0].id;
  await pg.query(`select public.set_default_cv($1)`, [d1]);
  await pg.query(`select public.set_default_cv($1)`, [d2]);
  const defs = await pg.query(
    `select count(*)::int n from public.documents where user_id=$1 and type='cv' and is_default and deleted_at is null`, [A.id]);
  ok('exactly one default CV survives', defs.rows[0].n === 1, `${defs.rows[0].n}`);
  await pg.query(`update public.documents set deleted_at = now() where id = $1`, [d2]);
  const purge = await pg.query(`select purge_after, is_default from public.documents where id=$1`, [d2]);
  ok('soft delete sets a 30-day purge date', purge.rows[0].purge_after !== null);
  ok('soft delete clears the default flag', purge.rows[0].is_default === false);

  console.log('\n12. two-path limit');
  const paths = (await pg.query(`select id from public.career_paths order by sort_order limit 3`)).rows;
  await pg.query(`insert into public.user_career_paths (user_id, path_id, is_primary) values ($1,$2,true)`, [B.id, paths[0].id]);
  await pg.query(`insert into public.user_career_paths (user_id, path_id) values ($1,$2)`, [B.id, paths[1].id]);
  let thirdBlocked = false;
  try { await pg.query(`insert into public.user_career_paths (user_id, path_id) values ($1,$2)`, [B.id, paths[2].id]); }
  catch { thirdBlocked = true; }
  ok('a third career path is refused', thirdBlocked);

  console.log('\n13. an application, created the way the app creates one');
  // Section 7 exercises the status machine over a direct connection, which
  // runs as the database owner and bypasses row level security. That is why it
  // passed for months while adding an application from the app failed every
  // time with 42501: the after-insert trigger writes the status timeline, and
  // as SECURITY INVOKER that write was refused by the policy meant to stop a
  // student forging their own history. This section goes through PostgREST
  // with the student's own token, which is the path that was broken.
  const userCompany = await asUser(A.token, '/rest/v1/rpc/upsert_company', {
    method: 'POST', body: JSON.stringify({ raw_name: 'bKash' })
  }).then(r => r.json());

  const userJob = await asUser(A.token, '/rest/v1/jobs?select=id', {
    method: 'POST',
    headers: { Prefer: 'return=representation' },
    body: JSON.stringify({
      user_id: A.id, company_id: userCompany, company_name: 'bKash',
      title: 'Backend intern'
    })
  }).then(r => r.json());
  ok('a student can add the job behind an application', Array.isArray(userJob) && userJob[0]?.id,
    JSON.stringify(userJob).slice(0, 140));

  const created = await asUser(A.token, '/rest/v1/job_applications?select=id', {
    method: 'POST',
    headers: { Prefer: 'return=representation' },
    body: JSON.stringify({ user_id: A.id, job_id: userJob[0].id, status: 'saved' })
  });
  const createdBody = await created.json();
  ok('a student can create an application', created.status === 201,
    `status ${created.status} ${JSON.stringify(createdBody).slice(0, 160)}`);

  if (created.status === 201) {
    const appId = createdBody[0].id;

    const moved = await asUser(A.token, `/rest/v1/job_applications?id=eq.${appId}`, {
      method: 'PATCH', body: JSON.stringify({ status: 'applied' })
    });
    ok('and move it along', moved.status < 300, `status ${moved.status}`);

    const timeline = await asUser(A.token,
      `/rest/v1/application_status_history?select=from_status,to_status&application_id=eq.${appId}&order=changed_at`
    ).then(r => r.json());
    ok('the timeline is written for them', timeline.length === 2, JSON.stringify(timeline));
    ok('starting at saved and ending at applied',
      timeline[0]?.to_status === 'saved' && timeline[1]?.to_status === 'applied',
      JSON.stringify(timeline));

    // The trigger writing history must not become a way to write it by hand.
    const forged = await asUser(A.token, '/rest/v1/application_status_history', {
      method: 'POST',
      body: JSON.stringify({ application_id: appId, user_id: A.id, to_status: 'offer' })
    });
    ok('a student still cannot forge their own history', forged.status >= 400,
      `status ${forged.status}`);

    const theirs = await asUser(B.token,
      `/rest/v1/job_applications?select=id&id=eq.${appId}`).then(r => r.json());
    ok('and cannot see someone else\'s application', Array.isArray(theirs) && theirs.length === 0,
      JSON.stringify(theirs));
  }

  // cleanup
  for (const u of users) await admin(`/auth/v1/admin/users/${u.id}`, { method: 'DELETE' });
  const left = await pg.query(`select count(*)::int n from public.profiles where id = any($1)`, [[A.id, B.id]]);
  ok('deleting the auth user cascades the profile away', left.rows[0].n === 0, `${left.rows[0].n}`);

  await pg.end();
  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error('\nERROR:', e.message); process.exit(1); });
