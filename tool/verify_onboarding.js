#!/usr/bin/env node
/* Live verification of the school-student path through onboarding.

   Two defects lived here undetected because nothing exercised this branch end
   to end: `intended_field_slug` is a multiChip, so the answers carry an array,
   and write_onboarding read it with `->>` — which on an array yields the
   literal text `["engineering"]` and matches no slug. Separately,
   profiles.intended_field was read from a key the flow never sends, and
   readiness_ratios awards a completeness point for it *only* to school
   students. So every one of them lost a point for a field they could not see
   and had no way to fill in.

   This drives the real function over PostgREST with a real token, the way the
   app does, and asserts on the rows that come out.

     node tool/verify_onboarding.js */
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
  const email = `onboarding_${label}_${Date.now()}@tack.test`;
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

  const { rows: [country] } = await pg.query(
    `select id from public.countries where iso2 = 'BD' limit 1`);
  const { rows: [city] } = await pg.query(
    `select id from public.cities where country_id = $1 order by name limit 1`, [country.id]);
  const { rows: [field] } = await pg.query(
    `select id, slug, name from public.career_fields where is_active order by sort_order limit 1`);

  const students = [];
  try {
    // ---------------------------------------------------------------------
    console.log('\n1. a school student, answering the way the app answers');

    const student = await makeStudent('school');
    students.push(student.id);

    // The multiChip sends an array. That is the whole bug.
    const answers = {
      stage: 'high_school',
      full_name: 'Tahmid Rahman',
      country_id: country.id,
      city_id: city.id,
      phone: '1711111111',
      dial_code: '+880',
      institution_name: 'Dhaka College',
      start_year: 2024,
      current_class: 'Class 11',
      curriculum: 'national',
      intended_field_slug: [field.slug],
      field_confidence: 'unsure',
      ten_year_note: 'Building things people use.',
    };

    const res = await asUser(student.token, '/rest/v1/rpc/submit_onboarding', {
      method: 'POST',
      body: JSON.stringify({ p_answers: answers }),
    });
    ok('submit_onboarding accepts the real answer shape', res.ok,
      `${res.status} ${await res.clone().text()}`);

    const { rows: [profile] } = await pg.query(
      `select intended_field, education_stage::text stage from public.profiles where id = $1`,
      [student.id]);
    ok('profiles.intended_field is written, not left null',
      profile.intended_field === field.name,
      `expected ${JSON.stringify(field.name)}, got ${JSON.stringify(profile.intended_field)}`);

    const { rows: [hs] } = await pg.query(
      `select intended_field_id from public.high_school_profiles where user_id = $1`,
      [student.id]);
    ok('high_school_profiles.intended_field_id resolves from the array',
      hs && hs.intended_field_id === field.id,
      `expected ${field.id}, got ${hs && hs.intended_field_id}`);

    // ---------------------------------------------------------------------
    console.log('\n2. and the score stops docking them for it');

    const { rows: ratios } = await pg.query(
      `select component, ratio from public.readiness_ratios($1)
        where component = 'profile_completeness'`, [student.id]);
    ok('readiness reports profile_completeness at all', ratios.length === 1,
      `got components: ${ratios.map((r) => r.component).join(', ') || 'none'}`);

    // Eight parts make up profile_completeness (0059:138), and this student
    // answered all eight. Asserted as exactly 1, not ">= 7/8": with the bug in
    // place they scored precisely 7/8, so the looser test would have passed
    // against the very defect it exists to catch.
    const filled = Number(ratios[0]?.ratio ?? 0);
    ok('a fully answered school profile scores all eight parts', filled === 1,
      `profile_completeness = ${filled}; 0.875 means intended_field is null again`);

    // ---------------------------------------------------------------------
    console.log('\n3. an older draft that saved a bare string still works');

    const legacy = await makeStudent('legacy');
    students.push(legacy.id);
    const older = { ...answers, intended_field_slug: field.slug };
    const res2 = await asUser(legacy.token, '/rest/v1/rpc/submit_onboarding', {
      method: 'POST',
      body: JSON.stringify({ p_answers: older }),
    });
    ok('the string shape is accepted too', res2.ok, `${res2.status}`);

    const { rows: [legacyProfile] } = await pg.query(
      `select intended_field from public.profiles where id = $1`, [legacy.id]);
    ok('and resolves to the same field', legacyProfile.intended_field === field.name,
      `got ${JSON.stringify(legacyProfile.intended_field)}`);

    // ---------------------------------------------------------------------
    console.log('\n4. a student who says nothing is not made to');

    const unsure = await makeStudent('unsure');
    students.push(unsure.id);
    const blank = { ...answers };
    delete blank.intended_field_slug;
    const res3 = await asUser(unsure.token, '/rest/v1/rpc/submit_onboarding', {
      method: 'POST',
      body: JSON.stringify({ p_answers: blank }),
    });
    ok('onboarding finishes without a chosen field', res3.ok, `${res3.status}`);

    const { rows: [none] } = await pg.query(
      `select intended_field from public.profiles where id = $1`, [unsure.id]);
    ok('and the field stays null rather than being invented',
      none.intended_field === null, `got ${JSON.stringify(none.intended_field)}`);
  } finally {
    for (const id of students) {
      await admin(`/auth/v1/admin/users/${id}`, { method: 'DELETE' });
    }
    const { rows: [left] } = await pg.query(
      `select count(*)::int n from public.profiles where id = any($1)`, [students]);
    ok('the throwaway accounts are gone', left.n === 0, `${left.n} left`);
    await pg.end();
  }

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail === 0 ? 0 : 1);
})().catch((e) => { console.error('ERROR:', e.message); process.exit(1); });
