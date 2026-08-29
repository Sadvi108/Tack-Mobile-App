#!/usr/bin/env node
/* Live verification of the roadmap, the way the app actually builds one.

   Everything here goes through PostgREST with a student's own token. The
   roadmap list query had been answering 400 for months without anyone seeing
   it, because the dashboard read the result as `.value ?? const []` and an
   error became an empty screen. A check that runs over the direct database
   connection would not have caught it either: that connection is the owner and
   bypasses row level security. */
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

// Exactly the select the app sends, nesting and all.
const SELECT = [
  'id, title, path_id',
  'career_paths(slug)',
  'roadmap_milestones(id, roadmap_id, order_index, title, description, unlock_text, typical_semester, state,',
  'roadmap_tasks(id, milestone_id, order_index, title, type, points, est_minutes, due_date, is_done, is_custom, shared_with_roadmaps))',
].join(', ').replace('state,, roadmap_tasks', 'state, roadmap_tasks');

(async () => {
  const pg = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await pg.connect();

  const email = `roadmap_${Date.now()}@tack.test`;
  const created = await admin('/auth/v1/admin/users', {
    method: 'POST',
    body: JSON.stringify({ email, password: 'Test-passw0rd!', email_confirm: true, user_metadata: { full_name: 'Roadmap Check' } })
  }).then(r => r.json());
  if (!created.id) throw new Error(`could not create user: ${JSON.stringify(created)}`);
  const uid = created.id;
  const token = (await fetch(`${URL}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: 'Test-passw0rd!' })
  }).then(r => r.json())).access_token;

  try {
    console.log('\n1. the template a roadmap is built from');
    const paths = await asUser(token, '/rest/v1/career_paths?select=id,slug,title&is_active=is.true&order=sort_order&limit=1').then(r => r.json());
    ok('a student can read the career paths', Array.isArray(paths) && paths.length === 1, JSON.stringify(paths).slice(0, 120));
    const pathId = paths[0].id;

    const templates = await asUser(token,
      `/rest/v1/career_path_milestones?select=id,order_index,title&path_id=eq.${pathId}&order=order_index`).then(r => r.json());
    ok('and the milestones behind one', Array.isArray(templates) && templates.length > 0, JSON.stringify(templates).slice(0, 120));

    const ids = templates.map(m => `"${m.id}"`).join(',');
    const tasks = await asUser(token,
      `/rest/v1/career_path_tasks?select=id,milestone_id,title&milestone_id=in.(${ids})`).then(r => r.json());
    ok('and the tasks behind those', Array.isArray(tasks) && tasks.length > 0, JSON.stringify(tasks).slice(0, 120));

    console.log('\n2. building the roadmap, as the app builds it');
    const roadmap = await asUser(token, '/rest/v1/roadmaps?select=id', {
      method: 'POST', headers: { Prefer: 'return=representation' },
      body: JSON.stringify({ user_id: uid, path_id: pathId, title: 'Check', origin: 'template' })
    }).then(r => r.json());
    ok('the roadmap row is created', Array.isArray(roadmap) && roadmap[0]?.id, JSON.stringify(roadmap).slice(0, 160));
    const roadmapId = roadmap[0].id;

    const milestoneRes = await asUser(token, '/rest/v1/roadmap_milestones?select=id,source_milestone_id', {
      method: 'POST', headers: { Prefer: 'return=representation' },
      body: JSON.stringify(templates.map(m => ({
        roadmap_id: roadmapId, user_id: uid, source_milestone_id: m.id,
        order_index: m.order_index, title: m.title,
        state: m.order_index === 0 ? 'active' : 'locked',
      })))
    });
    const milestones = await milestoneRes.json();
    ok('the milestones are copied onto it', milestoneRes.status === 201 && milestones.length === templates.length,
      `status ${milestoneRes.status} ${JSON.stringify(milestones).slice(0, 200)}`);

    if (milestoneRes.status === 201) {
      const byTemplate = Object.fromEntries(milestones.map(m => [m.source_milestone_id, m.id]));
      const taskRes = await asUser(token, '/rest/v1/roadmap_tasks', {
        method: 'POST',
        body: JSON.stringify(tasks.filter(t => byTemplate[t.milestone_id]).map(t => ({
          milestone_id: byTemplate[t.milestone_id], user_id: uid,
          title: t.title, shared_with_roadmaps: [roadmapId],
        })))
      });
      ok('and the tasks under the milestones', taskRes.status < 300,
        `status ${taskRes.status} ${(await taskRes.text()).slice(0, 200)}`);
    }

    console.log('\n3. reading it back the way the dashboard reads it');
    // The bug: roadmap_tasks is nested inside roadmap_milestones, so filtering
    // it as a top-level embed is rejected outright.
    const wrong = await asUser(token,
      `/rest/v1/roadmaps?select=${encodeURIComponent(SELECT)}&user_id=eq.${uid}&deleted_at=is.null&roadmap_tasks.deleted_at=is.null`);
    ok('the old top-level task filter is refused by PostgREST', wrong.status === 400, `status ${wrong.status}`);

    const right = await asUser(token,
      `/rest/v1/roadmaps?select=${encodeURIComponent(SELECT)}&user_id=eq.${uid}&deleted_at=is.null&roadmap_milestones.roadmap_tasks.deleted_at=is.null&order=created_at`);
    const list = await right.json();
    ok('the full nested path is accepted', right.status === 200, `status ${right.status} ${JSON.stringify(list).slice(0, 200)}`);
    ok('the roadmap comes back', Array.isArray(list) && list.length === 1, JSON.stringify(list).slice(0, 120));

    if (Array.isArray(list) && list[0]) {
      const ms = list[0].roadmap_milestones ?? [];
      ok('with its milestones', ms.length === templates.length, `${ms.length}`);
      const taskCount = ms.reduce((n, m) => n + (m.roadmap_tasks?.length ?? 0), 0);
      ok('and with steps under them, so the card is not "0 of 0"', taskCount > 0, `${taskCount} tasks`);
      ok('the first milestone is the active one',
        ms.find(m => m.order_index === 0)?.state === 'active',
        JSON.stringify(ms.map(m => [m.order_index, m.state])));
    }

    console.log('\n4. it stays the student\'s own');
    const other = await admin('/auth/v1/admin/users', {
      method: 'POST',
      body: JSON.stringify({ email: `roadmap_b_${Date.now()}@tack.test`, password: 'Test-passw0rd!', email_confirm: true })
    }).then(r => r.json());
    const otherToken = (await fetch(`${URL}/auth/v1/token?grant_type=password`, {
      method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: other.email, password: 'Test-passw0rd!' })
    }).then(r => r.json())).access_token;

    const theirs = await asUser(otherToken, `/rest/v1/roadmaps?select=id&id=eq.${roadmapId}`).then(r => r.json());
    ok('another student sees nothing of it', Array.isArray(theirs) && theirs.length === 0, JSON.stringify(theirs));
    await admin(`/auth/v1/admin/users/${other.id}`, { method: 'DELETE' });
  } finally {
    await admin(`/auth/v1/admin/users/${uid}`, { method: 'DELETE' });
    const left = await pg.query('select count(*)::int n from public.roadmaps where user_id = $1', [uid]);
    ok('the account and its roadmap are gone', left.rows[0].n === 0, `${left.rows[0].n}`);
    await pg.end();
  }

  console.log(`\n${pass} passed, ${fail} failed.`);
  process.exit(fail === 0 ? 0 : 1);
})().catch(e => { console.error('ERROR:', e.message); process.exit(1); });
