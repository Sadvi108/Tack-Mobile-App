# Production progress — 8 September 2026

This records implementation following the [production audit](PRODUCTION_AUDIT_2026-09-06.md), including the requested Vault opening fix and broader Radar catalogue. It does not mark the full production roadmap complete.

## Vault: open a resume with a device app

Tapping a document downloads a private local copy and asks the operating system to open it. Android offers installed readers through a chooser and a temporary FileProvider read grant. iOS uses its document options menu and system preview. The reader receives a local file, with the correct extension, rather than a Supabase URL.

The repository checks ownership before issuing a five-minute download URL. Copies use an account-specific cache folder; old copies are removed on subsequent opening. Downloads are bounded by size and time, incomplete files are discarded, and repeated taps do not start duplicate downloads. A separate options button retains rename, default-CV selection, supported CV checks and deletion. Phones without a reader receive an actionable message.

These native changes require installing a new mobile build. Hot reload cannot install a native method channel or Android provider. No physical phone was connected for an installed-reader test. Computer Use also timed out, so compiled native code and automated tests do not establish a complete device journey.

## Radar and career paths

Migration `0075` is live. The catalogue has **139 paths across all 39 named career fields**, up from ten paths. Each field has at least three roles. The 129 new paths each include starter skills, three milestones and nine tasks; following a new path generates real student roadmap tasks.

Radar now offers searchable field and role pickers. Selecting a role starts a Radar search. The Paths screen also supports searching and filtering by field. Roles cover technology, engineering, health, business, law, agriculture, sciences, arts, education, hospitality, public service and other existing fields. Regulated roles are framed as exploration with approved training requirements.

These are career paths, not additional vacancies. Local vacancy sourcing, eligibility and freshness still need the content work in the audit. New paths do not invent salary estimates or demand statistics.

## Production foundation

Migrations `0072`–`0074` are now live: atomic job submission and quota reservation, duplicate recovery, exact-once refunds, private error ingestion, and transactional application creation with stale-edit conflict detection. Tests exercise these contracts in rollback-only transactions without invoking the global worker.

Zod validates API boundaries and nested model responses. Model-backed coaching and interview work use the queue. Private error reporting, account-scoped offline storage, saved sync conflicts, recovery routing and free CV checks are included in the current app source from the earlier implementation. Their remaining device acceptance gates are listed below.

`public.ai_daily_limit()` remains the only definition of the daily allowance. The value was verified as ten. Dart, TypeScript and student-facing policy copy do not define a second allowance. Candidate migration `0072` was corrected before it was applied; already-applied migrations were not rewritten.

## Photo reading is deferred

The direct WASM OCR experiment produced usable text locally, but the deployed worker was terminated with `CPU Time exceeded` at 3,161 ms. The previous Node worker-constructor failure was therefore replaced by another runtime limitation, not a working production OCR service. [Supabase documents the hosted CPU limit](https://supabase.com/docs/guides/functions/limits).

The deployed endpoints now reject photo feedback before queueing or charging, with instructions to upload a text PDF or Word `.docx` file. Existing photo jobs get a readable terminal outcome when processed by the new worker. Photos can still be uploaded and opened; the app no longer automatically requests checks for them. Scanned PDFs also receive an explanation when they have no readable text layer. The experimental OCR module is retained only for further local feasibility work.

## Deployment record

All 75 migrations are recorded as applied. All public tables have enabled and forced RLS. The existing three cron schedules remain active.

| Function | Live version | Status |
|---|---:|---|
| worker | 9 | Active |
| score-cv | 6 | Active |
| cv-check | 3 | Active |
| analyze-jd | 6 | Active |
| coach | 7 | Active |
| interview | 5 | Active |
| radar | 7 | Active |
| policies | 1 | Active |

`profile` and `delete-account` remain at version 1. User-facing private endpoints authenticate through `requireUser`; the worker checks its cron bearer secret. Public policy routes intentionally allow unauthenticated reads.

## Verification completed

| Check | Result |
|---|---|
| Flutter static analysis | No issues |
| Flutter unit and widget suite | 366 passed, including Vault tapping/options and field selection at 360px |
| Android debug build | Passed; `app/build/app/outputs/flutter-apk/app-debug.apk` |
| iOS simulator debug build | Passed; `app/build/ios/iphonesimulator/Runner.app` |
| Backend tests | 99 passed; formatting, lint and all ten endpoint type checks passed |
| Live supported-CV release checks | 29 passed; private download bytes matched, text PDF scored 6.8/10 against its selected path, free check saved once, duplicate requests reused jobs, paid submission reserved one action, photo feedback queued nothing and charged nothing |
| Live public interfaces | Malformed inputs rejected by all six checked endpoints; all 139 paths readable by the synthetic student; privacy, terms and support returned readable public pages |
| Database contract checks | Atomic application/history writes, conflicts, quota reservations/refunds, duplicate identity, ownership, restricted RPC grants and private error filtering passed inside rollback-only transactions |
| Catalogue checks | 39 fields with at least three paths each; all 129 new paths have starter skills and nine tasks; following a new path generated student tasks |

Live fixtures used synthetic accounts and documents. Their accounts and uploaded files were removed. The tests used the normal worker cron and did not force global queue or digest operations. Local logs: `/tmp/tack-flutter-sept8.log`, `/tmp/tack-backend-sept8.log`, `/tmp/tack-live-final-sept8.log`, `/tmp/tack-android-sept8.log`, `/tmp/tack-ios-sept8.log`.

## Remaining release gates

- Install and verify opening, reader choice, cancel, missing reader, camera permissions and app resume on Android and iOS.
- Run the full sign-up, confirmation, recovery and OAuth journeys on devices.
- Verify airplane mode, restart, account switching and two-device conflict resolution end to end.
- Complete signed store builds, accessibility with screen readers and release performance measurements.
- Validate local opportunity quality, operational alerts, backup restoration and a controlled student pilot.
- Keep photo feedback out of production scope until an implementation fits the existing privacy boundary and deployed runtime limits.

The larger weekly-plan, evidence portfolio, application reminders and operations epics remain in the original roadmap. Public rollout is still gated on the above evidence.
