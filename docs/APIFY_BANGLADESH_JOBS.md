# Apify Bangladesh job sources — 25 October 2026

## Store review

The supplied [Store search](https://apify.com/store/categories?search=Bangladesh+job)
is dynamic. Results were retrieved through Apify's public
[Store API](https://api.apify.com/v2/store?search=Bangladesh%20job&limit=25),
which returned five Actors. Public metadata, deployed input schemas and output
documentation were inspected. No paid collections were started.

| Actor | Assessment and implementation |
| --- | --- |
| [vero-api/bdjobs-jobs-scraper](https://apify.com/vero-api/bdjobs-jobs-scraper) | Added: Bdjobs discovery with an explicit Bangladesh country selector, structured salaries and optional descriptions/skills. Recommended first task to evaluate because of its country filter; live quality has not been measured. |
| [hipersoft/bdjobs-scraper](https://apify.com/hipersoft/bdjobs-scraper) | Added: keyword/location/job-type discovery and optional details. Adapter handles numeric job IDs and explicit workplaces. |
| [scrapingmonkey/bdjobs-scraper](https://apify.com/scrapingmonkey/bdjobs-scraper) | Retained: Bdjobs search mode. Company/detail modes are not accepted as vacancy discovery. |
| [kalilfagundes.w/job-boards-scraper](https://apify.com/kalilfagundes.w/job-boards-scraper) | Added: only Bangladesh Bdjobs/LinkedIn rows. Its Indeed/Glassdoor country options do not include Bangladesh. Other boards and overseas/ambiguous locations are rejected. |
| [getdataforme/bdjobs-details-spider](https://apify.com/getdataforme/bdjobs-details-spider) | Excluded: enriches supplied `Urls`; empty input does not discover all vacancies. |

These are community scrapers exposed through Apify, not official job-board
APIs. Three adapters overlap on **the same Bdjobs vacancies**, rather than
representing three independent markets. A Bdjobs source/job ID and canonical
URL remain the same across Actors. LinkedIn has a separate source label.

Public metadata showed current Free-tier job events of $0.003 for Vero,
$0.002 for Hipersoft, $0.003 for ScrapingMonkey and $0.00125 for the multi-board
Actor, with separate startup events. Prices vary by tier and can change;
verify account/task charges and set collection/spend limits before scheduling.
Store headlines can reflect another tier or lag behind metadata changes.

## Extracted API endpoints

| Actor | Collection endpoint |
| --- | --- |
| Vero | `POST https://api.apify.com/v2/actors/vero-api~bdjobs-jobs-scraper/runs` |
| Hipersoft | `POST https://api.apify.com/v2/actors/hipersoft~bdjobs-scraper/runs` |
| ScrapingMonkey | `POST https://api.apify.com/v2/actors/scrapingmonkey~bdjobs-scraper/runs` |
| Multi-board | `POST https://api.apify.com/v2/actors/kalilfagundes.w~job-boards-scraper/runs` |

Use `Content-Type: application/json` and `Authorization: Bearer <APIFY_API_TOKEN>`.
POST starts paid collection work and returns run metadata, not finished jobs.
Do not put tokens in URLs, client builds, tracked files or chat.

Tack itself uses **GET only**, reading dedicated saved tasks and completed datasets:

```text
GET https://api.apify.com/v2/actor-tasks/{taskId}/runs/last?status=SUCCEEDED
GET https://api.apify.com/v2/datasets/{datasetId}/items?format=json&clean=true&offset=0&limit=100
```

See Apify's [task run](https://docs.apify.com/api/v2/actor-task-runs-last-get)
and [dataset](https://docs.apify.com/api/v2/dataset-items-get) references. No
student profile or search terms are sent to these Actors. Browsing never starts
a collection; scheduling and spending stay under the Apify account's control.

## Bounded saved-task inputs

Begin with one source. Overlapping Bdjobs tasks can increase cost without
increasing coverage. Create dedicated saved tasks, review one collection, then
choose a daily schedule and task-level spend cap. Avoid unlimited `0` settings
for the pilot. A result cap is not a guarantee of complete vacancy coverage.

Vero:

```json
{"keywords":"","country":"bd","maxItems":100,"fetchExtraJobInfo":true,"descriptionFormat":"text","enforceAnnualSalary":false}
```

Hipersoft:

```json
{"searchTerms":[],"locations":[],"includeDetails":true,"maxItems":100}
```

ScrapingMonkey:

```json
{"mode":"bdjobs-job-search","keywords":"","maxResults":100}
```

Multi-board:

```json
{"searchTerms":["intern","graduate","accountant","sales"],"locations":["Bangladesh"],"sites":["bdjobs","linkedin"],"resultsPerSearch":25,"maxItems":100,"fetchFullDescription":true}
```

## Activation

1. Set `APIFY_API_TOKEN` securely in Supabase Edge Function secrets. Set
   `APIFY_JOB_TASK_IDS` to comma-separated **saved task IDs**, such as
   `TaskIdOne,TaskIdTwo`. Up to eight unique tasks total are supported. The
   original `APIFY_BDJOBS_TASK_ID` remains compatible and is merged into the
   list when set. These are task IDs, not Actor slugs or run/dataset IDs.
2. Apply unapplied migrations in order. Earlier `0090`/`0091` add the Bdjobs
   infrastructure. New `0092_linkedin_source.sql` commits the LinkedIn enum
   before `0093_apify_job_sources.sql` adds the shared service-only cache RPC
   and feed update. Applied migrations remain unchanged.
3. Deploy `worker`, `radar` and updated `policies` using [DEPLOY.md](DEPLOY.md).
   Install an updated app build for the LinkedIn label and availability copy.
4. Complete one successful collection, then let the hourly import schedule
   run, or call `public.enqueue_bdjobs_import()` through trusted server tooling.
   Legacy `import_bdjobs`/`tack-bdjobs-import` names remain compatible; they now
   handle both allowed boards and all four reviewed Actor schemas.
5. Verify actual source counts, links, deadlines, task failures, source timestamps,
   city/workplace/job-type filters, pagination and saving on a mobile device.
   Metadata or fixture tests alone cannot prove live coverage.

## Behavior and safeguards

Each task imports independently, so one failed task does not block the others.
Page jobs preserve Actor identity, dataset, completion time and offset. Only
four reviewed Actor IDs are accepted. Older queued pages without Actor metadata
default to the original ScrapingMonkey schema. Pages contain up to 100 rows;
retries do not duplicate jobs and older datasets cannot overwrite newer rows.
The service-only `cache_apify_job_page(jsonb)` allows only `bdjobs`/`linkedin`.
The original `cache_bdjobs_page` stays available for older workers.

Country evidence comes from the **posting**, never search terms/location.
Vero's explicit country wins over conflicting location text. Bdjobs without a
country field use known domestic city/district names. LinkedIn requires an
explicit Bangladesh country/location; ambiguous city names and worldwide remote
roles are insufficient. Unresolved locations are skipped, reducing coverage.
First-party URLs are canonicalized and validated against the board/job identity.
Employer apply URLs are not followed by the server. Salary currency/period are
preserved, missing pay is not estimated, and a false remote flag does not prove
onsite. The feed excludes expired postings and snapshots older than 48 hours.

## Validation and remaining gates

`flutter analyze` and backend type/format/lint checks pass. **558 Flutter tests,
172 backend tests and 13 temporary SQL checks** passed. The SQL verifier
(`node tool/verify_bdjobs_db.js`) rolls back all fixtures/temporary objects;
it does not apply migrations, change cron or modify production records.

## Supabase deployment — 25 October 2026

Applied migrations `0090`–`0093` to production project
`uvwmjeqymychlsybekxz`; all 93 repository migrations are now recorded. The
updated functions are active: `worker` v17, `radar` v8 and `policies` v2.
All retain `verify_jwt=false`; worker checks the cron secret internally and
Radar validates the signed-in user. The hourly
`tack-bdjobs-import` cron is active at minute 12; the existing worker cron runs
every two minutes. Vault URL/worker-secret values match the configured backend.
No credentials were changed or copied into files/client configuration.

Verified against production:

- All public tables retain enabled and forced RLS. Import/cache RPCs are
  service-only; no application RPC is executable by `anon`. The RPC surface
  verifier and all 13 rolled-back SQL contract checks pass.
- The actual deployed cache RPC, real skill indexing and feed RPC passed a
  rolled-back fixture test; no synthetic vacancy remains in production.
- An isolated import job was processed by the normal cron worker and finished
  with `{"skipped":"bdjobs not configured"}`, without an error. The worker
  was not manually invoked to drain other jobs.
- Radar and worker reject unsigned requests with HTTP 401. The public privacy
  route serves the updated LinkedIn disclosure.
- Authenticated cache-only Radar requests passed for Dhaka and for the
  Chattogram/in-person/internship filter combination. Both reported the missing
  Bdjobs/LinkedIn refresh accurately. No external collection was requested.
  The disposable, admin-confirmed test account was deleted afterward; no email
  was sent and public signup behavior was not changed.

Apify secret-name checks found none of `APIFY_API_TOKEN`, `APIFY_JOB_TASK_IDS`
or `APIFY_BDJOBS_TASK_ID`. There are no imported Bdjobs/LinkedIn listings.
Dedicated Apify saved search tasks, collection schedules and a token still need
configuration; no paid collections were started. These are external account
requirements, not missing Supabase migrations. Set secrets through the
[project's Edge Function secrets](https://supabase.com/dashboard/project/uvwmjeqymychlsybekxz/functions/secrets),
then complete and verify a bounded real collection before claiming live coverage.
An updated mobile build and physical-device acceptance also remain required.
Missing setup is not evidence that no jobs exist.
