#!/usr/bin/env node
// SQL contract checks on temporary shadow tables inside a rolled-back
// transaction. Never applies migrations, changes cron, or creates users.
const fs = require('fs');
const path = require('path');
const { Client } = require('pg');
require('dotenv').config({ path: path.join(__dirname, '..', 'supabase', '.env'), quiet: true });
const assert = (condition, message) => {
  if (!condition) throw new Error(message);
  console.log(`PASS ${message}`);
};

(async () => {
  const pg = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await pg.connect();
  try {
    await pg.query('begin');
    await pg.query("set local statement_timeout='30s'");
    await pg.query('create temporary table job_listings (like public.job_listings including all)');
    // Include the new enum value in the isolated schema, without changing the
    // production enum. 0090 itself must commit before 0091 is deployed.
    const existing = (await pg.query("select unnest(enum_range(null::public.radar_source))::text as name")).rows.map(r => r.name);
    const labels = [...new Set([...existing, 'bdjobs', 'linkedin'])].map(s => `'${s.replaceAll("'", "''")}'`).join(',');
    await pg.query(`create type pg_temp.radar_source as enum (${labels})`);
    await pg.query('alter table pg_temp.job_listings alter column source type pg_temp.radar_source using source::text::pg_temp.radar_source');
    await pg.query('create temporary table job_listing_skills (like public.job_listing_skills including all)');
    await pg.query('create temporary table jobs_queue (like public.jobs_queue including all)');
    await pg.query('create function pg_temp.reindex_listings(uuid[]) returns int language sql as $$select 0$$');
    for (const migration of ['0091_bdjobs_import.sql', '0093_apify_job_sources.sql']) {
      let sql = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'migrations', migration), 'utf8');
      sql = sql.replace(/select cron\.schedule\('tack-bdjobs-import'[\s\S]*?'select public\.enqueue_bdjobs_import\(\)'\);/, '');
      // Shadow tables may clone columns already deployed in production.
      sql = sql.replace('add column workplace_known', 'add column if not exists workplace_known')
        .replace('add column expires_at', 'add column if not exists expires_at');
      for (const name of ['job_listings', 'job_listing_skills', 'jobs_queue', 'cache_bdjobs_page', 'cache_apify_job_page', 'enqueue_bdjobs_import', 'radar_feed', 'reindex_listings', 'radar_source']) {
        sql = sql.replaceAll(`public.${name}`, `pg_temp.${name}`);
      }
      await pg.query(sql);
    }
    await pg.query("select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000123',true)");
    const future = new Date(Date.now() + 86400000).toISOString();
    const now = new Date().toISOString();
    const older = new Date(Date.now() - 3600000).toISOString();
    const stale = new Date(Date.now() - 3 * 86400000).toISOString();
    const rows = Array.from({ length: 5 }, (_, i) => ({
      source: 'bdjobs', external_id: String(i + 1), title: `Zqbdtest vacancy ${i}`, company_name: 'Fixture employer',
      location: 'Fixturecity', is_remote: i === 2, workplace_known: i !== 0,
      url: `https://bdjobs.com/h/details/${i + 1}`, apply_url: `https://bdjobs.com/h/details/${i + 1}`,
      expires_at: i === 3 ? older : future, last_seen_at: i === 4 ? stale : now,
    }));
    const put = rows => pg.query('select pg_temp.cache_apify_job_page($1::jsonb) n', [JSON.stringify(rows)]);
    assert((await put(rows)).rows[0].n === 5, 'imports a valid page');
    await put([{ ...rows[0], title: 'Older snapshot', last_seen_at: older }]);
    assert((await pg.query("select title from pg_temp.job_listings where external_id='1'")).rows[0].title === rows[0].title, 'older snapshots cannot overwrite newer data');
    await put(rows);
    assert((await pg.query('select count(*)::int n from pg_temp.job_listings')).rows[0].n === 5, 'replayed imports do not duplicate postings');
    const feed = async remote => (await pg.query('select pg_temp.radar_feed($1,$2,$3,50,0,null) data', ['Zqbdtest', 'Fixturecity', remote])).rows[0].data;
    const all = await feed(null);
    assert(all.length === 3, 'feed excludes expired and stale Bdjobs rows');
    assert(all.find(r => r.title === rows[0].title)?.workplace_known === false, 'all-work feed preserves unknown workplace');
    assert((await feed(false)).length === 1, 'in-person filter excludes unknown and remote workplaces');
    assert((await feed(true)).length === 1, 'remote filter only includes known remote workplaces');
    await pg.query('select pg_temp.enqueue_bdjobs_import()');
    await pg.query('select pg_temp.enqueue_bdjobs_import()');
    assert((await pg.query('select count(*)::int n from pg_temp.jobs_queue')).rows[0].n === 1, 'hourly import enqueue is idempotent');
    const grants = (await pg.query("select has_function_privilege('anon','pg_temp.cache_apify_job_page(jsonb)','EXECUTE') a, has_function_privilege('authenticated','pg_temp.cache_apify_job_page(jsonb)','EXECUTE') u, has_function_privilege('service_role','pg_temp.cache_apify_job_page(jsonb)','EXECUTE') s")).rows[0];
    assert(!grants.a && !grants.u && grants.s, 'cache writes are service-only');
    const linked = { ...rows[0], source: 'linkedin', external_id: '42',
      title: 'Zqbdtest LinkedIn analyst', url: 'https://www.linkedin.com/jobs/view/42',
      apply_url: 'https://www.linkedin.com/jobs/view/42' };
    await put([linked]);
    assert((await feed(null)).some(row => row.source === 'linkedin'), 'fresh LinkedIn jobs appear in the same feed');
    await put([{ ...linked, external_id: '43', last_seen_at: stale }]);
    assert((await feed(null)).filter(row => row.source === 'linkedin').length === 1, 'stale LinkedIn jobs are hidden');
    await put([{ ...rows[0], title: 'Zqbdtest from another Actor' }]);
    assert((await pg.query("select count(*)::int n from pg_temp.job_listings where source='bdjobs' and external_id='1'")).rows[0].n === 1, 'different Actor imports keep one Bdjobs identity');
    await pg.query('savepoint invalid_source');
    let refused = false;
    try { await put([{ ...rows[0], source: 'aijobs' }]); } catch { refused = true; }
    await pg.query('rollback to savepoint invalid_source');
    assert(refused, 'shared importer refuses sources outside its allow-list');
    console.log('SQL checks complete; rolling back all temporary objects and fixtures.');
  } finally {
    await pg.query('rollback');
    await pg.end();
  }
})().catch(error => { console.error('FAIL', error.message); process.exitCode = 1; });
