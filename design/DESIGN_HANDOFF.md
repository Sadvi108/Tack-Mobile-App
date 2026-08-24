# Handoff: Tack — university-to-career workspace

## Overview

Tack is a mobile-first web app that helps university students in Bangladesh move from
university into their first professional job. It is not a job board — it is a personal
career workspace: a readiness score, a personalised roadmap, an application tracker, a
document vault, a job-description analyser and interview practice.

The app is **year-aware**. Students join in first year and stay until employed, and the
app runs in one of four modes driven by their year of study. Same components, different
priority and different language.

Target users: students aged 20–24 in Dhaka and other Bangladeshi cities, mostly on
mid-range Android phones on slow connections, mostly second-language English readers.

## About the design files

The files in this bundle are **design references created in HTML** — prototypes showing
intended look and behaviour, not production code to copy directly. The task is to
**recreate these designs in the target codebase's environment** using its established
patterns and libraries. If no environment exists yet, choose an appropriate stack
(a React or Next.js PWA is the natural fit for the constraints below) and implement there.

`Tack app.dc.html` is a *design document*: a canvas holding 13 sections of phone-sized
screens side by side, so every screen can be compared at once. It is not the app's
navigation structure. Each 360×720 frame inside it is one mobile screen.

Do not ship the HTML. Do not reuse the `.dc.html` component runtime (`support.js`) — it
is a design-tool artefact.

## Fidelity

**High fidelity.** Colours, typography, spacing, copy and states are final and intended
to be matched closely. Every hex value, font size and radius in this README is the real
value used in the design files. Interaction behaviour is documented but not implemented —
the prototypes are static.

## Hard constraints (from the product brief — treat as acceptance criteria)

- Mobile-first, **360px minimum width**. Primary actions must be thumb-reachable.
- Usable one-handed on a small screen.
- **Fast and light** — no heavy imagery, no decorative illustration. Assume a slow 3G/4G
  connection and a mid-range Android device. Budget accordingly; prefer system-rendered
  UI over images.
- Accessible: **minimum 16px body text**, **WCAG AA contrast**, **44px minimum tap
  targets**. The design has been audited against all three; see Design tokens for the
  text colours that pass.
- Copy is plain, short, sentence case everywhere — never title case. Second-language
  readers. Never blame the user; error and limit states explain what happened and what
  to do next.
- Empty states matter more than full ones. Most users arrive with nothing.

## Brand

The name comes from sailing: tacking is how you make progress toward a destination you
cannot sail at directly. You zigzag. The logo is a four-segment zigzag ascending left to
right with a dot at the end — reproduced inline as SVG in every screen:

```html
<svg width="34" height="21" viewBox="0 0 40 24" fill="none">
  <polyline points="3,21 11,12 17,16 25,7 31,11" stroke="#7A1B34" stroke-width="3.4"
            stroke-linecap="round" stroke-linejoin="round"/>
  <circle cx="36" cy="5" r="3.2" fill="#7A1B34"/>
</svg>
```

The zigzag recurs as a motif: the roadmap tab icon, the dashed line in the landing hero,
the empty-state graphic in the tracker.

## Design tokens

### Colour

| Token | Hex | Use |
|---|---|---|
| Maroon (primary) | `#7A1B34` | Primary buttons, active nav, headers, brand mark, key numbers |
| Maroon deep | `#5E1428` | Primary button hover/pressed |
| Maroon tint | `#F3E7EA` | Tinted chips, avatar wells, rejected pill |
| Maroon pale | `#FBF4F5` | Row backgrounds inside emphasised cards |
| Teal | `#5DCAA5` | Progress fill, success, score ring |
| Teal text | `#1A6B50` | Any teal used as **text** (passes AA on white and on mint) |
| Teal tint | `#EAF8F2` | Success pill and chip backgrounds |
| Teal deep tint | `#E4F0EB` | Year-3 mode chip |
| Amber | `#FAC775` | Highlights, attention, streaks, secondary CTA on maroon |
| Amber text | `#8A6415` | Any amber used as text |
| Amber tint | `#FDF6E7` | Warning/attention card and pill backgrounds |
| Sail white | `#F1EFE8` | App background |
| White | `#FFFFFF` | Cards, sheets, nav bar |
| Ink | `#23181C` | Primary text, dark toast/footer background |
| Muted | `#6E5B61` | Secondary text — **the only secondary text colour**; AA on white (6.25:1) and sail white (5.43:1) |
| Line | `#EDE7E4` | Hairline dividers inside cards |
| Line 2 | `#DCD4CF` | Input borders, dashed dropzones, inactive rail |
| Stroke faint | `#C9B6BC` | **Strokes and disabled fills only — never text** |
| Blue tint / text | `#EAF0F8` / `#2E5C8A` | Assessment status only |
| Danger | `#A32B2B` | Destructive actions, form errors, rejected text |

Contrast rules that were enforced and must be preserved:
`#C9B6BC` is never used for text. Teal and amber as text use `#1A6B50` / `#8A6415`, not
the fill values. Disabled controls are exempt from AA.

### Typography

Two families, both Google Fonts, plus a mono for small labels.

- **Outfit** — headings, numbers, section titles. Weight 600. Letter-spacing `-0.01em`
  at 19px+, `-0.02em` at 34px+.
- **Inter** — body, labels, buttons. Weights 400 / 500 / 600.
- **IBM Plex Mono** — small uppercase section labels and date stamps. Weight 500/600,
  `letter-spacing: 0.1em`, `text-transform: uppercase`, 10.5–11px. Chrome only, never body.

Scale as used:

| Role | Size / line-height / weight | Family |
|---|---|---|
| Landing H1 | 34px / 1.2 / 600 | Outfit |
| Screen title | 25–26px / 1.25 / 600 | Outfit |
| Section header in screen | 19–21px / 600 | Outfit |
| Card title | 16–17px / 600 | Outfit |
| Hero number (score) | 27–54px / 1 / 600 | Outfit |
| Body | 15–17px / 1.45–1.55 / 400 | Inter |
| List row title | 16px / 500 | Inter |
| Metadata / sub-line | 14.5px / 400 | Inter |
| Button | 16–17px / 600 | Inter |
| Field label | 13px / 500 | Inter |
| Mono label | 10.5–11px / 500–600 | IBM Plex Mono |
| Tab label | 10.5–11px / 500–600 | Inter |

`text-wrap: pretty` is set on every multi-line paragraph.

### Spacing, radius, elevation

- Screen horizontal padding: **20px** (22px on onboarding and landing).
- Card padding: 18–20px vertical, 20px horizontal. Compact list cards 16px/18px.
- Gap between stacked cards: **12–14px**. Between list rows: 10–11px.
- Radius: cards **20px**, list cards 18px, inputs and small buttons **12–14px**,
  pill/chip **20–22px** (fully round), bottom sheet **24px top corners**, phone frame 26px.
- Elevation is minimal by design: `0 1px 2px rgba(35,24,28,.06)` for resting cards,
  `0 6px 18px rgba(35,24,28,.10)` for the one card that overlaps a header,
  `0 6px 16px rgba(122,27,52,.35)` for the FAB. No other shadows.
- Emphasis is done with a `1.5px solid #7A1B34` border, not shadow — see "Your next
  three actions" on the dashboard.

### Controls

- Primary button: full width, **52–54px** tall, radius 14px (26px on the brand-led
  variants), `#7A1B34` on `#FFF`, hover `#5E1428`. Disabled `#DCD4CF` on `#6E5B61`.
- Secondary button: same box, `#FFF` with `1.5px solid #DCD4CF`, hover border `#7A1B34`.
- Ghost button: 48px, transparent, `#7A1B34` text, hover background `#F3E7EA`.
- Text input: 50–52px tall, radius 12px, `1.5px solid #DCD4CF`, focus border `#7A1B34`.
  Error border `#A32B2B` with a 13.5px message below.
- Chip (multi-select): min-height **44px**, radius 22px, unselected `#FFF` +
  `1.5px solid #DCD4CF`, selected `#7A1B34` on white with a leading `✓`.
- Every tappable row carries `min-height: 44px`.

## Screens

All screens are 360px wide. Structure is identical throughout and should be the app shell:

```
[status bar]            fixed
[header / progress]     fixed, optional
[scrollable body]       flex:1; min-height:0; overflow-y:auto
[pinned CTA]            fixed, optional
[bottom nav]            fixed, optional
```

The pinned CTA is outside the scroll region — this is load-bearing, it is what keeps the
primary action reachable on a 640px-tall viewport.

Sections below match the numbered sections in `Tack app.dc.html`.

### 01 — Landing page
Public marketing page, mobile web, one column. Maroon hero with H1 "Your first job starts
here", sub-line, one amber CTA "Start free". A scaled-down dashboard render overlaps the
hero seam (radius 20px top corners, pulled up under the maroon block) — this is built from
real UI, not a screenshot; keep it that way for weight. Then a three-item feature strip
(readiness score / career roadmap / application tracker) as white cards with 40px tinted
icon wells, a three-step "how it works" on a dotted rail, a repeated maroon CTA, and an
ink footer. **No pricing section — the product is free.**

### 02 — Sign up
**Must fit 360×640 with no scrolling.** Google sign-in is the prominent primary option
(white button, 1.5px border, four-colour conic dot as the mark); email + password below a
"or use email" divider. One line of document-privacy reassurance with a shield glyph,
pinned above a "Already have an account? Log in" link.

### 03 — Onboarding, four steps
Four-segment progress bar, back link, Continue pinned to the bottom. Each step must be
completable in under 30 seconds.
1. Name, city (select), phone (+880 prefix locked).
2. University, degree, graduation year, CGPA (optional, with a note that it is never shown).
3. **Skills** — search field plus a wrapping grid of preset chips, multi-select, selected
   count shown, "+ Add a skill not listed" escape hatch.
4. Target role (radio list) and target industry (chips).

*Pending change from the year-aware brief: add a step after education asking current year
of study and expected graduation date — this single answer drives the app's mode and must
be easy to change later. Plus an optional step to import current semester courses.*

### 04 — Dashboard (final-year default)
Designed for a nearly-empty account: onboarding done, two applications, no CV.
In priority order: greeting; readiness score ring with week-on-week change; **"Your next
three actions"** — the single most important element, emphasised with a maroon border,
each row naming its point value so the score and the to-do list explain each other;
roadmap percent complete; four-cell application funnel; a seven-day deadline strip;
bottom nav.

### 05 — Readiness score detail
Score ring, a 90-day trend polyline, then the component breakdown. Rows are **sorted by
points available descending** so the biggest win is first and the pinned CTA matches row
one. Each row: name, `n of max`, a progress bar coloured by health
(teal ≥ good, amber = partial, `#E4A0A0` = zero), one concrete action, and a `+n` chip.

Current nine components with weights: profile completeness 10, skills 12, projects 12,
experience 12, CV quality 15, certifications 8, portfolio 8, interview practice 10,
application activity 13.

*Pending change: add academic performance and extracurricular involvement to reach eleven
components; show the score relative to the student's own year; show which components are
weighted differently by year (applications matter enormously in final year, not at all in
first).*

### 06 — Career roadmap
Overall progress at top. Four to six milestones with **locked / active / completed**
states — locked ones state what unlocks them rather than showing a padlock alone.
Milestone 1 expanded with six tasks; each task has a checkbox, title, a type tag
(Skill / Project / Certificate / Networking / Application / CV, each with its own tint
pair) and an optional due date. "+ Add your own task" inside the expanded milestone.

*Pending change: support two active career paths with a path switcher at the top, shared
tasks marked as counting toward both, and the semester each milestone falls in.*

### 07 — Application tracker + detail
A **filterable list, not a kanban** — horizontal scrolling loses cards at 360px. Count
strip doubles as the filter. Six statuses: saved, applied, assessment, interview, offer,
rejected. Cards lead with the next action date. FAB bottom-right, 58px, offset above the
nav bar. Detail screen: full job info, status pill, two actions, a **status timeline**
with every change and its date, the CV version submitted, and notes.

### 08 — Document vault
Empty state does the heavy lifting: names the three things worth uploading, states plainly
who can see them, and offers the phone camera as an equal option (many students have paper
certificates and no scanner). Then: upload state with a determinate progress bar and a
cancel; **processing state** while a CV is parsed, with an indeterminate bar and a note
that the user can leave the screen; CV version history with a `Default` marker; a
bottom-sheet file menu (make default / download / replace / delete).

### 09 — Job description analyser
Input: large paste area, "use a saved job" alternative, **quota stated before the run**
("2 of 3 analyses left today", resets at midnight), and a note that analysis takes about a
minute and the app can be closed. Processing: progress ring with a checklist of stages.
Result: match percentage as the hero on a maroon card, matched skills as **teal** chips,
missing skills as **amber** chips, extracted requirements grouped into skills /
qualifications / experience, and one primary action — "Add missing skills to my roadmap".

### 10 — Interview practice
Setup (role, session type, difficulty, optional timer — **off by default**, a countdown is
the fastest way to make an anxious first-timer quit). Question screen: one question, large
textarea, visible counter and segment bar, skip + submit. Feedback: score out of 10, what
went well **before** what to improve, model answer in a collapsed section. Summary: overall
score, strongest and weakest areas, suggested next action, points earned.

### 11 — Profile
Completeness banner that **names the two missing things**, not just a percentage. Sections:
personal, education, skills with proficiency bars, projects, certifications, portfolio
links. Each section edits in place — no separate edit mode. A per-section health dot
(teal / amber / `#E4A0A0`).

*Pending change: add academic and activities sections; completeness meter to include
courses and activities.*

### 12 — Shared components
Buttons (primary / secondary / ghost, all states incl. loading), form inputs (text default
/ focus / error, select, chip multi-select, file upload), six status pills, success and
error toasts (ink background, coloured glyph, action on the right), loading skeletons for
cards and lists, empty states for dashboard / applications / vault / roadmap, offline
state, error state, **quota-exhausted state** (explains the daily AI limit as a
free-for-everyone tradeoff and redirects to roadmap work — never a punishment), and a
bottom sheet used for filters and confirmations.

### 13 — Year-aware dashboards
Four variants of the dashboard, one per academic year. Same components, different priority
and language. A mode chip sits above the greeting and warms from amber to maroon as the
years progress.

| Mode | Year | Leads with | Language | Funnel? |
|---|---|---|---|---|
| **Explore** | 1 | "Explore career paths" CTA on a maroon card, score framed as "ahead of most first-years" with the cohort average shown, gentle "try this month" list, this semester's courses | explore, discover, try — **never** deadline or apply | Hidden entirely |
| **Build** | 2 | Score vs year-2 average, skill progress bars with level transitions, a suggested first project, early internship awareness | build, learn, practise | No |
| **Prove** | 3 | Live internships with match percentages and closing dates, skill gap map (strong / developing / missing as a three-part bar), portfolio completeness, networking prompt | prove, ship, connect | No |
| **Launch** | Final | Seven-day date list on a maroon card, application funnel, readiness, interview practice for the next interview | apply, prepare, deadline — urgency is appropriate here | Yes |

The score is benchmarked against the student's **own year**, never against final-years, and
that framing is shown in words ("ahead of most first-years", "strong for a second-year").

**Bottom navigation restructure:** junior years get four tabs — Home, Paths, Roadmap,
Profile. Final year gains a fifth, Apply. Applications and Vault live inside Profile/Home
for junior years.

## Interactions and behaviour

The prototypes are static. Intended behaviour:

- **Navigation**: bottom tab bar switches root views; back chevron pops; cards push detail
  views. Bottom sheets slide from the bottom over a `rgba(35,24,28,.45)` scrim with a
  42×4px grab handle.
- **Buttons**: hover/pressed colour shifts as tokenised above; loading state swaps the
  label for a spinner and keeps the button width.
- **Checkboxes** (roadmap tasks): tapping toggles done, strikes the title, greys it to
  `#6E5B61`, and animates the score. Completing a task should surface a success toast that
  names the point gain.
- **Chips**: tap toggles selection; the selected count updates live.
- **Onboarding**: Continue is disabled until required fields are valid. Step 4 submits and
  transitions to the score reveal.
- **Uploads**: determinate progress for the transfer, then an indeterminate parsing state.
  Parsing must be backgroundable — the user can navigate away and get a toast on completion.
- **Analyser**: quota is decremented on submission, not on result. The remaining count is
  shown before and after. When exhausted, show the quota state rather than a disabled button.
- **Offline**: the app is read-write offline for tasks and applications; changes queue and
  sync. Say so in the offline state.
- Animations should be short and cheap — 150–200ms colour and transform transitions only.
  Avoid anything that costs a repaint on a mid-range Android.

## State

Per user: `yearOfStudy` (drives mode — the single most important value), `expectedGraduation`,
profile fields, `skills[]` with proficiency, `courses[]` by semester, `activities[]`,
`chosenPaths[]` (0–2), `readinessScore` with per-component sub-scores and history for the
trend chart, `roadmap` (milestones → tasks with done/due), `applications[]` with status +
status history, `documents[]` with CV versions and a default flag, `analyses` quota
(count + reset timestamp), `practiceSessions[]`.

Derived, not stored: overall score, percent complete, funnel counts, cohort comparison,
skill gap grouping, next-three-actions ranking (sort by points available ÷ effort).

## Assets

None. Every icon is an inline SVG on a 24×24 viewBox with `stroke-width: 2` and round caps
and joins; the logo mark is the zigzag above. Placeholder fills use a CSS stripe
(`repeating-linear-gradient(135deg,#FBFAF7 0 8px,#F5F2EC 8px 16px)`) rather than an image.
There is no photography or illustration anywhere, deliberately.

Fonts: Inter, Outfit, IBM Plex Mono from Google Fonts. Self-host or subset them for the
connection budget.

## Files in this bundle

- `Tack app.dc.html` — the full screen library, sections 01–13. Open in a browser.
- `Tack.dc.html` — the three early visual directions (calm cards / tack line / ledger),
  kept for context on why the final direction looks the way it does.
- `support.js` — runtime required to open the two files locally. **Design-tool artefact,
  not part of the handoff.**

## Build order

From the product's own scope decision, ship in this order:

1. Year-aware onboarding and dashboard — this is the positioning and it is cheap.
2. Academic profile with courses.
3. Extracurricular activities.
4. Career path explorer with **hand-written path templates, no AI calls** — ten well-written
   paths for the Bangladeshi market removes the feature's dependency on a daily AI quota.

After there are users: semester planner, skill gap map, achievement timeline and CV
generation, weekly check-in.

Screens not yet designed (specified but not drawn): career path explorer and its
comparison view, academic profile, activities, semester planner, skill gap map,
achievement timeline, weekly check-in.
