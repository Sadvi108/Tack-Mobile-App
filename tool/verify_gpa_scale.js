#!/usr/bin/env node
/* A result can never be higher than the scale it is out of (0089).
   A CGPA of 9.9 went through onboarding and was stored against a scale of 4,
   and school results — out of 5, with 4.83 as the field's own example — were
   stored against 4 as well. Everything here runs inside one transaction that
   is rolled back: no account is created and nothing is left behind. */
const path = require('path');
const { Client } = require('pg');
require('dotenv').config({ path: path.join(__dirname, '..', 'supabase', '.env'), quiet: true });
let pass = 0, fail = 0;
const ok = (n, c, extra = '') => { c ? (pass++, console.log(`  PASS  ${n}`)) : (fail++, console.log(`  FAIL  ${n} ${extra}`)); };

(async () => {
  const pg = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await pg.connect();
  const one = async (sql, args) => (await pg.query(sql, args)).rows[0];
  // Runs a statement under a savepoint and reports the SQLSTATE it failed
  // with, or null when it succeeded, without ending the transaction.
  const attempt = async (sql, args) => {
    await pg.query('savepoint try');
    try { await pg.query(sql, args); await pg.query('release savepoint try'); return null; }
    catch (e) { await pg.query('rollback to savepoint try'); return e.code; }
  };

  try {
    await pg.query('begin');

    console.log('\n1. which scale a result is out of');
    const scale = async (stage, given) =>
      Number((await one(`select public.gpa_scale_for($1::education_stage, $2::numeric) as s`, [stage, given])).s);
    ok('a school result is out of 5', await scale('high_school', null) === 5);
    ok('a university CGPA is out of 4', await scale('bachelors', null) === 4);
    ok('a graduate CGPA is out of 4', await scale('graduated', null) === 4);
    ok('a scale the student gave wins', await scale('high_school', 4) === 4);

    console.log('\n2. the table will not hold a result above its scale');
    const row = await one(`select user_id from public.education_profiles limit 1`);
    ok('there is a row to try it on', !!row);
    ok('9.9 out of 4 is refused',
      await attempt(`update public.education_profiles set gpa = 9.9, gpa_scale = 4 where user_id = $1`, [row.user_id]) === '23514');
    ok('4 out of 4 is fine',
      await attempt(`update public.education_profiles set gpa = 4, gpa_scale = 4 where user_id = $1`, [row.user_id]) === null);
    ok('no result is stored above its scale',
      Number((await one(`select count(*) n from public.education_profiles where gpa > gpa_scale`)).n) === 0);

    console.log('\n3. onboarding itself, as a student who finished it');
    const draft = await one(
      `select user_id, answers from public.onboarding_drafts
        where completed_at is not null and branch = 'bachelors'
        order by completed_at desc limit 1`);
    ok('a finished university draft exists', !!draft);
    await pg.query(`set local role authenticated`);
    await pg.query(`select set_config('request.jwt.claims', $1, true)`,
      [JSON.stringify({ sub: draft.user_id, role: 'authenticated' })]);
    const submit = gpa => attempt(`select public.write_onboarding($1::jsonb)`,
      [JSON.stringify({ ...draft.answers, gpa })]);

    ok('a CGPA of 9.9 is refused', await submit('9.9') === '23514');
    ok('a CGPA of 3.9 goes through', await submit('3.9') === null);
    const stored = await one(
      `select gpa::float8 as gpa, gpa_scale::float8 as scale from public.education_profiles where user_id = $1`,
      [draft.user_id]);
    ok('and is stored as 3.9 out of 4', stored.gpa === 3.9 && stored.scale === 4,
      JSON.stringify(stored));

    console.log('\n4. a school student, whose results are out of 5');
    // The same student's answers moved to the school branch, the shape
    // verify_onboarding.js submits. Rolled back with everything else.
    const school = {
      stage: 'high_school',
      full_name: draft.answers.full_name,
      country_id: draft.answers.country_id,
      city_id: draft.answers.city_id,
      institution_name: 'Dhaka College',
      current_class: 'Class 11',
      curriculum: 'national',
      intended_field_slug: [],
      field_confidence: 'unsure',
    };
    ok('a result of 4.83 goes through',
      await attempt(`select public.write_onboarding($1::jsonb)`,
        [JSON.stringify({ ...school, gpa: '4.83' })]) === null);
    const kept = await one(
      `select gpa::float8 as gpa, gpa_scale::float8 as scale from public.education_profiles where user_id = $1`,
      [draft.user_id]);
    ok('and is stored as 4.83 out of 5', kept.gpa === 4.83 && kept.scale === 5,
      JSON.stringify(kept));
    ok('a result of 5.5 is refused',
      await attempt(`select public.write_onboarding($1::jsonb)`,
        [JSON.stringify({ ...school, gpa: '5.5' })]) === '23514');
  } finally {
    await pg.query('rollback');
    await pg.end();
  }
  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
