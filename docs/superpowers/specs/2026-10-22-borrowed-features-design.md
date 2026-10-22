# Four features borrowed from awesome-llm-apps

Date: 2026-10-22. Source: [Shubhamsaboo/awesome-llm-apps](https://github.com/Shubhamsaboo/awesome-llm-apps),
read at the code level (16 apps, about 430 cited lines). We port the **mechanism**, not the
Python. Every feature follows Tack's rules in `AGENTS.md`: deterministic scoring, AI only through
`_shared/ai/`, PII redaction, 202 + job id, RLS on every table, sentence-case copy, and year-aware
wording.

Build order, one commit per feature, all on `feat/borrowed-features-2`:

1. Monday brief
2. Application checklist and interview prep brief
3. CV first read
4. Coach that cites or refuses

---

## 1. Monday brief

**Borrowed from:** `always_on_agents/release_radar_agent/ranker.py:33-116` (signal table, score
= top signal + 5 per extra reason, fixed "why you care" line per top reason, routine items
dropped) and `always_on_hn_briefing_agent/scheduler_api.py:61-72` (dry run by default, and only
an explicit `dry_run = false` delivers).

**What the student gets:** at most one push a week, Monday 09:00 Dhaka, with the three things
that most need their attention. No push when nothing qualifies.

**Signals** (SQL, per student; only the signals their mode allows):

| Signal | Rule | Score | Modes |
|---|---|---|---|
| `closing` | application `saved` or `applied`, and `jobs.closes_at` or `next_action_date` within 3 days | 100 | prove, launch, graduate |
| `interview` | application in `interview` with `next_action_date` in the next 7 days | 90 | prove, launch, graduate |
| `steps_late` | roadmap tasks past `due_date`, not done | 80 | all |
| `new_matches` | listings first seen in the last 7 days with fit ≥ 80 | 70 | build, prove, launch, graduate |
| `practice_due` | `interview_reviews.due_on <= today` | 60 | all that have reviews |
| `idle_step` | a not-done task untouched (`updated_at`) for 14 days | 50 | all |

An item is one thing (one application, one group of late steps). If an item matches more than
one signal, its score is its top signal plus 5 for each extra reason, as in the Release Radar
ranker. Ties break on the soonest date. Keep the top 3. Each item carries a fixed `why` line keyed
on its top reason, in that mode's wording. Explore and discover never see "deadline" or "apply"
(`closing` and `interview` are not computed for them), and a quiet week for those modes reads
"try".

**Data and server:**
- `weekly_brief_items(p_user uuid) returns jsonb`: a pure read, `security definer`, not granted
  to clients.
- `listing_fit(p_user, p_listing) returns int` mirrors the fit formula in `radar_feed` (0076,
  lines 86-94). `tool/verify_weekly_brief.js` checks that the two agree for a seeded student.
- `enqueue_weekly_brief(p_dry_run boolean default true) returns jsonb`: dry run returns what
  would be sent. `nightly_maintenance()` calls it with `false` when `tack_today()` is a Monday,
  **before** `enqueue_daily_digest()`. It uses the digest's dedupe key
  `digest:<user>:<date>`, so a student still gets at most one notification that day.
- `notify(type => 'weekly_brief')`. The title is "Your week: N things", the body is the top
  item's `why` line, and the payload is `{items: [{kind, title, why, route}]}`.

**App:** a weekly-brief notification opens a sheet listing the 3 items. Each item is tappable and
goes to its `route` (application detail, roadmap, radar, practise again).

**Existing bug found and fixed here (needs your OK):** `enqueue_daily_digest` (0066) runs at 00:20
Dhaka but schedules delivery for `(tack_today() + 1) 09:00`, which is about 33 hours later. A
"due soon" step can be overdue by the time the push arrives. The fix is to deliver at
`tack_today() 09:00`, which is what its own comment says it intends.

**Tests:** a SQL fixture through `tool/verify_weekly_brief.js` (throwaway users) covers ranking,
mode gating, the one-a-day cap shared with the digest, silence when nothing qualifies, and dry
run sending nothing. Plus a Flutter test for the sheet and its routing.

---

## 2. Application checklist and interview prep brief

**Borrowed from:** the insurance intake team. In `policies.py:276-632`, plain rules produce
findings with `rule_id`, `required_action` and a checklist `priority`; route precedence picks
one `_next_claimant_message` (`policies.py:240`); and `prepare_claim` (`policies.py:198`)
refuses to let the model claim evidence it was never given. The brief layout comes from
`ai_meeting_agent/meeting_agent.py:107-154`: talking points, Q&A prep, and questions to ask.

**Checklist** (free, deterministic):
`application_checklist(p_application uuid) returns jsonb` (owner only). Each rule has an id,
a severity and an action:

| Rule | When | Action |
|---|---|---|
| `APP-DATE` | `saved` and closes within 3 days | open the job link |
| `APP-CV` | no `cv_document_id` | attach a CV from the vault |
| `APP-JD` | no analysis for this job's description | open the analyser, prefilled |
| `APP-PRACTICE` | `interview`, and no answered practice question in 7 days | start practice for this role |
| `APP-PREP` | `interview`, and no prep brief yet | get the prep brief |
| `APP-FOLLOW` | `applied` more than 21 days ago with no status change | follow up or close it |

`next_step` takes the first match in this order: DATE, PRACTICE, PREP, CV, JD, FOLLOW. The
application detail screen shows the checklist and pins the `next_step` line at the top.

**Prep brief** (1 AI action, only from `interview` status): a new job type `interview_prep`,
added to the `enqueue_student_job` allowlist.
- **Input:** the job title and company, the job description (redacted) or its stored analysis,
  and the student's skill names and project titles and summaries (redacted). Nothing else.
- **Output schema:** `talking_points [{point, evidence}]`, `likely_questions [{question, why}]`,
  `questions_to_ask [string]`, `gaps [{skill, how_to_prepare}]`.
- **Evidence gate** (the insurance pattern): each `evidence` must name a skill or project that
  was in the input, using the same normalised substring match as the coach's citations. Points
  without valid evidence are dropped. Fewer than 2 valid points means the brief is not stored
  and the action is refunded through the existing `refund_job_quota` path.
- Stored in `interview_prep_briefs` (application id, input hash, brief jsonb), with owner-only
  RLS. Cached by input hash, so the same application with unchanged inputs is never charged
  twice.

**Tests:** Deno unit tests for the evidence gate and the schema, a Flutter test for the
checklist order and next step, and `tool/verify_application_checklist.js` to check the rules
against live SQL.

---

## 3. CV first read

**Borrowed from:** `agent_skills/first-reader`:
- personas with priors, situation, patience budget and stake, which must disagree with each other
  (`references/personas.md:9-60`)
- an interest needle from -2 to +2 per chunk, with the quit point as the main signal
  (`SKILL.md:173`, `scripts/feed.py:198`)
- a recall quiz: SAYBACK, POINTING, PEAK, ENDING, CENTER OF GRAVITY, ONE ACTION
  (`scripts/recall.py:37`)
- phone-screen skim maths, `chars / (38 × 14)` (`scripts/skim.py:18-52`)
- chunking into beats of about 85 words (`scripts/feed.py:63-68`)

**What the student gets:** on the CV check screen, after the free check, a "How a recruiter
reads this" card. Three readers show where each one stopped, what they remembered, and the
single thing to change.

**Free part** (added to the existing deterministic `check_cv`, no AI):
- `phone_screens`, using `skim.py`'s formula
- a `weak_phrases` list ("familiar with", "helped with", "assisted in", "responsible for",
  "basic knowledge of", "exposure to"), each with the line it appears on
- new findings `long-for-phone` and `weak-phrases` in `findings.ts`

**AI part** (1 AI action, opt-in button): a new job type `cv_first_read`.
1. The worker extracts the text, the same way `check_cv` does.
2. `redact()`, then `assertClean`.
3. Deterministic chunking: one chunk per CV section, split further above 85 words.
4. One model call with three fixed readers:
   - a Dhaka software-house recruiter: 8-second budget, skimming 40 CVs today
   - the hiring manager for the role: reads the projects first, sceptical
   - an HR officer at a large local company: checks basics and consistency
5. **Output schema:** `readers [{persona, needle: [{chunk, value}], quit_chunk | null,
   sayback, remembered: [string], one_action}]`.
6. **Recall gate** (Typed RAG's citation check, `agent.py:174-189`): each `remembered` item must
   be a normalised substring (at least 8 characters) of the CV text. Anything else is dropped,
   so a reader cannot "remember" what the CV never said.

Stored in `cv_first_reads` (document id, text hash, result), with owner-only RLS. Cached by text
hash. Shown with each reader's quit point drawn on the section list.

**Tests:** Deno tests for chunking, phone screens, weak phrases, and the recall gate (with a
forged quote dropped), plus a Flutter widget test for the card at 360 px.

---

## 4. Coach that cites or refuses

**Borrowed from:** `rag_tutorials/agentic_typed_rag_pydanticai`:
- seven rules: retrieve first, evidence only, verbatim quotes, no background knowledge
  (`agent.py:103-115`)
- the answer and its citations must agree (`agent.py:58-64`)
- a preflight refusal with no model call when retrieval is weak (`agent.py:230-232`)
- a quote is valid only if it is a substring of at least 8 characters of the cited chunk
  (`agent.py:174-189`)
- a refusal threshold of 0.20 (`app.py:125-131`)

**Retrieval** (in Postgres; no embeddings API, so no new provider or key):
- A `career_catalog_chunks` table is rebuilt from `career_paths` (summary, each `day_to_day`
  item, each `good_fit_if` item, salary line, demand) and `career_path_milestones` (description,
  unlock text). Columns: `chunk_id` (`<path-slug>:<kind>:<n>`), `path_id`, `text`, and a
  generated `tsvector`. A trigger keeps it in step when the catalog changes.
- `search_catalog(q text, k int = 4)` uses `websearch_to_tsquery('english', q)` and returns the
  top k chunks with `ts_rank_cd` normalised to 0-1, plus a path-name boost via the existing
  `pg_trgm`.

**Routing** (in the coach endpoint, after the free data rules):
- A question with catalog intent (it names a path, or asks about salary, day to day, "what does
  … do", "is … right for me", "become a") goes the grounded way.
- **Preflight:** a top score below 0.20 refuses with no model call and no AI action:
  "Tack's career guides don't cover that yet. Try asking about a path in Explore."
- Otherwise a `coach_cited` job runs on the evidence only. Its output schema is
  `answered, text, citations [{chunk_id, quote}], confidence`.
- **Code validation:** `answered` must have at least 1 valid citation and a refusal must have
  none. Invalid quotes are dropped, and no valid citation means a refusal with the action
  refunded.
- Everything else goes to the existing coach path unchanged.

**App:** a grounded reply shows "From Tack's career guides" with citation chips. Each chip opens
the path detail screen. A refusal is plain text and is never shown as an error.

**Tests:** Deno tests for intent routing, the preflight threshold, citation validation, and a
forged citation forcing a refusal (from `test_typed_rag.py:216`). `tool/verify_catalog_search.js`
checks that search returns the right path for 10 sample questions on live data.

---

## Shared rules, out of scope, risks

- **New job types and the allowlist:** `interview_prep`, `cv_first_read` and `coach_cited` are
  added to the `enqueue_student_job` allowlist in one migration. `coach_cited` is charged at
  submit like `coach_reply`, and refunded on a refusal after the model call.
- **Copy:** sentence case, plain English, no blame, and mode wording for every new string.
- **Out of scope:**
  - voice input
  - embeddings
  - students' GitHub repositories (explicitly not wanted)
  - multi-model panels
  - coach memory
- **Risks:**
  - The `listing_fit` mirror can drift from `radar_feed`. The verify script catches that.
  - Postgres `english` stemming will miss Bangla-English mixing. That is acceptable for v1 and
    is logged as a follow-up.
  - Three readers in one model call gives less independent readers than the source app's
    separate runs. That is acceptable at 1 AI action; three calls would cost three.
