# Tack API reference

Every call the app can make, and every call it answers.

Two transports, and the difference matters:

| | Postgres RPC | Edge Function |
|---|---|---|
| Called as | `supabase.rpc('name', params)` | `supabase.functions.invoke('name', body)` |
| Runs | inside the database | on Deno, at the edge |
| Costs AI quota | never | only where noted |
| Use it for | anything deterministic | anything that calls a model or a third party |

**The rule that decides which:** a readiness score, a job match, a skill
overlap and a roadmap are arithmetic, and arithmetic belongs in Postgres where
it gives the same answer twice. A model is only ever reached through an edge
function, and only for language. Nothing in `AGENTS.md` allows that boundary to
move.

## Authentication

**EXECUTE is deny-by-default.** A function in `public` is reachable from the app
only once it is granted to `authenticated` by name. The list in this document
*is* that allowlist — migration `0063` builds the grants from it.

Getting there took two goes, and the second is worth knowing about before you
add a function:

- Postgres grants `EXECUTE` on every new function to `PUBLIC`, and `PUBLIC`
  includes `anon`. Supabase separately pre-configures default privileges that
  grant `anon` and `authenticated` as well. A new function therefore arrives
  reachable by anyone holding the publishable key, which ships in every copy of
  the app.
- `ALTER DEFAULT PRIVILEGES … REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC` **does
  not fix this.** It cannot suppress Postgres's built-in default; measured, a
  function created after that statement has the identical ACL. It does work for
  Supabase's `anon` and `authenticated` grants, and `0065` uses it for those.
- What actually holds is an event trigger (`0065`): `tack_revoke_public_execute`
  fires on `CREATE FUNCTION` and strips `PUBLIC` and `anon` immediately.

So: **write the function, then grant it here explicitly**, and run
`node tool/verify_rpc_surface.js`. That check caught a real regression the same
day it was written — `0064` added two helpers and both came out anon-callable.

Every RPC and every edge function reads the caller's identity from the JWT.

- **RPCs** derive the user from `auth.uid()`. No function takes a user id as an
  argument. This is not a style preference: migration `0024` exists because an
  earlier function trusted a caller-supplied id, and the anon key is public, so
  anyone could pass somebody else's.
- **Edge functions** verify the bearer token, then use *two* clients on purpose:
  the caller's client for anything the student is allowed to read, and the
  service client only for shared rows they may read but must never write
  (job listings, the job queue). Radar is the clearest case — it writes
  listings as the service, then reads `radar_feed` **as the user**, so the fit
  score is computed against their skills and nobody else's.
- **RLS is the security boundary.** Client-side filtering is a convenience,
  never a control. Every table has RLS forced.

---

## RPCs, by feature

Signatures are the deployed ones — where a migration redefined a function, this
is the last definition. "Called by" names the repository that uses it today.

### Dashboard

| Function | Returns | Notes |
|---|---|---|
| `dashboard_feed()` | `jsonb` | The entire home screen in one round trip — greeting, week, score, streak, insights, roadmap and applications. Replaced nine PostgREST reads. Days are Dhaka-local via `tack_today()`. |
| `tack_today()` | `date` | Today in Asia/Dhaka. The one definition of "today" the whole app shares. |

Called by `dashboard/data/dashboard_repository.dart`.

### Roadmap and paths

| Function | Returns | Notes |
|---|---|---|
| `generate_roadmap(p_path_id uuid)` | `uuid` | Builds a personalised roadmap in one transaction. Skips `type='skill'` steps whose skill the student already holds at proficiency ≥ 3, spreads dates across the time to graduation, and records `skipped_count` so the screen can say why it is shorter. Idempotent. |
| `path_suggestions(p_limit int = 6)` | `jsonb` | Ranked career paths with the reason for each. Weights: target 45, field 25, skills 30, subjects 16, industry 10, speed 8. Speed is a tiebreak only — it cannot put a path on the list by itself. |
| `stop_following_path(p_path_id uuid)` | `boolean` | Unfollows and retires the roadmap. Reversible: following again restores the same roadmap and its progress. |
| `set_primary_path(p_path_id uuid)` | `void` | Marks which followed path is the target. |

Called by `roadmap/data/roadmap_repository.dart`, `paths/data/path_repository.dart`.

### Radar

| Function | Returns | Notes |
|---|---|---|
| `radar_feed(p_query text, p_location text, p_remote boolean, p_limit int = 20, p_offset int = 0, p_kind text)` | `jsonb` | Ranked openings with a fit score against the caller's skills. Prefer the `radar` edge function, which refreshes the boards first. |
| `radar_kinds()` | `jsonb` | Counts per employment kind, for the filter chips. |
| `save_listing(p_listing_id uuid)` | `uuid` | Saves an opening to the student's applications. |

Called by `radar/data/radar_repository.dart`.

### Notifications

| Function | Returns | Notes |
|---|---|---|
| `register_device(p_token text, p_platform text)` | `void` | Records this install against the signed-in student. Upserts on the token, so a reinstall or a second account on a shared phone reassigns it rather than leaving the previous owner receiving somebody else's reminders. |

`notify()` and `enqueue_daily_digest()` are **not** client-callable — see below.

### Coach

| Function | Returns | Notes |
|---|---|---|
| `coach_allowance()` | `jsonb` | `{used, limit}` for today. Read this to show the counter — do not derive it from `consume_quota`, which returns what is *left*. |
| `coach_context()` | `jsonb` | The student's numbers, assembled for the coach. Contact details are stripped again by `redact()` before anything leaves for a model. |

Called by `coach/data/coach_repository.dart`.

### Onboarding, profile and scoring

| Function | Returns | Notes |
|---|---|---|
| `submit_onboarding(p_answers jsonb)` | `readiness_scores` | Writes the answers and returns the first score in one call. |
| `write_onboarding(p_answers jsonb)` | `void` | The write half, without scoring. `SECURITY INVOKER`, so RLS applies to every statement inside it. |
| `onboarding_intended_field_slug(p_answers jsonb)` | `text` | The chosen field slug, whether the answer is an array or a string. Called from inside `write_onboarding`, which is why `authenticated` needs it. |
| `onboarding_intended_field(p_answers jsonb)` | `text` | The field's display name, resolved through `career_fields`. |
| `recompute_my_readiness(p_reason text = 'app')` | `readiness_scores` | Recomputes the caller's own score. |
| `current_readiness()` | `readiness_scores` | The latest score row. |
| `recompute_my_cv_score(p_document_id uuid)` | `cv_scores` | Rescores the caller's CV. |
| `current_cv_score()` | `cv_scores` | The latest CV score. |
| `set_default_cv(p_document_id uuid)` | `void` | Which CV the rest of the app uses. |

Called by `onboarding/data/draft_repository.dart`, `vault/data/document_repository.dart`.

### Applications

| Function | Returns | Notes |
|---|---|---|
| `upsert_company(raw_name text)` | `uuid` | Finds or creates a company, normalising the name so "Grameenphone Ltd." and "grameenphone" are one row. |
| `normalise_company_name(raw text)` | `text` | The normalisation on its own. |
| `is_valid_status_transition(from_s, to_s)` | `boolean` | Whether an application may move between two statuses. |

Called by `applications/data/application_repository.dart`.

### Pure helpers

`year_to_mode`, `stage_to_mode`, `derive_mode` and `classify_employment` are
deterministic converters, safe to call from anywhere. `derive_mode` is the
current one; the other two predate it.

---

## Edge functions

All are `POST` with a JSON body and a bearer JWT. All return JSON.

### `coach`

Ask the careers coach a question.

```json
{ "question": "What should I do next?", "threadId": "uuid | omitted" }
```

Answers from Tack's own numbers where it can, and spends one of the three daily
AI actions only when the question genuinely needs language.

```json
{ "threadId": "uuid", "reply": "…", "answeredBy": "data" | "model",
  "remaining": 2, "spent": false }
```

`answeredBy: "data"` means it cost nothing. When the allowance is gone:
`reply: null, remaining: 0, spent: false`.

### `radar`

Refresh the shared listing cache, then return the caller's ranked feed.

```json
{ "query": "backend", "location": "Dhaka", "remote": true,
  "kind": "internship", "limit": 20, "offset": 0, "refresh": true }
```

```json
{ "listings": [...], "fetched": 37, "problems": { "careerjet": "…" } }
```

`problems` is named per board so the screen can say *"Careerjet is not set up
yet"* rather than pretending there is nothing out there. Costs no quota —
nothing here calls a model. Boards are only refreshed on the first page
(`offset: 0`).

### `score-cv`

```json
{ "documentId": "uuid" }
```

Returns `202` with `{status: "queued", jobId, quotaRemaining}` and never
blocks — reading the file and calling the model happen in the worker. Bytes
already parsed come back `200` with `{status: "ready", …}` and cost no quota:
re-uploading your own CV should not spend one of three daily actions.

### `analyze-jd`

```json
{ "text": "the job description" }
```

Same shape as `score-cv`. An identical description already analysed is served
from the content-addressed cache at `200`, free.

### `interview`

Two actions on one function.

```json
{ "action": "questions", "role": "Backend developer", "sessionType": "mixed" }
{ "action": "evaluate", "questionId": "uuid", "answer": "…" }
```

→ `{questions, cached, quotaRemaining}` and `{feedback, quotaRemaining}`.

### `worker`

Not called by the app. A cron trigger every two minutes, guarded by the
`CRON_SECRET` bearer. Works to a 25-second budget rather than emptying the
queue, so it always returns before the platform limit and the next run picks up
where it stopped. Returns `{worker, processed, failed, elapsedMs}`.

---

## Not part of the client API

Granted to `authenticated`, but not for you to call:

- **RLS helpers** — `owns_application`, `owns_course`, `owns_document`,
  `owns_milestone`, `owns_question`, `owns_roadmap`, `owns_session`. Row
  policies call these. They are granted because a policy runs as the caller.

Never granted to `authenticated`, and deliberately so:

- **Worker and queue** — `claim_jobs`, `fail_job`, `reap_stuck_jobs`,
  `dispatch_worker`, `drain_local_jobs`, `is_coalesced_job`,
  `superseded_by_pending`, `nightly_maintenance`, `sweep_stuck_documents`.
- **Quota** — `consume_quota`, `quota_remaining`, `refund_quota`. Read
  `coach_allowance()` instead. `consume_quota` returns what is **left**, not
  what was used; subtracting from it again made the counter climb.
- **Scoring internals** — `recompute_readiness`, `readiness_ratios`,
  `score_cv_fit`, `cv_fix_copy`, `field_expected_skills`,
  `roadmap_progress_ratio`, `recompute_milestone_states`,
  `derive_career_field`, `tack_activity`, `tack_week_summary`.
- **Radar indexing** — `extract_listing_skills`, `reindex_listing_skills`,
  `reindex_listings`, `prune_job_listings`.
- **Notifications** — `notify`, `enqueue_daily_digest`. `notify()` is the only
  way a notification is made: it writes the in-app row *and* enqueues the push
  in one transaction, deduplicated on a key, so the phone can never announce
  something the inbox cannot show. A student who could call it could put a
  message in somebody else's inbox, so they cannot.

`tack_week_summary` is the cautionary one: it was granted, then revoked in
`0047`, because it took a user id as an argument.

Fourteen trigger functions maintain invariants and are never called directly:
`advance_milestone_state`, `enforce_max_two_paths`, `enqueue_cv_rescore`,
`enqueue_readiness_recompute`, `ensure_one_primary_path`,
`fail_document_on_dead_job`, `handle_new_user`, `promote_next_primary_path`,
`record_application_status`, `retire_roadmap_on_unfollow`, `set_updated_at`,
`stamp_document_purge`, `stamp_listing_kind`, `stamp_task_done`.

---

## Outbound: what Tack calls

### Job boards, via `_shared/radar/providers.ts`

| Board | Key needed | Notes |
|---|---|---|
| `artificialintelligencejobs.co` | no | |
| `remotive.com` | no | remote only |
| `arbeitnow.com` | no | |
| `themuse.com` | no | |
| `search.api.careerjet.net` | **yes** | `CAREERJET_API_KEY`, plus `CAREERJET_LOCALE`. The only board with real Bangladesh coverage — without it the fit score has little to read. |

Results are deduplicated by URL hash. `broaden()` strips generic role words,
because both the boards and the SQL matched `"Backend developer"` as a phrase
and returned nothing.

### Model

`generativelanguage.googleapis.com` — Gemini, reached only through
`_shared/ai/gateway.ts`. `AI_PROVIDER=mock` is the default and calls nothing.

**PII redaction before any model call is mandatory.** No CV text, no
application notes, no document contents, no email or phone. `redact()` is the
boundary and it has tests.

### Environment

Server-side only, set with `supabase secrets set`. None of these may appear in
`app/`:

`GEMINI_API_KEY`, `CAREERJET_API_KEY`, `CAREERJET_LOCALE`, `CRON_SECRET`,
`SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `AI_PROVIDER`.

The client gets its config from `--dart-define-from-file=env/dev.json`, which
is gitignored.

> `CRON_SECRET` was written into the worker before it was ever deployed, so
> every cron call answered 401 for a while. If the worker is silently doing
> nothing, check that first.

---

## Keeping this honest

The function lists here were extracted from `supabase/migrations/*.sql` rather
than written by hand — 72 functions across 62 migrations, several redefined
more than once, and the last definition is the one that is live. If you add a
migration, re-derive rather than editing the tables by memory:

```bash
grep -rhoiE "create or replace function public\.[a-z_]+" supabase/migrations/ \
  | sed 's/.*public\.//' | sort -u
```

and check the grants, which are what actually decide whether the client can
reach a function:

```bash
node tool/verify_rpc_surface.js
```

That asserts the invariant in two layers: the catalogue is the whole truth, but
PostgREST is what is exposed to the internet, so it also calls two functions
over HTTP with the publishable key and asserts they are refused.
