-- Commit separately before the shared import/feed migration uses the value.
alter type public.radar_source add value if not exists 'linkedin';
