-- The mode column is generated, and a generated column is evaluated as
-- whichever role is writing the row — so a student needs EXECUTE on the
-- function behind it or they cannot update their own profile at all.
--
-- Safe to grant: derive_mode is immutable, takes no user id, and returns a
-- mode from plain inputs. It reads nothing and can act on nobody.
grant execute on function public.derive_mode(education_stage, int, int, int, int)
  to authenticated;
grant execute on function public.year_to_mode(int, int) to authenticated;
grant execute on function public.stage_to_mode(education_stage, int, int) to authenticated;
