#!/usr/bin/env node
/* Puts the cron secret and the functions base URL into Supabase Vault.
   Reads them from the gitignored supabase/.env and never prints a value. */
const path = require('path');
const { Client } = require('pg');
require('dotenv').config({ path: path.join(__dirname, '..', 'supabase', '.env'), quiet: true });

(async () => {
  const secret = process.env.CRON_SECRET;
  const url = `${process.env.SUPABASE_URL}/functions/v1`;
  if (!secret) throw new Error('CRON_SECRET is not set in supabase/.env');

  const client = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await client.connect();

  for (const [name, value] of [['tack_cron_secret', secret], ['tack_functions_url', url]]) {
    const existing = await client.query('select id from vault.secrets where name = $1', [name]);
    if (existing.rows.length) {
      await client.query('select vault.update_secret($1, $2, $3)', [existing.rows[0].id, value, name]);
      console.log(`  updated  ${name}`);
    } else {
      await client.query('select vault.create_secret($1, $2)', [value, name]);
      console.log(`  created  ${name}`);
    }
  }

  const check = await client.query(
    `select name, length(decrypted_secret) > 0 as has_value
     from vault.decrypted_secrets where name in ('tack_cron_secret','tack_functions_url') order by name`,
  );
  console.log(check.rows.map((r) => `  ${r.name}: ${r.has_value ? 'set' : 'EMPTY'}`).join('\n'));

  await client.end();
})().catch((e) => { console.error('ERROR:', e.message); process.exit(1); });
