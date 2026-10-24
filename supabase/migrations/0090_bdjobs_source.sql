-- Separate transaction: the enum value must be committed before use in 0091.
alter type public.radar_source add value if not exists 'bdjobs';
