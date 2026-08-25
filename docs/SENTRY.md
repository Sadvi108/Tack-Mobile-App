# Crash reporting with Sentry

Sentry is the **only** thing in Tack that sends anything outside the Supabase
project. Product analytics, documents, profiles and scores all stay in
Postgres. This file covers what Sentry gets, and how to switch it on.

## What a crash report contains

| Sent | Not sent |
|---|---|
| Account id (a UUID) | Name, email, phone |
| Device model, OS version | IP address |
| Dart stack trace | Anything a student typed |
| App version, release | CV text, job descriptions, notes, interview answers |
| Navigation breadcrumbs | Console output, typed input, screenshots |

That boundary is enforced in `lib/core/crash_reporting.dart`, not in Sentry's
dashboard settings, and `test/core/crash_reporting_test.dart` proves it: an
email address hidden in a breadcrumb is dropped, and a user object arriving
with a name and IP leaves with only its id.

The account id is deliberately kept. A crash hitting one student is a
different problem from one hitting all of them, and without an id you cannot
tell those apart.

## Setting it up

**1. Create the project.** Go to sentry.io, sign up, and create a project with
platform **Flutter**. Name it `tack`.

**2. Copy the DSN.** Settings → Projects → tack → Client Keys (DSN). It looks
like `https://<hash>@o<org>.ingest.sentry.io/<project>`.

A DSN is not a secret in the way an API key is — it only allows *writing*
events, and it ships inside every copy of the app. It still does not belong in
a commit, because a leaked DSN invites junk into your issue list.

**3. Put it in your environment file**, which is gitignored:

```
app/env/prod.json
```

```json
{
  "SUPABASE_URL": "https://uvwmjeqymychlsybekxz.supabase.co",
  "SUPABASE_ANON_KEY": "<your anon key>",
  "SENTRY_DSN": "https://<hash>@o<org>.ingest.sentry.io/<project>",
  "APP_ENV": "prod"
}
```

Leave `SENTRY_DSN` empty in `env/dev.json`. With no DSN the app runs normally
and reports nothing, so your own crashes while developing never land in the
production issue list.

**4. Build with it.**

```bash
cd app && flutter build appbundle --release --dart-define-from-file=env/prod.json
```

**5. Check it works.** Add a button that throws, run a release build, and
confirm the issue appears in Sentry within a minute. Then remove the button.

## Making stack traces readable

Without this step a release crash shows memory offsets instead of Dart line
numbers, which makes Sentry roughly useless.

```bash
dart pub global activate sentry_dart_plugin
```

Create `app/sentry.properties`:

```
project=tack
org=<your org slug>
auth_token=<a token with project:releases scope>
upload_debug_symbols=true
upload_source_maps=false
```

Add `sentry.properties` to `.gitignore` — unlike the DSN, that auth token
**is** a real secret.

Then after each release build:

```bash
cd app && dart run sentry_dart_plugin
```

## Alerts worth having

Sentry's defaults are noisy. Two rules are enough to start:

- A **new** issue appears in production → email immediately. This is the one
  that matters; it means a release broke something that was working.
- An issue crosses **50 students affected in an hour** → email. Catches a
  problem that was always there but only just started spreading.

Mute everything else until you know what normal looks like.

## Turning it off

Clear `SENTRY_DSN` and rebuild. Nothing else changes: crashes still land in
`public.error_reports` inside Supabase, which is written independently of
Sentry and does not depend on it.
