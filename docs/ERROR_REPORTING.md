# Error reporting

Nothing in Tack sends student data outside the Supabase project. Crashes,
product analytics, documents, profiles and scores all stay in Postgres.

This used to be untrue: `sentry_flutter` was a direct dependency and crash
reports carried an account id and a raw stack trace to sentry.io. That was the
one hole in the data boundary `AGENTS.md` promises, so it was closed — the
dependency is gone and the reports now land in a table.

## What a report contains

The client sends five bounded fields and nothing else.

| Field | What it may be | Why it is safe |
|---|---|---|
| `p_code` | one of `invalid_data`, `invalid_state`, `invalid_argument`, `render_failure`, `unexpected_failure` | The exception *class*, never its message. An exception carrying `student@example.com` reports as `unexpected_failure`. |
| `p_stack` | up to 20 lines of `package:tack/<file>.dart:<line>:<col>` | Matched out of the trace by regex. A file path from the student's device, a URL with a token, or a frame from a package cannot survive it. |
| `p_context` | `{"phase": "startup" \| "render" \| "runtime"}` | Enumerated. Any other key is dropped server side. |
| `p_version` | `1.2.3` or `1.2.3+45`, or `unknown` | Pattern-checked. |
| `p_platform` | `android`, `iOS`, `macOS`, `linux`, `windows`, `fuchsia` | Enumerated. |

There is no account id in the payload. The server takes the user from
`auth.uid()`, so a client cannot report as somebody else, and no name, email,
device model, IP address, breadcrumb, screenshot or anything a student typed
is collected at all.

## Where the boundary is enforced

In two places, both of which have to agree:

- `app/lib/core/analytics.dart` — `Analytics.errorCode()` and
  `Analytics.safeStack()` reduce the error before it leaves the phone.
  `app/test/core/crash_reporting_test.dart` proves an email in an exception
  message and a URL in a stack trace are both dropped.
- `supabase/migrations/0073_private_error_reports.sql` — `record_client_error`
  re-checks every field and rejects the whole report if any of them is wrong.
  It is the actual control: `insert`, `update` and `delete` on
  `public.error_reports` are revoked from `authenticated` and `anon`, so the
  RPC is the only way in.

The client filter is a convenience. The function is the boundary.

## What is collected, and when

`CrashReporting.run()` wraps `runApp` and installs three handlers:
`FlutterError.onError` (`phase: render`), `PlatformDispatcher.instance.onError`
(`phase: runtime`), and a `try`/`catch` around the app runner itself
(`phase: startup`).

A startup crash usually happens before Supabase is signed in, so there is
nothing to report against yet. Up to ten reports are held in memory until
`CrashReporting.connect()` is called, then flushed. Beyond ten they are
dropped: a crash loop must not become the thing that runs the phone out of
memory.

Reporting never interrupts the student. If the RPC fails, the failure is
swallowed.

## Limits

- **20 reports per user per hour.** Enforced under an advisory lock inside the
  function, so a crash loop cannot fill the table. Reports over the limit are
  discarded silently rather than raising.
- **Signed in only.** `record_client_error` raises `sign_in_required` for an
  anonymous caller, so this is not a public ingestion endpoint anybody can spam.
- **90 days.** The nightly sweep deletes older rows; see
  `0066_notifications_that_arrive.sql`.

## Reading them

There is no dashboard. It is a table:

```sql
select occurred_at, message, platform, app_version, context, stack
from public.error_reports
order by occurred_at desc
limit 50;
```

Grouping by `message`, `app_version` and the first stack line is usually
enough to tell one broken release from one broken student.

## Setting it up

Nothing to set up. There is no DSN, no key and no environment variable — a
build with `SUPABASE_URL` and `SUPABASE_ANON_KEY` reports errors already.
