-- What cv_first_reads actually holds, said where it is held.
--
-- 0084's header said the table stores none of the CV's text. Each reader's
-- `remembered` list is up to three short phrases quoted from the CV, already
-- held to the CV's own words and taken from text with contact details
-- removed. That is CV text at rest, in the student's own row, readable only
-- by them; the comment now says so. And `checksum` is the document's id: a
-- document's file never changes after upload, so the id is its version.

comment on column public.cv_first_reads.readers is
  'Per reader: needle, quit_chunk, sayback, one_action, and remembered — up '
  'to three short phrases quoted from the CV (contact details removed). '
  'Readable only by the student who owns the CV.';

comment on column public.cv_first_reads.checksum is
  'The document id. A document''s file never changes after upload, so the id '
  'is its version; a re-upload is a new document and a new read.';
