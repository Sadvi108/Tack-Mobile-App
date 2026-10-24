# Bdjobs vacancies through Apify

The [expanded Store review](APIFY_BANGLADESH_JOBS.md) adds Vero, Hipersoft and a
restricted multi-board adapter alongside ScrapingMonkey, with multiple saved
tasks, LinkedIn support and additional `0092`/`0093` deployment steps. The
original single-task setting below remains compatible.

## What was verified

On 25 October 2026, the public Apify metadata and deployed input schemas were
read for both actors. No paid run was started.

- The originally supplied [getdataforme/bdjobs-details-spider](https://apify.com/getdataforme/bdjobs-details-spider)
  reads a supplied `Urls` list. It is a community scraper, not an official
  Bdjobs all-vacancies API. Its empty-input example is not vacancy discovery.
- [scrapingmonkey/bdjobs-scraper](https://apify.com/scrapingmonkey/bdjobs-scraper)
  supports `mode: "bdjobs-job-search"`, empty `keywords` for browsing, and
  `maxResults`. Its public Actor ID is `fHgKbgS18BmU9mLGL`; the importer verifies
  that identity and the row's mode/status.
- The search actor's public billing metadata reported $0.003 per dataset item
  on the Free tier and a separate startup event. Pricing varies by tier and
  can change. Check current account pricing, collection limits and usage before
  scheduling it. Failed result rows can also be billable.

An authenticated collection has **not** been run: no Apify token/task was
configured during implementation. Published schema/examples and fixture tests
cannot prove today's coverage, extraction quality or successful paid execution.
`maxResults` is a cap, not a guarantee that every vacancy is collected.

## How it works

1. A dedicated Apify search task collects a bounded public vacancy dataset on
   its own schedule. This is the only step that starts paid scraping.
2. Supabase cron enqueues `import_bdjobs` hourly, at minute 12. The existing
   worker reads the dedicated task's latest **successful** run. It does not
   start, restart or pay for an actor run.
3. Each 100-row page is a durable queue job. Retries reuse the same dataset and
   offset. `cache_apify_job_page` atomically upserts source/job IDs and reindexes
   skills; older datasets cannot overwrite newer rows. Queued page identities
   are unique per run/offset. Invalid rows are counted and skipped; a nonempty
   page with no valid job rows fails visibly instead of claiming a valid feed.
4. Radar searches Tack's shared cache. No student name, profile, device data
   or search terms are sent to Apify. Browsing, refreshing and pagination never
   start a paid collection. Existing providers continue to work independently.

Only HTTPS links to the matching `bdjobs.com/h/details/<id>` posting are
accepted. The original posting remains the application destination. Salary
and education/experience text are preserved without inventing compensation or
fit. Repeated imports do not duplicate a source/job ID; the existing general
provider deduplication does not guarantee elimination of every cross-source
duplicate already in the shared cache.

Deadlines exclude postings after the advertised day ends in Bangladesh.
Bdjobs commonly encodes a calendar deadline as midnight UTC; that value is
interpreted as the advertised day, not as a precise midnight cutoff. The feed
also excludes Bdjobs snapshots older than 48 hours. The cutoff uses the
collection's completion time, never the later import time. Already saved
applications remain in their owner's tracker.

Unknown/hybrid/unstated workplaces are retained as unknown. Radar now starts
with **All work** in the student's city, so an omitted workplace does not hide
the vacancy. Choosing **In person** or **Remote** remains strict. Cards say
“Workplace not stated” when the provider has not supplied a supported explicit
arrangement. A feed without a fresh, unexpired Bdjobs row reports that source
as unavailable. An empty cache is not represented as proof there are no jobs.

## Activation

Production migrations `0090`–`0093` and the import worker were deployed on
25 October 2026. See the [deployment verification](APIFY_BANGLADESH_JOBS.md)
for function versions and live checks. Apify credentials/saved tasks are still
missing; an installed app needs an updated build for the new default/filter
label behavior. The steps below also describe setup for another environment.

1. Create a **dedicated saved task** from `scrapingmonkey/bdjobs-scraper` in
   Apify. Use job-search mode, not company or detail mode. Begin with a bounded
   pilot input:

   ```json
   {
     "mode": "bdjobs-job-search",
     "keywords": "",
     "maxResults": 100
   }
   ```

   This collects up to 100 results, not all Bdjobs vacancies. Choose a larger
   cap only after reviewing coverage and cost. Configure an account/task spend
   limit and a daily schedule, then complete one successful run. Increase the
   frequency only after measuring the required freshness and cost. Do not use
   the same task for other collection modes or narrow keyword experiments.
2. Set **`APIFY_API_TOKEN`** and **`APIFY_BDJOBS_TASK_ID`** in Supabase Edge
   Function secrets through the dashboard or secure secret tooling. The task
   ID is the saved task's opaque ID, not the Actor slug or a run/dataset ID.
   Keep the token out of chat, files, Flutter defines and URLs. The worker uses
   the token in an Authorization header and only performs bounded GET reads.
3. Apply unapplied migrations in order, in separate transactions:

   ```sh
   node tool/migrate.js 0090_bdjobs_source
   node tool/migrate.js 0091_bdjobs_import
   node tool/migrate.js 0092_linkedin_source
   node tool/migrate.js 0093_apify_job_sources
   node tool/migrate.js 0094_radar_cache_freshness
   ```

   `0090` commits the enum value before `0091` uses it. `0091` adds cache
   metadata, service-only import functions, the hourly import schedule and the
   updated feed. `0092`/`0093` add the expanded shared importer used by the
   current worker. Existing RLS policies stay in place.
4. Deploy **worker**, **radar** and **policies** using the existing deployment
   procedure in [DEPLOY.md](DEPLOY.md). Worker remains cron-secret protected;
   do not enable gateway JWT verification on that endpoint. Deploy the worker
   promptly after migration so scheduled imports have a registered handler.
5. Enqueue the first import through trusted server tooling, or wait until the
   hourly schedule:

   ```sql
   select public.enqueue_bdjobs_import();
   ```

   The normal worker processes it. Do not force global job claiming/draining
   against real students for a verification run.
6. Verify the source count, recent `last_seen_at`, canonical links, deadlines,
   malformed-row counts and completed `import_bdjobs` page jobs. Inspect any
   `dead` jobs. Compare a sample against the original Bdjobs advertisements.
   Then check the feed on the updated Android/iOS app for All work, city,
   In person, Remote, job types, pagination, save and original-posting opening.

Successful cron/worker runs without credentials report a skipped import. That
is an incomplete setup, not proof of a populated source. A provider error never
empties the other sources. A saved task with the wrong actor, unsuccessful run,
stale run, non-search rows or inaccessible dataset must be corrected before
claiming activation.

## Validation

```sh
cd supabase/functions
deno task --frozen check
deno task --frozen test
deno fmt --check
deno lint
```

```sh
node tool/verify_bdjobs_db.js
```

The database verifier uses temporary shadow tables inside a rolled-back
transaction. It does not apply migrations, change production records/cron or
create users. It tests feed expiry/freshness, workplace filters, retry identity,
older-snapshot protection and import privileges. Its isolated skill-index stub
does not replace the existing real-vocabulary skill extraction checks.

```sh
cd app
flutter analyze
flutter test
```

Current checks: **558 Flutter tests**, **172 backend tests**, clean
Flutter analysis/backend type checks/format/lint, and **16 temporary SQL
contract checks** passed. Real paid collection and deployed end-to-end import
remain activation gates requiring the configured token/task.

The iOS verification also found stale rows from older providers. Migration
`0094` now applies the same last-observed freshness rule to every provider. See
[device verification](RADAR_IOS_VERIFICATION_2026-10-25.md).
