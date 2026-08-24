#!/usr/bin/env node
// Ad-hoc query runner: node tool/psql.js "select 1"
const path = require('path');
const { Client } = require('pg');
require('dotenv').config({ path: path.join(__dirname, '..', 'supabase', '.env'), quiet: true });
(async () => {
  const c = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await c.connect();
  const r = await c.query(process.argv[2]);
  console.log(Array.isArray(r) ? JSON.stringify(r.map(x => x.rows), null, 1) : JSON.stringify(r.rows, null, 1));
  await c.end();
})().catch(e => { console.error('ERROR:', e.message); process.exit(1); });
