-- Signed-in ingestion with bounded, enumerated fields. Never accepts an
-- exception message or a user identifier from a client.
create or replace function public.record_client_error(
  p_code text, p_stack text, p_context jsonb, p_version text, p_platform text
) returns void language plpgsql security definer set search_path=public
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'sign_in_required'; end if;
  if p_code not in ('invalid_data','invalid_state','invalid_argument','render_failure','unexpected_failure')
    or p_code is null or p_platform not in ('android','iOS','macOS','linux','windows','fuchsia')
    or p_platform is null or p_version is null
    or p_version !~ '^(unknown|[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}(\+[0-9]{1,10})?)$'
    or length(coalesce(p_stack,'')) > 3000
    or exists(select 1 from regexp_split_to_table(coalesce(p_stack,''), E'\n') line
      where line <> '' and line !~ '^package:tack/[a-zA-Z0-9_/]+\.dart:[0-9]+:[0-9]+$') then
    raise exception 'invalid_error_report';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('tack:errors:'||v_uid::text,0));
  if (select count(*) from public.error_reports where user_id=v_uid
    and occurred_at > now()-interval '1 hour') >= 20 then return; end if;
  insert into public.error_reports(user_id,message,stack,context,app_version,platform)
    values(v_uid,p_code,p_stack,
      case when p_context->>'phase' in ('startup','render','runtime')
        then jsonb_build_object('phase',p_context->>'phase') else '{}'::jsonb end,
      p_version,p_platform);
end $$;
revoke all on function public.record_client_error(text,text,jsonb,text,text) from public,anon;
grant execute on function public.record_client_error(text,text,jsonb,text,text) to authenticated;
revoke insert, update, delete on public.error_reports from authenticated, anon;
