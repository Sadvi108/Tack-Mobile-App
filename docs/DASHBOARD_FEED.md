# `dashboard_feed()` — the home screen's API

One RPC, one snapshot, one round trip. Everything the dashboard draws comes
from here.

```dart
final row = await supabase.rpc<Map<String, dynamic>?>('dashboard_feed');
```

## Why it exists

The home screen used to make nine PostgREST reads before it could draw
anything — profile, score, week change, cohort, roadmaps, documents, chosen
paths, application counts, upcoming dates. Two problems:

1. **Nine handshakes.** On a Dhaka 3G connection the student watched a skeleton
   for all of them.
2. **Nine moments.** The cards were computed from queries taken at different
   instants, so a task ticked between two of them showed as done in one card
   and pending in another.

One function fixes both. Every figure on the screen now describes the same
moment.

## Security

`SECURITY DEFINER`, and the user comes from `auth.uid()` — never from an
argument. This is the rule migration 0024 established after functions taking a
victim's user id turned out to be callable with nothing but the anon key. There
is no way to ask this function about anybody else, and
`tool/verify_dashboard.js` asserts that against the live database.

| Function | `authenticated` | Why |
|---|---|---|
| `dashboard_feed()` | granted | takes no argument, reads `auth.uid()` |
| `tack_today()` | granted | pure, no user data |
| `tack_activity(uuid)` | **revoked** | takes a user id — definer-only |
| `tack_week_summary(uuid, date, date)` | **revoked** | takes a user id — definer-only |

The migration asserts all three grants in a `do $$` block, so a future edit that
loosens one fails at apply time rather than in production.

## One definition of activity

`public.tack_activity(user_id)` returns every thing the student did, with the
Dhaka day it happened on and a `kind`. **Everything else aggregates it** — the
streak, the active-day counts, and the weekly `moves` total.

That is not tidiness. Migration 0047 wrote the definition twice: the streak
counted eleven sources, the week summary counted four. On a real account that
had added seven skills and nothing else, one snapshot said both of these at
once:

```
SHOWING UP    active on 26 August
THIS WEEK     "last week you got through 0 things"
```

Two cards, one screen, one moment, contradicting each other — exactly what the
single-snapshot feed exists to prevent. 0048 collapsed it to one function, and
`tool/verify_dashboard.js` now asserts that every day the streak lights up is a
day the week summaries can account for.

Application status history is included only where `from_status is not null`.
The history trigger also writes a row on insert, and counting that would score
every new application twice.

## Days are Dhaka days

Every date in the feed is computed at `at time zone 'Asia/Dhaka'`. A student
ticking a task at 1am in Dhaka is having a late Tuesday night, not an early
Tuesday morning in UTC. A streak that breaks on a timezone is a bug the student
experiences as the app calling them a liar.

## Shape

```jsonc
{
  "generated_at": "2026-08-26T09:00:00+00:00",
  "today": "2026-08-26",                      // Dhaka

  "profile":  { "id", "full_name", "mode", "stage", "target_role",
                "year_of_study", "years_total", "expected_graduation",
                "onboarding_completed_at" },

  "score":    { "total", "delta", "mode", "components", "computed_at",
                "week_change" },              // components is the same jsonb
                                              // readiness_scores stores

  "cohort":   { "average", "size" } | null,   // only cohorts of 5+, from the
                                              // cohort_benchmarks view

  "trend":    [{ "week": "2026-08-24", "total": 42 }],   // 12 weekly points

  "streak":   { "current", "longest", "days": ["2026-08-25", …] },  // last 28

  "this_week": { "from", "to",
                 "moves",        // every activity event, the streak's own rule
                 "active_days",  // distinct days with any activity
                 "tasks_done", "task_points", "applications_added",
                 "interviews_practised", "documents_added",
                 "skills_added", "projects_added", "score_gained" },
  "last_week": { …same… },                    // for the momentum comparison

  "roadmap":  { "done", "total", "overdue", "active_milestone",
                "next_task": { "id", "title", "points", "est_minutes", "type" } },

  "applications": { "applied": 6, "interview": 1 },   // keyed by status

  "timeline": [{ "kind": "task" | "application" | "closing",
                 "id", "title", "subtitle", "on", "points", "route",
                 "overdue" }],                // −30 to +14 days, pre-sorted

  "skill_gap": [{ "id", "name", "importance" }],      // core first
  "skill_fit": { "have", "total" },

  "paths":     { "chosen", "available",       // available = live count of
                 "primary_title", "primary_slug" },  // active career paths
  "documents": { "count", "has_cv" },
  "unread_notifications": 4
}
```

Returns **`null`**, not an error, when the account exists but onboarding has
written no profile row. The client reads that as "still setting up".

### `has_cv`

True when a `cv` document exists that is not `failed`. A CV still being parsed
counts — it is already uploaded, and asking for it again would be wrong. This
rule lives here rather than in Dart because two screens need it to agree.

### `timeline`

Merges three tables — roadmap task due dates, application follow-ups, and job
closing dates — into one list sorted by date. The client filters by year mode:
a first-year never sees `application` or `closing` entries. That filter is in
`DashboardData.timeline` and is covered by a widget test.

### `moves`

Counted by the database, not summed on the client. It used to be summed from
four fields, which is how it drifted away from the streak. If you add a new
kind of activity, add it to `tack_activity` and both the streak and the weekly
totals pick it up together — that is the whole point of the shape.

### What is *not* in it

Readiness recomputes never count toward a streak. They are enqueued by a
trigger twenty seconds after any write, so counting them would credit the
student with a streak the app awarded itself.

### A target is chosen, never assumed

`paths.primary_*` is populated only from a path with `is_primary = true`.
Anything else the student follows appears in `paths.following`, and the
dashboard offers it as a question rather than presenting it as a decision.

This mattered. `PathRepository.choose()` defaults `primary` to false and the
only caller never passed anything else, so **no row has ever had
`is_primary = true`**. 0047 ordered by `is_primary desc` and therefore fell
through to "any path they follow", which put this on a real home screen:

```
YOUR TARGET
Content writer                                    31%
```

over a profile whose `target_role` said *Backend developer*. Live data, read
correctly, and completely wrong — two sources of truth for "what am I aiming
at", with the dashboard silently preferring the weaker one.

0049 makes the first path a student follows their primary (a trigger, so it
holds whoever writes), promotes the survivor when a target is dropped, and adds
`set_primary_path(uuid)` so the card's "Make it my target" button does what it
says. Existing rows are deliberately **not** backfilled: guessing which of
somebody's paths was meant to be the target is the same mistake in a new place.

### Nothing is hardcoded

Copy that states a fact about data reads it from the feed. The dashboard used
to say "Ten real jobs", which was true only until somebody added an eleventh;
it now reads `paths.available`. The empty state of the seven-day card used to
say "a good week to add two more" to students who had never added one.

## Client

| Layer | File |
|---|---|
| Model | `app/lib/features/dashboard/data/dashboard_feed.dart` |
| The only caller | `app/lib/features/dashboard/data/dashboard_repository.dart` |
| Ranking and wording | `app/lib/features/dashboard/application/` |

Parsing is defensive throughout: a missing or null section yields an empty
value, never an exception. A dashboard missing one figure beats a dashboard
that throws. `dashboard_feed_test.dart` asserts an empty `{}` renders.

## Checking it

```bash
node tool/verify_dashboard.js
```

Creates two throwaway students against the live database, seeds real activity
as a student would create it, calls the function over PostgREST with each
student's own token, and asserts the numbers, the ordering, the grants, and
that neither student can see anything of the other. It deletes both accounts
afterwards.
