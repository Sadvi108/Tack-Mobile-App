#!/usr/bin/env node
/* The coach's career-guide search against the live catalog: ten questions a
   student might ask, each of which should land on the right path; three that
   the catalog cannot answer, which must come back weak enough to refuse
   without calling a model; and the index staying in step with the catalog.
   Changes to the catalog run inside a transaction that is rolled back. */
const path = require('path');
const { Client } = require('pg');
require('dotenv').config({ path: path.join(__dirname, '..', 'supabase', '.env'), quiet: true });

let pass = 0, fail = 0;
const ok = (n, c, extra = '') => { c ? (pass++, console.log(`  PASS  ${n}`)) : (fail++, console.log(`  FAIL  ${n} ${extra}`)); };

// Mirrors GROUNDED in supabase/functions/_shared/coach/cited.ts.
const grounded = top => !!top && (top.title_hit || top.score >= 1);

(async () => {
  const pg = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await pg.connect();
  const search = async (q, k = 4) => (await pg.query(
    `select public.search_career_catalog($1, $2) as r`, [q, k])).rows[0].r;

  try {
    console.log('\n1. the index');
    const counts = (await pg.query(
      `select count(*)::int n, count(distinct path_id)::int paths from public.career_catalog_chunks`)).rows[0];
    ok('every active path is indexed', counts.paths === Number((await pg.query(
      `select count(*) from public.career_paths where is_active`)).rows[0].count), JSON.stringify(counts));
    ok('with several chunks each', counts.n > counts.paths * 4, JSON.stringify(counts));

    console.log('\n2. questions the guides answer');
    const cases = [
      ['What does a data analyst do day to day?', 'data-analyst'],
      ['How much does a frontend developer earn?', 'frontend-developer'],
      ['Is backend development a good fit for me if I like APIs?', 'backend-developer'],
      ['What salary can a graphic designer expect in Bangladesh?', 'graphic-designer'],
      ['What does an HR executive actually do?', 'hr-executive'],
      ['How do I become a digital marketer?', 'digital-marketer'],
      ['What does a QA engineer do every day?', 'qa-engineer'],
      ['Is accounting a good career for someone who likes numbers?', 'accountant'],
      ['What does an accountant earn?', 'accountant'],
      ['What does a business analyst do?', 'business-analyst'],
      ['Steps to become a content writer', 'content-writer'],
    ];
    for (const [q, slug] of cases) {
      const r = await search(q);
      ok(`"${q}" finds ${slug}`, r[0]?.path_slug === slug && grounded(r[0]),
        JSON.stringify(r[0] && { slug: r[0].path_slug, score: r[0].score, title_hit: r[0].title_hit }));
    }
    const r = await search('What does a data analyst do day to day?');
    ok('the evidence is quotable text with an id', r.every(c => /^[a-z0-9-]+:[a-z_]+:\d+$/.test(c.chunk_id) && c.text.length > 5),
      JSON.stringify(r.map(c => c.chunk_id)));
    ok('at most four chunks by default', r.length <= 4);

    console.log('\n3. questions they cannot');
    for (const q of [
      'How do I become an astronaut?',
      'What is the salary of a marine biologist?',
      'Tell me about deep sea welding as a job',
    ]) {
      const top = (await search(q))[0];
      ok(`"${q}" is too weak to answer from`, !grounded(top),
        JSON.stringify(top && { slug: top.path_slug, score: top.score, title_hit: top.title_hit }));
    }
    ok('an empty question finds nothing', (await search('   ')).length === 0);
    ok('only stop words finds nothing', (await search('what is the a an')).length === 0);

    console.log('\n3b. everyday questions are not answered from a guide');
    for (const q of [
      'What does a good CV look like?',
      'How can I earn more points?',
      'Are internships paid?',
      'What are the steps to improve my CV?',
    ]) {
      const top = (await search(q))[0];
      ok(`"${q}" is left to the ordinary coach`, !grounded(top),
        JSON.stringify(top && { slug: top.path_slug, score: top.score, title_hit: top.title_hit }));
    }

    console.log('\n4. the index follows the catalog');
    await pg.query('begin');
    await pg.query(`update public.career_paths set summary = summary || ' Zebrafish husbandry.' where slug = 'data-analyst'`);
    const after = await search('zebrafish husbandry data analyst');
    await pg.query('rollback');
    ok('an edited summary is searchable at once', after[0]?.path_slug === 'data-analyst'
      && after[0]?.text.includes('Zebrafish'), JSON.stringify(after[0]));

    console.log('\n5. grants');
    const g = (await pg.query(
      `select has_function_privilege('authenticated', 'public.search_career_catalog(text,int)', 'execute') as a,
              has_function_privilege('anon', 'public.search_career_catalog(text,int)', 'execute') as b,
              has_table_privilege('authenticated', 'public.career_catalog_chunks', 'select') as c,
              exists (select 1 from information_schema.columns
                       where table_name = 'chat_messages' and column_name = 'citations') as d`)).rows[0];
    ok('search is for the coach endpoint only', !g.a && !g.b, JSON.stringify(g));
    ok('the index is not a table students query', !g.c);
    ok('chat messages can carry citations', g.d);

    console.log('\n6. a deleted conversation cannot be continued');
    const email = `cited_thread_${Date.now()}@tack.test`;
    const admin = (p, opt = {}) => fetch(`${process.env.SUPABASE_URL}${p}`, {
      ...opt, headers: { apikey: process.env.SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`, 'Content-Type': 'application/json' } });
    const user = await admin('/auth/v1/admin/users', { method: 'POST',
      body: JSON.stringify({ email, password: 'Test-passw0rd!', email_confirm: true }) }).then(r => r.json());
    try {
      const thread = (await pg.query(`insert into public.chat_threads (user_id, title, deleted_at)
        values ($1, 'old', now()) returning id`, [user.id])).rows[0].id;
      for (const type of ['coach_reply', 'coach_cited']) {
        await pg.query('begin');
        let error = null;
        try {
          await pg.query(`select public.enqueue_student_job($1, $2, $3::jsonb, $4)`,
            [user.id, type, JSON.stringify({ thread_id: thread, question: 'x' }), `${type}:verify:${Date.now()}`]);
        } catch (e) { error = e.message; }
        await pg.query('rollback');
        ok(`${type} into a deleted thread is refused`, /thread_not_owned/.test(error ?? ''), `${error}`);
      }
    } finally {
      await admin(`/auth/v1/admin/users/${user.id}`, { method: 'DELETE' });
    }
  } finally {
    await pg.query('rollback').catch(() => {});
    await pg.end();
  }

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error('\nERROR:', e.message); process.exit(1); });
