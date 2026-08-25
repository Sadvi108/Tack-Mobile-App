# Tack

A career workspace for Bangladeshi university students, from first year to
first job. Not a job board: a readiness score, a personalised roadmap, an
application tracker, a document vault, a job-description analyser and
interview practice.

The app is **year-aware**. One answer during onboarding — which year you are
in — decides what every dashboard leads with and what language it uses. A
first-year is shown career paths and never a deadline; a final-year is shown
dates and a funnel.

## Layout

```
app/                 Flutter app (Android and iOS)
  lib/design/        the design system — tokens, type, components, shell
  lib/features/      one folder per feature: data, application, presentation
  lib/core/          Supabase client, failure mapping, offline queue
supabase/
  migrations/        SQL, append-only, applied with tool/migrate.js
  functions/         Edge Functions (Deno) — the only place a model is called
  seed/              source data for the skill vocabulary and career paths
tool/                migration runner and live verification scripts
docs/                data model, deployment, workstreams
design/              the original design handoff
```

## Running it

```bash
cd app && flutter run --dart-define-from-file=env/dev.json
```

`env/dev.json` is gitignored. Copy `env/dev.example.json` and fill it in — it
holds only the Supabase URL and anon key, which are safe in a client because
Row Level Security is the actual boundary.

## Checks

```bash
cd app && flutter analyze && flutter test
```

```bash
cd supabase/functions && deno check analyze-jd/index.ts worker/index.ts interview/index.ts && deno test _shared/
```

```bash
node tool/verify_db.js && node tool/verify_storage.js
```

The last two create throwaway users against the live database, try to make one
read the other's data, and delete them again. Run them after any change to a
policy or a migration.

## Where the rules live

- `AGENTS.md` — stack, architecture, security and copy rules
- `docs/DATA_MODEL.md` — every table and column
- `docs/DEPLOY.md` — what is live and what still needs a human
- `design/DESIGN_HANDOFF.md` — colours, type, spacing and every screen's intent
