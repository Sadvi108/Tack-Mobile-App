# Tack production audit and improvement plan

**Implementation update, 8 September:** see [production progress](PRODUCTION_PROGRESS_2026-09-08.md) for the changes and current evidence. The findings below describe the original audit. The product owner has since confirmed the database-defined daily allowance; the earlier recommendation to restore three actions is superseded.

Audited on 5 September 2026 UTC / 5–6 September in Dhaka; live checks ran from approximately 17:51 to 18:14 UTC. Scope: the current Flutter source, all 16 feature areas, automated checks, the configured live Supabase project, and an iPhone 17 simulator launch.

**Recommendation: hold the public production release.** Much of the core backend works, but the deployed photo-CV pipeline fails, several user-facing promises do not match the implementation, and release safeguards are incomplete. Use the working foundation for a controlled beta after the release blockers below are resolved.

This is an audit and implementation plan. No application features, migrations, production configuration, or dependencies were changed. Live checks used synthetic accounts and documents. Existing student data was not edited. Test accounts and uploaded test files were removed; synthetic shared-cache cleanup is recorded in the audit logs.

## What was actually verified

| Check | Result | What the result establishes |
|---|---|---|
| `flutter analyze` | Passed; no issues | Dart static analysis is clean. |
| `flutter test --reporter expanded` | 363 passed | Existing unit/widget tests pass, including several 360px layouts and contrast pairs in both palettes. |
| `deno test _shared/ profile/render_test.ts` | 94 passed | Existing backend logic and public-profile renderer tests pass. |
| `deno lint` | Passed | Current backend passes its lint rules. |
| `deno check` for all nine endpoint entry points | Passed | All endpoint sources type-check locally. |
| `deno fmt --check` | Failed | `analyze-jd/index.ts` and `profile/render_test.ts` are not formatted; the existing CI formatting gate fails. |
| `flutter run` on iPhone 17 / iOS 26.5 simulator | Built and launched | Xcode build completed and Supabase initialization completed. This was a development build. |
| Live RPC surface test | Passed | Checked anonymous RPC access is denied and worker grants are retained. |
| Live storage test | 15 passed, 1 failed | Ownership, private bucket, signing and overwrite protections pass. Two pre-existing orphaned objects remain. |
| Live onboarding test | 10 passed | Tested school branch, validation and cleanup pass. University UI completion is not established by this script. |
| Live dashboard test | 38 passed | Feed contents, isolation and tested dashboard calculations pass. |
| Live roadmap test | 24 passed | Generation, personalization, task/milestone behavior and tested restoration behavior pass. |
| Live Radar test | 28 passed | Tested filtering, matching, saving and isolation pass against synthetic listings. |
| Live CV-builder test | 12 passed | Profile-document assembly and ownership pass. PDF generation also has passing Flutter tests. |
| Live interview-bank test | 13 passed, 1 failed | Question sets resolve and do not consume allowance. Its remaining-allowance assertion still expects 3; live configuration is 10. |
| Live deterministic CV-score test | 43 passed | Scoring arithmetic, basis selection, ownership and tested score rules pass. This does not establish OCR functionality. |
| Live account-deletion test | 12 passed | Tested account rows and uploaded bytes are deleted; supplying somebody else's ID does not delete that person. |
| Live photo-CV pipeline test | 4 passed, 2 failed | Upload and submission succeed; no score returns within five minutes. OCR reports `Not implemented: Worker.prototype.constructor`. |
| Targeted live text-PDF and JD pipeline test | Both completed with Gemini | Text PDF received an 8.7/10 score and JD analysis completed via the normal worker. Neither model job charged the account's allowance. |
| Targeted live application test | Passed | Application creation, status/notes update, two history entries, cross-user isolation and rejection of forged history were verified through the API. |
| Additional live API probes | Mixed; detailed below | Notifications, coach answers, text-PDF checking and JD completion work; validation and duplicate recovery have defects. |

The existing test files are in [app/test](../app/test) and the live scripts in [tool](../tool). The audit ran the existing scripts sequentially with pauses between them.

The Mac screen-capture service failed twice with ScreenCaptureKit error `-3811`. Consequently, **manual screen-by-screen UI verification is incomplete**. No Android device was connected. Real-device camera capture, email delivery, OAuth callbacks, password recovery, native PDF sharing, release performance and push delivery remain unverified. Passing backend checks must not be described as every mobile feature working end to end.

Some existing live scripts are unsuitable for an unrestricted production run: `verify_db.js` calls the global `claim_jobs`, and `verify_notifications.js` invokes a digest for all eligible users. Those operations were excluded. Targeted probes covered notifications and application behavior without invoking those global operations.

## Feature inventory and production status

| Feature | Current evidence | Production change needed |
|---|---|---|
| Email authentication | Synthetic confirmed-account sign-in works. Live email confirmation is enabled. | Test real confirmation, resend, expired links, reset and cold-start callbacks. |
| Social authentication | Live settings: Google and GitHub enabled; Facebook and Apple disabled. UI exposes Facebook. | Hide unavailable providers; complete real-device callback tests and iOS login review. |
| Onboarding and year modes | SQL and Dart mode tests pass; onboarding data checks pass. | Make completion and recovery part of the central router; keep university onboarding focused. |
| Dashboard | Live feed passes; year-specific widget tests pass. | Connect each insight to a useful action and refresh it after that action; avoid unsupported cohort claims. |
| Readiness score | Deterministic score tests pass; cohorts are scoped by year/mode. | Explain evidence, version the formula and distinguish average comparison from percentile ranking. |
| Career paths | Following, suggestions and generated roadmaps have working backend coverage. | Expand curated paths beyond the current 10, with explicit relevance to Bangladeshi students. |
| Roadmap | Live generation and progression pass; offline task submission exists. | Complete durable offline behavior and add proof of completed work. |
| Applications | Saving through Radar and targeted API create/status/history/isolation checks pass. | Transactional creation, offline notes/status, reminders, CV version links and duplicate prevention. |
| Opportunity Radar | 706 live listings across four sources; tested save/filter behavior passes. | Improve local relevance, entry-level classification, eligibility and freshness. |
| Document vault | Private upload/read/signing/isolation pass. | Repair orphan lifecycle, mobile permissions, cancellation/retry and document recovery. |
| Photo-CV parsing | **Fails in deployed runtime.** | Prove a runtime-compatible OCR implementation; provide a clear supported-file path until it works. |
| Text-PDF CV check | Synthetic PDF produced two completed `cv_checks` rows via normal cron. | Wire this free endpoint into Flutter and coalesce duplicate checks. |
| Text-PDF CV parsing and score | A synthetic PDF completed with Gemini and received a deterministic 8.7/10 score. | Repair quota charging; retain the proven text-PDF path while resolving photo support. |
| CV builder | Live document data and local PDF tests pass. | Verify native export/share, long content, Bangla names and consistent selected CV versions. |
| JD analysis | Fresh synthetic description completes with Gemini; repeat request uses cache. | Fix quota charging, duplicate job handback, persistent job recovery and bounded validation. |
| Coach | Data answer returned 200 without spending allowance; language answer returned 200 with Gemini in about 6.9 seconds. | Queue model work, validate replies and centralize redaction and quota handling. |
| Interview practice | Seeded sets work. Invalid numeric role was accepted and triggered Gemini. | Strict role/type validation; queue generated questions and answer evaluation; verify full answer-feedback flow. |
| Notifications | Test inbox read, ownership and mark-read pass. | Complete device registration, permission flow, token lifecycle, delivery receipts and exact destination links. |
| Profile and settings | Profile-document ownership and widget tests pass; live account deletion passes. | Account-switch isolation, recovery and public support links; expose export of personal data. |
| Public employer profile | Renderer is tested; a nonexistent handle returns 404 as `text/plain`; no publish flow found in Flutter. | Keep out of release scope until publishing, revocation and actual HTML delivery are proven. |

## Release blockers and concrete fixes

### B1. CV capture and deployed OCR are not ready

**Live failure:** `tool/verify_deployed.ts` uploads the repository's synthetic CV photograph and submits `score-cv`. The normal worker attempts OCR, records the unsupported Worker-constructor error, and produces no score within five minutes. This directly contradicts the working-photo claim in `docs/TESTFLIGHT.md`.

**Separate native defect:** both `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` are missing from the source and the newly built iOS app's Info.plist. The vault calls `ImageSource.camera`. The plugin requires those declarations for the corresponding features. See [image_picker setup](https://pub.dev/packages/image_picker).

Change:

- Add accurate iOS usage descriptions and test allow/deny/cancel on a real phone.
- Reproduce OCR inside Supabase Edge Runtime, then select an implementation that works within the existing stack and data boundary. Do not route unredacted CV images to a model as a shortcut.
- Keep text PDFs usable, clearly identify unsupported/scanned inputs, and provide an actionable failure state while OCR is unavailable.
- Classify permanent runtime failures separately from retryable network failures. Never leave a document looking indefinitely busy.
- Exercise Android activity recreation and recover interrupted picker results.

Acceptance: the exact deployed photo test passes; a blurry image has a useful terminal state; denied camera access leaves the app usable; restart during upload/processing recovers the correct document. A release that intentionally defers photo support must remove the offer and promise from its UI and documentation.

### B2. AI quota and request handling need one enforceable contract

The live daily limit is **10**, while `AGENTS.md` and the privacy copy say **3**. More seriously, `analyze-jd` and `score-cv` currently check `quotaRemaining()` without consuming it, while their worker handlers use `{ consumeQuota: false }`.

**Confirmed live:** a fresh test account started at `used: 0, limit: 10`. A new JD analysis and text-PDF CV parse both finished with successful Gemini usage records; the PDF received a score. Afterwards the account was still at `used: 0, limit: 10`. Two model jobs charged zero actions. This needs fixing before opening the service to more students.

Live malformed-request results:

| Endpoint | Synthetic input | Observed |
|---|---|---|
| `coach` | `{"question":42}` | 500 |
| `analyze-jd` | `{"text":42}` | 500 |
| `cv-check` | JSON `null` | 500 |
| `score-cv` | JSON `null` | 500 |
| `interview/questions` | `{"role":42}` | 200; invoked Gemini and created a shared question set |

Change:

- Add strict Zod request schemas, UUID/enum/length validation and method restrictions. Adding Zod requires the repository's dependency approval at implementation time.
- Validate model replies recursively, including nested objects and numeric ranges. The current `validate()` accepts `object[]` using only `typeof item === 'object'`, which also admits null and does not validate fields.
- Implement an atomic, idempotent quota reservation alongside enqueueing. Charge once for real model work; free checks/cache hits cost zero; failures have a consistent refund policy.
- Restore the three-action policy through an append-only migration unless the product rule is explicitly changed to ten. Use the same server value in copy and tests.
- Define the reset timezone. Current SQL resets on UTC dates, so “midnight” means 06:00 in Dhaka unless the policy is changed.
- Route every model call through the shared AI layer with validated, redacted inputs. The coach currently calls the provider directly; generated interview questions use the role text without redaction.
- Return 202/job ID for model work. The coach and uncached interview generation currently return completed responses synchronously.

Acceptance: malformed bodies consistently return 400 without quota or model usage; concurrent submissions cannot exceed the policy; a failed request cannot charge twice; no unredacted contact test fixture reaches a provider; a model action can finish after the app is closed.

Evidence: [analyze-jd](../supabase/functions/analyze-jd/index.ts), [score-cv](../supabase/functions/score-cv/index.ts), [job handlers](../supabase/functions/_shared/jobs/handlers.ts), [coach](../supabase/functions/coach/index.ts), [schemas](../supabase/functions/_shared/ai/schemas.ts), [quota migration](../supabase/migrations/0070_ai_daily_limit.sql).

### B3. Duplicate submission and result recovery can strand the student

Live: submitting the same new JD twice returns 202 both times, but the second response has no job ID. `AnalyserController` only starts polling when an ID is present. Reopening or retrying that submission can therefore leave it without progress tracking.

The free CV checker has the opposite defect: two immediate requests produce two different jobs and two results. Its idempotency key includes `Date.now()`, despite the comment promising one pending check per document.

Change: use stable operation keys, return the existing job ID, persist active work in Drift, reconcile status on startup/resume, and provide retry/cancel where supported. Bound concurrent free work per account without presenting it as a paid AI allowance. Use database constraints to coalesce pending work.

Acceptance: double-tap, timeout/retry, app restart, and two-device submission resolve to a discoverable operation; no duplicate model charge or duplicate pending CV check.

### B4. Offline support does not yet fulfill the product promise

Source findings:

- `putCache()` / `readCache()` have no production callers. A fresh offline launch cannot restore the advertised roadmap/application data from Drift.
- Only roadmap task toggles enqueue writes; application notes and status changes do not.
- The outbox and cache have no account identifier. Sign-out does not clear or partition them.
- Synchronization starts only on a detected offline-to-online transition, not an already-online cold start or successful reauthentication.
- A flush reads at most 50 changes and does not loop through the backlog.
- After five errors it silently discards a change. A prolonged connectivity issue can lose work.
- A queued roadmap toggle does not update the visible task state. Sync success also lacks coordinated provider refresh.

Change: make repositories combine remote data with account-scoped Drift tables; record local state and an outbox operation in one transaction; distinguish retryable failures from conflicts; retain failed work visibly; drain on reconnect, startup and resume; verify the intended account and successful server update before discarding.

Acceptance: edit a task and application on airplane mode, terminate the app, reopen offline, restore connectivity, and verify the edits on a second device. Test switching accounts with pending work and a backlog exceeding 50 items. Flutter's [offline architecture guidance](https://docs.flutter.dev/app-architecture/design-patterns/offline-first) places this responsibility in repositories.

Evidence: [local DB](../app/lib/core/offline/local_db.dart), [sync service](../app/lib/core/offline/sync.dart), [roadmap screen](../app/lib/features/roadmap/presentation/roadmap_screen.dart), [application repository](../app/lib/features/applications/data/application_repository.dart).

### B5. Store-facing authentication, policy links and signing need completion

- Both exact privacy/terms URLs used by the app returned **404 to an unsigned-in HTTP request**. Files existing in this checkout does not make the links accessible to students.
- Facebook is offered in the sign-in UI while live configuration disables it.
- Android's release build explicitly uses the debug signing configuration.
- The router redirects a newly signed-in user from login straight to `/home`; onboarding completion is checked only on the splash route. There is no `passwordRecovery` event handler in `app/lib`. These are source-level risks pending device reproduction.
- Google/GitHub sign-in are configured, but neither a full callback nor an equivalent privacy-preserving iOS login option was verified. Apple is disabled and absent from the app's provider enum.

Change: serve reachable policies and a support/deletion-request resource, expose only configured login methods, centralize onboarding/recovery routing, and build signed release artifacts. Review the iOS login offering against [Apple guideline 4.8](https://developer.apple.com/app-store/review/guidelines/#login-services). An App Store decision was not tested or inferred from a simulator launch.

Google Play also requires an accessible outside-app deletion-request path; the passing in-app endpoint alone does not establish that requirement. See [Google's deletion requirements](https://support.google.com/googleplay/android-developer/answer/13327111).

Acceptance: policies open without repository access; confirmation/reset links work on a cold and warm app; interrupted onboarding resumes correctly; enabled social login returns to the right screen; release bundles are signed with the intended production identity.

### B6. Crash reporting conflicts with the specified data boundary

Sentry is a direct dependency and `CrashReporting` sends an account ID and crash data when configured. This conflicts with the explicit Supabase-only crash/analytics rule. The audit did not verify a live Sentry transmission.

There is an `Analytics.reportError()` method for Supabase, but no calls to it were found. The statement in `docs/SENTRY.md` that errors independently land in Supabase is therefore not supported by the current wiring.

Change: implement the specified Supabase error path, with allowlisted error codes, sanitized stack/context and release identifiers; remove the external crash path in a scoped change. Make error ingestion survive startup/auth failures without exposing a public spam endpoint. Validate analytics properties by an allowlist, including permitted values; the current key blacklist and 40-character cap can still accept a short email under an unexpected key.

Acceptance: an intentional test crash produces a useful, scrubbed Supabase report; events contain only the permitted event names/counts/enums; student data has no external crash destination.

## Important issues after the first blockers

| Priority | Finding | Required change |
|---|---|---|
| P1 | All 69 public tables have RLS enabled, but `score_weights` and `schema_migrations` do not force it. No cross-user leak was demonstrated. | Add an append-only migration to meet the force-RLS rule and rerun access tests. Keep reference/admin tables explicitly read-only to clients. |
| P1 | Two storage objects without document rows predate this audit. Their timestamps were 09:03 and 17:28 UTC on 5 September. | Inventory ownership before cleanup; make upload rollback, account deletion and scheduled orphan reconciliation idempotent. Existing files were not deleted by this audit. |
| P1 | `cv-check` works live but there are no Flutter calls to it and no `cv_checks` read path. The vault sends every CV upload to `score-cv`. | Add the free check result screen, explain when optional AI help spends allowance, and make the main CV action match the free-feature copy. |
| P1 | Radar has 387 AI Jobs, 200 Arbeitnow, 101 The Muse and 18 Remotive listings; no location field matched Bangladesh/Dhaka/Chattogram/Chittagong/Sylhet. | Establish Bangladesh sources and explicit remote-country eligibility. Absence of a local label does not prove a remote role is ineligible. |
| P1 | Only 43 listings are classified as internships; many seniority fields are inconsistent or unknown. | Normalize seniority and distinguish unknown eligibility from a good match. Add provenance and reporting for stale or misleading listings. |
| P1 | Score copy says “Ahead of most” using `score >= average + 5`. A mean does not establish a percentile. | Either compare explicitly to the average or compute a real percentile for the student's own year with a minimum sample size. |
| P1 | Readiness can reward self-entered project counts without evidence quality. | Keep self-reported and verified evidence separate; show what changed the score and why. Avoid presenting readiness as a probability of employment. |
| P1 | 83 imports in presentation files point into data layers, including cross-feature dependencies. Several repository mutations scope only by row ID. | Introduce application providers/controllers and typed commands; scope repository operations by account as well as keeping RLS. Refactor feature by feature. |
| P1 | `ApplicationRepository.create()` makes separate company/job/application requests. | Put creation and initial history in one idempotent SQL transaction, and handle retries without orphan jobs or duplicate applications. |
| P1 | Body-muted text is 15px; feature code contains 15 literal-color occurrences; text scaling is capped at 1.3. | Restore the 16px body floor, named palette tokens, flexible large-text layouts, screen-reader semantics and keyboard-safe pinned CTAs. |
| P1 | Reveal animation is 620ms, with number/ring animation, beyond the 150–200ms color/transform rule. | Bring motion back to the specified budget and measure performance on a mid-range Android. |
| P1 | No `app/integration_test` suite; CI checks only six of nine endpoints and omits the profile renderer tests. | Add real device/emulator journeys, include every endpoint, enforce dependency locks and compile signed release candidates. |
| P1 | Backend import ranges are floating and `deno.json` disables locking. | Introduce reproducible dependency resolution and verify production deploy provenance. |
| P1 | Push has no Flutter device-registration or permission flow; initial DB inspection found no device tokens. | Complete client delivery or present only the working in-app inbox. Never send CV/job/note text in push payloads. |
| P2 | Public-profile publishing is unfinished; deployment docs suggest infrastructure excluded by `AGENTS.md`. | Correct the plan and prove a stack-compatible delivery route before offering shareable employer pages. |
| P2 | `docs/DEPLOY.md` says 65 migrations; live DB has 71. Several documents disagree on privacy, quotas and feature completion. | Generate/check a release manifest and keep product claims tied to live acceptance evidence. |

## The larger changes worth building

The next substantial release should make a student's weekly progress coherent: choose a direction, do a useful task, keep proof, improve a CV and act on a suitable opportunity.

The estimates below are planning ranges in **engineering days**, not delivery commitments. They assume the current stack and exclude account approvals, new paid providers, content acquisition and store review. Dependency additions and infrastructure changes need review when their implementation is proposed.

| Epic | Concrete scope | Completion criteria | Estimate |
|---|---|---|---|
| E1 — Reliable mobile foundation | Platform/auth/privacy fixes from B1/B5/B6; signed builds; recovery routing; reachable policies; runtime-tested CV fallback. | Platform and privacy blockers have passing regression checks; real-device critical paths pass. | 12–18 days; OCR feasibility is the main uncertainty. |
| E2 — Durable personal workspace | Account-scoped Drift reads and writes; optimistic state; sync status; retries/conflicts; startup/resume reconciliation; transactional application commands. | Airplane-mode/restart/account-switch/two-device tests pass without losing or mixing work. | 8–12 days. |
| E3 — Unified CV and AI workflow | B2/B3 quota/validation/job fixes first; free CV checks in Flutter; optional paid parsing/coaching; cancel/retry/resume; comparison between document versions. | Free paths stay free; model work charges once; each job has a recoverable visible outcome; PDF/photo behavior matches the supported formats. | 8–12 days. |
| E4 — Bangladesh opportunity quality | Curated local-source ingestion; entry-level and country eligibility; source/freshness labels; duplicate/expired listing handling; bookmarks and report-listing flow; scoped content-operations tools. | A manually reviewed pilot sample is relevant to the target students; stale records expire; users can explain why a role is shown. | 10–15 days plus ongoing content work. |
| E5 — Weekly plan and evidence portfolio | A short weekly plan based on year, skills and available time; project briefs/rubrics; evidence links; outcomes/reflection; CV bullets built from approved profile evidence. | A student can finish a project step, attach proof, see the justified score/plan change and reuse it in a CV. | 10–15 days. |
| E6 — Application and interview loop | Next action/date per application; tailored CV version; role-specific practice; saved feedback; interviewer notes; in-app reminders and optional verified push. | A launch-mode student can move from saved role to application to interview preparation with context preserved and no duplicate reminders. | 8–12 days. |
| E7 — Production operations and trust | Supabase-only health/error metrics; queue/dead-letter visibility; deployment verification; safe synthetic monitoring; restore drills; support tools; score versions and cohort-quality controls. | A failed job is detectable, diagnosable and recoverable; a backup restoration is demonstrated; every released binary can be tied to tested backend versions. | 8–12 days. |

The table totals approximately 64–96 engineering days before contingency. A reasonable planning envelope is **10–14 calendar weeks with two engineers**, part-time QA/design and a named content owner. Re-estimate after E1's OCR and release-device investigation. A solo implementation will take longer.

### Keep the experience year-aware

| Student mode | New experience should lead with | Release acceptance |
|---|---|---|
| Explore / first year | Two paths to try, this semester's courses, a small discovery activity. | No application funnel or deadline-led copy; comparisons use their own year. |
| Build / second year | One suggested project, skills to practise, a manageable weekly plan. | Project completion produces evidence; no application funnel. |
| Prove / third year | Internship eligibility, portfolio gaps, project proof and optional networking preparation. | Suitable internships and specific proof gaps take priority; no application funnel. |
| Launch / final year | Seven-day action list, applications, CV readiness and interview practice. | Every upcoming item opens the correct application or preparation task. |

School-age and graduate branches already exist in the source. Keep their existing data safe, but avoid expanding those journeys during this production push. First make the university-to-first-job experience complete; additional audiences need separate product acceptance criteria.

### Suggested sequence

1. **Weeks 1–3: make an internal release candidate.** Complete E1 and the blocking parts of E3, prove text-PDF and photo policy, fix AI quota and malformed requests, repair links/signing, add device smoke tests and baseline Supabase diagnostics.
2. **Weeks 3–6: make work durable.** Complete E2 and the stable-job/free-CV parts of E3. Introduce application controllers as those features are touched. Begin local opportunity sourcing in parallel with development.
3. **Weeks 6–9: improve the career outcome.** Ship E4 and a narrow E5: one weekly plan, one project brief and one evidence-to-CV flow per supported path.
4. **Weeks 9–12: complete the application loop.** Ship E6, validated reminders and the rest of E7. Run a controlled university pilot and fix measured friction.
5. **Weeks 12–14: contingency and rollout.** Device regressions, restored-backup validation, accessibility/performance fixes, support training and store review.

Release by passing gates, not by reaching a date. Avoid adding a social feed, recruiter marketplace, payments or another AI provider during this cycle: they do not resolve the failures or incomplete workflows found here.

## Production acceptance gates

These are proposed targets to validate with the pilot, not current measured service levels.

| Gate | Required evidence before public rollout |
|---|---|
| Automated checks | Clean analysis, all Flutter/backend tests, formatting, all endpoint type checks and a real Android/iOS compile. Add meaningful integration tests against a local/staging fixture environment. |
| Live critical journey | Sign up → confirm → finish onboarding → follow path → complete task → upload/check CV → save role → update application → practise interview → delete account. Run with synthetic accounts on both platforms. |
| Failure recovery | Network interruption, expired token, rejected upload, full/large file, backgrounding, restart, duplicate tap, 429, 5xx and two-device conflict all have tested outcomes. |
| AI and queue | The allowance from `public.ai_daily_limit()` is consistent end to end; zero model use on free/cache paths; invalid input rejected; paid actions queued; no stuck document or duplicate charge. Track queue wait and processing separately. |
| Accessibility | 360px width, both palettes, 44px controls, 16px body text, large system text, VoiceOver/TalkBack and keyboard-open forms. CTA stays outside the scroll region. |
| Performance | Measure release startup, frame times, memory and data use on a mid-range Android over constrained network. Initial proposed target: usable cached home under 2 seconds; ordinary warm API reads p95 under 1 second, validated from Bangladesh. |
| Security and privacy | Forced RLS; cross-user read/write/storage/RPC tests; account-switch cache isolation; scrubbed analytics/errors; reachable policies; tested deletion and documented retention. |
| Operations | Alerts for oldest runnable job, permanent failures, upload/parse errors and login failures; documented recovery owner; successful database **and file** restore exercise. Confirm service capacity with staged load tests. |
| Pilot quality | Start with a small, explicit university cohort; review activation, weekly completed work, failed saves/uploads, local-opportunity relevance and support requests. Expand only after the failures are resolved. |

Flutter's [integration-test guidance](https://docs.flutter.dev/testing/integration-tests) supports testing full application behavior beyond isolated widget tests. Supabase's [production checklist](https://supabase.com/docs/guides/deployment/going-into-prod) covers operational security, capacity, availability and recovery preparation; those dashboard settings were not all verified in this audit.

## Evidence and follow-up

Temporary local evidence files from this run:

- `/tmp/tack-flutter-test-audit.log`
- `/tmp/tack-deno-test-audit.log`, `/tmp/tack-deno-check-audit.log`, `/tmp/tack-deno-lint-audit.log`, `/tmp/tack-deno-format-audit.log`
- `/tmp/tack-ios-run-audit.log`
- `/tmp/tack-live-audit-results.json` and `/tmp/tack-live-*-audit.log`
- `/tmp/tack-live-probes-results.json`
- `/tmp/tack-final-live-results.json`

Temporary probes were intentionally kept outside the repository. A permanent test harness should record exact fixture IDs, guarantee cleanup in `finally`, remove synthetic shared cache entries and avoid global production queue/digest actions. Logs are local audit evidence, not deployable application assets.

Final cleanup verification: zero audit-created test accounts remained; test uploads were removed; the generated numeric-role question set and synthetic JD cache entries were removed. The two pre-existing orphan files remained unchanged. Aggregate AI usage/audit records can remain under the existing retention design after their test account is deleted.

**First implementation batch:** CV runtime/permissions, enforced AI quota and schemas, stable job IDs, reachable policy links, configured login methods and proper release signing. Complete those before investing in the larger product additions.
