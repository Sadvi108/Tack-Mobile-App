#!/usr/bin/env node
/* Live verification of the assembled profile document.

   The CV builder and the public profile page both render this one function, so
   a gap here shows up twice — and the second time on a page a stranger is
   looking at. Checked as a real student over PostgREST, the way the app calls
   it.

   The interesting cases are the boring ones: a student who has filled in
   nothing must get an empty document rather than an error, and every key a
   renderer expects must be present whether or not there is anything in it.

     node tool/verify_cv_builder.js */
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
  const email = `cv_${label}_${Date.now()}@tack.test`;
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

const document = async (token) => {
  const res = await asUser(token, '/rest/v1/rpc/my_profile_document', {
    method: 'POST',
    body: '{}',
  });
  if (!res.ok) throw new Error(`${res.status} ${await res.text()}`);
  return res.json();
};

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
    // ---------------------------------------------------------------------
    console.log('\n1. a student who has filled in nothing');

    const blank = await makeStudent('blank');
    students.push(blank.id);
    const empty = await document(blank.token);

    const keys = ['identity', 'education', 'experiences', 'projects',
      'certifications', 'skills', 'activities', 'courses', 'links'];
    const missing = keys.filter((k) => !(k in empty));
    ok('every key a renderer expects is present', missing.length === 0,
      `missing ${missing.join(', ')}`);

    const notArrays = keys
      .filter((k) => k !== 'identity')
      .filter((k) => !Array.isArray(empty[k]));
    ok('the collections are empty arrays, never null', notArrays.length === 0,
      `not arrays: ${notArrays.join(', ')}`);

    // ---------------------------------------------------------------------
    console.log('\n2. a student with a real history');

    const student = await makeStudent('full');
    students.push(student.id);
    const { rows: [city] } = await pg.query(
      `select id, country_id from public.cities limit 1`);

    await pg.query(
      `update public.profiles
          set full_name = 'Rafiq Hossain', city_id = $2, country_id = $3,
              phone = '1711111111', dial_code = '+880',
              target_role = 'Backend developer', education_stage = 'bachelors'
        where id = $1`, [student.id, city.id, city.country_id]);

    await pg.query(
      `insert into public.education
         (user_id, university_name, degree, field_of_study, start_year,
          graduation_year, cgpa, cgpa_scale, is_current)
       values ($1, 'BUET', 'BSc', 'Computer Science', 2022, 2026, 3.6, 4.0, true)`,
      [student.id]);
    await pg.query(
      `insert into public.experiences
         (user_id, company_name, title, start_date, end_date, description)
       values ($1, 'Pathao', 'Backend intern', '2025-06-01', '2025-09-01', 'Built APIs'),
              ($1, 'bKash',  'Trainee',        '2024-06-01', '2024-08-01', 'Reports')`,
      [student.id]);
    await pg.query(
      `insert into public.projects (user_id, title, summary, repo_url, completed_on)
       values ($1, 'Bus tracker', 'Live bus times for Dhaka',
               'https://github.com/rafiq/bus-tracker', '2025-12-01')`,
      [student.id]);
    await pg.query(
      `insert into public.certifications (user_id, title, issuer, issued_on)
       values ($1, 'AWS Cloud Practitioner', 'Amazon', '2025-03-01')`,
      [student.id]);
    await pg.query(
      `insert into public.activities (user_id, category, title, organisation)
       values ($1, 'volunteering', 'Teaching maths', 'BRAC')`, [student.id]);

    const { rows: skills } = await pg.query(
      `select id from public.skills where is_active order by name limit 3`);
    await pg.query(
      `insert into public.user_skills (user_id, skill_id, proficiency, source)
       values ($1, $2, 2, 'self'), ($1, $3, 5, 'self'), ($1, $4, 3, 'self')`,
      [student.id, skills[0].id, skills[1].id, skills[2].id]);

    const doc = await document(student.token);

    ok('identity carries the name and where they are',
      doc.identity?.full_name === 'Rafiq Hossain' && doc.identity?.country,
      JSON.stringify(doc.identity));
    ok('education is there', doc.education?.length === 1,
      JSON.stringify(doc.education));
    ok('both jobs are there', doc.experiences?.length === 2);
    ok('the project keeps its repo url',
      doc.projects?.[0]?.repo_url?.includes('github.com'),
      JSON.stringify(doc.projects?.[0]));
    ok('the certification is there', doc.certifications?.length === 1);
    ok('the activity is there', doc.activities?.length === 1);

    // Ordering is part of the contract: a CV that opens with the weakest
    // skill sells the student short.
    ok('skills come back strongest first',
      doc.skills?.[0]?.proficiency === 5 &&
      doc.skills?.[doc.skills.length - 1]?.proficiency === 2,
      doc.skills?.map((s) => s.proficiency).join(','));

    // The most recent job first, because that is the order a CV is read in.
    ok('the newest job is first',
      doc.experiences?.[0]?.company === 'Pathao',
      doc.experiences?.map((e) => e.company).join(','));

    // ---------------------------------------------------------------------
    console.log('\n3. the phone number');

    // Present here on purpose — the CV prints it. The public page must not,
    // and that is tested separately in verify_public_profile.js. Asserting it
    // here records which side of the line this function sits on.
    ok('is in the document, for the CV renderer to print',
      doc.identity?.phone === '+880 1711111111',
      JSON.stringify(doc.identity?.phone));

    // ---------------------------------------------------------------------
    console.log('\n4. it is the caller`s own document');

    const other = await document(blank.token);
    ok('a second student gets their own, not the first one`s',
      other.identity?.full_name !== 'Rafiq Hossain' &&
      other.experiences.length === 0,
      JSON.stringify(other.identity));
  } finally {
    for (const id of students) {
      await admin(`/auth/v1/admin/users/${id}`, { method: 'DELETE' });
    }
    await pg.end();
  }

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail === 0 ? 0 : 1);
})().catch((e) => { console.error('ERROR:', e.message); process.exit(1); });
