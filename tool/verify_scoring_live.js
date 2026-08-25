#!/usr/bin/env node
/* Proves a real signup produces a real readiness score with no Edge Function
   deployed: create a user, act like a student, let the cron drain, check the
   number moved. Cleans up after itself, storage included. */
const path = require('path');
const { Client } = require('pg');
require('dotenv').config({ path: path.join(__dirname, '..', 'supabase', '.env'), quiet: true });

const URL = process.env.SUPABASE_URL;
const SVC = process.env.SUPABASE_SERVICE_ROLE_KEY;
const admin = (p, opt = {}) => fetch(`${URL}${p}`, {
  ...opt, headers: { apikey: SVC, Authorization: `Bearer ${SVC}`, 'Content-Type': 'application/json', ...(opt.headers || {}) },
});

let pass = 0, fail = 0;
const ok = (n, c, extra = '') => { c ? (pass++, console.log(`  PASS  ${n}`)) : (fail++, console.log(`  FAIL  ${n} ${extra}`)); };

(async () => {
  const pg = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await pg.connect();

  const email = `scoring_${Date.now()}@tack.test`;
  const created = await admin('/auth/v1/admin/users', {
    method: 'POST',
    body: JSON.stringify({ email, password: 'Test-passw0rd!', email_confirm: true, user_metadata: { full_name: 'Rafiq Hossain' } }),
  }).then((r) => r.json());
  const uid = created.id;

  console.log('\n1. signing up');
  const profile = (await pg.query('select id, mode, onboarding_step from public.profiles where id = $1', [uid])).rows[0];
  ok('a profile row appears without the app asking for one', !!profile);
  ok('the student starts in explore mode', profile.mode === 'explore', profile?.mode);

  console.log('\n2. finishing onboarding');
  await pg.query(
    `update public.profiles set full_name='Rafiq Hossain', year_of_study=4, years_total=4,
       expected_graduation='2027-07-01', target_role='Frontend developer',
       onboarding_completed_at=now() where id=$1`, [uid]);
  const mode = (await pg.query('select mode from public.profiles where id=$1', [uid])).rows[0].mode;
  ok('year four of four becomes launch mode', mode === 'launch', mode);

  console.log('\n3. the recompute was queued by a trigger, not by the app');
  const queued = (await pg.query(
    `select count(*)::int n from public.jobs_queue where user_id=$1 and type='recompute_readiness'`, [uid])).rows[0].n;
  ok('a recompute job is waiting', queued > 0, `${queued}`);

  console.log('\n4. Postgres drains it with no Edge Function deployed');
  await pg.query(`update public.jobs_queue set run_after = now() where user_id=$1 and status='pending'`, [uid]);
  const drained = (await pg.query('select public.drain_local_jobs() n')).rows[0].n;
  ok('the drain ran and did work', drained >= 1, `${drained}`);

  const score = (await pg.query(
    'select total, mode, components from public.readiness_scores where user_id=$1 order by computed_at desc limit 1', [uid])).rows[0];
  ok('a real score snapshot exists', !!score);
  ok('it used the launch weights', score.mode === 'launch', score?.mode);
  ok('all eleven components are present', Object.keys(score.components).length === 11);
  const first = score.total;
  console.log(`        score after onboarding: ${first}`);

  console.log('\n5. doing something raises it');
  const skills = (await pg.query('select id from public.skills limit 8')).rows;
  for (const s of skills) {
    await pg.query(`insert into public.user_skills (user_id, skill_id, proficiency) values ($1,$2,3)`, [uid, s.id]);
  }
  await pg.query(`update public.jobs_queue set run_after = now() where user_id=$1 and status='pending'`, [uid]);
  await pg.query('select public.drain_local_jobs()');

  const after = (await pg.query(
    'select total, delta from public.readiness_scores where user_id=$1 order by computed_at desc limit 1', [uid])).rows[0];
  ok('adding eight skills raised the score', after.total > first, `${first} -> ${after.total}`);
  ok('the change is recorded as a delta the app can show', after.delta === after.total - first, `${after.delta}`);
  console.log(`        score after adding skills: ${after.total} (+${after.delta})`);

  console.log('\n6. cleaning up, storage included');
  const objects = (await pg.query(`select name from storage.objects where name like 'users/' || $1 || '%'`, [uid])).rows;
  for (const o of objects) {
    await admin(`/storage/v1/object/documents/${o.name}`, { method: 'DELETE' });
  }
  await admin(`/auth/v1/admin/users/${uid}`, { method: 'DELETE' });
  const left = (await pg.query('select count(*)::int n from public.profiles where id=$1', [uid])).rows[0].n;
  ok('the account and everything under it is gone', left === 0);

  await pg.end();
  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error('\nERROR:', e.message); process.exit(1); });
