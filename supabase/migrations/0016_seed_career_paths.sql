-- The ten seeded career paths, their skill requirements and template roadmaps.
-- Hand-written for the Bangladeshi entry-level market: this is the default
-- product path, not an AI fallback. Regenerate with:
--   python3 supabase/seed/career_paths.py

insert into public.career_paths
  (slug, title, summary, category, salary_min_bdt, salary_max_bdt, months_to_job_ready, demand_level, day_to_day, good_fit_if, sort_order)
values ('frontend-developer', 'Frontend developer', 'You build the part of a website or app that people actually see and click. Strong demand in Dhaka, and the fastest software path to a first job because your work is visible.', 'software', 25000, 45000, 8, 'very high', array['Turn a design into working screens','Fix layout and browser bugs','Connect screens to an API','Review teammates'' code']::text[], array['You like seeing a result immediately','You have an eye for detail','You would rather build than analyse']::text[], 1)
on conflict (slug) do update set
  title = excluded.title, summary = excluded.summary, category = excluded.category,
  salary_min_bdt = excluded.salary_min_bdt, salary_max_bdt = excluded.salary_max_bdt,
  months_to_job_ready = excluded.months_to_job_ready, demand_level = excluded.demand_level,
  day_to_day = excluded.day_to_day, good_fit_if = excluded.good_fit_if, sort_order = excluded.sort_order;

insert into public.career_path_skills (path_id, skill_id, importance)
select cp.id, s.id, 'core'::skill_importance
from public.career_paths cp join public.skills s on s.slug in ('html','css','javascript','react','git','responsive-design')
where cp.slug = 'frontend-developer'
on conflict (path_id, skill_id) do update set importance = excluded.importance;

insert into public.career_path_skills (path_id, skill_id, importance)
select cp.id, s.id, 'important'::skill_importance
from public.career_paths cp join public.skills s on s.slug in ('typescript','tailwind-css','rest-apis','web-accessibility','browser-devtools','figma')
where cp.slug = 'frontend-developer'
on conflict (path_id, skill_id) do update set importance = excluded.importance;

insert into public.career_path_skills (path_id, skill_id, importance)
select cp.id, s.id, 'nice'::skill_importance
from public.career_paths cp join public.skills s on s.slug in ('next-js','redux','web-performance','unit-testing')
where cp.slug = 'frontend-developer'
on conflict (path_id, skill_id) do update set importance = excluded.importance;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 0, 'Learn the three basics', 'HTML, CSS and JavaScript are the whole foundation. Everything after this is a shortcut on top of them.', null, 1
from public.career_paths cp where cp.slug = 'frontend-developer'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Build a static page from scratch, no framework', 'project'::task_type, 4, 240, (select id from public.skills where slug = 'html')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'frontend-developer' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Learn CSS flexbox and grid properly', 'skill'::task_type, 3, 180, (select id from public.skills where slug = 'css')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'frontend-developer' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Write 20 small JavaScript exercises', 'skill'::task_type, 3, 300, (select id from public.skills where slug = 'javascript')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'frontend-developer' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Make one page work on a 360px phone screen', 'skill'::task_type, 3, 120, (select id from public.skills where slug = 'responsive-design')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'frontend-developer' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Put your code on GitHub', 'skill'::task_type, 2, 60, (select id from public.skills where slug = 'git')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'frontend-developer' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 5, 'Add your first three skills to your Tack profile', 'skill'::task_type, 2, 10, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'frontend-developer' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 1, 'Build with a framework', 'One framework, learnt well, beats three learnt badly. React has the most job listings in Bangladesh.', 'Finish the three basics first', 3
from public.career_paths cp where cp.slug = 'frontend-developer'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Learn React components, props and state', 'skill'::task_type, 4, 420, (select id from public.skills where slug = 'react')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'frontend-developer' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Build a to-do app that saves data', 'project'::task_type, 5, 480, (select id from public.skills where slug = 'react')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'frontend-developer' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Learn to fetch data from a public API', 'skill'::task_type, 3, 180, (select id from public.skills where slug = 'rest-apis')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'frontend-developer' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Rebuild an existing Bangladeshi site''s homepage', 'project'::task_type, 5, 600, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'frontend-developer' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Learn TypeScript basics', 'skill'::task_type, 3, 300, (select id from public.skills where slug = 'typescript')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'frontend-developer' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 5, 'Deploy one project to a live URL', 'project'::task_type, 4, 120, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'frontend-developer' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 2, 'Make it look designed', 'The gap between a junior and a hireable junior is usually visual polish and accessibility.', 'Ship one framework project first', 4
from public.career_paths cp where cp.slug = 'frontend-developer'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Learn Figma well enough to read a handoff', 'skill'::task_type, 3, 180, (select id from public.skills where slug = 'figma')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'frontend-developer' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Rebuild one project from a real Figma file', 'project'::task_type, 5, 480, (select id from public.skills where slug = 'figma')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'frontend-developer' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Fix the accessibility issues in your best project', 'skill'::task_type, 4, 180, (select id from public.skills where slug = 'web-accessibility')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'frontend-developer' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Get the page loading in under 3 seconds on 3G', 'skill'::task_type, 4, 180, (select id from public.skills where slug = 'web-performance')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'frontend-developer' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Ask two people to use your app and write down what confused them', 'networking'::task_type, 3, 90, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'frontend-developer' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 3, 'Prove it in public', 'Employers in Dhaka hire from what they can see. Three good projects beat a long CV.', 'Have three deployed projects', 6
from public.career_paths cp where cp.slug = 'frontend-developer'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Write a README for each project explaining the problem', 'cv'::task_type, 3, 180, (select id from public.skills where slug = 'technical-writing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'frontend-developer' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Publish a portfolio site with your three projects', 'project'::task_type, 5, 480, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'frontend-developer' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Write one post about something you debugged', 'networking'::task_type, 3, 120, (select id from public.skills where slug = 'blog-writing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'frontend-developer' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Complete a free frontend certificate', 'certificate'::task_type, 4, 900, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'frontend-developer' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Add every project to your Tack profile', 'project'::task_type, 2, 20, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'frontend-developer' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 5, 'Connect with 10 developers on LinkedIn', 'networking'::task_type, 3, 60, (select id from public.skills where slug = 'linkedin-marketing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'frontend-developer' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 4, 'Apply and interview', 'Applying is a numbers game with a skill attached. Both parts need practice.', 'Have a portfolio site live', 7
from public.career_paths cp where cp.slug = 'frontend-developer'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Write a one-page CV aimed at frontend roles', 'cv'::task_type, 5, 180, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'frontend-developer' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Get your CV reviewed by someone working in the field', 'networking'::task_type, 4, 60, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'frontend-developer' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Practise 10 JavaScript interview questions', 'application'::task_type, 4, 300, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'frontend-developer' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Do three mock interviews in Tack', 'application'::task_type, 4, 120, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'frontend-developer' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Apply to 10 junior frontend roles', 'application'::task_type, 6, 240, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'frontend-developer' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 5, 'Follow up on every application after a week', 'application'::task_type, 3, 60, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'frontend-developer' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_paths
  (slug, title, summary, category, salary_min_bdt, salary_max_bdt, months_to_job_ready, demand_level, day_to_day, good_fit_if, sort_order)
values ('backend-developer', 'Backend developer', 'You build the part nobody sees: the database, the API, the logic that keeps data correct. Pays slightly more than frontend at entry level and stays in demand longer.', 'software', 28000, 50000, 10, 'very high', array['Write and test API endpoints','Design database tables','Fix production bugs','Make slow queries fast']::text[], array['You like systems and rules','You enjoy puzzles more than pixels','You are patient with detail']::text[], 2)
on conflict (slug) do update set
  title = excluded.title, summary = excluded.summary, category = excluded.category,
  salary_min_bdt = excluded.salary_min_bdt, salary_max_bdt = excluded.salary_max_bdt,
  months_to_job_ready = excluded.months_to_job_ready, demand_level = excluded.demand_level,
  day_to_day = excluded.day_to_day, good_fit_if = excluded.good_fit_if, sort_order = excluded.sort_order;

insert into public.career_path_skills (path_id, skill_id, importance)
select cp.id, s.id, 'core'::skill_importance
from public.career_paths cp join public.skills s on s.slug in ('python','sql','rest-apis','git','postgresql','data-structures')
where cp.slug = 'backend-developer'
on conflict (path_id, skill_id) do update set importance = excluded.importance;

insert into public.career_path_skills (path_id, skill_id, importance)
select cp.id, s.id, 'important'::skill_importance
from public.career_paths cp join public.skills s on s.slug in ('node-js','django','authentication-flows','docker','linux-administration','query-optimisation')
where cp.slug = 'backend-developer'
on conflict (path_id, skill_id) do update set importance = excluded.importance;

insert into public.career_path_skills (path_id, skill_id, importance)
select cp.id, s.id, 'nice'::skill_importance
from public.career_paths cp join public.skills s on s.slug in ('redis','aws','graphql','kubernetes')
where cp.slug = 'backend-developer'
on conflict (path_id, skill_id) do update set importance = excluded.importance;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 0, 'One language, properly', 'Pick Python or JavaScript and go deep. Switching languages early is the most common way to waste six months.', null, 1
from public.career_paths cp where cp.slug = 'backend-developer'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Choose one language and stick to it for six months', 'skill'::task_type, 2, 15, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'backend-developer' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Learn functions, loops and error handling', 'skill'::task_type, 3, 300, (select id from public.skills where slug = 'python')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'backend-developer' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Learn lists, dictionaries and sets', 'skill'::task_type, 3, 240, (select id from public.skills where slug = 'data-structures')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'backend-developer' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Solve 30 beginner algorithm problems', 'skill'::task_type, 4, 600, (select id from public.skills where slug = 'algorithms')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'backend-developer' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Learn Git and commit every day for a week', 'skill'::task_type, 3, 120, (select id from public.skills where slug = 'git')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'backend-developer' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 5, 'Write your first script that reads and writes a file', 'project'::task_type, 3, 120, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'backend-developer' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 1, 'Databases before frameworks', 'Most junior backend failures are database failures. Learn SQL before you learn an ORM.', 'Finish one language first', 3
from public.career_paths cp where cp.slug = 'backend-developer'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Learn SELECT, JOIN and GROUP BY until they are automatic', 'skill'::task_type, 4, 360, (select id from public.skills where slug = 'sql')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'backend-developer' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Design tables for a library system on paper', 'project'::task_type, 4, 180, (select id from public.skills where slug = 'database-design')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'backend-developer' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Learn primary keys, foreign keys and indexes', 'skill'::task_type, 4, 240, (select id from public.skills where slug = 'indexing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'backend-developer' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Install PostgreSQL and load real data into it', 'skill'::task_type, 3, 120, (select id from public.skills where slug = 'postgresql')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'backend-developer' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Write 15 queries against your own data', 'skill'::task_type, 3, 240, (select id from public.skills where slug = 'sql')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'backend-developer' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 2, 'Build a real API', 'An API you can demo is worth more than any certificate.', 'Be comfortable with SQL', 4
from public.career_paths cp where cp.slug = 'backend-developer'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Learn one web framework end to end', 'skill'::task_type, 5, 600, (select id from public.skills where slug = 'django')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'backend-developer' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Build a CRUD API with authentication', 'project'::task_type, 6, 720, (select id from public.skills where slug = 'authentication-flows')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'backend-developer' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Write tests for every endpoint', 'skill'::task_type, 4, 300, (select id from public.skills where slug = 'unit-testing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'backend-developer' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Add pagination and input validation', 'skill'::task_type, 3, 180, (select id from public.skills where slug = 'api-design')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'backend-developer' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Document your API so someone else can use it', 'cv'::task_type, 3, 120, (select id from public.skills where slug = 'technical-writing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'backend-developer' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 5, 'Deploy it and keep it running for a month', 'project'::task_type, 5, 240, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'backend-developer' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 3, 'Learn how it runs in production', 'Knowing Docker and Linux is what separates a student project from a job-ready one.', 'Have one API deployed', 6
from public.career_paths cp where cp.slug = 'backend-developer'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Learn Linux command line basics', 'skill'::task_type, 3, 240, (select id from public.skills where slug = 'linux-administration')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'backend-developer' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Containerise your API with Docker', 'skill'::task_type, 4, 240, (select id from public.skills where slug = 'docker')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'backend-developer' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Set up CI that runs your tests on every push', 'skill'::task_type, 4, 180, (select id from public.skills where slug = 'ci-cd')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'backend-developer' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Add logging and read your own logs after a bug', 'skill'::task_type, 3, 120, (select id from public.skills where slug = 'logging')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'backend-developer' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Make one slow query fast and write down how', 'project'::task_type, 4, 180, (select id from public.skills where slug = 'query-optimisation')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'backend-developer' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 5, 'Complete a cloud fundamentals certificate', 'certificate'::task_type, 4, 900, (select id from public.skills where slug = 'aws')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'backend-developer' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 4, 'Apply and interview', 'Backend interviews test SQL and problem solving far more than framework trivia.', 'Have a deployed, documented API', 8
from public.career_paths cp where cp.slug = 'backend-developer'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Write a CV that leads with your API project', 'cv'::task_type, 5, 180, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'backend-developer' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Practise 20 SQL interview questions', 'application'::task_type, 5, 300, (select id from public.skills where slug = 'sql')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'backend-developer' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Practise explaining your database design out loud', 'application'::task_type, 4, 120, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'backend-developer' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Do three mock technical interviews in Tack', 'application'::task_type, 4, 150, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'backend-developer' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Apply to 10 junior backend roles', 'application'::task_type, 6, 240, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'backend-developer' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 5, 'Join two Bangladeshi developer communities', 'networking'::task_type, 3, 60, (select id from public.skills where slug = 'networking')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'backend-developer' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_paths
  (slug, title, summary, category, salary_min_bdt, salary_max_bdt, months_to_job_ready, demand_level, day_to_day, good_fit_if, sort_order)
values ('data-analyst', 'Data analyst', 'You turn messy company data into a number a manager can act on. Excel and SQL get you hired; Python and dashboards get you promoted.', 'data', 25000, 45000, 7, 'high', array['Pull data with SQL','Clean it and check it is right','Build a dashboard','Explain what changed and why']::text[], array['You like finding the story in numbers','You are careful and sceptical','You can explain things simply']::text[], 3)
on conflict (slug) do update set
  title = excluded.title, summary = excluded.summary, category = excluded.category,
  salary_min_bdt = excluded.salary_min_bdt, salary_max_bdt = excluded.salary_max_bdt,
  months_to_job_ready = excluded.months_to_job_ready, demand_level = excluded.demand_level,
  day_to_day = excluded.day_to_day, good_fit_if = excluded.good_fit_if, sort_order = excluded.sort_order;

insert into public.career_path_skills (path_id, skill_id, importance)
select cp.id, s.id, 'core'::skill_importance
from public.career_paths cp join public.skills s on s.slug in ('excel','sql','data-cleaning','data-visualisation','statistics')
where cp.slug = 'data-analyst'
on conflict (path_id, skill_id) do update set importance = excluded.importance;

insert into public.career_path_skills (path_id, skill_id, importance)
select cp.id, s.id, 'important'::skill_importance
from public.career_paths cp join public.skills s on s.slug in ('power-bi','python','pandas','dashboard-design','data-storytelling','kpi-definition')
where cp.slug = 'data-analyst'
on conflict (path_id, skill_id) do update set importance = excluded.importance;

insert into public.career_path_skills (path_id, skill_id, importance)
select cp.id, s.id, 'nice'::skill_importance
from public.career_paths cp join public.skills s on s.slug in ('tableau','a-b-testing','business-intelligence','regression-analysis')
where cp.slug = 'data-analyst'
on conflict (path_id, skill_id) do update set importance = excluded.importance;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 0, 'Own Excel first', 'Almost every analyst job in Bangladesh still runs on Excel. Being genuinely fast in it is a hireable skill on its own.', null, 1
from public.career_paths cp where cp.slug = 'data-analyst'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Learn VLOOKUP, XLOOKUP and INDEX/MATCH', 'skill'::task_type, 3, 180, (select id from public.skills where slug = 'advanced-excel')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'data-analyst' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Learn pivot tables until they are automatic', 'skill'::task_type, 4, 180, (select id from public.skills where slug = 'excel')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'data-analyst' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Clean one messy public dataset by hand', 'project'::task_type, 4, 240, (select id from public.skills where slug = 'data-cleaning')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'data-analyst' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Build a monthly sales summary sheet', 'project'::task_type, 4, 240, (select id from public.skills where slug = 'excel')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'data-analyst' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Learn 10 keyboard shortcuts and stop using the mouse', 'skill'::task_type, 2, 60, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'data-analyst' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 1, 'SQL is the job', 'Every analyst posting asks for SQL. It is also the fastest of these skills to learn.', 'Be comfortable in Excel', 2
from public.career_paths cp where cp.slug = 'data-analyst'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Learn SELECT, WHERE and ORDER BY', 'skill'::task_type, 3, 180, (select id from public.skills where slug = 'sql')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'data-analyst' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Learn JOIN properly, all four kinds', 'skill'::task_type, 4, 240, (select id from public.skills where slug = 'sql')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'data-analyst' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Learn GROUP BY and window functions', 'skill'::task_type, 4, 300, (select id from public.skills where slug = 'sql')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'data-analyst' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Answer 25 business questions with SQL on a public database', 'project'::task_type, 5, 480, (select id from public.skills where slug = 'sql')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'data-analyst' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Learn how to check your own query is right', 'skill'::task_type, 3, 120, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'data-analyst' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 2, 'Make it visible', 'A correct number nobody looks at has no value. Dashboards are how analysts get noticed.', 'Be comfortable with JOINs', 4
from public.career_paths cp where cp.slug = 'data-analyst'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Learn Power BI or Looker Studio end to end', 'skill'::task_type, 5, 420, (select id from public.skills where slug = 'power-bi')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'data-analyst' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Build a dashboard from your SQL project', 'project'::task_type, 5, 360, (select id from public.skills where slug = 'dashboard-design')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'data-analyst' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Learn which chart to use for which question', 'skill'::task_type, 3, 120, (select id from public.skills where slug = 'data-visualisation')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'data-analyst' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Define three KPIs for a business you know', 'project'::task_type, 4, 120, (select id from public.skills where slug = 'kpi-definition')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'data-analyst' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Present your dashboard to someone non-technical', 'networking'::task_type, 4, 60, (select id from public.skills where slug = 'presentation-skills')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'data-analyst' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 3, 'Add Python and statistics', 'This is the step that moves you from reporting to analysis.', 'Have one dashboard built', 5
from public.career_paths cp where cp.slug = 'data-analyst'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Learn pandas for loading and cleaning data', 'skill'::task_type, 4, 360, (select id from public.skills where slug = 'pandas')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'data-analyst' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Redo one Excel analysis entirely in Python', 'project'::task_type, 5, 300, (select id from public.skills where slug = 'python')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'data-analyst' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Learn mean, median, distribution and outliers', 'skill'::task_type, 3, 180, (select id from public.skills where slug = 'statistics')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'data-analyst' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Learn what a p-value actually means', 'skill'::task_type, 3, 120, (select id from public.skills where slug = 'hypothesis-testing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'data-analyst' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Complete a data analytics certificate', 'certificate'::task_type, 4, 1200, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'data-analyst' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 5, 'Write up one analysis as a short report', 'cv'::task_type, 4, 180, (select id from public.skills where slug = 'report-writing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'data-analyst' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 4, 'Apply and interview', 'Analyst interviews are a SQL test plus a case question. Both are practisable.', 'Have a written-up analysis', 6
from public.career_paths cp where cp.slug = 'data-analyst'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Build a portfolio page with three analyses', 'project'::task_type, 5, 360, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'data-analyst' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Write a CV that names the tools in the job ad', 'cv'::task_type, 5, 180, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'data-analyst' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Practise 20 SQL questions under time pressure', 'application'::task_type, 5, 300, (select id from public.skills where slug = 'sql')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'data-analyst' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Practise one business case out loud', 'application'::task_type, 4, 120, (select id from public.skills where slug = 'analytical-thinking')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'data-analyst' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Apply to 10 analyst and MIS roles', 'application'::task_type, 6, 240, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'data-analyst' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 5, 'Do three mock interviews in Tack', 'application'::task_type, 4, 150, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'data-analyst' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_paths
  (slug, title, summary, category, salary_min_bdt, salary_max_bdt, months_to_job_ready, demand_level, day_to_day, good_fit_if, sort_order)
values ('digital-marketer', 'Digital marketer', 'You get a business in front of the right people online and prove it worked. The lowest barrier to entry of the ten paths, and the easiest to start earning from freelancing.', 'marketing', 20000, 35000, 5, 'high', array['Plan and write posts','Run and adjust paid ads','Read the analytics','Report what worked']::text[], array['You are curious about why people buy','You write clearly','You are comfortable being measured']::text[], 4)
on conflict (slug) do update set
  title = excluded.title, summary = excluded.summary, category = excluded.category,
  salary_min_bdt = excluded.salary_min_bdt, salary_max_bdt = excluded.salary_max_bdt,
  months_to_job_ready = excluded.months_to_job_ready, demand_level = excluded.demand_level,
  day_to_day = excluded.day_to_day, good_fit_if = excluded.good_fit_if, sort_order = excluded.sort_order;

insert into public.career_path_skills (path_id, skill_id, importance)
select cp.id, s.id, 'core'::skill_importance
from public.career_paths cp join public.skills s on s.slug in ('social-media-marketing','facebook-ads','content-writing','google-analytics','copywriting')
where cp.slug = 'digital-marketer'
on conflict (path_id, skill_id) do update set importance = excluded.importance;

insert into public.career_path_skills (path_id, skill_id, importance)
select cp.id, s.id, 'important'::skill_importance
from public.career_paths cp join public.skills s on s.slug in ('search-engine-optimisation','google-ads','email-marketing','campaign-planning','canva','funnel-analysis')
where cp.slug = 'digital-marketer'
on conflict (path_id, skill_id) do update set importance = excluded.importance;

insert into public.career_path_skills (path_id, skill_id, importance)
select cp.id, s.id, 'nice'::skill_importance
from public.career_paths cp join public.skills s on s.slug in ('conversion-rate-optimisation','marketing-automation','influencer-marketing','e-commerce-marketing')
where cp.slug = 'digital-marketer'
on conflict (path_id, skill_id) do update set importance = excluded.importance;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 0, 'Learn the language', 'Marketing has a vocabulary. Reach, impressions, CTR, CPC, conversion — none of it is hard, all of it is assumed.', null, 1
from public.career_paths cp where cp.slug = 'digital-marketer'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Complete the free Meta Blueprint basics', 'certificate'::task_type, 4, 300, (select id from public.skills where slug = 'facebook-ads')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'digital-marketer' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Learn what CTR, CPC, CPM and ROAS mean', 'skill'::task_type, 3, 90, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'digital-marketer' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Learn Canva well enough to make a post in 10 minutes', 'skill'::task_type, 3, 180, (select id from public.skills where slug = 'canva')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'digital-marketer' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Write 10 captions for a shop you know', 'project'::task_type, 3, 120, (select id from public.skills where slug = 'copywriting')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'digital-marketer' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Set up a Meta Business Suite account', 'skill'::task_type, 2, 60, (select id from public.skills where slug = 'meta-business-suite')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'digital-marketer' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 1, 'Run something real', 'Nobody hires a marketer who has never spent money or grown an account.', 'Finish the basics', 2
from public.career_paths cp where cp.slug = 'digital-marketer'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Grow one real page from zero for 30 days', 'project'::task_type, 6, 900, (select id from public.skills where slug = 'social-media-marketing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'digital-marketer' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Run one ad campaign with your own small budget', 'project'::task_type, 6, 300, (select id from public.skills where slug = 'facebook-ads')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'digital-marketer' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Write down what you changed and what happened', 'cv'::task_type, 4, 120, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'digital-marketer' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Set up Google Analytics on any site', 'skill'::task_type, 4, 120, (select id from public.skills where slug = 'google-analytics')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'digital-marketer' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Learn to read an analytics report without guessing', 'skill'::task_type, 4, 180, (select id from public.skills where slug = 'funnel-analysis')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'digital-marketer' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 2, 'Learn to be found, not just seen', 'Paid reach stops when the money stops. SEO and email keep working.', 'Run one real campaign', 3
from public.career_paths cp where cp.slug = 'digital-marketer'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Learn keyword research', 'skill'::task_type, 4, 180, (select id from public.skills where slug = 'search-engine-optimisation')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'digital-marketer' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Write one blog post that ranks for a long-tail keyword', 'project'::task_type, 5, 300, (select id from public.skills where slug = 'blog-writing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'digital-marketer' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Set up an email list and send four emails', 'project'::task_type, 4, 240, (select id from public.skills where slug = 'email-marketing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'digital-marketer' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Learn basic on-page SEO', 'skill'::task_type, 3, 180, (select id from public.skills where slug = 'search-engine-optimisation')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'digital-marketer' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Audit one Bangladeshi business''s online presence', 'project'::task_type, 5, 240, (select id from public.skills where slug = 'competitor-analysis')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'digital-marketer' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 3, 'Get paid proof', 'One paying client is worth more than any certificate in this field.', 'Have one campaign with real numbers', 4
from public.career_paths cp where cp.slug = 'digital-marketer'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Find one small business to manage free for a month', 'networking'::task_type, 6, 600, (select id from public.skills where slug = 'client-management')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'digital-marketer' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Turn the result into a one-page case study', 'cv'::task_type, 5, 180, (select id from public.skills where slug = 'report-writing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'digital-marketer' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Complete the Google Digital Marketing certificate', 'certificate'::task_type, 4, 1200, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'digital-marketer' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Build a portfolio page with two case studies', 'project'::task_type, 5, 300, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'digital-marketer' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Ask the client for a written reference', 'networking'::task_type, 4, 30, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'digital-marketer' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 4, 'Apply and interview', 'Marketing interviews ask for numbers. Bring them.', 'Have one case study written', 5
from public.career_paths cp where cp.slug = 'digital-marketer'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Write a CV that leads with campaign results', 'cv'::task_type, 5, 180, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'digital-marketer' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Prepare three campaign stories with real numbers', 'application'::task_type, 5, 180, (select id from public.skills where slug = 'data-storytelling')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'digital-marketer' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Practise explaining a campaign that failed', 'application'::task_type, 4, 90, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'digital-marketer' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Apply to 10 marketing executive roles', 'application'::task_type, 6, 240, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'digital-marketer' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Do three mock interviews in Tack', 'application'::task_type, 4, 150, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'digital-marketer' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 5, 'Connect with 15 marketers on LinkedIn', 'networking'::task_type, 3, 90, (select id from public.skills where slug = 'linkedin-marketing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'digital-marketer' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_paths
  (slug, title, summary, category, salary_min_bdt, salary_max_bdt, months_to_job_ready, demand_level, day_to_day, good_fit_if, sort_order)
values ('hr-executive', 'HR executive', 'You handle hiring, records, payroll and the people problems that come with them. Steady demand at every company above about thirty staff, and a path that rewards organisation over technical skill.', 'business', 18000, 30000, 6, 'moderate', array['Screen CVs and schedule interviews','Keep employee records correct','Answer staff questions','Run onboarding for new joiners']::text[], array['People come to you with problems already','You are organised and discreet','You like structure and process']::text[], 5)
on conflict (slug) do update set
  title = excluded.title, summary = excluded.summary, category = excluded.category,
  salary_min_bdt = excluded.salary_min_bdt, salary_max_bdt = excluded.salary_max_bdt,
  months_to_job_ready = excluded.months_to_job_ready, demand_level = excluded.demand_level,
  day_to_day = excluded.day_to_day, good_fit_if = excluded.good_fit_if, sort_order = excluded.sort_order;

insert into public.career_path_skills (path_id, skill_id, importance)
select cp.id, s.id, 'core'::skill_importance
from public.career_paths cp join public.skills s on s.slug in ('recruitment','cv-screening','interviewing','communication','microsoft-word')
where cp.slug = 'hr-executive'
on conflict (path_id, skill_id) do update set importance = excluded.importance;

insert into public.career_path_skills (path_id, skill_id, importance)
select cp.id, s.id, 'important'::skill_importance
from public.career_paths cp join public.skills s on s.slug in ('onboarding','bangladesh-labour-act','payroll-administration','hris','employee-engagement','advanced-excel')
where cp.slug = 'hr-executive'
on conflict (path_id, skill_id) do update set importance = excluded.importance;

insert into public.career_path_skills (path_id, skill_id, importance)
select cp.id, s.id, 'nice'::skill_importance
from public.career_paths cp join public.skills s on s.slug in ('hr-analytics','performance-management','compensation-and-benefits','workforce-planning')
where cp.slug = 'hr-executive'
on conflict (path_id, skill_id) do update set importance = excluded.importance;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 0, 'Learn the legal floor', 'In Bangladesh the Labour Act is not optional background reading. Knowing it is a hiring signal on its own.', null, 1
from public.career_paths cp where cp.slug = 'hr-executive'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Read the Bangladesh Labour Act sections on leave and termination', 'skill'::task_type, 5, 300, (select id from public.skills where slug = 'bangladesh-labour-act')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'hr-executive' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Learn what a compliant appointment letter contains', 'skill'::task_type, 4, 120, (select id from public.skills where slug = 'hr-policy-writing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'hr-executive' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Learn the statutory leave types and entitlements', 'skill'::task_type, 4, 120, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'hr-executive' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Write a one-page summary in your own words', 'cv'::task_type, 3, 90, (select id from public.skills where slug = 'report-writing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'hr-executive' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Learn the basics of provident fund and gratuity', 'skill'::task_type, 3, 120, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'hr-executive' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 1, 'Learn recruitment properly', 'Recruitment is the part of HR that gets you hired first, because it is measurable.', 'Know the legal basics', 2
from public.career_paths cp where cp.slug = 'hr-executive'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Write a job description for a role you understand', 'project'::task_type, 4, 120, (select id from public.skills where slug = 'hr-policy-writing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'hr-executive' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Screen 30 real CVs and rank them with reasons', 'project'::task_type, 5, 240, (select id from public.skills where slug = 'cv-screening')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'hr-executive' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Learn structured interviewing and write 10 questions', 'skill'::task_type, 4, 180, (select id from public.skills where slug = 'interviewing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'hr-executive' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Learn to source candidates on LinkedIn and BDJobs', 'skill'::task_type, 4, 180, (select id from public.skills where slug = 'talent-sourcing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'hr-executive' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Practise an interview with a friend and get feedback', 'networking'::task_type, 4, 60, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'hr-executive' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 2, 'Get comfortable with the admin', 'HR runs on spreadsheets and records. Being fast and accurate here is most of the daily job.', 'Be able to run a screening round', 3
from public.career_paths cp where cp.slug = 'hr-executive'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Learn Excel to pivot-table level', 'skill'::task_type, 4, 240, (select id from public.skills where slug = 'advanced-excel')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'hr-executive' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Build an employee record template with leave tracking', 'project'::task_type, 5, 240, (select id from public.skills where slug = 'excel')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'hr-executive' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Learn how monthly payroll is actually calculated', 'skill'::task_type, 5, 240, (select id from public.skills where slug = 'payroll-administration')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'hr-executive' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Learn one HRIS tool', 'skill'::task_type, 4, 180, (select id from public.skills where slug = 'hris')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'hr-executive' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Draft an onboarding checklist for a new joiner', 'project'::task_type, 4, 120, (select id from public.skills where slug = 'onboarding')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'hr-executive' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 3, 'Get real exposure', 'HR is a trust job. A reference from a real workplace outweighs coursework.', 'Have the admin skills', 5
from public.career_paths cp where cp.slug = 'hr-executive'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Do an HR internship or volunteer at a campus club', 'project'::task_type, 6, 1200, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'hr-executive' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Run recruitment for one club or society position', 'project'::task_type, 5, 300, (select id from public.skills where slug = 'recruitment')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'hr-executive' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Complete an HR management certificate', 'certificate'::task_type, 4, 900, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'hr-executive' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Write a short policy document for a real group', 'project'::task_type, 4, 180, (select id from public.skills where slug = 'hr-policy-writing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'hr-executive' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Ask for a written reference', 'networking'::task_type, 4, 30, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'hr-executive' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 4, 'Apply and interview', 'HR interviews test judgement with scenarios. Practise answering them out loud.', 'Have real HR exposure', 6
from public.career_paths cp where cp.slug = 'hr-executive'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Write a CV that names the HR tools and laws you know', 'cv'::task_type, 5, 180, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'hr-executive' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Prepare answers to five difficult-employee scenarios', 'application'::task_type, 5, 180, (select id from public.skills where slug = 'conflict-resolution')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'hr-executive' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Practise explaining a confidentiality decision', 'application'::task_type, 4, 90, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'hr-executive' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Apply to 10 HR executive and HR intern roles', 'application'::task_type, 6, 240, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'hr-executive' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Do three mock interviews in Tack', 'application'::task_type, 4, 150, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'hr-executive' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_paths
  (slug, title, summary, category, salary_min_bdt, salary_max_bdt, months_to_job_ready, demand_level, day_to_day, good_fit_if, sort_order)
values ('business-analyst', 'Business analyst', 'You sit between the people who need something and the people who build it, and make sure both mean the same thing. The best-paying non-coding entry point in tech.', 'business', 30000, 55000, 9, 'high', array['Interview stakeholders about what they need','Write requirements down precisely','Draw the current and future process','Check what was built matches what was asked']::text[], array['You ask a lot of questions','You write clearly and precisely','You are comfortable disagreeing politely']::text[], 6)
on conflict (slug) do update set
  title = excluded.title, summary = excluded.summary, category = excluded.category,
  salary_min_bdt = excluded.salary_min_bdt, salary_max_bdt = excluded.salary_max_bdt,
  months_to_job_ready = excluded.months_to_job_ready, demand_level = excluded.demand_level,
  day_to_day = excluded.day_to_day, good_fit_if = excluded.good_fit_if, sort_order = excluded.sort_order;

insert into public.career_path_skills (path_id, skill_id, importance)
select cp.id, s.id, 'core'::skill_importance
from public.career_paths cp join public.skills s on s.slug in ('business-analysis','requirements-gathering','stakeholder-management','process-mapping','report-writing')
where cp.slug = 'business-analyst'
on conflict (path_id, skill_id) do update set importance = excluded.importance;

insert into public.career_path_skills (path_id, skill_id, importance)
select cp.id, s.id, 'important'::skill_importance
from public.career_paths cp join public.skills s on s.slug in ('sql','user-story-writing','agile','jira','gap-analysis','excel')
where cp.slug = 'business-analyst'
on conflict (path_id, skill_id) do update set importance = excluded.importance;

insert into public.career_path_skills (path_id, skill_id, importance)
select cp.id, s.id, 'nice'::skill_importance
from public.career_paths cp join public.skills s on s.slug in ('bpmn','product-roadmapping','data-visualisation','feasibility-study')
where cp.slug = 'business-analyst'
on conflict (path_id, skill_id) do update set importance = excluded.importance;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 0, 'Learn to ask and write', 'The whole job is turning a vague sentence into an unambiguous one. Practise on anything.', null, 1
from public.career_paths cp where cp.slug = 'business-analyst'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Learn the difference between a need, a requirement and a solution', 'skill'::task_type, 4, 120, (select id from public.skills where slug = 'business-analysis')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'business-analyst' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Write requirements for a campus process you know', 'project'::task_type, 5, 240, (select id from public.skills where slug = 'requirements-gathering')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'business-analyst' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Learn to write user stories with acceptance criteria', 'skill'::task_type, 4, 180, (select id from public.skills where slug = 'user-story-writing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'business-analyst' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Interview three people about one process and find the disagreement', 'project'::task_type, 5, 180, (select id from public.skills where slug = 'stakeholder-management')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'business-analyst' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Learn to write a one-page summary a busy person will read', 'skill'::task_type, 4, 120, (select id from public.skills where slug = 'report-writing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'business-analyst' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 1, 'Draw the process', 'A diagram settles arguments that a document cannot.', 'Be able to write a requirement', 3
from public.career_paths cp where cp.slug = 'business-analyst'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Learn flowcharts and swimlane diagrams', 'skill'::task_type, 4, 180, (select id from public.skills where slug = 'process-mapping')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'business-analyst' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Map one real process as-is', 'project'::task_type, 5, 240, (select id from public.skills where slug = 'process-mapping')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'business-analyst' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Map the same process as it should be', 'project'::task_type, 5, 240, (select id from public.skills where slug = 'gap-analysis')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'business-analyst' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Learn BPMN notation basics', 'skill'::task_type, 3, 180, (select id from public.skills where slug = 'bpmn')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'business-analyst' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Present both diagrams to the people who do the work', 'networking'::task_type, 4, 90, (select id from public.skills where slug = 'presentation-skills')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'business-analyst' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 2, 'Learn enough tech to be trusted', 'You do not need to code. You do need to understand what you are asking for.', 'Have one process mapped', 5
from public.career_paths cp where cp.slug = 'business-analyst'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Learn SQL to the level of JOIN and GROUP BY', 'skill'::task_type, 5, 360, (select id from public.skills where slug = 'sql')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'business-analyst' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Learn how an API works and what JSON looks like', 'skill'::task_type, 4, 180, (select id from public.skills where slug = 'rest-apis')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'business-analyst' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Learn database design basics', 'skill'::task_type, 4, 240, (select id from public.skills where slug = 'database-design')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'business-analyst' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Learn Agile, Scrum and where a BA fits', 'skill'::task_type, 4, 180, (select id from public.skills where slug = 'agile')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'business-analyst' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Run a backlog in Jira for a student project', 'project'::task_type, 4, 180, (select id from public.skills where slug = 'jira')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'business-analyst' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 3, 'Do it on a real project', 'BA is a judgement role and judgement needs a real project to show.', 'Have technical grounding', 7
from public.career_paths cp where cp.slug = 'business-analyst'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Act as BA for one student or club software project', 'project'::task_type, 6, 1200, (select id from public.skills where slug = 'business-analysis')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'business-analyst' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Produce a full requirements document for it', 'cv'::task_type, 5, 300, (select id from public.skills where slug = 'requirements-gathering')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'business-analyst' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Run one sprint planning session', 'project'::task_type, 4, 120, (select id from public.skills where slug = 'sprint-planning')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'business-analyst' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Complete a business analysis certificate', 'certificate'::task_type, 4, 900, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'business-analyst' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Write a case study of the project', 'cv'::task_type, 4, 180, (select id from public.skills where slug = 'report-writing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'business-analyst' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 4, 'Apply and interview', 'BA interviews are case-based. They want to hear you think, not recite.', 'Have one real BA project', 8
from public.career_paths cp where cp.slug = 'business-analyst'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Write a CV built around outcomes, not duties', 'cv'::task_type, 5, 180, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'business-analyst' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Prepare three requirement-conflict stories', 'application'::task_type, 5, 180, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'business-analyst' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Practise a live process-mapping exercise', 'application'::task_type, 5, 120, (select id from public.skills where slug = 'process-mapping')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'business-analyst' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Apply to 10 BA and product analyst roles', 'application'::task_type, 6, 240, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'business-analyst' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Do three mock interviews in Tack', 'application'::task_type, 4, 150, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'business-analyst' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_paths
  (slug, title, summary, category, salary_min_bdt, salary_max_bdt, months_to_job_ready, demand_level, day_to_day, good_fit_if, sort_order)
values ('graphic-designer', 'Graphic designer', 'You make things people look at: logos, posts, packaging, brand systems. Portfolio matters more than degree in this field, and freelancing can start in month two.', 'design', 18000, 32000, 6, 'moderate', array['Take a brief and sketch options','Build the artwork','Take feedback and revise','Prepare files for print or web']::text[], array['You notice when something is misaligned','You can take criticism of your work','You have taste and want to develop it']::text[], 7)
on conflict (slug) do update set
  title = excluded.title, summary = excluded.summary, category = excluded.category,
  salary_min_bdt = excluded.salary_min_bdt, salary_max_bdt = excluded.salary_max_bdt,
  months_to_job_ready = excluded.months_to_job_ready, demand_level = excluded.demand_level,
  day_to_day = excluded.day_to_day, good_fit_if = excluded.good_fit_if, sort_order = excluded.sort_order;

insert into public.career_path_skills (path_id, skill_id, importance)
select cp.id, s.id, 'core'::skill_importance
from public.career_paths cp join public.skills s on s.slug in ('adobe-illustrator','adobe-photoshop','typography','colour-theory','layout-design')
where cp.slug = 'graphic-designer'
on conflict (path_id, skill_id) do update set importance = excluded.importance;

insert into public.career_path_skills (path_id, skill_id, importance)
select cp.id, s.id, 'important'::skill_importance
from public.career_paths cp join public.skills s on s.slug in ('figma','logo-design','brand-identity','canva','print-design','iconography')
where cp.slug = 'graphic-designer'
on conflict (path_id, skill_id) do update set importance = excluded.importance;

insert into public.career_path_skills (path_id, skill_id, importance)
select cp.id, s.id, 'nice'::skill_importance
from public.career_paths cp join public.skills s on s.slug in ('motion-graphics','adobe-after-effects','packaging-design','design-systems')
where cp.slug = 'graphic-designer'
on conflict (path_id, skill_id) do update set importance = excluded.importance;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 0, 'Learn to see', 'Software is a week. Taste is the actual skill, and it is trainable.', null, 1
from public.career_paths cp where cp.slug = 'graphic-designer'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Learn typography: pairing, hierarchy, spacing', 'skill'::task_type, 5, 300, (select id from public.skills where slug = 'typography')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'graphic-designer' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Learn colour theory and build five palettes', 'skill'::task_type, 4, 240, (select id from public.skills where slug = 'colour-theory')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'graphic-designer' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Learn grid and alignment', 'skill'::task_type, 4, 180, (select id from public.skills where slug = 'layout-design')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'graphic-designer' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Collect 100 designs you admire and note why', 'project'::task_type, 4, 300, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'graphic-designer' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Redraw one existing logo pixel-accurately', 'project'::task_type, 4, 180, (select id from public.skills where slug = 'logo-design')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'graphic-designer' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 1, 'Learn the tools', 'Illustrator for vector, Photoshop for raster, Figma for screens. All three, at working level.', 'Understand type and colour', 2
from public.career_paths cp where cp.slug = 'graphic-designer'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Learn Adobe Illustrator to working level', 'skill'::task_type, 5, 600, (select id from public.skills where slug = 'adobe-illustrator')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'graphic-designer' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Learn Adobe Photoshop to working level', 'skill'::task_type, 4, 480, (select id from public.skills where slug = 'adobe-photoshop')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'graphic-designer' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Learn Figma for screen design', 'skill'::task_type, 4, 300, (select id from public.skills where slug = 'figma')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'graphic-designer' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Learn export settings for print and for web', 'skill'::task_type, 3, 120, (select id from public.skills where slug = 'print-design')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'graphic-designer' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Do 30 daily one-hour design exercises', 'project'::task_type, 5, 1800, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'graphic-designer' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 2, 'Build a portfolio with a point of view', 'Ten random posts is not a portfolio. Three complete projects is.', 'Be fluent in the tools', 4
from public.career_paths cp where cp.slug = 'graphic-designer'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Design a full brand identity for an invented business', 'project'::task_type, 6, 900, (select id from public.skills where slug = 'brand-identity')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'graphic-designer' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Design a 10-post social campaign that holds together', 'project'::task_type, 5, 600, (select id from public.skills where slug = 'social-media-marketing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'graphic-designer' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Design one packaging or print piece', 'project'::task_type, 5, 480, (select id from public.skills where slug = 'packaging-design')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'graphic-designer' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Write the thinking behind each project, not just the images', 'cv'::task_type, 4, 240, (select id from public.skills where slug = 'copywriting')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'graphic-designer' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Publish a portfolio on Behance or your own site', 'project'::task_type, 5, 300, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'graphic-designer' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 3, 'Work with real clients', 'Client work teaches revision, deadlines and scope — the parts college never covers.', 'Have three portfolio projects', 5
from public.career_paths cp where cp.slug = 'graphic-designer'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Take on three small paid or free client jobs', 'project'::task_type, 6, 900, (select id from public.skills where slug = 'client-management')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'graphic-designer' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Learn to write a design brief and a quote', 'skill'::task_type, 4, 180, (select id from public.skills where slug = 'proposal-writing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'graphic-designer' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Handle one round of difficult feedback well', 'skill'::task_type, 4, 60, (select id from public.skills where slug = 'feedback-receiving')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'graphic-designer' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Add the client work to your portfolio with permission', 'cv'::task_type, 4, 120, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'graphic-designer' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Ask each client for a written testimonial', 'networking'::task_type, 4, 45, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'graphic-designer' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 4, 'Apply and interview', 'Design interviews are portfolio walkthroughs. Practise narrating your decisions.', 'Have a published portfolio', 6
from public.career_paths cp where cp.slug = 'graphic-designer'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Write a one-page CV with a portfolio link at the top', 'cv'::task_type, 5, 120, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'graphic-designer' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Practise a 10-minute walkthrough of three projects', 'application'::task_type, 5, 180, (select id from public.skills where slug = 'presentation-skills')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'graphic-designer' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Prepare an answer for ''why this colour, why this type''', 'application'::task_type, 4, 90, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'graphic-designer' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Apply to 10 designer and junior designer roles', 'application'::task_type, 6, 240, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'graphic-designer' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Do three mock interviews in Tack', 'application'::task_type, 4, 150, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'graphic-designer' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_paths
  (slug, title, summary, category, salary_min_bdt, salary_max_bdt, months_to_job_ready, demand_level, day_to_day, good_fit_if, sort_order)
values ('qa-engineer', 'QA engineer', 'You find the problems before the customer does. The most reliable way into a software company without a strong coding background, and automation raises the ceiling later.', 'software', 22000, 40000, 7, 'high', array['Write and run test cases','Report bugs so they can be reproduced','Retest fixes','Automate the tests you run most']::text[], array['You break things by accident already','You are systematic and stubborn','You write clear instructions']::text[], 8)
on conflict (slug) do update set
  title = excluded.title, summary = excluded.summary, category = excluded.category,
  salary_min_bdt = excluded.salary_min_bdt, salary_max_bdt = excluded.salary_max_bdt,
  months_to_job_ready = excluded.months_to_job_ready, demand_level = excluded.demand_level,
  day_to_day = excluded.day_to_day, good_fit_if = excluded.good_fit_if, sort_order = excluded.sort_order;

insert into public.career_path_skills (path_id, skill_id, importance)
select cp.id, s.id, 'core'::skill_importance
from public.career_paths cp join public.skills s on s.slug in ('manual-testing','test-case-design','bug-reporting','quality-assurance-processes','attention-to-detail')
where cp.slug = 'qa-engineer'
on conflict (path_id, skill_id) do update set importance = excluded.importance;

insert into public.career_path_skills (path_id, skill_id, importance)
select cp.id, s.id, 'important'::skill_importance
from public.career_paths cp join public.skills s on s.slug in ('api-testing','postman','sql','automated-testing','selenium','regression-testing')
where cp.slug = 'qa-engineer'
on conflict (path_id, skill_id) do update set importance = excluded.importance;

insert into public.career_path_skills (path_id, skill_id, importance)
select cp.id, s.id, 'nice'::skill_importance
from public.career_paths cp join public.skills s on s.slug in ('cypress','performance-testing','jmeter','appium')
where cp.slug = 'qa-engineer'
on conflict (path_id, skill_id) do update set importance = excluded.importance;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 0, 'Learn to test on purpose', 'Anyone can click around. Testing is deciding what to click and why before you start.', null, 1
from public.career_paths cp where cp.slug = 'qa-engineer'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Learn the software testing life cycle', 'skill'::task_type, 4, 180, (select id from public.skills where slug = 'quality-assurance-processes')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'qa-engineer' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Learn equivalence partitioning and boundary values', 'skill'::task_type, 4, 180, (select id from public.skills where slug = 'test-case-design')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'qa-engineer' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Write 40 test cases for a login screen', 'project'::task_type, 5, 240, (select id from public.skills where slug = 'test-case-design')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'qa-engineer' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Learn to write a bug report someone can reproduce', 'skill'::task_type, 4, 120, (select id from public.skills where slug = 'bug-reporting')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'qa-engineer' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Find and report 20 real bugs in any public app', 'project'::task_type, 5, 360, (select id from public.skills where slug = 'manual-testing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'qa-engineer' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 1, 'Test beneath the screen', 'API and database testing is where junior QAs become useful fast.', 'Be able to write test cases', 3
from public.career_paths cp where cp.slug = 'qa-engineer'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Learn how HTTP requests and responses work', 'skill'::task_type, 4, 180, (select id from public.skills where slug = 'rest-apis')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'qa-engineer' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Learn Postman and test a public API', 'project'::task_type, 5, 240, (select id from public.skills where slug = 'postman')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'qa-engineer' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Learn SQL well enough to verify data after a test', 'skill'::task_type, 4, 300, (select id from public.skills where slug = 'sql')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'qa-engineer' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Write an API test suite for one endpoint set', 'project'::task_type, 5, 300, (select id from public.skills where slug = 'api-testing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'qa-engineer' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Learn to test on a 360px Android screen', 'skill'::task_type, 3, 120, (select id from public.skills where slug = 'mobile-testing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'qa-engineer' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 2, 'Automate the boring part', 'Manual QA is the entry ticket; automation is the pay rise.', 'Be comfortable with API testing', 5
from public.career_paths cp where cp.slug = 'qa-engineer'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Learn Python or JavaScript basics', 'skill'::task_type, 4, 420, (select id from public.skills where slug = 'python')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'qa-engineer' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Learn Selenium or Playwright', 'skill'::task_type, 5, 480, (select id from public.skills where slug = 'selenium')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'qa-engineer' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Automate 10 regression cases', 'project'::task_type, 6, 600, (select id from public.skills where slug = 'automated-testing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'qa-engineer' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Put your suite in CI so it runs on every push', 'skill'::task_type, 4, 180, (select id from public.skills where slug = 'ci-cd')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'qa-engineer' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Learn to read a failing test and tell flake from real', 'skill'::task_type, 4, 120, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'qa-engineer' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 3, 'Work like a team QA', 'QA is a communication job as much as a technical one.', 'Have an automated suite', 6
from public.career_paths cp where cp.slug = 'qa-engineer'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Test a real student or open-source project for a month', 'project'::task_type, 6, 900, (select id from public.skills where slug = 'manual-testing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'qa-engineer' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Learn Jira and a real bug workflow', 'skill'::task_type, 4, 180, (select id from public.skills where slug = 'jira')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'qa-engineer' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Write a test plan for one release', 'cv'::task_type, 5, 240, (select id from public.skills where slug = 'test-planning')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'qa-engineer' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Complete an ISTQB foundation-level course', 'certificate'::task_type, 5, 900, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'qa-engineer' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Practise arguing for a bug that was closed as won''t-fix', 'networking'::task_type, 3, 60, (select id from public.skills where slug = 'negotiation')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'qa-engineer' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 4, 'Apply and interview', 'QA interviews ask you to test something on the spot. Practise thinking out loud.', 'Have a written test plan', 7
from public.career_paths cp where cp.slug = 'qa-engineer'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Write a CV listing tools, types of testing and domains', 'cv'::task_type, 5, 180, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'qa-engineer' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Practise ''how would you test this pen'' style questions', 'application'::task_type, 5, 150, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'qa-engineer' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Prepare three bugs you found and why they mattered', 'application'::task_type, 4, 120, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'qa-engineer' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Apply to 10 QA and SQA roles', 'application'::task_type, 6, 240, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'qa-engineer' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Do three mock interviews in Tack', 'application'::task_type, 4, 150, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'qa-engineer' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_paths
  (slug, title, summary, category, salary_min_bdt, salary_max_bdt, months_to_job_ready, demand_level, day_to_day, good_fit_if, sort_order)
values ('accountant', 'Accountant', 'You keep the money records correct and legal. The most stable of the ten paths, with a clear ladder through ACCA or CA if you want it.', 'finance', 18000, 32000, 6, 'moderate', array['Record transactions','Reconcile accounts','Prepare monthly statements','Handle VAT and tax filings']::text[], array['You are precise and patient','You like rules that have right answers','You want a career with clear steps']::text[], 9)
on conflict (slug) do update set
  title = excluded.title, summary = excluded.summary, category = excluded.category,
  salary_min_bdt = excluded.salary_min_bdt, salary_max_bdt = excluded.salary_max_bdt,
  months_to_job_ready = excluded.months_to_job_ready, demand_level = excluded.demand_level,
  day_to_day = excluded.day_to_day, good_fit_if = excluded.good_fit_if, sort_order = excluded.sort_order;

insert into public.career_path_skills (path_id, skill_id, importance)
select cp.id, s.id, 'core'::skill_importance
from public.career_paths cp join public.skills s on s.slug in ('financial-accounting','bookkeeping','journal-entries','advanced-excel','bank-reconciliation')
where cp.slug = 'accountant'
on conflict (path_id, skill_id) do update set importance = excluded.importance;

insert into public.career_path_skills (path_id, skill_id, importance)
select cp.id, s.id, 'important'::skill_importance
from public.career_paths cp join public.skills s on s.slug in ('taxation-bangladesh','vat-compliance','balance-sheet-preparation','tally','accounts-payable','ifrs')
where cp.slug = 'accountant'
on conflict (path_id, skill_id) do update set importance = excluded.importance;

insert into public.career_path_skills (path_id, skill_id, importance)
select cp.id, s.id, 'nice'::skill_importance
from public.career_paths cp join public.skills s on s.slug in ('financial-analysis','quickbooks','sap-fico','auditing')
where cp.slug = 'accountant'
on conflict (path_id, skill_id) do update set importance = excluded.importance;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 0, 'Get the fundamentals exact', 'Accounting is unforgiving of approximate understanding. Slow down here and everything after is easy.', null, 1
from public.career_paths cp where cp.slug = 'accountant'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Learn the accounting equation until it is obvious', 'skill'::task_type, 4, 180, (select id from public.skills where slug = 'financial-accounting')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'accountant' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Learn debit and credit rules for all five account types', 'skill'::task_type, 5, 240, (select id from public.skills where slug = 'journal-entries')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'accountant' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Post 100 practice journal entries', 'project'::task_type, 5, 480, (select id from public.skills where slug = 'journal-entries')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'accountant' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Prepare a trial balance from scratch', 'project'::task_type, 4, 180, (select id from public.skills where slug = 'trial-balance')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'accountant' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Learn accrual versus cash basis', 'skill'::task_type, 3, 120, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'accountant' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 1, 'Build the statements', 'Being able to produce a full set of statements is the line between student and junior accountant.', 'Be sound on debits and credits', 2
from public.career_paths cp where cp.slug = 'accountant'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Prepare an income statement from a trial balance', 'project'::task_type, 5, 240, (select id from public.skills where slug = 'income-statement-preparation')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'accountant' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Prepare a balance sheet from the same data', 'project'::task_type, 5, 240, (select id from public.skills where slug = 'balance-sheet-preparation')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'accountant' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Prepare a cash flow statement', 'project'::task_type, 5, 300, (select id from public.skills where slug = 'cash-flow-statement')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'accountant' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Do a full bank reconciliation', 'project'::task_type, 4, 180, (select id from public.skills where slug = 'bank-reconciliation')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'accountant' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Learn depreciation methods and apply all three', 'skill'::task_type, 4, 180, (select id from public.skills where slug = 'cost-accounting')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'accountant' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 2, 'Learn Bangladeshi compliance', 'Local tax and VAT knowledge is what makes you employable here specifically.', 'Be able to produce statements', 4
from public.career_paths cp where cp.slug = 'accountant'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Learn the VAT registration and return process', 'skill'::task_type, 5, 300, (select id from public.skills where slug = 'vat-compliance')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'accountant' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Learn personal and corporate income tax basics', 'skill'::task_type, 5, 300, (select id from public.skills where slug = 'taxation-bangladesh')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'accountant' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'File one practice income tax return', 'project'::task_type, 4, 180, (select id from public.skills where slug = 'income-tax-return')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'accountant' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Learn what an auditor will ask for', 'skill'::task_type, 4, 180, (select id from public.skills where slug = 'auditing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'accountant' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Learn IFRS as adopted in Bangladesh, at overview level', 'skill'::task_type, 4, 240, (select id from public.skills where slug = 'ifrs')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'accountant' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 3, 'Learn the software', 'Every firm runs on one of these. Knowing any two makes you portable.', 'Know local compliance', 5
from public.career_paths cp where cp.slug = 'accountant'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Learn Excel to pivot table and lookup level', 'skill'::task_type, 5, 300, (select id from public.skills where slug = 'advanced-excel')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'accountant' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Learn Tally or QuickBooks end to end', 'skill'::task_type, 5, 480, (select id from public.skills where slug = 'tally')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'accountant' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Keep a full month of books for a small real business', 'project'::task_type, 6, 600, (select id from public.skills where slug = 'bookkeeping')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'accountant' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Complete an accounting or ACCA foundation certificate', 'certificate'::task_type, 5, 1200, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'accountant' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Build a reusable monthly closing checklist', 'project'::task_type, 4, 120, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'accountant' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 4, 'Apply and interview', 'Accounting interviews test fundamentals directly. There is nowhere to hide, which is good news if you prepared.', 'Have practical book-keeping experience', 6
from public.career_paths cp where cp.slug = 'accountant'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Write a CV listing standards, software and filings you know', 'cv'::task_type, 5, 180, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'accountant' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Practise 20 fundamentals questions out loud', 'application'::task_type, 5, 240, (select id from public.skills where slug = 'financial-accounting')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'accountant' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Prepare to explain one adjusting entry from memory', 'application'::task_type, 4, 90, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'accountant' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Apply to 10 junior accountant and audit associate roles', 'application'::task_type, 6, 240, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'accountant' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Do three mock interviews in Tack', 'application'::task_type, 4, 150, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'accountant' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_paths
  (slug, title, summary, category, salary_min_bdt, salary_max_bdt, months_to_job_ready, demand_level, day_to_day, good_fit_if, sort_order)
values ('content-writer', 'Content writer', 'You write the words a business publishes. The lowest barrier of the ten paths and the easiest to prove — anyone can read your work in a minute.', 'content', 15000, 28000, 4, 'moderate', array['Research a topic','Write and edit a draft','Fit it to SEO and brand voice','Take edits without ego']::text[], array['You already write for fun','You can research quickly','You would rather explain than persuade']::text[], 10)
on conflict (slug) do update set
  title = excluded.title, summary = excluded.summary, category = excluded.category,
  salary_min_bdt = excluded.salary_min_bdt, salary_max_bdt = excluded.salary_max_bdt,
  months_to_job_ready = excluded.months_to_job_ready, demand_level = excluded.demand_level,
  day_to_day = excluded.day_to_day, good_fit_if = excluded.good_fit_if, sort_order = excluded.sort_order;

insert into public.career_path_skills (path_id, skill_id, importance)
select cp.id, s.id, 'core'::skill_importance
from public.career_paths cp join public.skills s on s.slug in ('content-writing','editing','proofreading','research-writing','english-communication')
where cp.slug = 'content-writer'
on conflict (path_id, skill_id) do update set importance = excluded.importance;

insert into public.career_path_skills (path_id, skill_id, importance)
select cp.id, s.id, 'important'::skill_importance
from public.career_paths cp join public.skills s on s.slug in ('blog-writing','search-engine-optimisation','copywriting','social-media-copy','bangla-content-writing')
where cp.slug = 'content-writer'
on conflict (path_id, skill_id) do update set importance = excluded.importance;

insert into public.career_path_skills (path_id, skill_id, importance)
select cp.id, s.id, 'nice'::skill_importance
from public.career_paths cp join public.skills s on s.slug in ('technical-writing','email-marketing','script-writing','translation')
where cp.slug = 'content-writer'
on conflict (path_id, skill_id) do update set importance = excluded.importance;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 0, 'Write every day', 'Volume first, quality second. The quality arrives through the volume.', null, 1
from public.career_paths cp where cp.slug = 'content-writer'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Write 500 words a day for 30 days', 'project'::task_type, 6, 900, (select id from public.skills where slug = 'content-writing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'content-writer' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Learn to write a headline that is not clickbait', 'skill'::task_type, 3, 120, (select id from public.skills where slug = 'copywriting')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'content-writer' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Learn structure: hook, body, close', 'skill'::task_type, 4, 180, (select id from public.skills where slug = 'content-writing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'content-writer' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Learn to cut 20% from any draft', 'skill'::task_type, 4, 120, (select id from public.skills where slug = 'editing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'content-writer' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Read your writing out loud and fix what trips', 'skill'::task_type, 3, 60, (select id from public.skills where slug = 'proofreading')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'content-writer' and m.order_index = 0
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 1, 'Learn to research', 'The difference between a paid writer and a hobbyist is that the paid one is checkable.', 'Have a 30-day writing habit', 2
from public.career_paths cp where cp.slug = 'content-writer'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Learn to find and verify a primary source', 'skill'::task_type, 4, 180, (select id from public.skills where slug = 'research-writing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'content-writer' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Write one 1,200-word researched article with citations', 'project'::task_type, 5, 360, (select id from public.skills where slug = 'research-writing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'content-writer' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Learn to interview someone for an article', 'skill'::task_type, 4, 120, (select id from public.skills where slug = 'interviewing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'content-writer' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Write one piece in Bangla and one in English on the same topic', 'project'::task_type, 5, 300, (select id from public.skills where slug = 'bangla-content-writing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'content-writer' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Learn plagiarism rules and how to paraphrase properly', 'skill'::task_type, 3, 90, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'content-writer' and m.order_index = 1
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 2, 'Write for the internet', 'Web writing has rules print does not. Learn them or your work is never found.', 'Have one researched article', 3
from public.career_paths cp where cp.slug = 'content-writer'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Learn keyword research and search intent', 'skill'::task_type, 4, 180, (select id from public.skills where slug = 'search-engine-optimisation')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'content-writer' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Write three posts targeting long-tail keywords', 'project'::task_type, 5, 480, (select id from public.skills where slug = 'blog-writing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'content-writer' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Learn to write for scanning, not reading', 'skill'::task_type, 3, 120, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'content-writer' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Learn to match a brand voice from a style guide', 'skill'::task_type, 4, 180, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'content-writer' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Write 20 social captions in three different voices', 'project'::task_type, 4, 240, (select id from public.skills where slug = 'social-media-copy')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'content-writer' and m.order_index = 2
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 3, 'Get published', 'A byline someone else published beats anything self-published.', 'Have SEO-aware writing samples', 4
from public.career_paths cp where cp.slug = 'content-writer'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Publish three pieces on someone else''s site or newsletter', 'project'::task_type, 6, 600, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'content-writer' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Take three paid or free client briefs', 'project'::task_type, 6, 600, (select id from public.skills where slug = 'client-management')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'content-writer' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Build a portfolio page with five best pieces', 'project'::task_type, 5, 240, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'content-writer' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Learn to write a pitch email that gets a reply', 'skill'::task_type, 4, 120, (select id from public.skills where slug = 'proposal-writing')
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'content-writer' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Ask two editors for a written reference', 'networking'::task_type, 4, 45, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'content-writer' and m.order_index = 3
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_milestones (path_id, order_index, title, description, unlock_text, typical_semester)
select cp.id, 4, 'Apply and interview', 'Content interviews come with a paid or unpaid writing test. Treat it as the interview.', 'Have a published portfolio', 4
from public.career_paths cp where cp.slug = 'content-writer'
on conflict (path_id, order_index) do update set
  title = excluded.title, description = excluded.description,
  unlock_text = excluded.unlock_text, typical_semester = excluded.typical_semester;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 0, 'Write a CV with your three strongest links at the top', 'cv'::task_type, 5, 120, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'content-writer' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 1, 'Prepare for a timed writing test', 'application'::task_type, 5, 120, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'content-writer' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 2, 'Practise explaining an edit you disagreed with', 'application'::task_type, 4, 90, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'content-writer' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 3, 'Apply to 10 content writer and copywriter roles', 'application'::task_type, 6, 240, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'content-writer' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

insert into public.career_path_tasks (milestone_id, order_index, title, type, points, est_minutes, skill_id)
select m.id, 4, 'Do three mock interviews in Tack', 'application'::task_type, 4, 150, null::uuid
from public.career_path_milestones m
join public.career_paths cp on cp.id = m.path_id
where cp.slug = 'content-writer' and m.order_index = 4
on conflict (milestone_id, order_index) do update set
  title = excluded.title, type = excluded.type, points = excluded.points,
  est_minutes = excluded.est_minutes, skill_id = excluded.skill_id;

