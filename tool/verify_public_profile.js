#!/usr/bin/env node
/* Live verification of the published profile page.

   This is the one thing in Tack that a stranger can read, so the checks that
   matter are about what it refuses to say:

     - the phone number appears nowhere, under any combination of toggles;
     - an unpublished handle is a 404 and not "this student is private", which
       would confirm the handle belongs to somebody;
     - a toggle that is off actually removes the section from the HTML, rather
       than hiding it with CSS;
     - it is readable with no bearer token at all.

     node tool/verify_public_profile.js */
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
const PHONE = '1719998887';

let pass = 0, fail = 0, parked = 0;
const ok = (n, c, extra = '') => {
  c ? (pass++, console.log(`  PASS  ${n}`))
    : (fail++, console.log(`  FAIL  ${n} ${extra}`));
};

/* A thing that is known not to work, for a reason that is written down and
   decided. Distinct from a failure: nothing here is broken, the page simply
   has no front door yet. Printed every run so it cannot be forgotten. */
const park = (n, why) => {
  parked++;
  console.log(`  PARK  ${n}\n        ${why}`);
};

const admin = (p, o = {}) => fetch(`${URL}${p}`, {
  ...o,
  headers: { apikey: SVC, Authorization: `Bearer ${SVC}`, 'Content-Type': 'application/json', ...(o.headers || {}) },
});
const asUser = (t, p, o = {}) => fetch(`${URL}${p}`, {
  ...o,
  headers: { apikey: ANON, Authorization: `Bearer ${t}`, 'Content-Type': 'application/json', ...(o.headers || {}) },
});

/* A stranger following a link. No apikey, no bearer, nothing. */
const asStranger = (handle) =>
  fetch(`${URL}/functions/v1/profile/${handle}`, { redirect: 'manual' });

async function makeStudent(label) {
  const email = `pub_${label}_${Date.now()}@tack.test`;
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
  return { id: u.id, email, token };
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

  const students = [];
  const handle = `test-${Date.now().toString(36)}`;
  try {
    const student = await makeStudent('owner');
    students.push(student.id);

    await pg.query(
      `update public.profiles
          set full_name = 'Rafiq Hossain', phone = $2, dial_code = '+880',
              target_role = 'Backend developer'
        where id = $1`, [student.id, PHONE]);
    await pg.query(
      `insert into public.experiences (user_id, company_name, title, start_date)
       values ($1, 'Pathao', 'Backend intern', '2025-06-01')`, [student.id]);
    await pg.query(
      `insert into public.projects (user_id, title, summary, repo_url)
       values ($1, 'Bus tracker', 'Live bus times', 'https://github.com/flutter/flutter')`,
      [student.id]);

    // ---------------------------------------------------------------------
    console.log('\n1. before publishing');

    const claim = await asUser(student.token, '/rest/v1/rpc/set_handle', {
      method: 'POST',
      body: JSON.stringify({ p_handle: handle }),
    });
    ok('a student can claim a handle', claim.ok,
      `${claim.status} ${await claim.clone().text()}`);

    const hidden = await asStranger(handle);
    ok('an unpublished profile is 404, not "private"', hidden.status === 404,
      `got ${hidden.status}`);

    const unknown = await asStranger('no-such-handle-at-all');
    const hiddenBody = await hidden.text();
    const unknownBody = await unknown.text();
    ok('an unknown handle is indistinguishable from an unpublished one',
      unknown.status === 404 && unknownBody === hiddenBody);

    // ---------------------------------------------------------------------
    console.log('\n2. published, and read by a stranger');

    await pg.query(`update public.profiles set is_public = true where id = $1`,
      [student.id]);

    const page = await asStranger(handle);
    const html = await page.text();
    ok('the page loads with no token at all', page.status === 200,
      `got ${page.status}`);
    const contentType = page.headers.get('content-type') ?? '';
    if (contentType.includes('text/html')) {
      ok('the page is served as html', true);
    } else {
      park('the page is served as html, not as source text',
        `content-type is "${contentType}". Supabase's gateway rewrites every ` +
        'Edge Function response to text/plain and adds `sandbox` to the CSP — ' +
        'an anti-phishing measure on *.supabase.co. The HTML is correct and ' +
        'escaped; a browser renders it as source. Needs a domain we control. ' +
        'See docs/DEPLOY.md.');
    }
    ok('it shows the student', html.includes('Rafiq Hossain'));
    ok('and their work', html.includes('Pathao') && html.includes('Bus tracker'));

    // The rule the feature rests on.
    ok('the phone number is nowhere on it', !html.includes(PHONE),
      'a phone number was published');
    ok('nor is the email address', !html.includes(student.email));

    ok('it declares a content security policy',
      (page.headers.get('content-security-policy') ?? '').includes("default-src 'none'"));

    // ---------------------------------------------------------------------
    console.log('\n3. the toggles actually remove things');

    await pg.query(
      `insert into public.public_profile_settings (user_id, show_experience, show_projects)
       values ($1, false, false)
       on conflict (user_id) do update set show_experience = false, show_projects = false`,
      [student.id]);

    // The page is cached for five minutes; a fresh query string gets past it.
    const trimmed = await fetch(
      `${URL}/functions/v1/profile/${handle}?t=${Date.now()}`);
    const trimmedHtml = await trimmed.text();
    ok('a section switched off is gone from the html, not hidden with css',
      !trimmedHtml.includes('Pathao') && !trimmedHtml.includes('Bus tracker'),
      'content survived its toggle being turned off');
    ok('and the rest of the page still renders',
      trimmedHtml.includes('Rafiq Hossain'));
    ok('the phone number is still absent', !trimmedHtml.includes(PHONE));

    // ---------------------------------------------------------------------
    console.log('\n4. handles');

    const reserved = await asUser(student.token, '/rest/v1/rpc/handle_available', {
      method: 'POST',
      body: JSON.stringify({ p_handle: 'admin' }),
    }).then((r) => r.json());
    ok('a reserved handle is not available', reserved === false);

    const taken = await makeStudent('rival');
    students.push(taken.id);
    const steal = await asUser(taken.token, '/rest/v1/rpc/set_handle', {
      method: 'POST',
      body: JSON.stringify({ p_handle: handle }),
    });
    ok('a handle somebody already has cannot be taken', !steal.ok,
      `got ${steal.status}`);

    // ---------------------------------------------------------------------
    console.log('\n5. the repository check');

    const { rows: [job] } = await pg.query(
      `select payload, status from public.jobs_queue
        where type = 'verify_project' and user_id = $1`, [student.id]);
    ok('adding a repo url queued a verification', job !== undefined,
      'no job was enqueued');

    const { rows: [s] } = await pg.query(
      `select decrypted_secret x from vault.decrypted_secrets
        where name = 'tack_cron_secret'`);
    await fetch(`${URL}/functions/v1/worker`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${s.x}`, 'Content-Type': 'application/json' },
      body: '{}',
    });

    const { rows: [verified] } = await pg.query(
      `select v.state, v.language, v.stars from public.project_verifications v
        join public.projects p on p.id = v.project_id
       where p.user_id = $1`, [student.id]);
    ok('the worker verified a real public repository',
      verified?.state === 'verified',
      JSON.stringify(verified));
    ok('and recorded what it found',
      typeof verified?.stars === 'number' && verified?.language,
      JSON.stringify(verified));
  } finally {
    for (const id of students) {
      await admin(`/auth/v1/admin/users/${id}`, { method: 'DELETE' });
    }
    const gone = await asStranger(handle);
    ok('a deleted account takes its page with it', gone.status === 404,
      `got ${gone.status}`);
    await pg.end();
  }

  console.log(
    `\n${pass} passed, ${fail} failed` + (parked ? `, ${parked} parked` : ''),
  );
  process.exit(fail === 0 ? 0 : 1);
})().catch((e) => { console.error('ERROR:', e.message); process.exit(1); });
