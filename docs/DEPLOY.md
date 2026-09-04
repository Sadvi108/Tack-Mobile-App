# Deploying Tack

Two things ship independently: the Flutter app to the stores, and the Supabase
backend (migrations, Edge Functions, secrets).

Nothing in this file contains a secret value, and nothing here should ever be
edited to contain one.

## What is already live

Checked against the project rather than remembered, on 3 September 2026.

- **65 migrations applied.** Row Level Security forced on every table,
  reference data seeded.
- **All seven Edge Functions deployed and `ACTIVE`**: `analyze-jd`, `coach`,
  `delete-account`, `interview`, `radar`, `score-cv`, and `worker`.
- **Three cron jobs**, all active: `tack-worker` every two minutes,
  `tack-score-drain` every minute, `tack-nightly` at 18:20 UTC — just after
  midnight in Dhaka.
- **Region `ap-northeast-2` (Seoul).** Worth knowing: student data is stored
  outside Bangladesh, and [PRIVACY.md](../PRIVACY.md) says so.

The cron bearer secret and the functions base URL live in Supabase Vault under
`tack_cron_secret` and `tack_functions_url`, read at call time — so rotating
the secret is a Vault update and needs no code change:

```bash
node tool/set_vault_secrets.js
```

## EXECUTE is deny-by-default

Since `0063`–`0065`, a function in `public` is **not** reachable from the app
until it is granted to `authenticated` by name.

This matters when you add one. Postgres grants `EXECUTE` on every new function
to `PUBLIC`, and Supabase separately pre-grants `anon` and `authenticated`;
an event trigger (`tack_revoke_public_execute`) now strips `PUBLIC` and `anon`
as each function is created. `ALTER DEFAULT PRIVILEGES` cannot do this — it
does not suppress Postgres's built-in default, which was measured, not assumed.

So: write the function, add an explicit `grant execute … to authenticated` if
the client needs it, list it in [API.md](API.md), and run:

```bash
node tool/verify_rpc_surface.js
```

That check caught a real regression the day it was written.

## Still to do by a human

These need credentials or a dashboard, and cannot be done from the repository.

**Secrets that are not set yet.** Names only — take the values from your own
`supabase/.env`, and do not paste them into a chat, a commit, or a ticket:

```bash
supabase secrets set CAREERJET_API_KEY CAREERJET_LOCALE
```

`CAREERJET_LOCALE` should be `en_BD`. Without the key, Radar still runs on the
four free boards and says so on screen — "one board is off" — rather than
showing an empty list as though there were no work in the world. Careerjet is
the one that actually covers Bangladesh, so until it is set the feed is mostly
senior roles abroad.

**Push notifications need a Firebase project.** Nothing about push works
until then, and nothing breaks either: `send_push` jobs finish with
`{"skipped":"fcm not configured"}` rather than dead-lettering, and the in-app
inbox fills normally. To switch it on:

1. Create a Firebase project and add an Android app with the applicationId
   `com.tack.tack`.
2. Put `google-services.json` in `app/android/app/`, and add
   `firebase_messaging` plus the `com.google.gms.google-services` Gradle plugin.
   **Until that file exists the Android build fails**, which is why the client
   half is not wired yet.
3. Give the server the service account, whole:

```bash
supabase secrets set FCM_SERVICE_ACCOUNT
```

**The public profile page has no front door.** `public_profile()`, handles,
the visibility settings and GitHub repo verification are all built, applied and
verified — but the page itself is not usable yet, and there is no way to publish
one from the app on purpose.

Supabase's gateway rewrites **every** Edge Function response to
`content-type: text/plain` and injects `sandbox` into the
`content-security-policy`. Measured on both the 200 and the 404 path:

```
content-type: text/plain
content-security-policy: default-src 'none'; sandbox
```

That is an anti-phishing measure on `*.supabase.co` and it cannot be overridden
from inside the function — the HTML it returns is correct and escaped, but a
browser displays it as source. A page that renders as source code is not a page
a student can send to an employer.

The fix is to serve it from a domain we control: a ~20-line Cloudflare Worker
or Vercel function that fetches `/functions/v1/profile/<handle>` and re-serves
the body as `text/html`. Free on either. Until then `profiles.is_public`
defaults to false, no screen sets it, and nothing is exposed.

**`AI_PROVIDER` must be decided before a beta.** It should stay `mock` for
development. If it is still `mock` when real students arrive, the coach, CV
scoring, JD analysis and interview practice will all answer with fixtures.

**Crash reporting is off until a DSN is set.** A beta with no crash reports
wastes the beta. See [SENTRY.md](SENTRY.md) for what it sends.

**Leaked-password protection** is disabled. One toggle in Authentication →
Settings; it checks new passwords against HaveIBeenPwned.

**Google sign-in** needs enabling in Authentication → Providers → Google, with
`com.tack.app://auth-callback` in the allowed redirect URLs.

## Deploying a function

The CLI needs a personal access token and the project ref. The import map is
not optional — without it the bundler cannot resolve `@supabase/supabase-js`
and the deploy fails with a confusing relative-import error:

```bash
supabase functions deploy <name> \
  --project-ref uvwmjeqymychlsybekxz \
  --import-map supabase/functions/deno.json
```

**The worker is deployed separately and without JWT verification, on purpose.**
`dispatch_worker()` calls it from `pg_cron` with `Authorization: Bearer
<CRON_SECRET>`, which is a shared secret and not a JWT. With verification on,
Supabase's gateway answers 401 before the function runs, the queue silently
never drains, and every CV sits in `processing` until the nightly sweep fails
it. The function is not unprotected — `isWorkerAuthorised` does a constant-time
compare of that same secret as its first act.

```bash
supabase functions deploy worker --no-verify-jwt \
  --project-ref uvwmjeqymychlsybekxz \
  --import-map supabase/functions/deno.json
```

## Checks before shipping

Run these, do not assume them.

```bash
cd app && flutter analyze && flutter test
```

```bash
cd supabase/functions && deno fmt --check && deno lint \
  && deno check analyze-jd/index.ts coach/index.ts delete-account/index.ts \
       interview/index.ts radar/index.ts score-cv/index.ts worker/index.ts
```

Live checks against real throwaway accounts, each of which cleans up after
itself:

```bash
node tool/verify_rpc_surface.js      # nothing reachable without signing in
node tool/verify_db.js               # RLS: one student cannot read another
node tool/verify_storage.js          # documents, signed URLs, orphaned objects
node tool/verify_onboarding.js       # the school-student branch end to end
node tool/verify_delete_account.js   # deletion really deletes, files included
node tool/verify_notifications.js    # the inbox, the digest and its daily cap
node tool/verify_dashboard.js
node tool/verify_roadmap.js
node tool/verify_radar.js
```

Run `verify_db` and `verify_rpc_surface` after **any** migration that touches a
policy, a grant, or a function.

The one that exercises Supabase's Edge Runtime rather than plain Deno — which
matters because the OCR engine wants Node worker threads:

```bash
deno run --allow-all --config supabase/functions/deno.json tool/verify_deployed.ts
```

Do not run the live scripts back to back in a tight loop: they each create
throwaway auth users, and Supabase rate-limits that. A failure that disappears
on a re-run is usually this, not a regression.

## The app

Build configuration comes from `--dart-define-from-file`, so no key is ever
read from a file on the device.

```bash
cd app && flutter build appbundle --release --dart-define-from-file=env/prod.json
```

`env/prod.json` is gitignored. Copy `env/dev.example.json`, fill it in, and
keep it off version control.

Android release signing needs `android/key.properties` and a keystore, both
gitignored. **Back the keystore up somewhere you will still have in two
years** — losing it means never being able to update this app again.

TestFlight, signing and the install QR are in [TESTFLIGHT.md](TESTFLIGHT.md).

## Rolling back

Migrations are append-only. To undo one, write a new migration that reverses
it — never edit or delete a file that has already run, because
`schema_migrations` records what was applied and by name.
