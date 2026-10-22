-- Review fixes for the application checklist (0082).
--
-- 1. tack_text_hash() must equal hashText() byte for byte, or "you checked
--    this description" never comes true for pasted text. JavaScript's trim()
--    and \s count the ECMAScript whitespace set — including the byte-order mark
--    and the line and paragraph separators — and Postgres's \s does not count
--    the byte-order mark. The set is now spelled out on both sides of the
--    collapse, and tool/verify_application_checklist.js feeds both functions
--    the awkward characters.
-- 2. A CV deleted from the vault is not attached, whatever the application
--    row still points at: vault deletion is soft, so the pointer survives.
-- 3. "Check the job description" only when the analyser would accept it: at
--    least 80 characters once trimmed the way the endpoint trims.
-- 4. Practice is counted across every role, so the item no longer says "for
--    this role".
-- 5. Students may read their briefs and do nothing else to the table.

-- --------------------------------------------------------------------- 1, 3
-- The ECMAScript WhiteSpace and LineTerminator characters: what JavaScript's
-- trim() strips and what its \s matches.
create or replace function public.tack_js_trim(p_text text)
returns text
language sql
immutable
set search_path = public
as $$
  select regexp_replace(p_text,
    '^[\t\n\v\f\r    -     　﻿]+'
    || '|[\t\n\v\f\r    -     　﻿]+$',
    '', 'g');
$$;

revoke all on function public.tack_js_trim(text) from public, anon, authenticated;

create or replace function public.tack_text_hash(p_text text)
returns text
language sql
immutable
set search_path = public
as $$
  select encode(sha256(convert_to(
           public.tack_js_trim(regexp_replace(
             lower(p_text),
             '[\t\n\v\f\r    -     　﻿]+',
             ' ', 'g')),
           'UTF8')), 'hex');
$$;

revoke all on function public.tack_text_hash(text) from public, anon, authenticated;

-- ------------------------------------------------------------------ 2, 3, 4
create or replace function public.application_checklist(p_application uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid    uuid := (select auth.uid());
  v_today  date := public.tack_today();
  v_items  jsonb := '[]'::jsonb;
  v_since  timestamptz;
  a        record;
begin
  if v_uid is null then
    raise exception 'sign_in_required' using errcode = '42501';
  end if;

  select ap.id, ap.status, ap.cv_document_id, ap.applied_at, ap.created_at,
         j.closes_at, j.description
    into a
    from public.job_applications ap
    join public.jobs j on j.id = ap.job_id
   where ap.id = p_application
     and ap.user_id = v_uid
     and ap.deleted_at is null;

  if not found then
    raise exception 'application_not_owned' using errcode = '42501';
  end if;

  -- An offer or a rejection asks nothing more of the checklist.
  if a.status not in ('saved', 'applied', 'assessment', 'interview') then
    return jsonb_build_object('items', '[]'::jsonb, 'next_step', null);
  end if;

  -- Appended in precedence order, so the first item is the next step.

  if a.status = 'saved' and a.closes_at between v_today and v_today + 3 then
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'id', 'APP-DATE', 'severity', 'required', 'action', 'open_job',
      'title', 'Closes ' || to_char(a.closes_at, 'Dy DD Mon')
               || '. Send it, or let it go.'));
  end if;

  if a.status = 'interview' and not exists (
       select 1
         from public.interview_questions q
         join public.interview_sessions s on s.id = q.session_id
        where q.user_id = v_uid
          and s.deleted_at is null
          and q.answered_at >= now() - interval '7 days') then
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'id', 'APP-PRACTICE', 'severity', 'required', 'action', 'practise',
      'title', 'Practise a few interview questions this week'));
  end if;

  if a.status = 'interview' and not exists (
       select 1 from public.interview_prep_briefs b
        where b.application_id = a.id) then
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'id', 'APP-PREP', 'severity', 'recommended', 'action', 'prep',
      'title', 'Get your interview prep brief'));
  end if;

  if not exists (
       select 1 from public.documents d
        where d.id = a.cv_document_id
          and d.user_id = v_uid
          and d.deleted_at is null) then
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'id', 'APP-CV', 'severity', 'recommended', 'action', 'attach_cv',
      'title', case when a.status = 'saved'
                    then 'Attach the CV you will send'
                    else 'Attach the CV you sent' end));
  end if;

  if length(coalesce(public.tack_js_trim(a.description), '')) >= 80
     and not exists (
       select 1
         from public.job_match_scores m
         join public.job_analyses ja on ja.id = m.analysis_id
        where m.user_id = v_uid
          and ja.raw_text_hash = public.tack_text_hash(a.description)) then
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'id', 'APP-JD', 'severity', 'recommended', 'action', 'analyse',
      'title', 'Check the job description against your skills'));
  end if;

  if a.status = 'applied' then
    select max(h.changed_at) into v_since
      from public.application_status_history h
     where h.application_id = a.id;
    if coalesce(v_since, a.applied_at, a.created_at) < now() - interval '21 days' then
      v_items := v_items || jsonb_build_array(jsonb_build_object(
        'id', 'APP-FOLLOW', 'severity', 'recommended', 'action', 'follow_up',
        'title', 'No reply in three weeks. Follow up, or move it on.'));
    end if;
  end if;

  return jsonb_build_object(
    'items', v_items,
    'next_step', case when jsonb_array_length(v_items) > 0
                      then v_items -> 0 else null end);
end $$;

-- ------------------------------------------------------------------------ 5
revoke all on public.interview_prep_briefs from anon, authenticated;
grant select on public.interview_prep_briefs to authenticated;
