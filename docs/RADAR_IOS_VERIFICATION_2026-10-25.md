# Radar iOS verification — 25 October 2026

## Environment

- Feature commit `139b6ad` was pushed to `main` before the device check.
- Xcode 27.1, `app/ios/Runner.xcworkspace`, Runner scheme, iPhone 17e/iOS 26.5.
- `flutter build ios --simulator --debug --dart-define-from-file=env/dev.json`
  succeeded; Xcode's Run action built and launched the app. The existing client
  configuration points to production project `uvwmjeqymychlsybekxz`.
- Used the simulator's existing signed-in session. No signup, emails or paid
  Actor collections were triggered, and no applications were submitted.

## Checks and findings

1. Opened Radar from Home. Its Data analyst/Dhaka search loaded provider cards
   and the notice that Bangladesh coverage is limited.
2. Switched between In person, Remote, Full time and All. The initial in-person
   search showed zero results with a useful empty state; remote results loaded.
3. Opened the Remotive Senior Data Scientist/Lemon.io posting from a card. The
   browser showed that the source had archived it. The cache row's last source
   observation was 20 September, demonstrating a real stale-cache bug.
4. Added and deployed append-only migration `0094_radar_cache_freshness.sql`.
   Discovery now requires a source observation within 48 hours for every board.
   Publication age is separate: a recently confirmed older role remains visible.
   Existing cache records and saved applications are retained.
5. Reloaded through the All filter with Remote selected. The Data analyst/Dhaka
   search displayed **14 openings** from existing providers, with the limited
   Bangladesh coverage notice. The archived posting was absent. An independent
   live database feed call returned the same 14 results and no stale rows;
   full-time filtering returned zero after obsolete entries were removed.
6. Opened the first remaining card. Arbeitnow showed the matching Senior Data
   Engineer — Document & AI Pipelines role at Tracium GmbH, marked Remote and
   Contract/Freelance. Returned to Radar and left the corrected feed visible.

Screenshot evidence was saved locally as `/tmp/tack-radar-fresh-results.jpg`,
`/tmp/tack-radar-current-source.jpg` and `/tmp/tack-radar-archived-before.jpg`.
These are device observations, not mock data or screenshots generated from code.

## Automated checks

- `flutter analyze`: clean; **558 Flutter tests** passed.
- Backend type checks, lint and formatting: clean; **172 Deno tests** passed.
- **16 temporary SQL checks** passed, including stale rows from every other
  source, recently confirmed older postings, explicit expiry, workplace filters,
  idempotent imports and restricted RPC access. Fixtures were rolled back.
- Deployed RPC access checks passed again after migration `0094`.
- The deployed feed excluded the archived job and all returned rows satisfied
  the 48-hour observation rule. The remote/all feed matched the simulator count.

## Limits

Supabase secrets still contain no `APIFY_API_TOKEN`, `APIFY_JOB_TASK_IDS` or
`APIFY_BDJOBS_TASK_ID`. The latest scheduled import completed with
`{"skipped":"bdjobs not configured"}`. No Bdjobs or LinkedIn rows have imported.
The user chose to continue checking the current setup without configuring Apify.
Therefore this is verification of the existing-provider Radar flow and missing
source behavior; it does **not** prove live Apify/Bangladesh vacancy coverage.

The observed remote role has a Berlin location on its source page. A provider's
remote flag does not prove that every Bangladeshi applicant is eligible; check
employer restrictions before applying. Source freshness also cannot guarantee
that a provider never returns an archived posting. Physical-device acceptance,
Apify credentials/tasks and a bounded real import remain outstanding.
