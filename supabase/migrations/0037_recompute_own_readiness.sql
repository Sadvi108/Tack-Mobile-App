-- submit_onboarding runs as the student so Row Level Security applies to it,
-- which means it cannot call recompute_readiness(uuid) — that one takes a user
-- id and is service-role only, precisely so nobody can score another student.
--
-- This wrapper takes no argument and can only ever act on the caller, so it is
-- safe to hand to authenticated users.
create or replace function public.recompute_my_readiness(p_reason text default 'app')
returns public.readiness_scores
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.readiness_scores;
begin
  if v_uid is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;
  select * into v_row from public.recompute_readiness(v_uid, p_reason);
  return v_row;
end $$;

grant execute on function public.recompute_my_readiness(text) to authenticated;

-- Point the submit path at it.
create or replace function public.submit_onboarding(p_answers jsonb)
returns public.readiness_scores
language plpgsql
security invoker
set search_path = public
as $body$
declare
  v_score public.readiness_scores;
begin
  perform public.write_onboarding(p_answers);
  select * into v_score from public.recompute_my_readiness('onboarding');
  return v_score;
end $body$;

grant execute on function public.submit_onboarding(jsonb) to authenticated;
