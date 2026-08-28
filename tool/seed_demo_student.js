#!/usr/bin/env node
/* Creates a throwaway account parked on one onboarding step, so each screen of
   the new flow can be looked at without tapping through by hand. */
const path = require('path');
const { Client } = require('pg');
require('dotenv').config({ path: path.join(__dirname, '..', 'supabase', '.env'), quiet: true });

const URL = process.env.SUPABASE_URL, SVC = process.env.SUPABASE_SERVICE_ROLE_KEY;
const admin = (p, o = {}) => fetch(`${URL}${p}`, { ...o, headers: { apikey: SVC, Authorization: `Bearer ${SVC}`, 'Content-Type': 'application/json', ...(o.headers || {}) } });

const [, , stepArg, stageArg] = process.argv;
const step = Number(stepArg ?? 0);
const stage = stageArg ?? null;

(async () => {
  const pg = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await pg.connect();

  const email = `demo_${Date.now()}@tack.test`;
  const password = 'Demo-passw0rd!';
  const user = await admin('/auth/v1/admin/users', {
    method: 'POST',
    body: JSON.stringify({ email, password, email_confirm: true }),
  }).then((r) => r.json());

  const bd = (await pg.query(`select id from public.countries where iso2='BD'`)).rows[0].id;
  const dhaka = (await pg.query(`select id from public.cities where name='Dhaka'`)).rows[0].id;

  if (step >= 1) {
    await pg.query(
      `update public.profiles set full_name='Nusrat Jahan', country_id=$1, city_id=$2,
         phone='+8801712345678', onboarding_step=$3 where id=$4`,
      [bd, dhaka, step, user.id]);
  }
  if (stage) {
    await pg.query(`update public.profiles set education_stage=$1 where id=$2`, [stage, user.id]);
  }
  if (step >= 3 && stage === 'high_school') {
    await pg.query(
      `insert into public.education (user_id, stage, institution_name, class_level, current_grade, cgpa, cgpa_scale, is_current)
       values ($1,'high_school','Viqarunnisa Noon College','Class 11 (HSC first year)','A+',4.83,5.0,true)`,
      [user.id]);
  }

  console.log(JSON.stringify({ email, password, id: user.id }));
  await pg.end();
})();
