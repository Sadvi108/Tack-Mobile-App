# Application checklist and interview prep brief Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every active application shows a checklist built from rules, with one pinned next step.
An application at the interview stage can get a prep brief (1 AI action) whose talking points
must cite a skill or project the student really has.

**Architecture:**
- The checklist is a SQL function, `application_checklist(id)`, with fixed rule ids and the
  precedence DATE > PRACTICE > PREP > CV > JD > FOLLOW. It uses the insurance intake team's
  findings plus next-message pattern.
- The prep brief is a worker job, `interview_prep`, with the endpoint `interview-prep`. Its
  inputs are built from the student's own rows, then redacted. The model returns
  `talking_points`, `likely_questions`, `questions_to_ask` and `gaps`.
- An evidence gate in `_shared/prep/evidence.ts` keeps only the points whose evidence names an
  input skill or project as a whole word. It keeps only the gaps the student does not already
  have. With fewer than 2 grounded points, the job returns `skipped`, and the existing trigger
  refunds the action.
- Briefs are cached per application and input hash in `interview_prep_briefs`.
- The allowlist migration also admits `cv_first_read` and `coach_cited`, so the next two
  features don't redefine `enqueue_student_job` again.

**Tech stack:** Postgres, Deno Edge Functions with zod, and Flutter.

Spec: `docs/superpowers/specs/2026-10-22-borrowed-features-design.md`, section 2.

## Files

- `supabase/migrations/0082_application_checklist.sql`. It adds:
  - `tack_text_hash`: the SQL twin of `hashText`
  - `application_checklist`
  - the `interview_prep_briefs` table and its RLS
  - `enqueue_student_job` with the three new types and their ownership checks
- `tool/verify_application_checklist.js`: live rules, the hash matching `hashText`, ownership
  checks, and RLS.
- `supabase/functions/_shared/prep/inputs.ts`: builds the redacted inputs and hashes them.
- `supabase/functions/_shared/prep/evidence.ts` and `evidence_test.ts`: the gate.
- `supabase/functions/interview-prep/index.ts`: the endpoint. Cache first, then enqueue.
- `supabase/functions/_shared/jobs/conversation_handlers.ts`: the `interview_prep` handler.
- `supabase/functions/_shared/ai/response_validation.ts`, `provider.ts` and `schemas.ts`: the
  schema, the shape, and the mock fixture.
- `app/lib/features/applications/data/checklist_models.dart`: `Checklist`, `ChecklistItem`,
  `PrepBrief`.
- `app/lib/features/applications/data/application_repository.dart`: `checklist`, `prepBrief`,
  `requestPrep`, `cvOptions`.
- `app/lib/features/applications/presentation/checklist_card.dart` and `prep_brief_card.dart`.
- `app/lib/features/applications/presentation/application_detail_screen.dart`: wire them in.
- `app/lib/features/analyser/...`: `analyse(text, jobId:)`, so the checklist can check this
  job's own description.
- Tests:
  - `app/test/features/applications/checklist_models_test.dart`
  - `app/test/features/applications/checklist_card_test.dart`
  - `supabase/functions/_shared/prep/evidence_test.ts`

## Tasks

1. Red: `node tool/verify_application_checklist.js` fails with `application_checklist` not
   existing.
2. Green: write 0082, apply it with `node tool/migrate.js 0082_application_checklist`, and run
   the verify script until all checks pass.
3. Red, then green: `deno test _shared/prep/`. Then write the inputs, evidence, handler,
   endpoint, schema and mock, and run `deno check` / `lint` / `fmt` on everything.
4. Deploy `interview-prep`, then `worker` with `--no-verify-jwt`. Live-check one brief end to
   end on a throwaway student, including an ungrounded mock reply being refunded.
5. Red, then green: Flutter model and card tests. Then the repository, cards, and detail
   screen wiring. Run `flutter analyze && flutter test`.
6. A cavecrew reviewer audits the diff, then fixes, then
   `feat(applications): a checklist, and a prep brief that cites you`.
