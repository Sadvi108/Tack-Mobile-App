-- Documents live in the private 'documents' storage bucket under
-- users/{user_id}/{type}/{document_id}. The row is the source of truth for
-- ownership; storage policies mirror it via the path prefix.
create table public.documents (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references public.profiles(id) on delete cascade,
  type               document_type not null default 'other',
  title              text not null,
  storage_path       text not null unique,
  mime_type          text,
  size_bytes         bigint check (size_bytes >= 0),
  checksum           text,
  status             document_status not null default 'pending',
  failure_reason     text,
  is_default         boolean not null default false,
  version            int not null default 1,
  parent_document_id uuid references public.documents(id) on delete set null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz,
  purge_after        timestamptz
);
create index documents_user_type_idx on public.documents(user_id, type) where deleted_at is null;
-- Exactly one default CV per user.
create unique index documents_one_default_cv on public.documents(user_id)
  where type = 'cv' and is_default and deleted_at is null;
create trigger documents_updated_at before update on public.documents
  for each row execute function public.set_updated_at();

alter table public.job_applications
  add constraint job_applications_cv_fk
  foreign key (cv_document_id) references public.documents(id) on delete set null;

alter table public.certifications
  add constraint certifications_document_fk
  foreign key (document_id) references public.documents(id) on delete set null;

-- Soft delete keeps the object for 30 days so an accidental delete is recoverable.
create or replace function public.stamp_document_purge()
returns trigger
language plpgsql
as $$
begin
  if new.deleted_at is not null and old.deleted_at is null then
    new.purge_after := new.deleted_at + interval '30 days';
    new.is_default := false;
  elsif new.deleted_at is null then
    new.purge_after := null;
  end if;
  return new;
end $$;

create trigger documents_purge_stamp
  before update of deleted_at on public.documents
  for each row execute function public.stamp_document_purge();

-- Promoting a CV to default demotes the previous one in the same statement,
-- so the partial unique index above is never violated.
create or replace function public.set_default_cv(p_document_id uuid)
returns void
language plpgsql
security invoker
as $$
declare uid uuid;
begin
  select user_id into uid from public.documents
    where id = p_document_id and type = 'cv' and deleted_at is null;
  if uid is null then
    raise exception 'no such CV' using errcode = 'no_data_found';
  end if;
  update public.documents set is_default = false
    where user_id = uid and type = 'cv' and is_default and id <> p_document_id;
  update public.documents set is_default = true where id = p_document_id;
end $$;

create table public.cv_parse_results (
  id            uuid primary key default gen_random_uuid(),
  document_id   uuid not null references public.documents(id) on delete cascade,
  user_id       uuid not null references public.profiles(id) on delete cascade,
  parsed        jsonb not null default '{}'::jsonb,
  quality_score int check (quality_score between 0 and 100),
  warnings      jsonb not null default '[]'::jsonb,
  created_at    timestamptz not null default now()
);
create index cv_parse_results_user_idx on public.cv_parse_results(user_id, created_at desc);
