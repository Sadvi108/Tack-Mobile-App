# Workstreams

Five parallel streams over a shared foundation. The foundation — database,
Row Level Security, seeds, design system, app shell, routing — is already in
place and is **not** owned by any stream.

## File ownership

Each stream owns its directories exclusively. Nobody edits another stream's
files, and nobody edits the shared foundation; changes there are requested,
not made.

| Stream | Owns | Depends on |
|---|---|---|
| 1 — Auth and onboarding | `app/lib/features/auth/`, `app/lib/features/onboarding/` | profiles, education, user_skills, cities, universities, skills |
| 2 — Dashboards and readiness | `app/lib/features/dashboard/`, `app/lib/features/score/` | readiness_scores, cohort_benchmarks, score_weights, roadmap_tasks |
| 3 — Career paths and roadmap | `app/lib/features/paths/`, `app/lib/features/roadmap/` | career_paths and its template tables, roadmaps, roadmap_milestones, roadmap_tasks |
| 4 — Applications and vault | `app/lib/features/applications/`, `app/lib/features/vault/` | jobs, job_applications, application_status_history, documents, storage |
| 5 — AI layer and features | `supabase/functions/`, `app/lib/features/analyser/`, `app/lib/features/interview/` | jobs_queue, ai_usage, rate_limits, job_analyses, interview tables |

Shared and owned by the CTO: `app/lib/core/`, `app/lib/design/`,
`app/lib/config/`, `app/lib/routing/`, `app/lib/features/profile/`,
`supabase/migrations/`, `tool/`.

## Ground rules

- `flutter analyze` must be clean and `flutter test` must pass before a stream
  is done. Run them; do not assume.
- Do not run `flutter build apk` — the Gradle lock is shared and concurrent
  builds deadlock. The CTO runs builds.
- Do not commit. The CTO commits after review.
- Do not add a dependency. Everything needed is already in `pubspec.yaml`.
- Do not write a migration. Request one.
- Screens are exported widgets. Routing is wired at integration, so no stream
  edits `routing/router.dart`.

## Reading order for anyone joining a stream

1. `AGENTS.md` — the rules, including the year-aware model and copy standards
2. `design/DESIGN_HANDOFF.md` — colours, type, spacing, every screen's intent
3. `app/lib/design/tack.dart` and the files it exports — the component library
4. `docs/DATA_MODEL.md` — every table and column
5. `supabase/migrations/` — the constraints and functions that back it

## Querying the database while working

```bash
node tool/psql.js "select slug, title from public.career_paths order by sort_order"
```
