# Bangladesh job discovery

Radar starts with in-person work in the student's profile city (Dhaka if no city
is set). Location, workplace, and employment type are independent: for example,
in-person internships in Chattogram. A location sheet supports quick city choices
and a typed district. Search controls scroll with results on short screens.
Refresh, additional cached result pages, immediate save feedback, and clearer
partial-source notices complete the browsing flow. Cache-wide counts no longer
appear on filtered chips, because those counts did not describe the active city.

## Additional API

[JSearch by OpenWeb Ninja](https://www.openwebninja.com/api/jsearch) aggregates
general job postings and provides country/location search, employment types,
application links, and salary fields when supplied by the employer. This is an
additional source alongside Careerjet, not a replacement for Bangladesh boards.
Bangladesh listing volume and quality still need a live credentialed check.

The adapter calls `https://api.openwebninja.com/jsearch/search` with `country=bd`,
`language=en`, a city and Bangladesh in the query, and one page of listings from
the past month. The direct portal key goes in the `x-api-key` header. RapidAPI
keys are not interchangeable with this direct API key.

`work_from_home=false` includes both arrangements upstream. Tack checks each
returned boolean independently. Unknown arrangements are skipped because the
current shared listing schema only supports a boolean. Overseas on-site results
are rejected; remote eligibility must still be checked on the original posting.
Empty salary values are not estimated. Invalid rows, unsafe links, and invalid
dates cannot break a valid page. Source failures preserve the existing cached feed.

Repeated identical requests share a 15-minute, 100-entry cache within a warm
Edge Function isolate. This is not a durable rate limiter across isolates.
Review the provider's current plan/terms and set account-side request limits
before enabling a production key. No automatic retry or multi-page upstream
request is made. “Load more” reads the existing Supabase cache, not the paid API.

## Activation

The integration is implemented locally. It has not been deployed or tested
against live JSearch data; no JSearch key was present in the local configuration.

1. Obtain a direct OpenWeb Ninja key for JSearch and put `JSEARCH_API_KEY` in
   Supabase Edge Function secrets using the dashboard or existing secure secret
   tooling. Never put it in Flutter config, a tracked file, or chat.
2. Apply `0076_radar_jsearch.sql` before deploying the function:
   `node tool/migrate.js 0076_radar_jsearch`.
3. Deploy `radar` using the command in [DEPLOY.md](DEPLOY.md).
4. With an authenticated account, search for accountant, sales, teacher, and
   operations roles in Dhaka. Confirm the source and application links and test
   the in-person + internship combination. A fixture test cannot establish live
   Bangladesh coverage.

Careerjet remains supported using `CAREERJET_API_KEY` and `CAREERJET_LOCALE=en_BD`.
The missing-key state is nonfatal for either provider. Existing free sources
remain available, and the remote-only Remotive request is skipped for in-person
searches.

## Validation

```sh
cd app
flutter analyze
flutter test
cd ../supabase/functions
deno check radar/index.ts
deno test --allow-env=JSEARCH_API_KEY _shared/radar/
```

Provider tests use network fixtures, including an explicit false work-location
flag, malformed rows, missing configuration, rate limiting, and concurrent
request reuse. Flutter tests exercise combined filters, location selection,
pagination, save feedback, and the minimum phone viewport.
