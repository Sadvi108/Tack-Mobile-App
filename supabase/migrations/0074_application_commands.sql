create table public.application_commands (
  user_id uuid not null references public.profiles(id) on delete cascade,
  operation_key text not null,
  application_id uuid not null references public.job_applications(id) on delete cascade,
  primary key(user_id, operation_key)
);
alter table public.application_commands enable row level security;
alter table public.application_commands force row level security;
revoke all on public.application_commands from anon, authenticated;
grant all on public.application_commands to service_role;

create or replace function public.create_application(
  p_title text, p_company text, p_location text default null,
  p_source_url text default null, p_closes_at date default null,
  p_status public.application_status default 'saved'
) returns uuid language plpgsql security definer set search_path=public
as $$
declare
  v_uid uuid := auth.uid(); v_key text; v_app uuid; v_job uuid; v_company uuid;
begin
  if v_uid is null then raise exception 'sign_in_required'; end if;
  if p_title is null or length(trim(p_title)) not between 1 and 160
    or p_company is null or length(trim(p_company)) not between 1 and 160
    or length(p_location) > 160 or length(p_source_url) > 2000
    or (p_source_url is not null and p_source_url !~ '^https?://[^[:space:]]+$')
    or p_status not in ('saved','applied') or p_status is null then
    raise exception 'invalid_application';
  end if;
  v_key := md5(jsonb_build_array(lower(trim(p_title)), lower(trim(p_company)),
    p_location,p_source_url,p_closes_at)::text);
  perform pg_advisory_xact_lock(hashtextextended('tack:application:'||v_uid::text||v_key,0));
  select application_id into v_app from public.application_commands where user_id=v_uid and operation_key=v_key;
  if found then return v_app; end if;
  v_company := public.upsert_company(trim(p_company));
  insert into public.jobs(user_id,company_id,company_name,title,location,source_url,closes_at)
    values(v_uid,v_company,trim(p_company),trim(p_title),p_location,p_source_url,p_closes_at) returning id into v_job;
  insert into public.job_applications(user_id,job_id,status) values(v_uid,v_job,p_status) returning id into v_app;
  insert into public.application_commands values(v_uid,v_key,v_app);
  return v_app;
end $$;
revoke all on function public.create_application(text,text,text,text,date,public.application_status) from public,anon;
grant execute on function public.create_application(text,text,text,text,date,public.application_status) to authenticated;

-- A write from an old offline snapshot must not silently replace a newer edit.
create or replace function public.apply_application_patch(p_id uuid, p_patch jsonb, p_expected_updated_at timestamptz)
returns uuid language plpgsql security definer set search_path=public
as $$
declare v_row public.job_applications; v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'sign_in_required'; end if;
  if p_patch is null or jsonb_typeof(p_patch)<>'object' or octet_length(p_patch::text)>30000
    or exists(select 1 from jsonb_object_keys(p_patch) k where k not in
      ('status','notes','next_action','next_action_date','cv_document_id','applied_at'))
    or length(p_patch->>'notes')>20000 or length(p_patch->>'next_action')>500 then
    raise exception 'invalid_application_patch';
  end if;
  select * into v_row from public.job_applications where id=p_id and user_id=v_uid and deleted_at is null for update;
  if not found then raise exception 'application_not_owned'; end if;
  -- A lost response can be retried safely even though its timestamp changed.
  if to_jsonb(v_row) @> p_patch then return p_id; end if;
  if p_expected_updated_at is not null and v_row.updated_at <> p_expected_updated_at then
    raise exception 'sync_conflict';
  end if;
  if p_patch->>'cv_document_id' is not null and not exists(select 1 from public.documents
    where id=(p_patch->>'cv_document_id')::uuid and user_id=v_uid and type='cv' and deleted_at is null) then
    raise exception 'document_not_owned';
  end if;
  update public.job_applications set
    status=case when p_patch ? 'status' then (p_patch->>'status')::public.application_status else status end,
    notes=case when p_patch ? 'notes' then p_patch->>'notes' else notes end,
    next_action=case when p_patch ? 'next_action' then p_patch->>'next_action' else next_action end,
    next_action_date=case when p_patch ? 'next_action_date' then (p_patch->>'next_action_date')::date else next_action_date end,
    cv_document_id=case when p_patch ? 'cv_document_id' then (p_patch->>'cv_document_id')::uuid else cv_document_id end,
    applied_at=case when p_patch ? 'applied_at' then (p_patch->>'applied_at')::timestamptz else applied_at end
    where id=p_id and user_id=v_uid;
  return p_id;
end $$;
revoke all on function public.apply_application_patch(uuid,jsonb,timestamptz) from public,anon;
grant execute on function public.apply_application_patch(uuid,jsonb,timestamptz) to authenticated;
