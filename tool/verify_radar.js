#!/usr/bin/env node
/* Live verification of Radar's database half.

   The Edge Function is the part that talks to the job boards; everything a
   student can be harmed by — who may read listings, whose skills the fit score
   is computed against, what saving does to their tracker — is in Postgres, and
   that is what this checks, over PostgREST, with a real student's token. */
const path = require('path');
const { Client } = require('pg');
require('dotenv').config({ path: path.join(__dirname, '..', 'supabase', '.env'), quiet: true });

const URL = process.env.SUPABASE_URL;
const ANON = process.env.SUPABASE_ANON_KEY;
const SVC = process.env.SUPABASE_SERVICE_ROLE_KEY;
const PASSWORD = 'Test-passw0rd!';

let pass = 0, fail = 0;
const ok = (n, c, extra = '') => { c ? (pass++, console.log(`  PASS  ${n}`)) : (fail++, console.log(`  FAIL  ${n} ${extra}`)); };

const admin = (p, o = {}) => fetch(`${URL}${p}`, { ...o, headers: { apikey: SVC, Authorization: `Bearer ${SVC}`, 'Content-Type': 'application/json', ...(o.headers || {}) } });
const asUser = (t, p, o = {}) => fetch(`${URL}${p}`, { ...o, headers: { apikey: ANON, Authorization: `Bearer ${t}`, 'Content-Type': 'application/json', ...(o.headers || {}) } });
const feed = (t, body = {}) => asUser(t, '/rest/v1/rpc/radar_feed', { method: 'POST', body: JSON.stringify(body) }).then(r => r.json());

async function makeStudent(label) {
  const email = `radar_${label}_${Date.now()}@tack.test`;
  const u = await admin('/auth/v1/admin/users', {
    method: 'POST',
    body: JSON.stringify({ email, password: PASSWORD, email_confirm: true }),
  }).then(r => r.json());
  if (!u.id) throw new Error(`could not create user: ${JSON.stringify(u)}`);
  const token = (await fetch(`${URL}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: PASSWORD }),
  }).then(r => r.json())).access_token;
  return { id: u.id, token };
}

(async () => {
  const pg = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await pg.connect();

  const a = await makeStudent('a');
  const b = await makeStudent('b');
  const listingIds = [];

  try {
    console.log('\n1. skill extraction, against the real vocabulary');
    const cases = [
      ['Node.js, PostgreSQL and Docker. React a plus.', ['Docker', 'Node.js', 'PostgreSQL', 'React'], []],
      ['Google is a great company in Gopalganj. We go fast.', [], ['Go']],
      ['Backend engineer. Go and PostgreSQL.', ['Go', 'PostgreSQL'], []],
      ['Data analyst using R and Python.', ['R', 'Python'], []],
      ['react, css, html and typescript.', ['React', 'CSS', 'HTML', 'TypeScript'], []],
    ];
    for (const [text, expected, forbidden] of cases) {
      const { rows: [r] } = await pg.query(
        `select coalesce(array_agg(s.name order by s.name), '{}') a
           from public.extract_listing_skills($1) x join public.skills s on s.id = x`, [text]);
      const missing = expected.filter(e => !r.a.includes(e));
      const wrong = forbidden.filter(f => r.a.includes(f));
      ok(`"${text.slice(0, 40)}…"`, missing.length === 0 && wrong.length === 0,
        `missing ${JSON.stringify(missing)} wrong ${JSON.stringify(wrong)} got ${JSON.stringify(r.a)}`);
    }

    console.log('\n2. listings are shared, and read-only to a student');
    const seed = async (external, title, body, remote = false, loc = 'Dhaka') => {
      const { rows: [l] } = await pg.query(
        `insert into public.job_listings (source, external_id, title, company_name, location, is_remote, url, description, posted_at)
         values ('aijobs', $1, $2, 'Acme', $3, $4, $5, $6, now()) returning id`,
        [external, title, loc, remote, `https://example.test/${external}`, body]);
      await pg.query('select public.reindex_listing_skills($1)', [l.id]);
      listingIds.push(l.id);
      return l.id;
    };
    const backend = await seed(`v-be-${Date.now()}`, 'Backend developer',
      'We use Node.js, PostgreSQL and Docker.');
    const vague = await seed(`v-vague-${Date.now()}`, 'Graduate programme',
      'A great opportunity for a motivated person.');
    await seed(`v-remote-${Date.now()}`, 'Remote React developer',
      'React and TypeScript.', true, null);

    const read = await asUser(a.token, '/rest/v1/job_listings?select=id&limit=1');
    ok('a student can read listings', read.status === 200, `status ${read.status}`);

    const write = await asUser(a.token, '/rest/v1/job_listings', {
      method: 'POST',
      body: JSON.stringify({ source: 'aijobs', external_id: 'hack', title: 'x', url: 'https://x.test' }),
    });
    ok('a student cannot write one', write.status >= 400, `status ${write.status}`);

    const anonRead = await fetch(`${URL}/rest/v1/job_listings?select=id`, { headers: { apikey: ANON } });
    ok('the anon key alone reads nothing', anonRead.status >= 400 || (await anonRead.json()).length === 0,
      `status ${anonRead.status}`);

    console.log('\n3. the fit score is about the caller, and nobody else');
    const { rows: skills } = await pg.query(
      `select id, name from public.skills where is_active and name in ('Node.js','PostgreSQL') order by name`);
    for (const s of skills) {
      await pg.query(
        `insert into public.user_skills (user_id, skill_id, proficiency, source) values ($1,$2,4,'self')`,
        [a.id, s.id]);
    }

    const aFeed = await feed(a.token, { p_limit: 50 });
    const bFeed = await feed(b.token, { p_limit: 50 });
    const aBackend = aFeed.find(l => l.id === backend);
    const bBackend = bFeed.find(l => l.id === backend);

    ok('the student with the skills scores higher',
      aBackend.fit > bBackend.fit, `${aBackend.fit} vs ${bBackend.fit}`);
    ok('and is told which skills matched',
      aBackend.matched_skills.length === 2 && aBackend.missing_skills.includes('Docker'),
      JSON.stringify({ m: aBackend.matched_skills, x: aBackend.missing_skills }));
    ok('the other student sees the same job with none matched',
      bBackend.matched_skills.length === 0, JSON.stringify(bBackend.matched_skills));

    /* The one that matters most for honesty: a listing Tack could read nothing
       from must not look like a listing the student matches none of. */
    const aVague = aFeed.find(l => l.id === vague);
    ok('an unreadable listing scores null, not zero',
      aVague.fit === null && aVague.asks === 0, JSON.stringify({ fit: aVague.fit, asks: aVague.asks }));
    ok('and a scored listing is ranked above it',
      aFeed.findIndex(l => l.id === backend) < aFeed.findIndex(l => l.id === vague));

    console.log('\n4. filters');
    const remoteOnly = await feed(a.token, { p_remote: true, p_limit: 50 });
    ok('remote only returns only remote roles',
      remoteOnly.length > 0 && remoteOnly.every(l => l.remote === true),
      JSON.stringify(remoteOnly.map(l => l.remote)));
    const searched = await feed(a.token, { p_query: 'Backend', p_limit: 50 });
    ok('a text search narrows the list',
      searched.some(l => l.id === backend) && !searched.some(l => l.id === vague));

    console.log('\n5. saving copies, it never shares');
    const appId = await asUser(a.token, '/rest/v1/rpc/save_listing', {
      method: 'POST', body: JSON.stringify({ p_listing_id: backend }),
    }).then(r => r.json());
    ok('saving returns an application id', typeof appId === 'string' && appId.length > 20, JSON.stringify(appId));

    const again = await asUser(a.token, '/rest/v1/rpc/save_listing', {
      method: 'POST', body: JSON.stringify({ p_listing_id: backend }),
    }).then(r => r.json());
    ok('saving twice is idempotent', again === appId);

    const afterSave = await feed(a.token, { p_limit: 50 });
    ok('the feed now shows it as saved',
      afterSave.find(l => l.id === backend)?.saved_application_id === appId);
    ok('and the other student is unaffected',
      (await feed(b.token, { p_limit: 50 })).find(l => l.id === backend)?.saved_application_id === null);

    /* The copy, not the reference. A listing that later changes or disappears
       must not rewrite an application the student already sent. */
    const { rows: [job] } = await pg.query(
      `select j.title, j.user_id from public.job_applications a
         join public.jobs j on j.id = a.job_id where a.id = $1`, [appId]);
    ok('the saved job belongs to the student', job.user_id === a.id);
    await pg.query(`update public.job_listings set title = 'CHANGED UPSTREAM' where id = $1`, [backend]);
    const { rows: [after] } = await pg.query(
      `select j.title from public.job_applications a join public.jobs j on j.id = a.job_id where a.id = $1`, [appId]);
    ok('an upstream change does not rewrite what they saved',
      after.title === job.title && after.title !== 'CHANGED UPSTREAM', after.title);

    console.log('\n6. signed out');
    const out = await fetch(`${URL}/rest/v1/rpc/radar_feed`, {
      method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' }, body: '{}',
    });
    ok('the anon key cannot ask for a feed', out.status >= 400, `status ${out.status}`);
  } finally {
    await admin(`/auth/v1/admin/users/${a.id}`, { method: 'DELETE' });
    await admin(`/auth/v1/admin/users/${b.id}`, { method: 'DELETE' });
    if (listingIds.length) {
      await pg.query('delete from public.job_listings where id = any($1)', [listingIds]);
    }
    const { rows: [left] } = await pg.query(
      'select count(*)::int n from public.job_listings where external_id like $1', ['v-%']);
    ok('the seeded listings are cleaned up', left.n === 0, `${left.n} left`);
    await pg.end();
    console.log(`\n${pass} passed, ${fail} failed\n`);
    process.exit(fail === 0 ? 0 : 1);
  }
})().catch(e => { console.error('ERROR:', e.message); process.exit(1); });
