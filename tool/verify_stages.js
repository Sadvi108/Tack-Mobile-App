#!/usr/bin/env node
/* A school student and a graduate must each get a score that reflects what
   they can actually control. Walks both through onboarding and checks the
   weights, the mode and the things that should and should not count. */
const path = require('path');
const { Client } = require('pg');
require('dotenv').config({ path: path.join(__dirname, '..', 'supabase', '.env'), quiet: true });

const URL = process.env.SUPABASE_URL, ANON = process.env.SUPABASE_ANON_KEY, SVC = process.env.SUPABASE_SERVICE_ROLE_KEY;
const admin = (p, o = {}) => fetch(`${URL}${p}`, { ...o, headers: { apikey: SVC, Authorization: `Bearer ${SVC}`, 'Content-Type': 'application/json', ...(o.headers || {}) } });

let pass = 0, fail = 0;
const ok = (n, c, e = '') => { c ? (pass++, console.log(`  PASS  ${n}`)) : (fail++, console.log(`  FAIL  ${n} ${e}`)); };

(async () => {
  const pg = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await pg.connect();

  const made = [];
  const create = async (tag) => {
    const u = await admin('/auth/v1/admin/users', {
      method: 'POST',
      body: JSON.stringify({ email: `stage_${tag}_${Date.now()}@tack.test`, password: 'Test-passw0rd!', email_confirm: true }),
    }).then((r) => r.json());
    made.push(u.id);
    return u.id;
  };

  const bd = (await pg.query(`select id from public.countries where iso2='BD'`)).rows[0].id;
  const dhaka = (await pg.query(`select id from public.cities where name='Dhaka'`)).rows[0].id;

  console.log('\n1. the stage decides the mode, not the year');
  const cases = [
    ['primary', null, null, 'school'],
    ['high_school', null, null, 'school'],
    ['graduated', null, null, 'graduate'],
    ['bachelors', 1, 4, 'explore'],
    ['bachelors', 2, 4, 'build'],
    ['bachelors', 3, 4, 'prove'],
    ['bachelors', 4, 4, 'launch'],
  ];
  const probe = await create('mode');
  for (const [stage, year, total, expected] of cases) {
    await pg.query(
      `update public.profiles set education_stage=$1, year_of_study=$2, years_total=$3 where id=$4`,
      [stage, year, total, probe]);
    const mode = (await pg.query('select mode::text m from public.profiles where id=$1', [probe])).rows[0].m;
    ok(`${stage}${year ? ` year ${year}/${total}` : ''} -> ${expected}`, mode === expected, mode);
  }

  console.log('\n2. a school student');
  const school = await create('school');
  await pg.query(
    `update public.profiles set full_name='Nusrat', country_id=$1, city_id=$2, phone='+8801712345678',
       education_stage='high_school', intended_field='Computer science', passion='Building small games'
     where id=$3`, [bd, dhaka, school]);
  await pg.query(
    `insert into public.education (user_id, stage, institution_name, class_level, current_grade, cgpa, cgpa_scale, is_current)
     values ($1,'high_school','Dhaka Residential Model College','Class 11','A+',4.9,5.0,true)`, [school]);
  for (const s of ['Physics', 'Mathematics', 'ICT']) {
    await pg.query(`insert into public.student_interests (user_id, kind, label) values ($1,'favourite_subject',$2)`, [school, s]);
  }
  for (const h of ['Chess', 'Robotics club']) {
    await pg.query(`insert into public.student_interests (user_id, kind, label) values ($1,'hobby',$2)`, [school, h]);
  }

  const schoolScore = (await pg.query('select * from public.recompute_readiness($1,$2)', [school, 'test'])).rows[0];
  ok('is scored in school mode', schoolScore.mode === 'school', schoolScore.mode);
  ok('has a score above zero', schoolScore.total > 0, `${schoolScore.total}`);

  const sc = schoolScore.components;
  ok('applications are worth nothing to them', sc.application_activity.max === 0, JSON.stringify(sc.application_activity));
  ok('CV quality is worth nothing to them', sc.cv_quality.max === 0, JSON.stringify(sc.cv_quality));
  ok('interview practice is worth nothing to them', sc.interview_practice.max === 0);
  ok('academic is their biggest component', sc.academic.max === 24, `${sc.academic.max}`);
  ok('their grades and subjects actually score', sc.academic.earned > 0, JSON.stringify(sc.academic));
  ok('their interests count as skills', sc.skills.earned > 0, JSON.stringify(sc.skills));
  console.log(`        school student scored ${schoolScore.total}`);

  console.log('\n3. a graduate');
  const grad = await create('grad');
  await pg.query(
    `update public.profiles set full_name='Tanvir', country_id=$1, city_id=$2, phone='+8801812345678',
       education_stage='graduated', target_role='Backend developer' where id=$3`, [bd, dhaka, grad]);
  await pg.query(
    `insert into public.education (user_id, stage, institution_name, degree, graduation_year, cgpa, cgpa_scale, is_current)
     values ($1,'graduated','BUET','BSc Computer Science',2026,3.6,4.0,false)`, [grad]);

  const gradScore = (await pg.query('select * from public.recompute_readiness($1,$2)', [grad, 'test'])).rows[0];
  ok('is scored in graduate mode', gradScore.mode === 'graduate', gradScore.mode);
  const gc = gradScore.components;
  ok('applications are their largest component', gc.application_activity.max === 16, `${gc.application_activity.max}`);
  ok('coursework barely counts any more', gc.academic.max === 4, `${gc.academic.max}`);
  ok('CV quality matters a lot', gc.cv_quality.max === 14, `${gc.cv_quality.max}`);
  console.log(`        graduate scored ${gradScore.total}`);

  console.log('\n4. every mode still adds up to a hundred');
  for (const mode of ['school', 'explore', 'build', 'prove', 'launch', 'graduate']) {
    const total = (await pg.query('select sum(weight)::int t from public.score_weights where mode=$1', [mode])).rows[0].t;
    ok(`${mode} weights total 100`, total === 100, `${total}`);
  }

  console.log('\n5. interests belong to their owner');
  const otherToken = await (async () => {
    const email = `stage_thief_${Date.now()}@tack.test`;
    const u = await admin('/auth/v1/admin/users', {
      method: 'POST', body: JSON.stringify({ email, password: 'Test-passw0rd!', email_confirm: true }),
    }).then((r) => r.json());
    made.push(u.id);
    const s = await fetch(`${URL}/auth/v1/token?grant_type=password`, {
      method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password: 'Test-passw0rd!' }),
    }).then((r) => r.json());
    return s.access_token;
  })();

  const seen = await fetch(`${URL}/rest/v1/student_interests?select=label`, {
    headers: { apikey: ANON, Authorization: `Bearer ${otherToken}` },
  }).then((r) => r.json());
  ok("another student sees none of them", Array.isArray(seen) && seen.length === 0, JSON.stringify(seen).slice(0, 80));

  for (const id of made) await admin(`/auth/v1/admin/users/${id}`, { method: 'DELETE' });
  await pg.end();
  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error('\nERROR:', e.message); process.exit(1); });
