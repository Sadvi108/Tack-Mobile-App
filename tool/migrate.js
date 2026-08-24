#!/usr/bin/env node
// Applies supabase/migrations/*.sql in filename order, tracked in public.schema_migrations.
// Reads DATABASE_URL from supabase/.env — never prints secret values.
const fs = require('fs');
const path = require('path');
const { Client } = require('pg');
require('dotenv').config({ path: path.join(__dirname, '..', 'supabase', '.env'), quiet: true });

const DIR = path.join(__dirname, '..', 'supabase', 'migrations');
const only = process.argv[2];

(async () => {
  if (!process.env.DATABASE_URL) throw new Error('DATABASE_URL missing from supabase/.env');
  const client = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await client.connect();
  await client.query(`create table if not exists public.schema_migrations (
    version text primary key,
    applied_at timestamptz not null default now()
  )`);
  const applied = new Set((await client.query('select version from public.schema_migrations')).rows.map(r => r.version));
  const files = fs.readdirSync(DIR).filter(f => f.endsWith('.sql')).sort();
  let ran = 0;
  for (const f of files) {
    if (only && !f.includes(only)) continue;
    if (applied.has(f)) { console.log(`  skip  ${f}`); continue; }
    const sql = fs.readFileSync(path.join(DIR, f), 'utf8');
    process.stdout.write(`  apply ${f} ... `);
    try {
      await client.query('begin');
      await client.query(sql);
      await client.query('insert into public.schema_migrations(version) values ($1)', [f]);
      await client.query('commit');
      console.log('ok');
      ran++;
    } catch (e) {
      await client.query('rollback');
      console.log('FAILED');
      console.error(`\n${f}: ${e.message}\n  ${e.position ? 'at char ' + e.position : ''}${e.hint ? '\n  hint: ' + e.hint : ''}`);
      await client.end();
      process.exit(1);
    }
  }
  console.log(`\n${ran} migration(s) applied, ${files.length} total on disk.`);
  await client.end();
})().catch(e => { console.error('ERROR:', e.message); process.exit(1); });
