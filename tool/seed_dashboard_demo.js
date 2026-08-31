#!/usr/bin/env node
/* Creates a demo student whose dashboard actually has something on it.

   Every card on the home screen needs different data to be worth looking at —
   a streak needs consecutive days, a sparkline needs weeks of history, the
   timeline needs three kinds of date. Tapping all of that in by hand takes
   twenty minutes and produces something slightly different every time, which
   makes a design review of the dashboard nearly impossible.

   Prints the credentials as JSON. Delete the account with
   tool/cleanup_test_users.js when you are done with it.

     node tool/seed_dashboard_demo.js [launch|prove|build|explore]
*/
const path = require('path');
const { Client } = require('pg');
require('dotenv').config({ path: path.join(__dirname, '..', 'supabase', '.env'), quiet: true });

const URL = process.env.SUPABASE_URL, SVC = process.env.SUPABASE_SERVICE_ROLE_KEY;
const admin = (p, o = {}) => fetch(`${URL}${p}`, {
  ...o, headers: { apikey: SVC, Authorization: `Bearer ${SVC}`, 'Content-Type': 'application/json', ...(o.headers || {}) }
});

const mode = process.argv[2] ?? 'launch';
const YEAR = { explore: 1, build: 2, prove: 3, launch: 4 }[mode];
if (!YEAR) throw new Error(`unknown mode "${mode}" — use launch, prove, build or explore`);

/* Dhaka days, because that is what the feed counts. */
const day = (n) => {
  const d = new Date(Date.now() + 6 * 3600 * 1000 + n * 86400000);
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate())).toISOString().slice(0, 10);
};
const stamp = (n) => `${day(n)}T14:00:00+06:00`;

(async () => {
  const pg = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await pg.connect();

  const email = `demo_dash_${Date.now()}@tack.test`;
  const password = 'Demo-passw0rd!';
  const user = await admin('/auth/v1/admin/users', {
    method: 'POST',
    body: JSON.stringify({ email, password, email_confirm: true, user_metadata: { full_name: 'Nusrat Jahan' } }),
  }).then((r) => r.json());
  if (!user.id) throw new Error(`could not create user: ${JSON.stringify(user)}`);
  const uid = user.id;

  const one = async (q, p = []) => (await pg.query(q, p)).rows[0];

  const bd = await one(`select id from public.countries where iso2='BD'`);
  const dhaka = await one(`select id from public.cities where name='Dhaka' limit 1`);

  // ---- the profile. mode is a generated column, so it follows from these ----
  await pg.query(
    `update public.profiles set
       full_name='Nusrat Jahan', country_id=$1, city_id=$2, phone='+8801712345678',
       education_stage='bachelors', year_of_study=$3, years_total=4,
       expected_graduation=$4, target_role='Data analyst',
       onboarding_step=99, onboarding_completed_at=now() - interval '60 days'
     where id=$5`,
    [bd.id, dhaka.id, YEAR, day(120), uid]);

  await pg.query(
    `insert into public.education
       (user_id, stage, institution_name, university_name, degree, field_of_study,
        start_year, graduation_year, cgpa, cgpa_scale, is_current)
     values ($1,'bachelors','BRAC University','BRAC University','BSc','Computer Science',
             2022, 2026, 3.62, 4.0, true)`, [uid]);

  // ---- a career path first: the skills are chosen against it ----
  const pathRow = await one(
    `select id, title from public.career_paths where is_active order by sort_order limit 1`);
  await pg.query(
    `insert into public.user_career_paths (user_id, path_id, is_primary, selected_at)
     values ($1,$2,true,$3)`, [uid, pathRow.id, stamp(-30)]);

  /* About a third of what the path asks for, plus a few from elsewhere. A
     student who holds none of their target's skills makes the fit card read
     0% and tells you nothing about how it looks in use. */
  const pathSkills = (await pg.query(
    `select s.id, s.name from public.career_path_skills cps
       join public.skills s on s.id = cps.skill_id
      where cps.path_id = $1 order by cps.importance, s.name`, [pathRow.id])).rows;
  const otherSkills = (await pg.query(
    `select id, name from public.skills where is_active
       and id <> all($1) order by name limit 3`,
    [pathSkills.map(s => s.id)])).rows;

  let held = 0;
  for (const s of [...pathSkills.filter((_, i) => i % 3 === 1), ...otherSkills]) {
    await pg.query(
      `insert into public.user_skills (user_id, skill_id, proficiency, source, created_at)
       values ($1,$2,$3,'self',$4) on conflict do nothing`,
      [uid, s.id, 3 + (s.name.length % 3), stamp(-1 * (s.name.length % 20) - 3)]);
    held++;
  }

  // ---- a bit of substance for the score ----
  await pg.query(
    `insert into public.projects (user_id, title, summary, created_at)
     values ($1,'Load-shedding tracker','A map of outages in Dhaka, built with Flutter and Supabase.',$2)`,
    [uid, stamp(-26)]);
  await pg.query(
    `insert into public.activities (user_id, category, title, organisation, created_at)
     values ($1,'club','Vice president','BRACU Computer Club',$2)`, [uid, stamp(-24)]);
  await pg.query(
    `insert into public.certifications (user_id, title, issuer, created_at)
     values ($1,'Google Data Analytics','Coursera',$2)`, [uid, stamp(-15)]);
  await pg.query(
    `insert into public.documents (user_id, type, title, storage_path, status, created_at)
     values ($1,'cv','Nusrat CV.pdf',$2,'ready',$3)`,
    [uid, `users/${uid}/cv/demo.pdf`, stamp(-18)]);

  // ---- the roadmap built from that path ----
  const roadmap = await one(
    `insert into public.roadmaps (user_id, path_id, title, origin)
     values ($1,$2,$3,'template') returning id`, [uid, pathRow.id, pathRow.title]);

  const templates = (await pg.query(
    `select id, order_index, title, description, unlock_text
       from public.career_path_milestones where path_id=$1 order by order_index limit 4`,
    [pathRow.id])).rows;

  const milestones = [];
  for (const t of templates) {
    milestones.push(await one(
      `insert into public.roadmap_milestones
         (roadmap_id, user_id, source_milestone_id, order_index, title, description, unlock_text, state)
       values ($1,$2,$3,$4,$5,$6,$7,$8) returning id, order_index, title`,
      [roadmap.id, uid, t.id, t.order_index, t.title, t.description, t.unlock_text,
       t.order_index === 0 ? 'completed' : t.order_index === 1 ? 'active' : 'locked']));
  }

  const tasksFor = (ms) => (pg.query(
    `select title, type, points, est_minutes, order_index
       from public.career_path_tasks where milestone_id=$1 order by order_index`,
    [templates.find(t => t.order_index === ms.order_index).id])).then(r => r.rows);

  /* Ticked on six of the last eight days, with a gap — a streak that is real
     and not suspiciously perfect. done_at is written in a second statement
     because stamp_task_done rewrites it on any insert or update of is_done. */
  const tickDays = [-7, -6, -5, -3, -2, -1, 0];
  let tick = 0;

  for (const ms of milestones) {
    const tasks = await tasksFor(ms);
    for (const t of tasks) {
      const done = ms.order_index === 0 || (ms.order_index === 1 && t.order_index < 2);
      const row = await one(
        `insert into public.roadmap_tasks
           (milestone_id, user_id, order_index, title, type, points, est_minutes, is_done, due_date, shared_with_roadmaps)
         values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) returning id`,
        [ms.id, uid, t.order_index, t.title, t.type, t.points ?? 5, t.est_minutes ?? 45, done,
         // one already late, one today, one tomorrow, the rest further out
         ms.order_index === 1 && t.order_index === 2 ? day(-2)
           : ms.order_index === 1 && t.order_index === 3 ? day(0)
           : ms.order_index === 1 && t.order_index === 4 ? day(1)
           : ms.order_index === 2 ? day(9 + t.order_index) : null,
         [roadmap.id]]);
      if (done && tick < tickDays.length) {
        await pg.query(`update public.roadmap_tasks set done_at=$2 where id=$1`,
          [row.id, stamp(tickDays[tick++])]);
      }
    }
  }

  // ---- applications, in a few statuses, with dates ahead ----
  const jobs = [
    ['bKash', 'Data analyst', 'applied', 'Send the portfolio', day(2), day(6)],
    ['Pathao', 'Junior analyst', 'interview', 'Prepare for the call', day(4), null],
    ['Grameenphone', 'Business analyst', 'assessment', 'Finish the take-home', day(1), day(3)],
    ['Chaldal', 'Data associate', 'saved', null, null, day(5)],
    ['ShopUp', 'Analytics intern', 'rejected', null, null, null],
  ];
  for (const [company, title, status, action, actionDate, closes] of jobs) {
    const job = await one(
      `insert into public.jobs (user_id, company_name, title, location, closes_at)
       values ($1,$2,$3,'Dhaka',$4) returning id`, [uid, company, title, closes]);
    await pg.query(
      `insert into public.job_applications
         (user_id, job_id, status, next_action, next_action_date, created_at, applied_at)
       values ($1,$2,$3,$4,$5,$6,$7)`,
      [uid, job.id, status, action, actionDate, stamp(-10 + jobs.indexOf(jobs.find(j => j[0] === company))),
       status === 'saved' ? null : stamp(-9)]);
  }

  // ---- a practice session, so interview_practice is not a flat zero ----
  await pg.query(
    `insert into public.interview_sessions
       (user_id, role, session_type, difficulty, question_count, started_at, completed_at, overall_score)
     values ($1,'Data analyst','behavioural','medium',5,$2,$2,7.5)`, [uid, stamp(-4)]);

  // ---- a few notifications, one unread ----
  await pg.query(
    `insert into public.notifications (user_id, type, title, body, created_at, read_at)
     values ($1,'cv_parsed','Your CV has been read','Six skills were added to your profile.',$2,$2),
            ($1,'score_changed','Your score went up','Finishing two steps added four points.',$3,null)`,
    [uid, stamp(-18), stamp(-1)]);

  /* Score history, so the twelve-week line has something to draw. Written
     directly rather than by recompute, which only ever writes "now". */
  const curve = [9, 12, 12, 16, 19, 21, 24, 27, 29, 31, 34];
  for (let i = 0; i < curve.length; i++) {
    await pg.query(
      `insert into public.readiness_scores (user_id, total, mode, components, delta, reason, computed_at)
       values ($1,$2,(select mode from public.profiles where id=$1),'{}'::jsonb,$3,'demo',$4)`,
      [uid, curve[i], i === 0 ? curve[0] : curve[i] - curve[i - 1], stamp(-7 * (curve.length - i))]);
  }
  // The real one, last, so the components on screen are genuine.
  await pg.query(`select public.recompute_readiness($1, 'demo')`, [uid]);

  /* Prove the dashboard actually builds for this student before printing
     credentials. The direct connection has no JWT, so auth.uid() has to be
     set the way PostgREST sets it. */
  await pg.query(`select set_config('request.jwt.claims', $1, false)`,
    [JSON.stringify({ sub: uid, role: 'authenticated' })]);
  const feed = await one(`select public.dashboard_feed() is not null as ok`);
  console.log(JSON.stringify({
    email, password, id: uid, mode,
    path: pathRow.title,
    skills_held: held,
    feed_builds: feed.ok,
  }, null, 2));
  await pg.end();
})().catch((e) => { console.error('ERROR:', e.message); process.exit(1); });
