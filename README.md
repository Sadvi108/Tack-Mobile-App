# Tack

For university graduates and soon-to-be graduates who want to know their
career map and build toward it.

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

Every piece of data Tack holds lives in one Supabase project: accounts, tables,
documents, analytics and error reports. There is no third-party analytics or
crash service, so nothing about a student leaves it.

## Checks

```bash
cd app && flutter analyze && flutter test
```

```bash
cd supabase/functions && deno check analyze-jd/index.ts worker/index.ts interview/index.ts && deno test _shared/
```

```bash
node tool/verify_db.js && node tool/verify_storage.js && node tool/verify_dashboard.js
```

The last three create throwaway users against the live database, try to make
one read the other's data, and delete them again. Run them after any change to
a policy or a migration.

## Where the rules live

- `AGENTS.md` — stack, architecture, security and copy rules
- `docs/API.md` — every call the app can make: the RPCs, the edge
  functions, what is deliberately not reachable, and the boards Tack calls out to
- `docs/DATA_MODEL.md` — every table and column
- `docs/DASHBOARD_FEED.md` — the home screen's one RPC, its shape, and the two
  places it used to contradict itself
- `docs/DEPLOY.md` — what is live and what still needs a human
- `PRIVACY.md` and `TERMS.md` — what Tack holds, what leaves the database,
  and what the app does and does not promise
- `design/DESIGN_HANDOFF.md` — colours, type, spacing and every screen's intent
