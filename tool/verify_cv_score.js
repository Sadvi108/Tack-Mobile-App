#!/usr/bin/env node
/* Live verification of the CV field-fit score (migrations 0040, 0041).

   Checks the backfill, the weight table, the deterministic scorer, the basis
   ladder, mode-awareness, the readiness hand-off, and that a student cannot
   write a score of their own choosing. Creates throwaway auth users and
   deletes them at the end. */
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
const asUser = (tok, p, opt = {}) => fetch(`${URL}${p}`, {
  ...opt, headers: { apikey: ANON, Authorization: `Bearer ${tok}`, 'Content-Type': 'application/json', ...(opt.headers || {}) }
});

const monthsAgo = (n) => {
  const d = new Date();
  d.setMonth(d.getMonth() - n);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
};

// A CV that actually does the things the score rewards.
const strongParsed = {
  headline: 'Frontend developer',
  summary: 'Final-year CSE student building web interfaces.',
  skills: ['HTML', 'CSS', 'JavaScript', 'React', 'Git', 'Responsive design',
           'TypeScript', 'REST APIs', 'Figma'],
  education: [{ degree: 'BSc Computer Science', institution: 'BUET', year: 2026 }],
  experience: [{
    title: 'Frontend intern', organisation: 'bKash', months: 6,
    summary: 'Built React and TypeScript screens against REST APIs, cut load time 40%. ' +
             'Wrote responsive design breakpoints in CSS and shipped through Git.'
  }],
  projects: [{
    title: 'Campus marketplace',
    summary: 'HTML and JavaScript front end, Figma designs, 300 weekly users.'
  }]
};
const strongMetrics = {
  chars: 3100, words: 520, pages: 1,
  bullets: 12, bullets_quantified: 8, bullets_action_led: 11,
  sections: ['contact', 'education', 'experience', 'projects', 'skills'],
  has_contact: true, dated_entries: 3, undated_entries: 0,
  latest_entry_date: monthsAgo(3), placeholder_hits: 0,
  extractor: 'unpdf', truncated: false
};

// The same student, before any of that advice was taken.
const weakParsed = {
  headline: 'Student',
  skills: ['MS Word', 'Communication'],
  education: [{ degree: 'BSc Computer Science', institution: 'BUET' }],
  experience: [],
  projects: []
};
const weakMetrics = {
  chars: 9000, words: 1600, pages: 3,
  bullets: 10, bullets_quantified: 0, bullets_action_led: 1,
  sections: ['education'],
  has_contact: false, dated_entries: 0, undated_entries: 3,
  latest_entry_date: null, placeholder_hits: 2,
  extractor: 'unpdf', truncated: true
};

(async () => {
  const pg = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await pg.connect();

  const stamp = Date.now();
  const users = [];
  for (const tag of ['a', 'b']) {
    const email = `cvscore_${tag}_${stamp}@tack.test`;
    const r = await admin('/auth/v1/admin/users', {
      method: 'POST',
      body: JSON.stringify({ email, password: 'Test-passw0rd!', email_confirm: true, user_metadata: { full_name: `CV ${tag.toUpperCase()}` } })
    });
    const j = await r.json();
    if (!j.id) throw new Error(`could not create user: ${JSON.stringify(j)}`);
    const s = await fetch(`${URL}/auth/v1/token?grant_type=password`, {
      method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password: 'Test-passw0rd!' })
    }).then(x => x.json());
    users.push({ id: j.id, email, token: s.access_token });
  }
  const [A, B] = users;

  const addCv = async (user, parsed, metrics, tag) => {
    const d = await pg.query(
      `insert into public.documents (user_id, type, title, storage_path, mime_type, size_bytes, status, checksum)
       values ($1,'cv',$2,$3,'application/pdf',120000,'ready',$4) returning id`,
      [user.id, `CV ${tag}`, `users/${user.id}/cv/${tag}-${stamp}`, `sum-${tag}-${stamp}`]);
    const doc = d.rows[0].id;
    await pg.query(
      `insert into public.cv_parse_results (document_id, user_id, parsed, metrics) values ($1,$2,$3,$4)`,
      [doc, user.id, JSON.stringify(parsed), JSON.stringify(metrics)]);
    return doc;
  };
  const score = async (user, doc) =>
    (await pg.query('select public.score_cv_fit($1,$2) as id', [user.id, doc])).rows[0].id;
  const row = async (id) => (await pg.query('select * from public.cv_scores where id = $1', [id])).rows[0];

  console.log('\n1. backfill and reference data');
  const paths = await pg.query('select count(*)::int n from public.career_paths where is_active and field_id is null');
  ok('every active career path has a field', paths.rows[0].n === 0, `${paths.rows[0].n} without`);
  const w = await pg.query('select mode, sum(weight)::int t from public.cv_score_weights group by 1');
  ok('weights sum to 100 in all six modes', w.rows.length === 6 && w.rows.every(r => r.t === 100),
    JSON.stringify(w.rows));
  const fes = await pg.query(
    `select count(*)::int n from public.field_expected_skills((select id from public.career_fields where slug='computer-science'))`);
  ok('field skills are the union of the field\'s paths', fes.rows[0].n > 20, `${fes.rows[0].n}`);
  const dup = await pg.query(
    `select count(*)::int n from (
       select skill_id from public.field_expected_skills((select id from public.career_fields where slug='computer-science'))
       group by 1 having count(*) > 1) x`);
  ok('a skill shared by two paths appears once', dup.rows[0].n === 0);

  console.log('\n2. a chosen path scores against that path');
  await pg.query('update public.profiles set year_of_study = 4, years_total = 4 where id = $1', [A.id]);
  await pg.query(
    `insert into public.user_career_paths (user_id, path_id, is_primary, selected_at)
     values ($1, (select id from public.career_paths where slug='frontend-developer'), true, now())`, [A.id]);
  const docA = await addCv(A, strongParsed, strongMetrics, 'strong');
  const sA = await row(await score(A, docA));
  ok('basis is the chosen path', sA.basis === 'path', sA.basis);
  ok('mode recorded as launch', sA.mode === 'launch', sA.mode);
  ok('all eight components are scored', Object.keys(sA.components).length === 8,
    Object.keys(sA.components).join(','));
  ok('a strong CV scores well', sA.score_raw >= 70, `${sA.score_raw}`);
  ok('score_10 is score_raw to one decimal', Number(sA.score_10) === Math.round(sA.score_raw) / 10,
    `${sA.score_10} vs ${sA.score_raw}`);
  ok('matched skills are listed', sA.matched_skills.length >= 8, `${sA.matched_skills.length}`);
  ok('nice-to-have skills are not reported as missing',
    !sA.missing_skills.includes('Redux') && !sA.missing_skills.includes('Next.js'),
    JSON.stringify(sA.missing_skills));
  ok('first run has no delta', sA.delta === null, `${sA.delta}`);

  console.log('\n3. the score is deterministic');
  const sA2 = await row(await score(A, docA));
  ok('a second run gives the same number', sA2.score_raw === sA.score_raw, `${sA.score_raw} then ${sA2.score_raw}`);
  ok('the second run reports a delta of zero', sA2.delta === 0, `${sA2.delta}`);
  ok('components are identical', JSON.stringify(sA2.components) === JSON.stringify(sA.components));

  console.log('\n4. a weak CV scores lower, and says why');
  const docWeak = await addCv(A, weakParsed, weakMetrics, 'weak');
  const sW = await row(await score(A, docWeak));
  ok('the weak CV scores below the strong one', sW.score_raw < sA.score_raw, `${sW.score_raw} vs ${sA.score_raw}`);
  ok('the weak CV gets a fix list', sW.fixes.length > 0 && sW.fixes.length <= 4, `${sW.fixes.length}`);
  ok('fixes are ordered by the points they recover',
    sW.fixes.every((f, i) => i === 0 || sW.fixes[i - 1].points >= f.points), JSON.stringify(sW.fixes.map(f => f.points)));
  ok('every fix carries copy the app can show',
    sW.fixes.every(f => f.title && f.body && f.points > 0));
  ok('hygiene is penalised on the weak CV', sW.components.hygiene.ratio < 0.3, `${sW.components.hygiene.ratio}`);
  ok('quantification is zero with no numbers in any bullet', Number(sW.components.quantification.ratio) === 0);

  console.log('\n5. no path and no field is scored, not punished');
  await pg.query('update public.profiles set year_of_study = 2, years_total = 4 where id = $1', [B.id]);
  const docB = await addCv(B, strongParsed, strongMetrics, 'generic');
  const sB = await row(await score(B, docB));
  ok('basis is generic', sB.basis === 'generic', sB.basis);
  ok('the two field components drop out entirely', Object.keys(sB.components).length === 6,
    Object.keys(sB.components).join(','));
  ok('field components are absent, not zero',
    !('field_skill_coverage' in sB.components) && !('evidence_depth' in sB.components));
  ok('the remaining components still produce a real score', sB.score_raw >= 70, `${sB.score_raw}`);

  console.log('\n6. weights follow the student\'s mode');
  // The same thin CV, scored as a first-year and as a final-year. A first-year
  // must not be marked down for having no experience to write about.
  const thinParsed = { skills: ['HTML', 'CSS'], education: [{ degree: 'BSc' }], experience: [], projects: [] };
  const thinMetrics = { words: 280, pages: 1, bullets: 6, bullets_quantified: 1, bullets_action_led: 4,
    sections: ['contact', 'education', 'skills'], has_contact: true, dated_entries: 1, undated_entries: 0,
    latest_entry_date: monthsAgo(30), placeholder_hits: 0, extractor: 'unpdf', truncated: false };
  const docThin = await addCv(A, thinParsed, thinMetrics, 'thin');
  await pg.query('update public.profiles set year_of_study = 4, years_total = 4 where id = $1', [A.id]);
  const thinLaunch = await row(await score(A, docThin));
  await pg.query('update public.profiles set year_of_study = 1, years_total = 4 where id = $1', [A.id]);
  const thinExplore = await row(await score(A, docThin));
  ok('the same CV scores higher for a first-year than a final-year',
    thinExplore.score_raw > thinLaunch.score_raw, `explore ${thinExplore.score_raw} vs launch ${thinLaunch.score_raw}`);
  ok('recency is weighted lower in explore than launch',
    thinExplore.components.recency.weight < thinLaunch.components.recency.weight,
    `${thinExplore.components.recency.weight} vs ${thinLaunch.components.recency.weight}`);
  ok('the mode change is recorded as a delta', thinExplore.delta !== null);

  console.log('\n7. readiness picks the number up on its own');
  const q = await pg.query(
    'select quality_score from public.cv_parse_results where document_id = $1 order by created_at desc limit 1', [docA]);
  ok('the score is written back to cv_parse_results.quality_score',
    q.rows[0].quality_score === sA.score_raw, `${q.rows[0].quality_score} vs ${sA.score_raw}`);
  await pg.query('update public.profiles set year_of_study = 4, years_total = 4 where id = $1', [A.id]);
  await pg.query('select public.recompute_readiness($1, $2)', [A.id, 'verify']);
  const rd = await pg.query(
    'select components from public.readiness_scores where user_id = $1 order by computed_at desc limit 1', [A.id]);
  const cvq = rd.rows[0].components.cv_quality;
  ok('readiness cv_quality reflects the CV score', Number(cvq.ratio) > 0.5, JSON.stringify(cvq));

  console.log('\n8. a student cannot write their own score');
  const forge = await asUser(A.token, '/rest/v1/cv_scores', {
    method: 'POST',
    body: JSON.stringify({ user_id: A.id, document_id: docA, basis: 'path', mode: 'launch',
      score_raw: 100, score_10: 10, algo_version: 1 })
  });
  ok('POST /cv_scores is refused', forge.status >= 400, `status ${forge.status}`);
  const patch = await asUser(A.token, `/rest/v1/cv_scores?id=eq.${sA.id}`, {
    method: 'PATCH', body: JSON.stringify({ score_raw: 100 })
  });
  ok('PATCH /cv_scores is refused', patch.status >= 400, `status ${patch.status}`);
  const stillA = await row(sA.id);
  ok('the stored score is unchanged', stillA.score_raw === sA.score_raw);

  console.log('\n9. one student cannot read another\'s');
  const mine = await asUser(A.token, '/rest/v1/cv_scores?select=id,user_id').then(r => r.json());
  ok('a student sees only their own scores',
    Array.isArray(mine) && mine.length > 0 && mine.every(r => r.user_id === A.id), JSON.stringify(mine).slice(0, 120));
  const theirs = await asUser(B.token, `/rest/v1/cv_scores?select=id&user_id=eq.${A.id}`).then(r => r.json());
  ok('asking for someone else\'s scores returns nothing', Array.isArray(theirs) && theirs.length === 0,
    JSON.stringify(theirs).slice(0, 120));

  console.log('\n10. the client rescore path');
  const rpc = await asUser(A.token, '/rest/v1/rpc/recompute_my_cv_score', {
    method: 'POST', body: JSON.stringify({ p_document_id: docA })
  });
  const rpcBody = await rpc.json();
  ok('recompute_my_cv_score works for the signed-in student', rpc.ok && rpcBody?.score_raw === sA.score_raw,
    `status ${rpc.status} ${JSON.stringify(rpcBody).slice(0, 140)}`);
  const steal = await asUser(B.token, '/rest/v1/rpc/recompute_my_cv_score', {
    method: 'POST', body: JSON.stringify({ p_document_id: docA })
  });
  const stealBody = await steal.json();
  // A composite function returning null comes back from PostgREST as an object
  // of nulls rather than as JSON null, so the assertion is on the payload.
  ok('it refuses to score a document belonging to someone else',
    stealBody === null || (stealBody && stealBody.id === null && stealBody.score_raw === null),
    JSON.stringify(stealBody).slice(0, 140));
  const crossRows = await pg.query(
    'select count(*)::int n from public.cv_scores where user_id = $1 and document_id = $2', [B.id, docA]);
  ok('and writes no row for the document it was pointed at', crossRows.rows[0].n === 0, `${crossRows.rows[0].n}`);
  const direct = await asUser(A.token, '/rest/v1/rpc/score_cv_fit', {
    method: 'POST', body: JSON.stringify({ p_user_id: B.id, p_document_id: docB })
  });
  ok('score_cv_fit is not callable with someone else\'s user id', direct.status >= 400, `status ${direct.status}`);

  console.log('\n11. rescore is enqueued when the target changes');
  await pg.query('delete from public.jobs_queue where user_id = $1 and type = $2', [A.id, 'score_cv']);
  await pg.query(
    `insert into public.user_skills (user_id, skill_id, proficiency, source)
     values ($1, (select id from public.skills limit 1), 3, 'self')
     on conflict do nothing`, [A.id]);
  const jq = await pg.query(
    `select count(*)::int n from public.jobs_queue where user_id = $1 and type = 'score_cv' and status = 'pending'`, [A.id]);
  ok('a skill change queues a rescore', jq.rows[0].n === 1, `${jq.rows[0].n} job(s)`);
  await pg.query(
    `insert into public.user_skills (user_id, skill_id, proficiency, source)
     values ($1, (select id from public.skills offset 1 limit 1), 3, 'self')
     on conflict do nothing`, [A.id]);
  const jq2 = await pg.query(
    `select count(*)::int n from public.jobs_queue where user_id = $1 and type = 'score_cv' and status = 'pending'`, [A.id]);
  ok('a burst of changes coalesces to one pending job', jq2.rows[0].n === 1, `${jq2.rows[0].n} job(s)`);
  const noParse = await pg.query(
    `select count(*)::int n from public.jobs_queue where user_id = $1 and type = 'score_cv'`, [B.id]);
  await pg.query('delete from public.cv_parse_results where user_id = $1', [B.id]);
  await pg.query('update public.profiles set phone = $2 where id = $1', [B.id, '0170000000']);
  const noParse2 = await pg.query(
    `select count(*)::int n from public.jobs_queue where user_id = $1 and type = 'score_cv'`, [B.id]);
  ok('no rescore is queued for a student with nothing parsed', noParse2.rows[0].n === noParse.rows[0].n,
    `${noParse.rows[0].n} then ${noParse2.rows[0].n}`);

  console.log('\ncleanup');
  for (const u of users) await admin(`/auth/v1/admin/users/${u.id}`, { method: 'DELETE' });
  const left = await pg.query('select count(*)::int n from public.cv_scores where user_id = any($1)', [[A.id, B.id]]);
  ok('scores are removed with the account', left.rows[0].n === 0, `${left.rows[0].n} left`);

  await pg.end();
  console.log(`\n${pass} passed, ${fail} failed.`);
  process.exit(fail === 0 ? 0 : 1);
})().catch(e => { console.error('ERROR:', e.message); process.exit(1); });
