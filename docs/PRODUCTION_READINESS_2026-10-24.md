# Production readiness review — 24 October 2026

**Decision: hold the public production release.** The app has a substantial working foundation, but authentication delivery/callbacks and account-deletion correctness need work before launch.

This review combines current Flutter/Edge Function source, automated checks, and read-only checks against the configured live Supabase project. It did not send emails, create accounts, delete data, change server settings, drain workers, or claim to complete a physical-device journey. Findings marked “source” describe a code path; they are not newly reproduced destructive failures.

## Your signup example

The live project currently has **email confirmation enabled** (`mailer_autoconfirm=false`). Supabase can create a pending account before verification; creating that record is different from granting access. No new unverified-login bypass was demonstrated in this review.

The concrete problems are that **custom SMTP is absent**, the project has a **two-emails-per-hour limit**, its **site URL is `http://localhost:3000`**, and its **redirect allow-list is empty**. The app requests `com.tack.app://auth-callback` for signup, password recovery and OAuth. These settings leave the email journey unsuitable for a public launch.

The code also intentionally accepts an immediate signup session when email confirmation is disabled. A future server-configuration regression would therefore be accepted by the app. A release preflight must detect that regression. A client check alone is not an access-control boundary, and `email_confirmed_at` alone cannot distinguish an email verified by its owner from one automatically confirmed while the server setting was disabled.

An emailed confirmation link satisfies the email-ownership requirement. An email OTP is an alternative; both are not necessary. Neither is the same thing as requiring a second factor at every login.

Supabase documents the default sender as unsuitable for production and restricted to authorized recipients. See [custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp), [confirmation configuration](https://supabase.com/docs/guides/auth/general-configuration), and [email link/OTP templates](https://supabase.com/docs/guides/auth/auth-email-templates).

## Prioritized findings and fixes

P0 means fix before any public release. P1 means complete before general availability, or explicitly remove the affected feature from the release. P2 identifies functionality that can remain deferred with accurate UI and release scope.

| ID | Priority | Gap and evidence | Fix and completion evidence |
| --- | --- | --- | --- |
| F01 | P0 | **Production email delivery is not configured.** Live auth configuration has no custom SMTP host or sender; email capacity is two/hour. Confirmation and password recovery share this dependency. | Configure a verified sending domain and SMTP credentials securely, disable link rewriting, and set pilot-appropriate capacity. Prove delivery to ordinary external inboxes, confirmation and password recovery. An API “sent” timestamp is not inbox delivery evidence. |
| F02 | P0 | **Mobile auth redirects are missing on the server.** Live allow-list is empty and site URL points to localhost. Native scheme declarations already exist on Android and iOS. | Allow the exact app callback, configure a real HTTPS fallback, then verify signup, recovery and Google/GitHub returns with the app running, backgrounded and closed. Check expired/used links and callbacks opened on another device. |
| F03 | P0 | **Account deletion can report success without reliably enumerating all files.** Source: `delete-account/index.ts` returns an empty list on storage listing errors, lists only 1,000 entries per folder without pagination, and uses `users/<uid>` for both buckets even though avatar policies use `<uid>/…`. A later removal failure can say “Nothing has been removed” after an earlier bucket was removed. These failure paths were reviewed, not destructively exercised live. | Fail on enumeration errors, paginate, use each bucket's actual ownership prefix, batch removals, and make partial progress/retry behavior truthful and idempotent. Prevent concurrent uploads from escaping deletion. Test listing failure, nested files, pagination, avatar cleanup, retry and final absence of owned objects before removing identity. |
| F04 | P1 | **Verification has no complete user journey.** Source: signup shows a toast and goes to login; resend exists in repository/controller but no presentation calls it. No code-entry screen exists. The existing tests cover validation/layout, not the complete ownership-verification contract. | Add a persistent “Confirm your email” state with the entered address, resend cooldown, change-address/back-to-login options, and useful expiry/delivery errors. Keep protected access under server control. Test new, pending, duplicate, confirmed, expired and rate-limited cases. Retain links, or deliberately implement OTP plus matching templates. |
| F05 | P1 | **Server account protections lag behind the app.** Live password minimum is six, while Dart requires eight. Leaked-password protection, CAPTCHA, password-change security email and server password-change reauthentication are disabled. Client reauthentication exists for changing a password, but a direct API caller bypasses that UI. Deletion only requires a live session and typed confirmation. | Enforce the chosen minimum on the server, configure supported password/abuse protections, enable security notices, and require recent ownership proof for sensitive actions through a server-enforced mechanism that also works for OAuth accounts. Test direct API calls, not just forms. Document alternatives for unavailable plan features. |
| F06 | P1 | **Deleting an account does not erase its local copies.** Source: deletion removes server data and signs out, but does not purge that user's Drift cache/outbox or downloaded vault files. `DeviceDocument.destination` removes old temporary files only on a later document open. | Add account-scoped local cleanup after confirmed server deletion, including cached documents and queued writes. Close database handles safely and test deletion followed by restart/account switching. Preserve ordinary logout's intentional offline queue behavior. |
| F07 | P1 | **Age eligibility and the “no account is created” promise do not agree.** Source: onboarding requires an authenticated user; `handle_new_user` creates a profile at signup, before the primary-school/under-13 exit. Waitlist copy says no account/profile exists. Current onboarding SQL blocks `primary`, but the age band/birth year minimum is not enforced there or by the live profile constraints. | Decide the exact eligibility rule, check it before account creation, enforce it on all server write paths, and define cleanup for ineligible existing pending accounts/drafts. Align waitlist collection and copy with what is actually retained. Add direct-RPC and direct-table tests for declared under-13 age and inconsistent birth year/age-band input. |
| F08 | P1, scope-dependent | **Push notifications are unfinished.** No `firebase_messaging` dependency or client token registration flow; no deployed `FCM_SERVICE_ACCOUNT`; live `device_tokens` count is zero. The server deliberately skips push. The in-app inbox is a separate working mechanism. | Complete Android/iOS permissions, FCM/APNs credentials, token registration/rotation/removal and notification tap destinations, or ship explicitly with in-app notifications only. Prove foreground/background/terminated delivery and correct-account routing. A new dependency requires approval under `AGENTS.md` when implementation reaches that step. |
| F09 | P1, product quality | **Bangladesh-focused vacancy sources are inactive.** Neither `JSEARCH_API_KEY` nor `CAREERJET_API_KEY` exists in deployed secrets. Free-source fallback remains; this is not proof Radar is empty. | Activate an appropriate supported source securely, verify deployed adapter parity, and review real Bangladesh/city/entry-level results for relevance, eligibility, duplicates, expired links and freshness. Set an explicit content-quality acceptance threshold for the pilot. |
| F10 | P1 | **Privacy/product claims need reconciliation.** `PRIVACY.md` and the served policy source describe Google sign-in only while the current release offers Google and GitHub. The child/waitlist “no profile” claim conflicts with F07. Account deletion's complete-erasure claim depends on F03/F06. | Update actual behavior and matching policy copies together; review retention, third-party processing, supported document formats and the external deletion/support route. Verify the deployed policy text after publishing. This is a factual product review, not a legal-compliance certification. |
| F11 | P1, accessibility | **Large-text support is capped.** `app.dart` clamps system text scale at 1.3; users requesting larger text cannot obtain it. Authentication copy also contains explicit 13.5/15px text sizes. Existing 360px tests do not establish full screen-reader or large-text usability. | Allow the intended accessibility sizes through responsive scrolling/layout, audit body text and tap targets against `AGENTS.md`, and verify key journeys at 200% text plus TalkBack/VoiceOver in both themes. |
| F12 | P1 | **Release evidence and drift detection are incomplete.** Existing CI covers Flutter and backend checks plus an Android debug compile, but no live auth-configuration preflight, physical journeys or signed iOS release gate. `DEPLOY.md` still describes 75 migrations/ten functions and setup items already completed; live now has 89 migrations/12 active functions. | Use the new preflight as an authenticated release gate, update deployment evidence, and record device/release acceptance results. A manual or protected release job must use securely stored management access; do not put credentials in app builds or ordinary PR jobs. |
| F13 | P2, deferred feature | **Employer-facing public profiles are not ready.** There is no deliberate publish/revoke UI. Live nonexistent-profile response remains `text/plain` with sandbox CSP, consistent with the previous hosting blocker. This response test is not a successful published-profile test. | Keep sharing out of the launch promise, or provide a supported controlled-domain rendering path, publication/revocation controls and privacy tests. Resolve any hosting choice against the repository's stack constraints before implementation. |
| F14 | P2, deferred feature | **Photo/scanned-CV feedback is intentionally unsupported.** Existing code accepts supported text PDFs/DOCX for checks and stores photos privately; the previous deployed OCR CPU failure is documented. No new OCR feasibility test was run. | Keep format limits clear before upload/check submission. Test useful terminal messages and no quota charge for unsupported feedback. Implement OCR only after proving it fits the deployed runtime and privacy requirements. |

### Release gates still requiring evidence

These are unverified release requirements, not assertions that every listed flow is broken.

| Gate | Required evidence |
| --- | --- |
| G01 — Mobile journeys | Fresh install and update on Android/iOS; real email signup/confirmation/reset and Google/GitHub callbacks; onboarding branches/year modes; vault reader choice/export/camera allow-deny-cancel; CV/JD/coach/interview completion and quota/refund behavior. Include network interruption, backgrounding and restart. Only an iOS simulator was connected during this review; no physical mobile acceptance run was completed. |
| G02 — Offline and account isolation | Airplane-mode read/write, process restart, reconnect, two-device conflict resolution, account switch with queued writes, and deleted-account cleanup. Existing unit tests provide useful coverage but do not complete this matrix. |
| G03 — Operations and release | Successful backup restoration into an isolated environment; alerting for failed/stale jobs, email failures and provider outages; tested incident/deployment rollback procedures; signed store builds and installation/update checks; release performance and a controlled student pilot. Restore capability and operational alerts were not validated by this audit. Cron success alone does not establish those capabilities. |

## What was verified successfully

- `flutter analyze`: no issues.
- `flutter test`: **551 passed** at the audit run.
- `deno task --frozen check`: all **12** endpoint entry points checked.
- `deno task --frozen test`: **154 passed**, none failed.
- `deno fmt --check` and `deno lint`, run from `supabase/functions`: passed.
- Live: **89 applied migrations**, **12 active Edge Functions**.
- Live: every public table has RLS enabled and forced. The 31 anonymously executable functions found in `public` belong to `pg_trgm`; no application-owned function appeared in that result. This metadata check does not replace cross-account adversarial tests.
- Live: documents bucket is private with a 10 MB limit. Avatars bucket is public; do not describe every storage bucket as private.
- Live: three cron schedules active, with successful runs over the preceding 24 hours; no stale pending/running queue rows were found, and the initial queue summary contained 25 completed jobs.
- Live: 24 Gemini usage rows in the preceding seven days, showing the older “AI may still be mock” warning is not the current observed state. This is not a complete feature-by-feature model quality test.
- Google and GitHub are enabled and offered in the current UI. Facebook is disabled and already hidden in the current default provider row; it is not a new launch defect.
- The public privacy endpoint returned HTTP 200 with readable plain text.

The source tree changed concurrently during the review in unrelated app files. Those changes were left untouched. Test counts describe the recorded audit run, not certification of every subsequent edit.

## Fix plan and order

### Phase 0 — Establish the release gates — started

- [x] Review source and current live configuration without mutating student data.
- [x] Run the existing local checks and distinguish confirmed defects from missing acceptance evidence.
- [x] Add `tool/verify_production_readiness.js`, a sanitized, read-only configuration preflight.
- [x] Run it live: **7 pass, 5 fail, 6 warn, 0 unknown**. The five failures are custom SMTP, email capacity, callback allow-list, production site URL and server password minimum.
- [ ] Wire this into the protected release process after secure access is provided there.

Run from the repository root:

```sh
node tool/verify_production_readiness.js
```

It uses the existing gitignored `supabase/.env`/environment with `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_ACCESS_TOKEN`. It sends no mail, creates no users and reads no student records or secret values. Exit 1 means failed configuration gates; exit 2 means an incomplete read; warnings must be resolved or explicitly scoped before release. Exit 0 alone is not production approval. Function presence does not establish deployed-source parity, and secret-name presence does not verify a provider value or successful delivery.

### Phase 1 — Make account ownership work — next

Addresses F01, F02, F04 and the server policy part of F05.

1. Obtain the chosen sending domain and SMTP setup through the existing secure secret workflow. Keep credentials out of chat, source and client builds.
2. Configure the sender/domain records, email capacity, callback allow-list and HTTPS fallback. Keep email confirmation enabled. SMTP is the external prerequisite; callbacks and the mobile UI can be prepared independently.
3. Implement the confirmation screen/resend/retry journey and callback error handling. Use an emailed link initially; add OTP only if deliberately chosen and tested with matching templates.
4. Enforce the agreed password rules on the server and add the selected abuse/security controls. Plan safe treatment of older accounts potentially created while auto-confirmation was enabled; do not infer historical proof from a confirmation timestamp alone.
5. Test unverified login rejection through Auth directly and the app, verified access, duplicate signup, resend cooldown, expiry, recovery, rate limits and both offered OAuth providers.

Exit gate: the five failed preflight checks pass and real-device ownership/recovery evidence is recorded. A confirmation-send timestamp alone cannot close F01.

### Phase 2 — Protect deletion and eligibility

Addresses F03, F06, F07 and sensitive-action ownership proof in F05.

1. Repair storage enumeration/prefixes/pagination and idempotent account-deletion failure handling. Use fixtures and fault injection first; run live deletion checks only on clearly identified disposable accounts.
2. Add server-enforced recent ownership proof, including the OAuth path, and prevent deletion/upload races.
3. Purge only the deleted account's local cache, outbox and downloaded files after server confirmation.
4. Rework eligibility before signup and add append-only SQL migration(s) enforcing declared age/education rules on every relevant write path. Align waiting-list collection and cleanup behavior.
5. Run targeted cross-account/storage/RPC checks and keep tests away from global job-claim/digest actions against real students.

Exit gate: no orphaned owned storage objects after a completed deletion, accurate retriable partial-failure states, no deleted-account local data, and server-side eligibility tests passing.

### Phase 3 — Complete the selected launch feature set

Addresses F08–F11, F13 and F14.

1. Decide whether the first release includes device push or just the in-app inbox. If push is included, complete and verify the native integration before promising off-app reminders.
2. Activate/review local opportunity sourcing and record pilot quality results.
3. Finish accessibility layouts and the physical-device document/export/permission matrix.
4. Update privacy/support/release descriptions to the implemented behavior. Keep public employer profiles and scanned-CV feedback explicitly deferred unless their acceptance gates are completed.

Exit gate: every advertised feature has a demonstrated user journey and accurate limitations.

### Phase 4 — Prove the release and run the pilot

Addresses F12 and G01–G03.

1. Re-run local checks and the authenticated configuration preflight against the exact release revision.
2. Record the Android/iOS, offline, account-switch, native permissions, accessibility and poor-network acceptance matrix.
3. Complete isolated restore/alert/incident exercises and signed installation/update checks.
4. Run a controlled student pilot, resolve blocker findings, and record the release decision with version, migration/function deployment evidence and rollback steps.

Do not mark the app production-ready until all P0 items and applicable P1 items are closed, deferred scope is explicit, and the three release gates have current evidence.
