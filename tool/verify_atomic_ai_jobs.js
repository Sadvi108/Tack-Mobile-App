#!/usr/bin/env node
// Applies the candidate migration in a rollback-only transaction. No worker,
// existing account, existing quota, or live queue item is touched.
const fs = require('fs');
const path = require('path');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { Client } = require('pg');
require('dotenv').config({ path: path.join(__dirname, '../supabase/.env'), quiet: true });
(async () => {
  const db = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await db.connect();
  try {
    await db.query('begin');
    const applied = await db.query("select 1 from public.schema_migrations where version='0072_atomic_ai_jobs.sql'");
    if (!applied.rowCount) await db.query(fs.readFileSync(path.join(__dirname, '../supabase/migrations/0072_atomic_ai_jobs.sql'), 'utf8'));
    for (const name of ['0073_private_error_reports.sql','0074_application_commands.sql']) {
      const applied = await db.query('select 1 from public.schema_migrations where version=$1',[name]);
      if (!applied.rowCount) await db.query(fs.readFileSync(path.join(__dirname,'../supabase/migrations',name),'utf8'));
    }
    const uid = randomUUID();
    await db.query("insert into auth.users(id,email,raw_user_meta_data) values ($1,$2,'{}')", [uid, `atomic-${uid}@example.invalid`]);
    const enqueue = async (key, type = 'analyse_jd', payload = {}) => (await db.query(
      'select public.enqueue_student_job($1,$2,$3,$4) as result', [uid, type, payload, key])).rows[0].result;
    const first = await enqueue(`${uid}:one`);
    assert.equal(first.remaining, 2);
    const twice = await enqueue(`${uid}:one`);
    assert.equal(twice.jobId, first.jobId);
    assert.equal(twice.remaining, 2);
    assert.equal(twice.duplicate, true);
    assert.equal((await enqueue(`${uid}:two`)).remaining, 1);
    assert.equal((await enqueue(`${uid}:three`)).remaining, 0);
    await db.query('savepoint expected_limit');
    await assert.rejects(() => enqueue(`${uid}:four`), /quota_exhausted/);
    await db.query('rollback to savepoint expected_limit');
    await db.query("update public.jobs_queue set status='dead' where id=$1", [first.jobId]);
    const refund = await db.query('select public.refund_job_quota($1) as refunded', [first.jobId]);
    assert.equal(refund.rows[0].refunded, false);
    const retry = await enqueue(`${uid}:one`);
    assert.equal(retry.jobId, first.jobId);
    assert.equal(retry.remaining, 0);
    await db.query("update public.jobs_queue set status='done',result='{\"cached\":true}' where id=$1", [first.jobId]);
    assert.equal((await db.query('select public.quota_remaining($1,\'ai\',999) as n', [uid])).rows[0].n, 1);
    const coach = await enqueue(`${uid}:coach`, 'coach_reply', { question: 'How do I practise a skill?', context: '{}' });
    assert.ok(coach.threadId);
    assert.equal((await enqueue(`${uid}:coach`, 'coach_reply', { question: 'How do I practise a skill?', context: '{}' })).threadId, coach.threadId);
    assert.equal((await db.query('select count(*)::int n from public.chat_messages where job_id=$1', [coach.jobId])).rows[0].n, 1);
    await db.query('savepoint ownership');
    await assert.rejects(() => enqueue(`${uid}:cv`, 'check_cv', { document_id: randomUUID() }), /document_not_owned/);
    await db.query('rollback to savepoint ownership');
    for (const role of ['anon','authenticated']) {
      const grants = await db.query('select has_function_privilege($1,\'public.enqueue_student_job(uuid,text,jsonb,text)\',\'execute\') as allowed', [role]);
      assert.equal(grants.rows[0].allowed, false);
    }
    await db.query("select set_config('request.jwt.claims',$1,true)", [JSON.stringify({sub:uid,role:'authenticated'})]);
    const app = (await db.query("select public.create_application('Junior tester','Test company') id")).rows[0].id;
    assert.equal((await db.query("select public.create_application('Junior tester','Test company') id")).rows[0].id,app);
    assert.equal((await db.query('select count(*)::int n from public.application_status_history where application_id=$1',[app])).rows[0].n,1);
    const version = (await db.query('select updated_at::text from public.job_applications where id=$1',[app])).rows[0].updated_at;
    await db.query('select public.apply_application_patch($1,$2,$3)',[app,{notes:'A saved note'},version]);
    await db.query('savepoint conflict');
    await assert.rejects(() => db.query('select public.apply_application_patch($1,$2,$3)',[app,{notes:'Stale note'},'2000-01-01']), /sync_conflict/);
    await db.query('rollback to savepoint conflict');
    await db.query('select public.record_client_error($1,$2,$3,$4,$5)', ['invalid_state','package:tack/main.dart:1:1',{phase:'runtime',email:'never@store.test'},'1.0.0+1','android']);
    const report = (await db.query('select message,context from public.error_reports where user_id=$1',[uid])).rows[0];
    assert.deepEqual(report,{message:'invalid_state',context:{phase:'runtime'}});
    await db.query('savepoint invalid_report');
    await assert.rejects(() => db.query('select public.record_client_error($1,$2,$3,$4,$5)', ['student@email.test',null,{},'1.0.0','android']), /invalid_error_report/);
    await db.query('rollback to savepoint invalid_report');
    console.log('PASS: application creation/history is atomic and idempotent; stale edits conflict; error ingestion removes unknown properties and rejects raw messages.');
    console.log('PASS: migration, three-action cap, duplicate identity, exact-once refunds, failed retry, cached refund, atomic coach thread/message, document ownership and client RPC denial.');
  } finally { await db.query('rollback'); await db.end(); }
})().catch(e => { console.error(e.message); process.exitCode=1; });
