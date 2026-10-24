# Monday brief Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** At most one push a week, Monday 09:00 Dhaka, listing the three things that most need the
student's attention. Ranked by plain rules, worded for the student's year. The plan also fixes the
daily digest, which currently arrives a day late.

**Architecture:**
- Two read-only SQL functions. `listing_fit` mirrors `radar_feed`'s fit formula.
  `weekly_brief_items` ranks one student's items the way Release Radar does: top signal + 5 per
  extra reason, at most 3 items.
- `enqueue_weekly_brief` runs as a dry run by default. `nightly_maintenance` calls it with dry run
  off on Mondays, before the daily digest. It reuses the digest's dedupe key, so a student still
  gets at most one notification a day.
- In the app, the weekly-brief notification opens a sheet of tappable items.

**Tech stack:** Postgres (Supabase), applied with `node tool/migrate.js`; Node verify script
against the live database; Flutter with Riverpod and go_router.

Spec: `docs/superpowers/specs/2026-10-22-borrowed-features-design.md`, section 1.

---

## Files

- Create `supabase/migrations/0080_monday_brief.sql`. It holds `listing_fit`,
  `weekly_brief_items`, `enqueue_weekly_brief`, the fixed `enqueue_daily_digest`, and
  `nightly_maintenance` with the Monday branch.
- Create `tool/verify_weekly_brief.js`: throwaway students checked against live SQL.
- Modify `app/lib/features/notifications/data/notification_repository.dart`: add `payload`,
  `BriefItem`, `briefItems`, and the `weekly_brief` route.
- Create `app/lib/features/notifications/presentation/weekly_brief_sheet.dart`: the sheet.
- Modify `app/lib/features/notifications/presentation/notifications_screen.dart`: a brief opens
  the sheet.
- Modify `app/test/features/notifications/notification_route_test.dart`: route and parsing tests.
- Create `app/test/features/notifications/weekly_brief_sheet_test.dart`: widget test.
- Modify `docs/API.md`: document the new internal functions.

---

### Task 1: The verify script (red)

**Files:** create `tool/verify_weekly_brief.js`.

- [ ] **Step 1: Write the script.** The full code is in the file. It covers:
  - three throwaway students: launch (year 4 of 4), explore (year 1 of 4), and a quiet launch
    student with nothing
  - seeded applications, roadmap tasks (backdated through `updated_at` on insert), a due review,
    and one fresh Dhaka listing whose skills the launch student has
  - assertions:
    - launch ranks closing, then interview, then roadmap (late + idle = 85)
    - explore gets roadmap only, with no deadline wording
    - quiet gets `[]`
    - a dry run sends nothing
    - `listing_fit` equals `radar_feed`'s fit
    - a real run writes one `weekly_brief` notification with a push at or before 09:00 Dhaka
      today
    - the digest's key is then taken
    - the digest (run inside a rolled-back transaction) schedules today, not tomorrow
    - `nightly_maintenance` calls the brief before the digest
  - cleanup of users and the listing
- [ ] **Step 2: Run it.** `node tool/verify_weekly_brief.js`. Expected: FAIL with
  `function public.weekly_brief_items(uuid, date) does not exist`.

### Task 2: Migration 0080 (green)

**Files:** create `supabase/migrations/0080_monday_brief.sql`.

- [ ] **Step 1: Write the migration.** The full SQL is in the file. Signals and scores:

  | Signal | Score |
  |---|---|
  | closing | 100 |
  | interview | 90 |
  | steps_late | 80 |
  | new_matches | 70 |
  | practice_due | 60 |
  | idle_roadmap | 50 |

  `closing` and `interview` only for prove, launch and graduate. `new_matches` for build and
  above. The `why` lines use each mode's wording.
- [ ] **Step 2: Apply it.** `node tool/migrate.js 0080_monday_brief`. Expected:
  `apply 0080_monday_brief.sql ... ok`.
- [ ] **Step 3: Run the verify script.** `node tool/verify_weekly_brief.js`. Expected: all PASS,
  `0 failed`.

### Task 3: Flutter parsing and route (red, then green)

**Files:** `notification_repository.dart`, `notification_route_test.dart`.

- [ ] **Step 1: Write the tests.** `weekly_brief` routes to `/notifications`. `briefItems` reads
  `{title, why, route}` and drops malformed items and routes outside
  `/applications/`, `/roadmap`, `/interview` and `/radar`.
- [ ] **Step 2: Run them.** `flutter test test/features/notifications/notification_route_test.dart`.
  Expected: FAIL (`briefItems` isn't defined).
- [ ] **Step 3: Implement.** Add `payload` to `TackNotification.fromRow`, plus the `BriefItem`
  class and the `briefItems` getter.
- [ ] **Step 4: Run them again.** Expected: PASS.

### Task 4: The sheet (red, then green)

**Files:** `weekly_brief_sheet.dart`, `weekly_brief_sheet_test.dart`, `notifications_screen.dart`.

- [ ] **Step 1: Write the widget test.** At 360 px it renders 3 titles and 3 why lines, and
  tapping the second item calls `onOpen` with its route.
- [ ] **Step 2: Run it.** Expected: FAIL (`WeeklyBriefSheet` isn't defined).
- [ ] **Step 3: Implement the sheet.** `WeeklyBriefSheet({items, onOpen})`, one `TackCard` per
  item. Then wire `notifications_screen.dart`: a notification with `briefItems` opens
  `showTackSheet` instead of navigating.
- [ ] **Step 4: Run `flutter analyze && flutter test`.** Expected: no issues, all pass.

### Task 5: Docs and commit

- [ ] **Step 1:** Add `listing_fit`, `weekly_brief_items` and `enqueue_weekly_brief` to the
  internal section of `docs/API.md`, and note the digest delivery fix.
- [ ] **Step 2:** Commit `feat(brief): rank the week and send it Monday morning`.
