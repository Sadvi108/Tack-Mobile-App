#!/usr/bin/env node
const fs=require('fs'),path=require('path'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {Client}=require('pg');
require('dotenv').config({path:path.join(__dirname,'../supabase/.env'),quiet:true});
(async()=>{
  const db=new Client({connectionString:process.env.DATABASE_URL,ssl:{rejectUnauthorized:false}});
  await db.connect();
  try {
    await db.query('begin');
    const name='0075_expand_career_catalog.sql';
    const applied=await db.query('select 1 from public.schema_migrations where version=$1',[name]);
    if(!applied.rowCount) await db.query(fs.readFileSync(path.join(__dirname,'../supabase/migrations',name),'utf8'));
    const coverage=await db.query(`select cf.slug,count(cp.id)::int n from public.career_fields cf
      left join public.career_paths cp on cp.field_id=cf.id and cp.is_active
      where cf.slug<>'undecided' group by cf.slug`);
    assert.equal(coverage.rows.length,39);
    assert.ok(coverage.rows.every(r=>r.n>=3));
    const templates=await db.query(`select cp.slug,count(distinct m.id)::int milestones,count(distinct t.id)::int tasks,
      count(distinct s.skill_id)::int skills from public.career_paths cp
      left join public.career_path_milestones m on m.path_id=cp.id
      left join public.career_path_tasks t on t.milestone_id=m.id
      left join public.career_path_skills s on s.path_id=cp.id
      where cp.sort_order>=200 group by cp.slug`);
    assert.equal(templates.rows.length,129);
    assert.ok(templates.rows.every(r=>r.milestones>=3 && r.tasks>=9 && r.skills>=3));
    const uid=randomUUID();
    await db.query("insert into auth.users(id,email,raw_user_meta_data) values($1,$2,'{}')",[uid,`catalog-${uid}@example.invalid`]);
    await db.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:uid,role:'authenticated'})]);
    const p=(await db.query("select id from public.career_paths where slug='mobile-app-developer'")).rows[0].id;
    await db.query('insert into public.user_career_paths(user_id,path_id,is_primary) values($1,$2,true)',[uid,p]);
    const roadmap=(await db.query('select public.generate_roadmap($1) id',[p])).rows[0].id;
    assert.ok(roadmap);
    const tasks=await db.query('select count(*)::int n from public.roadmap_tasks where user_id=$1',[uid]);
    assert.ok(tasks.rows[0].n>=9);
    console.log('PASS: 39 fields have at least 3 paths; 129 new paths have skills and 9-task roadmaps; following a new path generates real student tasks.');
  } finally {await db.query('rollback');await db.end();}
})().catch(e=>{console.error(e.message);process.exitCode=1;});
