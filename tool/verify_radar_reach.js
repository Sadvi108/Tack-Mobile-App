#!/usr/bin/env node
/* Radar shows only what a student in Bangladesh can take (0095).
   With no Bangladesh source configured, the feed was nothing but foreign
   roles the boards had marked remote: "USA - Remote", "Berlin", "Germany
   (Remote)". Everything here runs inside one transaction that is rolled back,
   so the sample listings never reach a real student. */
const path = require('path');
const { Client } = require('pg');
require('dotenv').config({ path: path.join(__dirname, '..', 'supabase', '.env'), quiet: true });
let pass = 0, fail = 0;
const ok = (n, c, extra = '') => { c ? (pass++, console.log(`  PASS  ${n}`)) : (fail++, console.log(`  FAIL  ${n} ${extra}`)); };

// source, location, remote, should a Dhaka student see it?
const CASES = [
  // The importer checks the country before it stores these two sources, and
  // nothing else writes them, so the source is the evidence.
  ['bdjobs', null, false, true, 'a Bdjobs vacancy with no location'],
  ['bdjobs', 'Gulshan', false, true, 'a Bdjobs vacancy in a Dhaka area'],
  ['linkedin', null, false, true, 'a LinkedIn vacancy validated by country, no location'],
  ['linkedin', 'Remote', true, true, 'a LinkedIn vacancy validated by country, "Remote"'],
  ['linkedin', 'Dhaka, Dhaka, Bangladesh', false, true, 'a LinkedIn role in Dhaka'],
  // A place in Bangladesh.
  ['careerjet', 'Chattogram', false, true, 'a Careerjet role in Chattogram'],
  ['jsearch', 'Sylhet', false, true, 'a role in Sylhet'],
  ['jsearch', 'Chittagong', false, true, 'the older spelling of Chattogram'],
  ['jsearch', 'Gopalganj', false, true, 'a district that is not in the cities table'],
  ['jsearch', 'ঢাকা', false, true, 'Dhaka written in Bangla'],
  ['jsearch', 'Gopalganj, India', false, false, 'a Bangladeshi district name in India'],
  ['jsearch', 'Anywhere except Dhaka', true, false, 'a place named only to exclude it'],
  // Remote, and open to Bangladesh.
  ['remotive', 'Worldwide', true, true, 'remote and open worldwide'],
  ['aijobs', 'Remote - Asia', true, true, 'remote and open to Asia'],
  ['aijobs', 'South Asia', true, true, 'remote and open to South Asia'],
  ['aijobs', 'APAC', true, true, 'remote and open to APAC'],
  ['remotive', 'Worldwide', false, false, 'open worldwide but on site'],
  ['aijobs', 'Southeast Asia', true, false, 'remote in Southeast Asia, which Bangladesh is not'],
  ['remotive', 'Worldwide except Bangladesh', true, false, 'worldwide except Bangladesh'],
  ['remotive', 'APAC — Australia only', true, false, 'APAC, Australia only'],
  ['remotive', 'Europe, USA, Canada, APAC', true, false, 'a list that names the USA'],
  ['aijobs', 'USA - Remote', true, false, 'remote for the USA only'],
  ['aijobs', 'Canada (Remote)', true, false, 'remote for Canada only'],
  ['aijobs', 'Remote - UK', true, false, 'remote for the UK only'],
  ['arbeitnow', 'Berlin', true, false, 'hybrid in Berlin'],
  ['arbeitnow', 'Remote', true, false, 'a bare "Remote"'],
  ['themuse', 'Flexible / Remote', true, false, 'a US board\'s "Flexible / Remote"'],
  ['aijobs', 'San Francisco', false, false, 'on site in San Francisco'],
  ['aijobs', null, true, false, 'remote with no location at all'],
  // Raised in review with Codex.
  ['bdjobs', 'Riyadh, Saudi Arabia', false, false, 'a Bdjobs vacancy abroad'],
  ['bdjobs', 'Gopalganj, India', false, false, 'a Bdjobs-sourced row placed in India'],
  ['linkedin', 'Worldwide except Bangladesh', true, false, 'a LinkedIn row that excludes Bangladesh'],
  ['jsearch', 'Not Bangladesh', true, false, 'a location that says not Bangladesh'],
  ['remotive', 'Anywhere in Europe', true, false, 'remote anywhere in Europe'],
  ['remotive', 'EMEA', true, false, 'remote in EMEA'],
  ['remotive', 'LATAM', true, false, 'remote in Latin America'],
  ['remotive', 'North America', true, false, 'remote in North America'],
  ['aijobs', 'South East Asia', true, false, '"South East Asia" written apart'],
  ['aijobs', 'South-East Asia', true, false, '"South-East Asia" hyphenated'],
  ['jsearch', 'ঢাকা, বাংলাদেশ', false, true, 'Dhaka, Bangladesh in Bangla'],
  ['jsearch', 'Dhaka (not remote)', false, true, 'a Dhaka role that is "not remote"'],
  // Second review with Codex.
  ['remotive', 'Worldwide — usa', true, false, 'a lower-case "usa"'],
  ['jsearch', 'Dhaka, uk', false, false, 'a lower-case "uk" beside Dhaka'],
  ['remotive', 'Worldwide (Uae)', true, false, 'a mixed-case "Uae"'],
  ['jsearch', 'Business Bay', false, false, '"us" inside an ordinary word is not the USA, and not Bangladesh either'],
  ['jsearch', 'Not ঢাকা', false, false, '"not" in front of Dhaka in Bangla'],
  ['jsearch', 'Not বাংলাদেশ', true, false, '"not" in front of Bangladesh in Bangla'],
  ['jsearch', 'অফিস: ঢাকা।', false, true, 'Dhaka in Bangla ending a sentence'],
  ['jsearch', 'ঢাকাই', false, false, 'a longer Bangla word that only starts with Dhaka'],
];

(async () => {
  const pg = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await pg.connect();
  try {
    await pg.query('begin');
    // REACH_PREVIEW=<migration file> runs an unapplied migration inside this
    // transaction first, so a rule can be checked before it is applied.
    if (process.env.REACH_PREVIEW) {
      await pg.query(require('fs').readFileSync(process.env.REACH_PREVIEW, 'utf8'));
      console.log(`  (previewing ${path.basename(process.env.REACH_PREVIEW)}, rolled back after)`);
    }
    const student = (await pg.query(
      `select id from public.profiles where onboarding_completed_at is not null
        order by created_at desc limit 1`)).rows[0];
    ok('there is a finished student to read the feed as', !!student);

    console.log('\n1. who reaches Bangladesh');
    const tag = `reach-check-${Date.now()}`;
    for (const [i, [source, location, remote]] of CASES.entries()) {
      await pg.query(
        `insert into public.job_listings
           (source, external_id, title, company_name, location, is_remote,
            workplace_known, url, last_seen_at)
         values ($1, $2, $3, 'Reach check', $4, $5, true, $6, now())`,
        [source, `${tag}-${i}`, `${tag} ${i}`, location, remote,
          `https://example.invalid/${tag}/${i}`]);
    }
    // The stored flag is what the feed reads; the trigger sets it on insert.
    for (const [i, [, , , want, name]] of CASES.entries()) {
      const r = await pg.query(
        `select reaches_bangladesh as yes from public.job_listings
          where source is not null and external_id = $1`, [`${tag}-${i}`]);
      ok(`${want ? 'shown' : 'hidden'}: ${name}`, r.rows[0]?.yes === want,
        `(got ${r.rows[0]?.yes}, case ${i})`);
    }

    // An edit to the location re-decides it.
    await pg.query(
      `update public.job_listings set location = 'Dhaka' where external_id = $1`,
      [`${tag}-${CASES.findIndex((c) => c[1] === 'San Francisco')}`]);
    const moved = await pg.query(
      `select reaches_bangladesh as yes from public.job_listings where external_id = $1`,
      [`${tag}-${CASES.findIndex((c) => c[1] === 'San Francisco')}`]);
    ok('moving a listing to Dhaka makes it reachable', moved.rows[0].yes === true);
    await pg.query(
      `update public.job_listings set location = 'San Francisco' where external_id = $1`,
      [`${tag}-${CASES.findIndex((c) => c[1] === 'San Francisco')}`]);

    const flag = async (i) => (await pg.query(
      `select reaches_bangladesh as yes from public.job_listings where external_id = $1`,
      [`${tag}-${i}`])).rows[0].yes;
    // A change of source re-decides it: a null location only passes for the
    // two importer-written sources.
    const blank = CASES.findIndex((c) => c[0] === 'aijobs' && c[1] === null);
    await pg.query(`update public.job_listings set source = 'bdjobs' where external_id = $1`,
      [`${tag}-${blank}`]);
    ok('switching a blank-location row to Bdjobs makes it reachable', await flag(blank) === true);
    await pg.query(`update public.job_listings set source = 'aijobs' where external_id = $1`,
      [`${tag}-${blank}`]);
    ok('and switching it back hides it again', await flag(blank) === false);
    // So does a change of workplace.
    const ww = CASES.findIndex((c) => c[1] === 'Worldwide' && c[2] === false);
    await pg.query(`update public.job_listings set is_remote = true where external_id = $1`,
      [`${tag}-${ww}`]);
    ok('marking a worldwide role remote makes it reachable', await flag(ww) === true);
    await pg.query(`update public.job_listings set is_remote = false where external_id = $1`,
      [`${tag}-${ww}`]);

    const stale = Number((await pg.query(
      `select count(*) n from public.job_listings
        where reaches_bangladesh is distinct from
              public.listing_reaches_bangladesh(source, location, is_remote)`)).rows[0].n);
    ok('every stored row agrees with the rule (the backfill ran)', stale === 0, `${stale} rows`);

    console.log('\n2. the feed a Dhaka student gets');
    await pg.query(`set local role authenticated`);
    await pg.query(`select set_config('request.jwt.claims', $1, true)`,
      [JSON.stringify({ sub: student.id, role: 'authenticated' })]);
    const feedFor = async (location, remote) => new Set((await pg.query(
      `select public.radar_feed($1, $2, $3, 50, 0, null) as f`,
      [tag, location, remote])).rows[0].f.map((l) => l.title));
    // A blank city is "all of Bangladesh", never "anywhere".
    const anywhere = await feedFor('', null);
    for (const [i, [, , , want, name]] of CASES.entries()) {
      ok(`${want ? 'in' : 'not in'} the feed: ${name}`,
        anywhere.has(`${tag} ${i}`) === want);
    }
    const remoteOnly = await feedFor('', true);
    const onSite = await feedFor('', false);
    const title = (location, remote, source) =>
      `${tag} ${CASES.findIndex((c) => c[0] === source && c[1] === location && c[2] === remote)}`;
    ok('the remote filter keeps a worldwide remote role',
      remoteOnly.has(title('Worldwide', true, 'remotive')));
    ok('the remote filter still hides a USA-only remote role',
      !remoteOnly.has(title('USA - Remote', true, 'aijobs')));
    ok('the in-person filter keeps a role in Sylhet', onSite.has(title('Sylhet', false, 'jsearch')));
    ok('the in-person filter hides a role in San Francisco',
      !onSite.has(title('San Francisco', false, 'aijobs')));
    const dhaka = await feedFor('Dhaka', null);
    ok('the Dhaka feed keeps a worldwide remote role', dhaka.has(title('Worldwide', true, 'remotive')));
    ok('the Dhaka feed leaves out a role in Sylhet', !dhaka.has(title('Sylhet', false, 'jsearch')));

    const all = (await pg.query(
      `select public.radar_feed(null, 'Dhaka', null, 50, 0, null) as f`)).rows[0].f;
    const foreign = all.filter((l) =>
      !l.title.startsWith(tag) &&
      /\b(usa|united states|canada|berlin|germany|san francisco|new york|london|uk)\b/i
        .test(l.location ?? ''));
    ok('nothing in the live feed is tied to a foreign country or city',
      foreign.length === 0, foreign.slice(0, 3).map((l) => l.location).join(' | '));
  } finally {
    await pg.query('rollback');
    await pg.end();
  }
  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error(e.message); process.exit(1); });
