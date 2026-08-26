# Tack — Feature 1: Onboarding & Profile Intake

Architecture and build prompt for Claude Code.

---

## PART 1 — What this feature is

A branching intake flow that takes a new user from "just signed up" to "profile complete, mode assigned, ready to see a dashboard."

It is the **most important feature in the product**. Everything downstream — readiness score, roadmap, path explorer — reads from what this collects. If the data model is wrong here, every later feature inherits the mistake.

It uses **zero AI**. Everything is forms, validation and deterministic logic.

---

## PART 2 — Architecture decisions

### 2.1 The flow is data, not code

The step sequence lives in one declarative config file. Steps, branches, fields, validation and order are all data. The renderer walks the config.

**Why:** you will change this flow a dozen times. If steps are hardcoded React components with `if (stage === 'high_school')` scattered through them, every change is a refactor. With a config, adding a question is one object.

```
src/server/modules/onboarding/flow.config.ts
```

### 2.2 Drafts are separate from real data

Answers go into an `onboarding_drafts` table as JSONB, saved after every step. Only on final submission does the app write to `user_profiles`, `education_profiles`, `user_skills` and so on in a single transaction.

**Why:** partial answers never pollute the real tables. A user who abandons at step 3 doesn't leave a half-built profile that the readiness score then tries to grade. Resume-where-you-left-off becomes trivial. And you can inspect drafts to see exactly where people drop off.

### 2.3 Stage-typed tables, not one JSONB blob

`education_profiles` holds what's common (stage, institution, country). Stage-specific detail goes in `high_school_profiles` or `university_profiles` — real columns, real types, real constraints.

**Why:** you will query "all students graduating in 2027" and "all users whose favourite subject is physics." JSONB makes those queries slow and untyped. The flexible-schema argument doesn't apply — you know these fields.

### 2.4 Mode is derived, never stored as a free value

A single function maps stage plus year to a mode. Store the inputs; compute the mode.

| Stage | Year | Mode | Focus |
|---|---|---|---|
| High school | — | **Discover** | Subjects, interests, what degree to aim for |
| Bachelor's | 1 | **Explore** | Try things, find direction |
| Bachelor's | 2 | **Build** | Skills, first projects |
| Bachelor's | 3 | **Prove** | Internships, portfolio |
| Bachelor's | Final | **Launch** | Applications, interviews |
| Graduated | — | **Launch** | Same, higher urgency |

**Why:** if a user corrects their graduation year, the mode must update automatically. Storing a mode string means it silently goes stale.

### 2.5 Primary school creates no account

The Primary branch is a terminal screen. It captures an email into a `waitlist` table and stops. No user row, no profile.

**Why:** honest product behaviour, and it avoids holding personal data on children who can't meaningfully consent.

### 2.6 One validation source

Each step's Zod schema is used by the client for inline validation and by the server route on submit. Same file, imported both sides.

**Why:** client validation is UX, server validation is security. Two copies drift, and the drift is always the server being weaker.

---

## PART 3 — The flow

```
                      ┌─ Primary ──► waitlist screen ─── END (no account)
                      │
signup ► step 1 ► step 2 ─┼─ High school ─► HS-1 ► HS-2 ► HS-3 ─┐
        basic    stage    │                                      ├─► review ► complete
                      ├─ Bachelor's ──► UNI-1 ► UNI-2 ► UNI-3 ──┤
                      │                                          │
                      └─ Graduated ───► GRAD-1 ► GRAD-2 ─────────┘
```

### Step 1 — About you (all users)
- Full name (required)
- Country (required, searchable select, defaults to Bangladesh)
- City (required, free text with suggestions once country is known)
- Phone (optional, dial code derived from country, never hardcoded)
- Date of birth **or** age band (required — drives the under-13 guard)

### Step 2 — Where are you now? (all users)
Four large tappable cards, not a dropdown. Each with a one-line description.

- **Primary school** → terminal branch
- **High school / college** → HS branch
- **Bachelor's — currently studying** → UNI branch
- **Graduated** → GRAD branch

### Primary branch — terminal
Honest copy: Tack is built for high school and above, we're not ready for you yet, we'd like to tell you when we are. One email field, one button, no account created. Never the word "rejected."

### High school branch

**HS-1 — Your school**
- School name, current class/grade (9–12 or equivalent), expected finish year
- Curriculum (National / English medium / O-A Level / IB / other) — country-dependent options
- Current grade or GPA (optional, with a note it's never shown publicly)

**HS-2 — What you enjoy**
- Favourite subjects (chip multi-select, min 1)
- Subjects you find hard (chip multi-select, optional — feeds gap analysis later)
- Interests and hobbies (chips + free-text escape hatch)

**HS-3 — Where you're heading**
- Field you want to study at bachelor's (chips: engineering, medicine, business, CS, arts, law, science, undecided)
- **"Not sure yet" is a first-class, prominently offered answer** — this is the honest state for most 16-year-olds and the app should reward it, not penalise it
- What matters most to you in a career (rank or pick 3: money, stability, creativity, helping people, independence, recognition)
- One free-text: what would you love to be doing in ten years (optional, 200 chars)

### Bachelor's branch

**UNI-1 — Your university**
- University (searchable, with "not listed" fallback), degree, major/department
- **Current year of study** and expected graduation month/year — *this is the single most important field in the flow, it drives the entire app mode*
- CGPA (optional, noted as never shown)

**UNI-2 — Your courses**
- Current semester courses (add rows: code, title, credits — max 8, skippable)
- Favourite courses so far (chips drawn from the courses just entered plus common ones)
- Skills (chip multi-select from taxonomy, plus "add your own")

**UNI-3 — Your direction**
- Target role (searchable, "not sure yet" allowed and prominent)
- Target industry (chips)
- Any internship or work experience yet (yes/no → if yes, brief detail)
- Extracurricular involvement (chips: clubs, volunteering, competitions, leadership, sports, none yet)

### Graduated branch

**GRAD-1 — Your degree**
- University, degree, major, graduation year, CGPA (optional)
- Currently: job hunting / employed / freelancing / studying further

**GRAD-2 — Your direction**
- Target role, target industry
- Experience so far (internships, jobs — repeatable rows)
- Skills (chip multi-select)

### Review step (all accepted branches)
Every answer, grouped, each with an inline edit link jumping back to that step. One primary button: "Finish setup."

### Completion
Single transaction writes everything, marks the draft complete, computes the first readiness score, seeds a template roadmap if a target role was chosen, then reveals the score.

---

## PART 4 — Data model

```
users                    (from Supabase Auth)
user_profiles            1-1 with users: name, country, city, phone,
                         dial_code, birth_year, age_band, onboarding_completed_at
education_profiles       1-1: stage enum, institution_name, institution_id?,
                         country, start_year, expected_end_year, gpa, gpa_scale
high_school_profiles     1-1 with education_profiles where stage='high_school':
                         current_class, curriculum enum, intended_field,
                         field_confidence enum (sure | leaning | unsure)
university_profiles      1-1 where stage in ('bachelors','graduated'):
                         degree, major, year_of_study, graduation_month,
                         current_status enum
courses                  N-1 user: code, title, credits, semester, is_favourite
user_subjects            N-1 user: subject_id, sentiment enum (loves | finds_hard)
user_interests           N-1 user: interest_id, source enum (preset | custom)
user_skills              N-1 user: skill_id, proficiency, source
career_preferences       1-1: target_role, target_industry, confidence enum,
                         values[] (ranked), ten_year_note
experiences              N-1 user: type enum, org, role, start, end, description
activities               N-1 user: category enum, org, role, dates
onboarding_drafts        1-1 user: current_step, branch, answers jsonb,
                         started_at, updated_at, completed_at
waitlist                 email, stage_requested, country, created_at
```

Reference tables seeded up front: `countries` (with dial codes), `subjects`, `interests`, `skills`, `universities` (Bangladeshi ones first), `career_fields`.

---

## PART 5 — The prompt for Claude Code

Paste Part 5.1 into `CLAUDE.md` at your project root first. Then dispatch 5.2 through 5.6 one at a time.

### 5.1 — CLAUDE.md additions

```markdown
## Feature: Onboarding

The onboarding flow is a branching, resumable, config-driven intake.

Rules specific to this feature:
- The step sequence is defined in flow.config.ts as data. Never hardcode
  step order or branch logic into components.
- Answers save to onboarding_drafts (JSONB) after every step. Real tables
  are written only on final submit, in one transaction.
- Each step has one Zod schema used by BOTH client and server.
- User mode (discover/explore/build/prove/launch) is ALWAYS derived by
  deriveMode(stage, yearOfStudy, graduationYear). Never stored as a value.
- The Primary school branch creates no account. Waitlist only.
- Country is dynamic. Never hardcode +880, BDT, or Bangladeshi universities
  as the only option — default to them, don't assume them.
- "Not sure yet" is a valid, prominent answer wherever direction is asked.
  Never make it feel like a failure state.

Design tokens (from the design handoff — match exactly):
- Maroon #7A1B34 primary, deep #5E1428, tint #F3E7EA, pale #FBF4F5
- Teal #5DCAA5 fill / #1A6B50 as text, tint #EAF8F2
- Amber #FAC775 fill / #8A6415 as text, tint #FDF6E7
- Sail white #F1EFE8 background, white #FFFFFF cards
- Ink #23181C text, muted #6E5B61 secondary text (the ONLY secondary colour)
- Line #EDE7E4, Line2 #DCD4CF, danger #A32B2B
- #C9B6BC is for strokes and disabled fills only, NEVER text
- Outfit 600 for headings/numbers, Inter 400/500/600 for body, IBM Plex Mono
  for small uppercase labels only
- Cards 20px radius, inputs 12-14px, chips fully round 20-22px
- Primary button 52-54px tall, full width, radius 14px
- Chips min-height 44px. Every tappable row min-height 44px.
- Screen padding 20px (22px on onboarding)
- Shadow only: 0 1px 2px rgba(35,24,28,.06)
- Emphasis via 1.5px solid #7A1B34 border, not shadow

Layout shell for every screen:
[status bar fixed] [progress fixed] [scrollable body flex:1 min-h-0]
[pinned CTA fixed outside scroll]
The pinned CTA outside the scroll region is load-bearing. Do not change it.

Copy rules: sentence case always, never title case. Plain English for
second-language readers. Short. Never blame the user.
```

### 5.2 — Task 1: schema and reference data

```
Build the database layer for Tack's onboarding feature.

Read the design handoff at ./design/README.md first.

1. Drizzle schema in src/server/db/schema/ for: user_profiles,
   education_profiles, high_school_profiles, university_profiles, courses,
   user_subjects, user_interests, user_skills, career_preferences,
   experiences, activities, onboarding_drafts, waitlist.
   Plus reference tables: countries, subjects, interests, skills,
   universities, career_fields.

   Use the model in ./docs/onboarding-architecture.md Part 4. UUID PKs,
   timestamptz created_at/updated_at, soft delete via deleted_at on
   user-owned tables. Enums as real Postgres enums.

2. Indexes: unique on (user_id) for all 1-1 tables, unique on
   (user_id, skill_id), (user_id, subject_id), index on
   education_profiles(stage), waitlist(email) unique.

3. RLS policies: users read/write only rows where user_id = auth.uid().
   Reference tables readable by all authenticated users, writable by none.
   waitlist is insert-only for anon. Enable RLS on every table.

4. Seed data:
   - ~200 countries with ISO code, name, dial code
   - ~120 school subjects (sciences, humanities, commerce, languages)
   - ~80 interests and hobbies
   - ~400 skills across software, business, finance, design, soft skills
   - Top 60 Bangladeshi universities, plus a "not listed" escape
   - ~40 career fields

5. Generate the migration. Do not run it yet.

Show me the schema and seed plan before writing code.
```

### 5.3 — Task 2: the flow engine

```
Build the onboarding flow engine for Tack. No UI yet.

1. src/server/modules/onboarding/flow.config.ts — declarative definition of
   every step: id, branch, title, subtitle, fields (type, label, options
   source, required), and the next-step resolver. Branches: primary,
   high_school, bachelors, graduated. Use the flow in
   ./docs/onboarding-architecture.md Part 3.

   Field types needed: text, select, searchable-select, multi-chip,
   radio-cards, repeatable-rows, textarea, date-parts, rank-picker.

2. src/server/modules/onboarding/schemas.ts — one Zod schema per step,
   exported individually and as a map keyed by step id.

3. src/server/modules/onboarding/mode.ts — deriveMode(stage, yearOfStudy,
   graduationYear) returning discover | explore | build | prove | launch.
   Pure function. Unit tested, including edge cases: a bachelor's student in
   year 4 of a 4-year degree is launch; year 4 of a 5-year degree is prove;
   graduation year in the past means graduated regardless of stated stage.

4. src/server/modules/onboarding/service.ts — saveStep, getDraft,
   resumePosition, submitOnboarding. submitOnboarding writes all real tables
   in ONE transaction and is idempotent — calling it twice must not duplicate
   rows.

5. Route handlers under /api/v1/onboarding: GET /draft, POST /step,
   POST /submit, POST /waitlist. Zod-validate everything. Scope every query
   by userId in the repository.

6. Unit tests for deriveMode and for submitOnboarding idempotency.

Show me the plan first.
```

### 5.4 — Task 3: the UI shell and field components

```
Build the onboarding UI shell and reusable field components for Tack,
matching ./design/README.md and the screens in
./design/Tack_app_dc.html section 03 exactly.

1. The app shell layout: fixed status bar, fixed progress bar, scrollable
   body with flex:1 and min-height:0, pinned CTA outside the scroll region.
   360px minimum width. Test at exactly 360x640.

2. Progress bar: segmented, one segment per step in the CURRENT branch,
   since branches have different lengths. Back link on the left.

3. Field components, all keyboard accessible, all 44px minimum targets:
   TextField, SelectField, SearchableSelect (virtualised for 200 countries),
   ChipMultiSelect (with selected count and "add your own"), RadioCards
   (large tappable cards for step 2), RepeatableRows (courses, experience),
   TextArea with character count, DateParts (month + year), RankPicker.

4. Each field renders label, optional help text, error state with
   #A32B2B border and a 13.5px message below.

5. The Continue button is disabled until the step's Zod schema passes.
   Show a loading state on submit that keeps button width.

Match the design tokens exactly. Do not invent colours or spacing.
Build components only — not the step screens yet.
```

### 5.5 — Task 4: the step screens

```
Build all onboarding step screens for Tack, driven by flow.config.ts.

1. A single StepRenderer that reads the config and renders the right fields.
   Individual step files only where a step needs custom layout.

2. Route: /onboarding/[step] with a server-side guard that redirects to the
   correct resume position if the user jumps ahead.

3. Step 2 (stage selection): four large radio cards, each with a one-line
   description. Selecting Primary routes to the waitlist screen.

4. Waitlist screen: honest, warm copy — Tack is built for high school and
   above, we're not ready for you yet, tell us where to reach you. One email
   field, one button, no account created. Never use the words rejected,
   denied, or ineligible.

5. Branch steps: HS-1/2/3, UNI-1/2/3, GRAD-1/2 per the architecture doc.

6. Review step: every answer grouped by section with an inline edit link
   that jumps to that step and returns to review on save.

7. On submit: transaction, then a score reveal screen showing the first
   readiness score with a short explanation of what it means and one CTA
   into the dashboard.

8. Autosave after every step. If the user closes the tab and returns, they
   resume exactly where they were, with previous answers intact.

Wherever direction is asked (intended field, target role), "not sure yet"
must be a prominent, positively-framed option — not a greyed-out last resort.
```

### 5.6 — Task 5: hardening

```
Harden Tack's onboarding flow.

1. Under-13 guard: if the entered age or birth year implies under 13, do not
   create a profile. Show the waitlist screen with age-appropriate copy and
   stop. Add a test.

2. Country-driven behaviour: dial code, curriculum options, university list
   and city suggestions all derive from the selected country. Verify nothing
   hardcodes Bangladesh. Changing country mid-flow must clear dependent
   fields rather than leaving stale values.

3. Accessibility pass: every input labelled, focus order correct, focus
   visible, errors announced to screen readers, all targets 44px, body text
   never below 16px, contrast verified against the token rules.

4. Empty and error states: network failure on save shows a retry that does
   not lose entered data. Draft conflict (two tabs) resolves last-write-wins
   with a notice.

5. Performance: measure the bundle for the onboarding route. Searchable
   selects must not ship 200 countries plus 400 skills to the client
   eagerly — load reference data on demand.

6. Analytics: PostHog events for step viewed, step completed, step
   abandoned, branch chosen, onboarding completed, with step id and branch
   as properties. This is how you find the drop-off point.

7. Write an integration test walking each of the three accepted branches
   end to end, plus the primary/waitlist path.

Run typecheck and lint. Report what you changed.
```

---

## PART 6 — Acceptance criteria

Check these yourself before calling the feature done.

- [ ] Complete each branch end to end on a 360×640 viewport with no horizontal scroll
- [ ] Close the browser mid-flow, reopen, land on the same step with answers intact
- [ ] Choose Primary — no user row is created, email lands in waitlist
- [ ] Enter a birth year implying age 12 — blocked with kind copy
- [ ] Change country from Bangladesh to India — dial code, universities and curriculum options all change
- [ ] Submit twice by double-tapping — no duplicate rows
- [ ] A bachelor's year-4-of-4 student gets launch mode; year-2 gets build
- [ ] Every text colour passes AA; `#C9B6BC` appears nowhere as text
- [ ] The Continue button is reachable one-handed with the keyboard open
- [ ] PostHog shows a per-step funnel

---

## PART 7 — What I'd watch

**Step 2 is where you'll lose people.** Asking someone to classify themselves is more cognitively expensive than it looks. Keep the four cards large, plainly worded, and resist adding a fifth option.

**The high school branch is a different product.** Once it works, a 16-year-old will land on a dashboard built for job applications. Discover mode needs to genuinely exist before you promote this branch, or you'll acquire users you immediately disappoint.

**Instrument abandonment from day one.** Task 5 point 6 isn't optional polish — the per-step drop-off number is the single most valuable thing this feature will teach you, and it only exists if you build it in now.
