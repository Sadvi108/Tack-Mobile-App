#!/usr/bin/env node
/* The submit path is the one moment a draft becomes real data. It has to be
   atomic and idempotent: double-tapping Finish is not a rare edge case on a
   slow connection, it is the normal thing an impatient student does. */
const path = require('path');
const { Client } = require('pg');
require('dotenv').config({ path: path.join(__dirname, '..', 'supabase', '.env'), quiet: true });

const URL = process.env.SUPABASE_URL, ANON = process.env.SUPABASE_ANON_KEY, SVC = process.env.SUPABASE_SERVICE_ROLE_KEY;
const admin = (p, o = {}) => fetch(`${URL}${p}`, { ...o, headers: { apikey: SVC, Authorization: `Bearer ${SVC}`, 'Content-Type': 'application/json', ...(o.headers || {}) } });
const rpc = (token, fn, params) => fetch(`${URL}/rest/v1/rpc/${fn}`, {
  method: 'POST',
  headers: { apikey: ANON, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify(params),
});

let pass = 0, fail = 0;
const ok = (n, c, e = '') => { c ? (pass++, console.log(`  PASS  ${n}`)) : (fail++, console.log(`  FAIL  ${n} ${e}`)); };

(async () => {
  const pg = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await pg.connect();

  const made = [];
  const create = async (tag) => {
    const email = `submit_${tag}_${Date.now()}@tack.test`;
    const u = await admin('/auth/v1/admin/users', {
      method: 'POST', body: JSON.stringify({ email, password: 'Test-passw0rd!', email_confirm: true }),
    }).then((r) => r.json());
    made.push(u.id);
    const s = await fetch(`${URL}/auth/v1/token?grant_type=password`, {
      method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password: 'Test-passw0rd!' }),
    }).then((r) => r.json());
    return { id: u.id, token: s.access_token };
  };

  const bd = (await pg.query(`select id from public.countries where iso2='BD'`)).rows[0].id;
  const dhaka = (await pg.query(`select id from public.cities where name='Dhaka'`)).rows[0].id;
  const skills = (await pg.query('select id from public.skills limit 4')).rows.map((r) => r.id);

  // ---------------------------------------------------------- high school
  console.log('\n1. a high school student finishes');
  const hs = await create('hs');
  const hsAnswers = {
    full_name: 'Nusrat Jahan', country_id: bd, city_id: dhaka,
    phone: '1712345678', dial_code: '+880', birth_year: 2009, age_band: '16_18',
    stage: 'high_school',
    institution_name: 'Viqarunnisa Noon College', current_class: 'Class 11',
    curriculum: 'national', expected_end_year: 2027, gpa: 4.83, gpa_scale: 5,
    favourite_subjects: ['physics', 'higher-mathematics', 'information-and-communication-technology'],
    hard_subjects: ['bangla-first-paper'],
    interests: ['chess', 'programming'],
    custom_interests: ['Building small games'],
    intended_field_slug: 'computer-science', field_confidence: 'leaning',
    career_values: ['creativity', 'independence', 'money'],
    ten_year_note: 'Making games people in Bangladesh actually play.',
  };

  const first = await rpc(hs.token, 'submit_onboarding', { p_answers: hsAnswers });
  ok('submit succeeds', first.status < 400, `status ${first.status} ${(await first.clone().text()).slice(0, 160)}`);

  const profile = (await pg.query(
    `select education_stage::text stage, mode::text, birth_year, age_band::text,
            onboarding_completed_at is not null as done
       from public.profiles where id=$1`, [hs.id])).rows[0];
  ok('the stage is stored', profile.stage === 'high_school');
  ok('the mode is derived as discover', profile.mode === 'discover', profile.mode);
  ok('onboarding is marked complete', profile.done);

  const hsProfile = (await pg.query(
    `select current_class, curriculum::text, field_confidence::text,
            intended_field_id is not null as has_field
       from public.high_school_profiles where user_id=$1`, [hs.id])).rows[0];
  ok('the school detail landed in its own table', hsProfile?.current_class === 'Class 11');
  ok('the curriculum is typed, not free text', hsProfile.curriculum === 'national');
  ok('"leaning" is kept as a real answer', hsProfile.field_confidence === 'leaning');
  ok('the intended field resolved to a real career field', hsProfile.has_field);

  const subjects = (await pg.query(
    `select sentiment::text, count(*)::int n from public.user_subjects
      where user_id=$1 group by 1 order by 1`, [hs.id])).rows;
  ok('subjects they find hard are kept, not just the ones they love',
    subjects.length === 2, JSON.stringify(subjects));
  ok('three favourite subjects stored',
    subjects.find((s) => s.sentiment === 'loves')?.n === 3, JSON.stringify(subjects));

  const interests = (await pg.query(
    `select source::text, count(*)::int n from public.user_interests
      where user_id=$1 group by 1 order by 1`, [hs.id])).rows;
  ok('a typed-in interest is kept alongside the preset ones',
    interests.length === 2, JSON.stringify(interests));

  const prefs = (await pg.query(
    'select values_ranked, ten_year_note from public.career_preferences where user_id=$1',
    [hs.id])).rows[0];
  ok('what they said matters to them is stored in order',
    prefs.values_ranked[0] === 'creativity', JSON.stringify(prefs.values_ranked));
  ok('their ten-year note is kept', (prefs.ten_year_note ?? '').includes('games'));

  ok('no university row was created for a school student',
    (await pg.query('select count(*)::int n from public.university_profiles where user_id=$1', [hs.id])).rows[0].n === 0);

  console.log('\n2. submitting twice duplicates nothing');
  const counts = async (id) => (await pg.query(`
    select
      (select count(*)::int from public.education_profiles where user_id=$1) education,
      (select count(*)::int from public.high_school_profiles where user_id=$1) hs,
      (select count(*)::int from public.career_preferences where user_id=$1) prefs,
      (select count(*)::int from public.user_subjects where user_id=$1) subjects,
      (select count(*)::int from public.user_interests where user_id=$1) interests
  `, [id])).rows[0];

  const before = await counts(hs.id);
  const again = await rpc(hs.token, 'submit_onboarding', { p_answers: hsAnswers });
  ok('a second submit is accepted', again.status < 400, `status ${again.status}`);
  const after = await counts(hs.id);
  ok('every table has exactly the same number of rows',
    JSON.stringify(before) === JSON.stringify(after),
    `${JSON.stringify(before)} vs ${JSON.stringify(after)}`);

  // ------------------------------------------------------------ bachelor's
  console.log('\n3. a bachelor\'s student, final year');
  const uni = await create('uni');
  const uniSubmit = await rpc(uni.token, 'submit_onboarding', {
    p_answers: {
      full_name: 'Rafiq Hossain', country_id: bd, city_id: dhaka,
      birth_year: 2003, age_band: '19_22', stage: 'bachelors',
      institution_name: 'BUET', degree: 'BSc', major: 'Computer Science',
      year_of_study: 4, years_total: 4, graduation_month: 6, graduation_year: 2027,
      gpa: 3.6, gpa_scale: 4,
      courses: [
        { code: 'CSE routines', title: 'Data structures', credits: 3, semester: 'Spring 2026' },
        { code: 'CSE 202', title: 'Databases', credits: 3, semester: 'Spring 2026' },
      ],
      skills, target_role: 'Backend developer', target_industry: ['Software and IT'],
      activities: ['club', 'competition'],
      experiences: [{ organisation: 'bKash', role: 'Intern', type: 'internship' }],
    },
  });
  ok('submit succeeds', uniSubmit.status < 400, `status ${uniSubmit.status} ${(await uniSubmit.clone().text()).slice(0, 200)}`);

  const uniProfile = (await pg.query(
    `select mode::text, education_stage::text from public.profiles where id=$1`, [uni.id])).rows[0];
  ok('year 4 of 4 is launch mode', uniProfile.mode === 'launch', uniProfile.mode);

  const uniDetail = (await pg.query(
    'select year_of_study, graduation_year from public.university_profiles where user_id=$1',
    [uni.id])).rows[0];
  ok('the year of study is stored where the app reads it', uniDetail.year_of_study === 4);
  ok('two courses landed', (await pg.query('select count(*)::int n from public.courses where user_id=$1', [uni.id])).rows[0].n === 2);
  ok('the internship landed', (await pg.query('select count(*)::int n from public.experiences where user_id=$1', [uni.id])).rows[0].n === 1);
  ok('activities landed', (await pg.query('select count(*)::int n from public.activities where user_id=$1', [uni.id])).rows[0].n === 2);
  ok('no school row was created', (await pg.query('select count(*)::int n from public.high_school_profiles where user_id=$1', [uni.id])).rows[0].n === 0);

  console.log('\n4. a student cannot submit as someone else');
  const cross = await rpc(uni.token, 'write_onboarding', { p_answers: { stage: 'bachelors' } });
  const hsStillSchool = (await pg.query('select education_stage::text s from public.profiles where id=$1', [hs.id])).rows[0].s;
  ok("another student's stage is untouched", hsStillSchool === 'high_school', hsStillSchool);

  console.log('\n5. primary never becomes a profile');
  const primary = await create('primary');
  const refused = await rpc(primary.token, 'submit_onboarding', { p_answers: { stage: 'primary' } });
  ok('submitting as primary is refused', refused.status >= 400, `status ${refused.status}`);
  ok('and no education profile exists',
    (await pg.query('select count(*)::int n from public.education_profiles where user_id=$1', [primary.id])).rows[0].n === 0);

  for (const id of made) await admin(`/auth/v1/admin/users/${id}`, { method: 'DELETE' });
  await pg.end();
  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error('\nERROR:', e.message); process.exit(1); });
