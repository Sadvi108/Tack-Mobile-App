-- Classify on write, not at the call site.
--
-- The radar function could set `kind` itself, but then the rule lives in
-- TypeScript and holds only for as long as every future writer remembers it.
-- AGENTS.md is explicit that a rule which must hold regardless of client
-- belongs in Postgres, and this is one: a listing with no kind is a listing
-- that silently disappears from every filter.
create or replace function public.stamp_listing_kind()
returns trigger
language plpgsql
as $$
begin
  -- Only when the writer did not decide for itself, so a provider that knows
  -- better than the text can still say so.
  if new.kind is null or new.kind = 'unknown' then
    new.kind := public.classify_employment(new.employment_type, new.title);
  end if;
  return new;
end $$;

drop trigger if exists job_listings_kind on public.job_listings;
create trigger job_listings_kind
  before insert or update of employment_type, title on public.job_listings
  for each row execute function public.stamp_listing_kind();
