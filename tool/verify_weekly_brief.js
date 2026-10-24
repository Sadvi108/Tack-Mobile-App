#!/usr/bin/env node
/* The Monday brief against live SQL. Three throwaway students: one in their
   final year with things that need attention, one first-year who must never
   hear about a deadline, and one with nothing at all, who must hear nothing.

   Everything that would reach a real student — the digest — runs inside a
   transaction that is rolled back, and the brief's real run is narrowed to
   one throwaway student. */
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

(async () => {
  const pg = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await pg.connect();
  const one = async (sql, args) => (await pg.query(sql, args)).rows[0];
  const today = (await one(`select public.tack_today()::text as d`)).d;
  const day = n => (new Date(Date.parse(today) + n * 86400000)).toISOString().slice(0, 10);
  const nineDhaka = async d => (await one(
    `select extract(epoch from ($1::date::timestamp at time zone 'Asia/Dhaka' + interval '9 hours')) as t`, [d])).t;

  const stamp = Date.now();
  const users = {};
  for (const [tag, year] of [['launch', 4], ['explore', 1], ['quiet', 4]]) {
    const email = `brief_${tag}_${stamp}@tack.test`;
    const created = await admin('/auth/v1/admin/users', {
      method: 'POST',
      body: JSON.stringify({ email, password: 'Test-passw0rd!', email_confirm: true })
    }).then(r => r.json());
    const session = await fetch(`${URL}/auth/v1/token?grant_type=password`, {
      method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password: 'Test-passw0rd!' })
    }).then(r => r.json());
    users[tag] = { id: created.id, token: session.access_token };
    await pg.query(
      `update public.profiles set
         city_id = (select id from public.cities where name = 'Dhaka' limit 1),
         education_stage = 'bachelors', year_of_study = $2, years_total = 4,
         onboarding_step = 99, onboarding_completed_at = now() - interval '30 days'
       where id = $1`, [created.id, year]);
  }
  const L = users.launch, E = users.explore, Q = users.quiet;
  const listings = [];

  try {
    console.log('\n0. modes');
    const modes = (await pg.query(
      `select id, mode::text from public.profiles where id = any($1)`, [[L.id, E.id, Q.id]])).rows;
    const modeOf = id => modes.find(m => m.id === id)?.mode;
    ok('the final-year student is in launch mode', modeOf(L.id) === 'launch', modeOf(L.id));
    ok('the first-year student is in explore mode', modeOf(E.id) === 'explore', modeOf(E.id));

    // ---- seed: applications ----
    const job = async (uid, company, closes) => (await one(
      `insert into public.jobs (user_id, company_name, title, location, closes_at)
       values ($1, $2, 'Junior analyst', 'Dhaka', $3) returning id`, [uid, company, closes])).id;
    const app = async (uid, jobId, status, step, stepDate) => (await one(
      `insert into public.job_applications
         (user_id, job_id, status, applied_at, next_action, next_action_date)
       values ($1, $2, $3::application_status,
               case when $3::application_status = 'saved' then null else now() - interval '9 days' end,
               $4, $5::date)
       returning id`, [uid, jobId, status, step, stepDate])).id;

    const closingApp = await app(L.id, await job(L.id, 'Meghna Foods', day(2)), 'saved', null, null);
    const interviewApp = await app(L.id, await job(L.id, 'Padma Textiles', null), 'interview',
      'Prepare for the call', day(3));
    // A reminder is not a closing date, and a sent application's posting
    // closing asks nothing of the student.
    await app(L.id, await job(L.id, 'Karnaphuli Paper', null), 'saved', 'Call HR', day(1));
    await app(L.id, await job(L.id, 'Surma Tea', day(1)), 'applied', null, null);
    await app(E.id, await job(E.id, 'Jamuna Group', day(1)), 'saved', null, null);

    // ---- seed: a roadmap with a late step, untouched for three weeks ----
    for (const s of [L, E]) {
      const roadmap = await one(
        `insert into public.roadmaps (user_id, title) values ($1, 'Test roadmap') returning id`, [s.id]);
      const milestone = await one(
        `insert into public.roadmap_milestones (roadmap_id, user_id, order_index, title, state)
         values ($1, $2, 0, 'First', 'active') returning id`, [roadmap.id, s.id]);
      // updated_at is only rewritten by the BEFORE UPDATE trigger, so an
      // insert can say when the step was last touched.
      await pg.query(
        `insert into public.roadmap_tasks
           (milestone_id, user_id, order_index, title, type, points, due_date, updated_at, created_at)
         values ($1, $2, 0, 'Late step', 'skill', 3, $3, now() - interval '21 days', now() - interval '30 days'),
                ($1, $2, 1, 'Later step', 'skill', 3, $4, now() - interval '21 days', now() - interval '30 days')`,
        [milestone.id, s.id, day(-2), day(10)]);
    }

    // ---- seed: practice. L has one due; E's only due one is in a deleted session ----
    const review = async (uid, deleted) => {
      const session = await one(
        `insert into public.interview_sessions (user_id, role, deleted_at)
         values ($1, 'Analyst', $2) returning id`, [uid, deleted ? new Date() : null]);
      const question = await one(
        `insert into public.interview_questions (session_id, user_id, order_index, question)
         values ($1, $2, 0, 'Tell me about a project.') returning id`, [session.id, uid]);
      await pg.query(
        `insert into public.interview_reviews (question_id, user_id, due_on) values ($1, $2, $3)`,
        [question.id, uid, day(-1)]);
    };
    await review(L.id, false);
    await review(E.id, true);

    // ---- seed: one fresh Dhaka opening whose two skills L has ----
    const skills = (await pg.query(
      `select id from public.skills where is_active order by name limit 2`)).rows.map(r => r.id);
    await pg.query(
      `insert into public.user_skills (user_id, skill_id, proficiency, source)
       values ($1, $2, 3, 'self'), ($1, $3, 3, 'self')`, [L.id, skills[0], skills[1]]);
    const listing = async (suffix, skillIds) => {
      const id = (await one(
        `insert into public.job_listings (source, external_id, title, company_name, location, url)
         values ('careerjet', $1, $2, 'Brief test company', 'Dhaka', $3) returning id`,
        [`brief-test-${stamp}-${suffix}`, `Brief test ${suffix}`, `https://example.com/brief-test-${stamp}-${suffix}`])).id;
      listings.push(id);
      for (const s of skillIds) {
        await pg.query(`insert into public.job_listing_skills (listing_id, skill_id) values ($1, $2)`, [id, s]);
      }
      return id;
    };
    const fullMatch = await listing('full', skills);

    console.log('\n1. ranking');
    const itemsOf = async (id, d = today) => (await one(
      `select public.weekly_brief_items($1, $2::date) as items`, [id, d])).items;
    const l = await itemsOf(L.id);
    ok('the final-year student gets three items', l.length === 3, JSON.stringify(l.map(i => i.kind)));
    ok('closing first, scored 100', l[0]?.reasons?.[0] === 'closing' && l[0]?.score === 100, JSON.stringify(l[0]));
    ok('it names the company and the day', /^Meghna Foods closes /.test(l[0]?.title ?? ''), l[0]?.title);
    ok('it opens that application', l[0]?.route === `/applications/${closingApp}`, l[0]?.route);
    ok('the interview stage second, scored 90', l[1]?.reasons?.[0] === 'interview' && l[1]?.score === 90, JSON.stringify(l[1]));
    ok('in the student\'s own words, not a claimed interview day',
      /^Padma Textiles: Prepare for the call, /.test(l[1]?.title ?? ''), l[1]?.title);
    ok('the interview opens its application', l[1]?.route === `/applications/${interviewApp}`, l[1]?.route);
    ok('the roadmap third: late and quiet, 80 + 5',
      l[2]?.kind === 'roadmap' && l[2]?.score === 85
        && l[2]?.reasons?.includes('steps_late') && l[2]?.reasons?.includes('idle_roadmap'),
      JSON.stringify(l[2]));
    ok('a reminder date never reads as a posting closing',
      !JSON.stringify(l).includes('Karnaphuli'), JSON.stringify(l.map(i => i.title)));
    ok('a sent application\'s posting closing is not news',
      !JSON.stringify(l).includes('Surma'), JSON.stringify(l.map(i => i.title)));
    ok('every item says why', l.every(i => typeof i.why === 'string' && i.why.length > 10));

    const e = await itemsOf(E.id);
    ok('the first-year gets the roadmap only', e.length === 1 && e[0].kind === 'roadmap', JSON.stringify(e));
    const words = JSON.stringify(e).toLowerCase();
    ok('and never the word deadline or apply', !/deadline|apply|closes/.test(words), words);
    ok('a question from a deleted session is never due', !e.some(i => i.kind === 'practice'));

    ok('a student with nothing gets nothing', (await itemsOf(Q.id)).length === 0);

    console.log('\n2. dry run');
    const notesBefore = (await one(`select count(*)::int n from public.notifications where user_id = $1`, [L.id])).n;
    const dry = (await one(`select public.enqueue_weekly_brief(true, $1::date, $2) as out`, [today, L.id])).out;
    ok('a dry run reports what it would send', dry.length === 1 && dry[0].items.length === 3, JSON.stringify(dry));
    const notesAfterDry = (await one(`select count(*)::int n from public.notifications where user_id = $1`, [L.id])).n;
    ok('and sends nothing', notesAfterDry === notesBefore, `${notesBefore} -> ${notesAfterDry}`);
    const quiet = (await one(`select public.enqueue_weekly_brief(true, $1::date, $2) as out`, [today, Q.id])).out;
    ok('a quiet week is left out entirely', quiet.length === 0, JSON.stringify(quiet));

    console.log('\n3. the digest delivers on the morning it is for');
    await pg.query('begin');
    await pg.query(`select public.enqueue_daily_digest($1::date)`, [day(1)]);
    const digest = await one(
      `select extract(epoch from run_after) as t from public.jobs_queue
        where idempotency_key = 'push:digest:' || $1 || ':' || $2`, [E.id, day(1)]);
    await pg.query('rollback');
    ok('the digest was queued for the first-year', !!digest);
    ok('at exactly 09:00 Dhaka that morning', Number(digest?.t) === Number(await nineDhaka(day(1))),
      `${digest?.t} vs ${await nineDhaka(day(1))}`);
    const stale = (await one(
      `select count(*)::int n from public.jobs_queue
        where type = 'send_push' and status = 'pending' and idempotency_key like 'push:digest:%'
          and (run_after at time zone 'Asia/Dhaka')::date > split_part(idempotency_key, ':', 4)::date`)).n;
    ok('no digest is still queued for the morning after its own', stale === 0, `${stale}`);

    console.log('\n4. a real run, for tomorrow');
    const real = (await one(`select public.enqueue_weekly_brief(false, $1::date, $2) as out`, [day(1), L.id])).out;
    ok('one student briefed', real.length === 1);
    const note = await one(
      `select title, body, payload from public.notifications
        where user_id = $1 and type = 'weekly_brief'`, [L.id]);
    ok('a weekly_brief notification exists', !!note);
    ok('its title counts the items', note?.title === 'Your week: 3 things', note?.title);
    ok('its body is the top item\'s reason', note?.body === note?.payload?.items?.[0]?.why, note?.body);
    ok('and never anything the student typed', !/Meghna|Padma|Prepare/.test(note?.body ?? ''), note?.body);
    ok('the items ride along for the app', note?.payload?.items?.length === 3);
    const push = await one(
      `select extract(epoch from run_after) as t from public.jobs_queue
        where idempotency_key = 'push:digest:' || $1 || ':' || $2`, [L.id, day(1)]);
    ok('the push is queued for exactly 09:00 Dhaka', Number(push?.t) === Number(await nineDhaka(day(1))),
      `${push?.t}`);
    const again = (await one(
      `select public.notify($1::uuid, 'step_due', 'x', null, '{}'::jsonb, $2::text) as id`,
      [L.id, `digest:${L.id}:${day(1)}`])).id;
    ok('the day\'s digest slot is taken, so no second notification', again === null, `${again}`);

    console.log('\n5. the nightly sweep');
    const def = (await one(`select pg_get_functiondef('public.nightly_maintenance()'::regprocedure) as d`)).d;
    const brief = def.indexOf('enqueue_weekly_brief'), digestAt = def.indexOf('enqueue_daily_digest');
    ok('runs the brief on Mondays', /isodow from public\.tack_today\(\)\)\s*=\s*1\b/.test(def));
    ok('before the digest, so the brief takes the slot', brief > 0 && brief < digestAt);
    ok('and a fault in the brief cannot stop the rest', /exception when others/.test(def));

    console.log('\n6. nobody outside the database can call these');
    for (const fn of ['listing_fit(uuid,uuid)', 'weekly_brief_items(uuid,date)',
                      'enqueue_weekly_brief(boolean,date,uuid)', 'enqueue_daily_digest(date)']) {
      const g = await one(
        `select has_function_privilege('authenticated', $1, 'execute') as a,
                has_function_privilege('anon', $1, 'execute') as b`, [`public.${fn}`]);
      ok(`${fn} is not callable by a student or the public`, !g.a && !g.b, JSON.stringify(g));
    }

    console.log('\n7. fit agrees with the radar');
    const radarFit = async id => {
      const feed = await fetch(`${URL}/rest/v1/rpc/radar_feed`, {
        method: 'POST',
        headers: { apikey: ANON, Authorization: `Bearer ${L.token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ p_query: 'Brief test', p_location: 'Dhaka', p_remote: null, p_limit: 50, p_offset: 0, p_kind: null }),
      }).then(r => r.json());
      return (Array.isArray(feed) ? feed : feed?.listings ?? []).find(x => x.id === id)?.fit;
    };
    const fit = async id => (await one(`select public.listing_fit($1, $2) as f`, [L.id, id])).f;
    ok('two of two skills is 80', await fit(fullMatch) === 80, `${await fit(fullMatch)}`);
    ok('the radar shows the same', await radarFit(fullMatch) === await fit(fullMatch), `${await radarFit(fullMatch)}`);

    // Following a path brings in the on-path term. Done last: following can
    // build a roadmap, which would change the ranking above.
    const pathRow = await one(
      `select cps.path_id, array_agg(cps.skill_id) as s
         from public.career_path_skills cps
        where cps.skill_id <> all($1::uuid[])
        group by cps.path_id having count(*) >= 2 limit 1`, [skills]);
    await pg.query(
      `insert into public.user_career_paths (user_id, path_id, is_primary) values ($1, $2, true)`,
      [L.id, pathRow.path_id]);
    const partial = await listing('partial', [skills[0], pathRow.s[0], pathRow.s[1]]);
    const partialFit = await fit(partial);
    ok('one of three skills, two on the path, is a partial fit', partialFit > 0 && partialFit < 80, `${partialFit}`);
    ok('and the radar gives the same number', await radarFit(partial) === partialFit, `${await radarFit(partial)}`);
  } finally {
    // A failure inside the digest's transaction would leave it open, and every
    // cleanup statement below would be refused.
    await pg.query('rollback').catch(() => {});
    for (const id of listings) await pg.query(`delete from public.job_listings where id = $1`, [id]);
    for (const u of Object.values(users)) await admin(`/auth/v1/admin/users/${u.id}`, { method: 'DELETE' });
    const left = (await one(
      `select count(*)::int n from public.job_listings where external_id like 'brief-test-%'`)).n;
    ok('no test listings are left behind', left === 0, `${left}`);
    await pg.end();
  }

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error('\nERROR:', e.message); process.exit(1); });
