# Data model

Generated from the live database, Row Level Security enabled and forced on
every table. The interview pool of 0096 is added by hand until the next
regeneration. Regenerate with `node tool/psql.js` — see the command in
`docs/` history if it drifts.

Ownership shapes:

- **owned** — `user_id = auth.uid()`, full CRUD by the owner
- **child** — owned, plus a `WITH CHECK` proving the parent is owned too
- **reference** — readable by any authenticated user, writable by none
- **server** — readable by the owner, written only by Edge Functions

### `activities`

```
id uuid
user_id uuid
category USER-DEFINED
title text
organisation text
role text
start_date date
end_date date
description text
created_at timestamp with time zone
updated_at timestamp with time zone
deleted_at timestamp with time zone
```

### `ai_usage`

```
id uuid
user_id uuid
feature text
provider text
model text
prompt_tokens integer
completion_tokens integer
cached boolean
succeeded boolean
error_code text
queue_job_id uuid
created_at timestamp with time zone
```

### `application_status_history`

```
id uuid
application_id uuid
user_id uuid
from_status USER-DEFINED
to_status USER-DEFINED
note text
changed_at timestamp with time zone
```

### `audit_log`

```
id bigint
user_id uuid
action text
entity text
entity_id uuid
meta jsonb
created_at timestamp with time zone
```

### `career_path_milestones`

```
id uuid
path_id uuid
order_index integer
title text
description text
unlock_text text
typical_semester integer
```

### `career_path_skills`

```
path_id uuid
skill_id uuid
importance USER-DEFINED
```

### `career_path_tasks`

```
id uuid
milestone_id uuid
order_index integer
title text
type USER-DEFINED
points integer
est_minutes integer
skill_id uuid
```

### `career_paths`

```
id uuid
slug text
title text
summary text
category text
salary_min_bdt integer
salary_max_bdt integer
months_to_job_ready integer
demand_level text
day_to_day ARRAY
good_fit_if ARRAY
sort_order integer
is_active boolean
created_at timestamp with time zone
```

### `certifications`

```
id uuid
user_id uuid
title text
issuer text
issued_on date
expires_on date
credential_id text
credential_url text
document_id uuid
created_at timestamp with time zone
updated_at timestamp with time zone
deleted_at timestamp with time zone
```

### `cities`

```
id uuid
name text
division text
sort_order integer
```

### `cohort_benchmarks`

```
year_of_study integer
mode USER-DEFINED
avg_total integer
cohort_size integer
```

### `companies`

```
id uuid
name text
normalised_name text
website text
location text
created_at timestamp with time zone
```

### `course_skills`

```
course_id uuid
skill_id uuid
```

### `courses`

```
id uuid
user_id uuid
semester text
semester_order integer
code text
title text
grade text
grade_points numeric
credits numeric
created_at timestamp with time zone
updated_at timestamp with time zone
deleted_at timestamp with time zone
```

### `cv_parse_results`

```
id uuid
document_id uuid
user_id uuid
parsed jsonb
quality_score integer
warnings jsonb
created_at timestamp with time zone
```

### `documents`

```
id uuid
user_id uuid
type USER-DEFINED
title text
storage_path text
mime_type text
size_bytes bigint
checksum text
status USER-DEFINED
failure_reason text
is_default boolean
version integer
parent_document_id uuid
created_at timestamp with time zone
updated_at timestamp with time zone
deleted_at timestamp with time zone
purge_after timestamp with time zone
```

### `education`

```
id uuid
user_id uuid
university_id uuid
university_name text
degree text
field_of_study text
start_year integer
graduation_year integer
cgpa numeric
cgpa_scale numeric
is_current boolean
created_at timestamp with time zone
updated_at timestamp with time zone
deleted_at timestamp with time zone
```

### `experiences`

```
id uuid
user_id uuid
company_name text
title text
employment_type text
location text
start_date date
end_date date
is_current boolean
description text
created_at timestamp with time zone
updated_at timestamp with time zone
deleted_at timestamp with time zone
```

### `interview_feedback`

```
id uuid
question_id uuid
user_id uuid
score numeric
went_well jsonb
to_improve jsonb
model_answer text
created_at timestamp with time zone
```

### `interview_pool_questions`

Reference (0096). Written only by seed migrations.

```
id uuid                  -- uuid5 from build.py: role and normalised text, stable across builds
role_slug text           -- null for the behavioural pool
kind text                -- 'behavioural' | 'role'
difficulty USER-DEFINED
category text            -- sentence case, as written ("Data quality", "HR round")
question text
key_points jsonb         -- 2-4 strings: what a strong answer covers
source_url text          -- set when the question cites a Bangladesh rule
sort_order integer       -- authoring order within the role
is_active boolean
created_at timestamp with time zone
```

### `interview_question_bank`

Reference. The fixed sets old app builds read through the interview function.

```
id uuid
role_slug text
session_type USER-DEFINED
difficulty USER-DEFINED
questions jsonb          -- [{question, category, key_points?, pool_id?}]
created_at timestamp with time zone
source text              -- 'seed' | 'model' (0096); the seed guard protects 'seed'
```

### `interview_questions`

```
id uuid
session_id uuid
user_id uuid
order_index integer
question text
category text
answer_text text
skipped boolean
answered_at timestamp with time zone
pool_question_id uuid    -- 0096: the pool question it was drawn from
key_points jsonb         -- 0096: copied from the pool, [] for packs and old sets
self_check jsonb         -- 0096: {"covered": [0, 2], "total": 4}, written by the owner
```

### `interview_role_aliases`

Reference (0096). Other names job ads use for a role, lower case.

```
alias text
role_slug text
```

### `interview_role_paths`

Reference (0096). Catalog career paths with no role of their own, mapped to
the nearest role.

```
path_slug text
role_slug text
```

### `interview_roles`

Reference (0096). One default per career field.

```
slug text
title text
cluster text             -- the content file it comes from
field_slug text
summary text
is_field_default boolean
sort_order integer       -- line of the field in career_fields.txt x 100, default first
is_active boolean        -- a role is retired, never deleted
created_at timestamp with time zone
```

### `interview_sessions`

```
id uuid
user_id uuid
role text
session_type USER-DEFINED
difficulty USER-DEFINED
timer_enabled boolean
question_count integer
started_at timestamp with time zone
completed_at timestamp with time zone
overall_score numeric
strongest_area text
weakest_area text
points_earned integer
summary jsonb
deleted_at timestamp with time zone
role_slug text           -- 0096: the pool role; null for packs and older sessions
```

`role` keeps the role's title, so history, `interview_due()`, the application
checklist and `coach_context()` read what they always did. `overall_score` is
null when nothing was scored by AI, so free practice never lowers readiness.

### Interview question pool (0096, 0098)

- **Where questions come from.** Hand-written content in
  `supabase/seed/interview_bank/roles_*.py` and `behavioural.py`, checked by
  `validate.py`. `build.py` turns it into a seed migration (0098). Questions
  never come from a model: the interview function serves a role's fixed set or
  the student's nearest role's.
- **Practice.** `start_practice_session()` draws from the pool (avoiding what
  the student saw in the last 90 days) and writes the session and its questions
  in one transaction. Free: no model, no AI action. Forty starts a day per
  student, counting deleted sessions.
- **Which role.** `interview_resolve_role_for()` tries a hint, then the
  student's primary path, their target role, their intended field, then
  `management-trainee`. `interview_catalog()` returns the suggestion and every
  field with its roles.
- **The seed guard.** A `BEFORE UPDATE` trigger on `interview_question_bank`
  skips any update to a `source = 'seed'` row unless the transaction set
  `tack.seeding = 'on'`. Only a seed migration sets it (`set local`, and a DO
  block that fails if it is not on). The worker's model sets can never replace
  a hand-written set.
- **Adding a role next round.** Add it to `MANIFEST` in `validate.py`, write its
  content in its cluster's file, have the other writer read it and set
  `reviewed_on`, then:

  ```
  python3 supabase/seed/interview_bank/validate.py --strict --all \
    supabase/seed/interview_bank/roles_*.py supabase/seed/interview_bank/behavioural.py
  python3 supabase/seed/interview_bank/build.py --out supabase/migrations/NNNN_interview_pool_refresh.sql
  python3 supabase/seed/interview_bank/build.py --verify
  ```

  Never edit an applied migration; a refresh is a new one. Ids come from the
  text, so unchanged questions keep their ids and students their history.

### `job_analyses`

```
id uuid
raw_text_hash text
source_job_id uuid
job_title text
company_name text
extracted jsonb
model text
created_at timestamp with time zone
```

### `job_applications`

```
id uuid
user_id uuid
job_id uuid
status USER-DEFINED
applied_at timestamp with time zone
next_action text
next_action_date date
cv_document_id uuid
notes text
source text
created_at timestamp with time zone
updated_at timestamp with time zone
deleted_at timestamp with time zone
```

### `job_match_scores`

```
id uuid
user_id uuid
analysis_id uuid
match_percent integer
matched_skills jsonb
missing_skills jsonb
computed_at timestamp with time zone
```

### `jobs`

```
id uuid
user_id uuid
company_id uuid
company_name text
title text
location text
employment_type text
description text
source_url text
posted_at date
closes_at date
salary_min_bdt integer
salary_max_bdt integer
is_public boolean
created_at timestamp with time zone
updated_at timestamp with time zone
deleted_at timestamp with time zone
```

### `jobs_queue`

```
id uuid
user_id uuid
type text
payload jsonb
status USER-DEFINED
attempts integer
max_attempts integer
idempotency_key text
run_after timestamp with time zone
locked_at timestamp with time zone
locked_by text
last_error text
result jsonb
created_at timestamp with time zone
updated_at timestamp with time zone
```

### `notifications`

```
id uuid
user_id uuid
type text
title text
body text
payload jsonb
read_at timestamp with time zone
created_at timestamp with time zone
```

### `portfolio_links`

```
id uuid
user_id uuid
kind text
url text
created_at timestamp with time zone
deleted_at timestamp with time zone
```

### `profiles`

```
id uuid
full_name text
city_id uuid
phone text
avatar_url text
year_of_study integer
years_total integer
expected_graduation date
mode USER-DEFINED
target_role text
target_industry ARRAY
onboarding_step integer
onboarding_completed_at timestamp with time zone
locale text
created_at timestamp with time zone
updated_at timestamp with time zone
deleted_at timestamp with time zone
```

### `projects`

```
id uuid
user_id uuid
title text
summary text
url text
repo_url text
started_on date
completed_on date
created_at timestamp with time zone
updated_at timestamp with time zone
deleted_at timestamp with time zone
```

### `rate_limits`

```
id uuid
user_id uuid
bucket text
window_start date
count integer
```

### `readiness_scores`

```
id uuid
user_id uuid
total integer
mode USER-DEFINED
components jsonb
delta integer
reason text
computed_at timestamp with time zone
```

### `roadmap_milestones`

```
id uuid
roadmap_id uuid
user_id uuid
source_milestone_id uuid
order_index integer
title text
description text
unlock_text text
typical_semester integer
state USER-DEFINED
completed_at timestamp with time zone
created_at timestamp with time zone
updated_at timestamp with time zone
```

### `roadmap_tasks`

```
id uuid
milestone_id uuid
user_id uuid
order_index integer
title text
type USER-DEFINED
points integer
est_minutes integer
skill_id uuid
due_date date
is_done boolean
done_at timestamp with time zone
is_custom boolean
shared_with_roadmaps ARRAY
created_at timestamp with time zone
updated_at timestamp with time zone
deleted_at timestamp with time zone
```

### `roadmaps`

```
id uuid
user_id uuid
path_id uuid
title text
origin USER-DEFINED
is_active boolean
created_at timestamp with time zone
updated_at timestamp with time zone
deleted_at timestamp with time zone
```

### `score_weights`

```
mode USER-DEFINED
component text
weight integer
```

### `skills`

```
id uuid
slug text
name text
category text
aliases ARRAY
is_active boolean
created_at timestamp with time zone
```

### `universities`

```
id uuid
name text
short_name text
city_id uuid
is_active boolean
```

### `user_career_paths`

```
id uuid
user_id uuid
path_id uuid
is_primary boolean
selected_at timestamp with time zone
deleted_at timestamp with time zone
```

### `user_skills`

```
id uuid
user_id uuid
skill_id uuid
proficiency integer
source USER-DEFINED
evidence text
created_at timestamp with time zone
updated_at timestamp with time zone
```

