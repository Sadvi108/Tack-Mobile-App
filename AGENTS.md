# Tack — engineering rules

## Product

Tack helps Bangladeshi university students move from university into their first
job. Students join in first year and stay until employed. Not a job board — a
personal career workspace.

The app is **year-aware**. `profiles.mode` is derived from year of study and
drives what every dashboard shows:

| Mode | Year | Leads with | Language | Funnel |
|---|---|---|---|---|
| `explore` | 1 | Career path exploration, cohort comparison, this semester's courses | explore, discover, try — **never** deadline or apply | hidden |
| `build` | 2 | Skill progress, a suggested first project, early internship awareness | build, learn, practise | no |
| `prove` | 3 | Live internships, skill gap map, portfolio completeness, networking | prove, ship, connect | no |
| `launch` | final | Seven-day date list, application funnel, readiness, interview practice | apply, prepare, deadline | yes |

The score is benchmarked against the student's **own year**, never against
final-years, and that framing appears in words ("ahead of most first-years").

## Stack — do not substitute

- **Flutter** (Dart 3.12) — Android and iOS. One codebase, no web target.
- **Riverpod** for state, **go_router** for navigation, **Drift** for the local
  cache and the offline write queue.
- **Supabase** — Postgres, Auth (email/password and Google), Storage, Edge
  Functions (Deno/TypeScript). Everything is in one project: there is no
  third-party analytics or crash service, and no student data leaves it.
- **Gemini** behind an Edge Function abstraction. Never called from Dart.
- No Next.js, no Cloudflare Workers, no R2. The earlier build guide assumed a
  web app; the product is a Flutter app and the server side is Supabase.

## Hard security rules

- **Never** put a real secret value in a file. Client config arrives through
  `--dart-define-from-file=env/dev.json`, which is gitignored.
- The service role key, the Gemini key and the database password are **server
  only**. They live in Supabase Edge Function secrets. They must never appear
  in `app/`.
- Row Level Security is enabled and forced on every table. It is the actual
  security boundary — client-side filtering is a convenience, never a control.
- Repository functions scope by user themselves. Never rely on the caller
  having remembered to add `.eq('user_id', …)`.
- Documents are private. Access only through a signed URL with a short TTL,
  issued after an ownership check.
- Validate everything crossing a boundary. Dart models parse defensively;
  Edge Functions validate request bodies with Zod.
- Analytics go to `public.analytics_events` in Tack's own database. Event names
  and counts only — never a name, email, phone, CV text, job description,
  note or answer. The client filters properties as a last line of defence, and
  that filter is tested.

## Architecture

```
lib/
  config/          compile-time env
  core/            supabase client, failure mapping, analytics, connectivity, offline queue
  design/          the design system — tokens, typography, components, shell
  features/<area>/
    data/          models + repository (the only place that talks to Supabase)
    application/   Riverpod providers, controllers, pure logic
    presentation/  screens and widgets
  routing/         go_router
```

Rules:
- `presentation` never imports `data` directly. It goes through `application`.
- A feature never imports another feature's `data`. Expose a provider instead.
- Every Supabase call lives in a repository. No `supabase.from(...)` in a widget.
- Feature code imports the design system as `package:tack/design/tack.dart`.
  Never import a component file directly, and never hardcode a colour, radius,
  duration or font — if a token is missing, add it to `tokens.dart`.

## Server side

- SQL migrations live in `supabase/migrations/NNNN_name.sql` and are applied
  with `node tool/migrate.js`. Migrations are append-only: never edit one that
  has been applied, add a new one.
- Business rules that must hold regardless of client belong in Postgres
  (triggers, check constraints, `security definer` functions), not in Dart.
- The readiness score, job matching and skill matching are **deterministic**.
  Never use a model for them.
- Background work goes on `jobs_queue` and is drained by the `worker` Edge
  Function. Anything slower than about 300ms is background work.

## AI rules

- All model access goes through `supabase/functions/_shared/ai/`. Feature code
  calls an endpoint, never a provider.
- PII redaction before any model call is mandatory. Contact details are pulled
  out locally with a regex and never sent.
- Every model response is validated against a schema before it is stored.
- AI endpoints return `202` with a job id. They never block.
- `AI_PROVIDER=mock` is the default and stays that way in development.
- Per-user quota is 3 AI actions a day, enforced by `public.consume_quota`.
- Job description analysis is cached by content hash. The same text is never
  analysed twice.

## Copy

- Sentence case everywhere. Never title case.
- Plain, short English for second-language readers.
- Never blame the user. Error and limit states say what happened and what to do
  next.
- Empty states name the thing to do, not the absence of data.
- The quota state is a tradeoff that keeps the app free, never a punishment.

## Layout and accessibility — treat as acceptance criteria

- 360px minimum width. Test at that width.
- Body text never below 16px. WCAG AA contrast. 44px minimum tap targets.
- The pinned CTA sits outside the scroll region. This is load-bearing.
- `#C9B6BC` is never used for text. Teal and amber as text use `#1A6B50` and
  `#8A6415`.
- `#6E5B61` is the only secondary text colour.
- Animations are 150–200ms colour and transform only. Nothing that costs a
  repaint per frame on a mid-range Android.
- No photography, no illustration, no icon font. Icons are inline SVG on a
  24×24 viewBox with a 2px stroke.

## Workflow

- Run `flutter analyze` and `flutter test` before calling anything done.
- Never claim something works without running it.
- Do not add a dependency without asking.
- Conventional commits, small and scoped.
