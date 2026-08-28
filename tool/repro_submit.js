const path = require('path');
const { Client } = require('pg');
require('dotenv').config({ path: path.join(__dirname, '..', 'supabase', '.env'), quiet: true });

const URL = process.env.SUPABASE_URL, ANON = process.env.SUPABASE_ANON_KEY, SVC = process.env.SUPABASE_SERVICE_ROLE_KEY;
const admin = (p, o = {}) => fetch(`${URL}${p}`, { ...o, headers: { apikey: SVC, Authorization: `Bearer ${SVC}`, 'Content-Type': 'application/json', ...(o.headers || {}) } });

(async () => {
  const pg = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await pg.connect();

  const email = `repro_${Date.now()}@tack.test`;
  const u = await admin('/auth/v1/admin/users', {
    method: 'POST', body: JSON.stringify({ email, password: 'Test-passw0rd!', email_confirm: true }),
  }).then((r) => r.json());
  const s = await fetch(`${URL}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: 'Test-passw0rd!' }),
  }).then((r) => r.json());

  const bd = (await pg.query(`select id from public.countries where iso2='BD'`)).rows[0].id;
  const dhaka = (await pg.query(`select id from public.cities where name='Dhaka'`)).rows[0].id;
  const uni = (await pg.query(`select id from public.universities limit 1`)).rows[0].id;
  const skill = (await pg.query(`select id from public.skills limit 1`)).rows[0].id;

  // Exactly the shape the app builds: every key the renderer writes, including
  // the __label companions and the __custom lists.
  const answers = {
    full_name: 'Shadman Sakib',
    country_id: bd, country_id__label: 'Bangladesh',
    city_id: dhaka, city_id__label: 'Dhaka',
    phone: '1789666154', dial_code: '+880',
    age_band: '19_22', age_band__label: '19 to 22',
    stage: 'graduated',
    institution_id: uni, institution_id__label: 'BUET', institution_name: 'BUET',
    degree: 'BSc',
    major: 'Computer Science',
    graduation: '2027-4', graduation__label: 'April 2027',
    graduation_year: 2027, graduation_month: 4,
    current_status: 'job_hunting', current_status__label: 'Looking for a job',
    gpa: '3.45',
    target_role: 'Backend developer', target_role__label: 'Backend developer',
    target_industry: ['Software and IT'],
    skills: [skill],
    interests__custom: ['Something typed'],
    custom_interests: ['Something typed'],
    experiences: [{ role: 'Intern', organisation: 'bKash' }],
  };

  const res = await fetch(`${URL}/rest/v1/rpc/submit_onboarding`, {
    method: 'POST',
    headers: { apikey: ANON, Authorization: `Bearer ${s.access_token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_answers: answers }),
  });

  console.log('status :', res.status);
  console.log('body   :', (await res.text()).slice(0, 400));

  const row = (await pg.query(
    `select education_stage::text stage, mode::text, dial_code,
            (select count(*)::int from public.education_profiles where user_id=$1) edu,
            (select count(*)::int from public.user_interests where user_id=$1) interests
       from public.profiles where id=$1`, [u.id])).rows[0];
  console.log('result :', JSON.stringify(row));

  await admin(`/auth/v1/admin/users/${u.id}`, { method: 'DELETE' });
  await pg.end();
})();
