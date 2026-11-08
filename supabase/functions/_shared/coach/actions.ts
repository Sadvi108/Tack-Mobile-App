/**
 * The chips under a coach reply: one list of route ids, the labels Tack
 * writes for them, and which ones each year may see.
 *
 * The same list lives in three places, and tests hold them together: here,
 * the CHECK on chat_messages.actions (0097, actions_test.ts), and the app's
 * chip destinations (coach_routes_test.dart). A model only ever picks a route
 * id. It never writes a label, and it can never pick `path`.
 */
import type { Context } from "./router.ts";

export const COACH_ROUTES = [
  "interview",
  "practice",
  "analyser",
  "cv_check",
  "cv_builder",
  "roadmap",
  "radar",
  "score",
  "paths",
  "path",
  "applications",
  "profile",
] as const;
export type CoachRoute = typeof COACH_ROUTES[number];

export interface CoachAction {
  label: string;
  route: CoachRoute;
  slug?: string;
}

/** What a model may choose from: everything but `path`, which needs a slug
 *  only Tack's own data can supply. */
export const MODEL_ROUTES: CoachRoute[] = COACH_ROUTES.filter((r) =>
  r !== "path"
);

export const MODES = [
  "discover",
  "explore",
  "build",
  "prove",
  "launch",
  "graduate",
] as const;
export type Mode = typeof MODES[number];

/** Not job hunting yet. */
export const EARLY_MODES: readonly Mode[] = ["discover", "explore", "build"];

/** Words early years never read in coach copy (AGENTS.md, §0.5). */
export const MODE_WORDS =
  /\b(deadlines?|apply|applying|applied|applications?)\b/i;

/** Anything unrecognised is treated as explore, the safe side. */
export function normaliseMode(mode: unknown): Mode {
  return (MODES as readonly string[]).includes(mode as string)
    ? mode as Mode
    : "explore";
}

export function isEarly(mode: Mode): boolean {
  return EARLY_MODES.includes(mode);
}

const SLUG = /^[a-z0-9-]{1,80}$/;

const FIRST_YEARS: CoachRoute[] = [
  "paths",
  "path",
  "roadmap",
  "score",
  "profile",
  "analyser",
];
const MIDDLE_YEARS: CoachRoute[] = [
  ...FIRST_YEARS,
  "cv_check",
  "cv_builder",
  "interview",
  "practice",
  "radar",
];

/** C7.2: the routes a year may be offered, in COACH_ROUTES order. */
export function routesForMode(mode: Mode): CoachRoute[] {
  const allowed: CoachRoute[] = mode === "discover" || mode === "explore"
    ? FIRST_YEARS
    : mode === "build" || mode === "prove"
    ? MIDDLE_YEARS
    : [...COACH_ROUTES];
  return COACH_ROUTES.filter((r) => allowed.includes(r));
}

/** Label length the database allows (chat_messages_actions_shape). */
const MAX_LABEL = 48;

/** C7.2: the label Tack writes for a chip. */
export function labelFor(
  route: CoachRoute,
  mode: Mode,
  title?: string,
): string {
  switch (route) {
    case "interview":
      return "Practise an interview";
    case "practice":
      return "Practise again";
    case "analyser":
      return mode === "discover" || mode === "explore"
        ? "See what a job asks for"
        : "Check a job description";
    case "cv_check":
      return "Check your CV";
    case "cv_builder":
      return "Build your CV";
    case "roadmap":
      return "Open your roadmap";
    case "radar":
      return mode === "build" ? "See internships" : "See your matches";
    case "score":
      return "See your score";
    case "paths":
      return "Explore paths";
    case "path": {
      const name = (title ?? "").trim() || "this path";
      const room = MAX_LABEL - "Read about ".length;
      return `Read about ${
        name.length > room ? `${name.slice(0, room - 1).trimEnd()}…` : name
      }`;
    }
    case "applications":
      return "Open your applications";
    case "profile":
      return "Update your profile";
  }
}

/**
 * The route a score component's action opens. Mirrors `ScoreComponent.route`
 * in app/lib/features/score/data/readiness.dart (actions_test.ts reads it).
 */
export function componentRoute(key: string): CoachRoute {
  switch (key) {
    case "cv_quality":
      return "cv_check";
    case "interview_practice":
      return "interview";
    case "application_activity":
      return "applications";
    case "roadmap_progress":
      return "roadmap";
    default:
      return "profile";
  }
}

/** The component with the most points left, among those this year counts. */
export function biggestGapKey(ctx: Context): string | null {
  let best: { key: string; available: number } | null = null;
  for (const [key, c] of Object.entries(ctx.score?.components ?? {})) {
    const available = c?.available ?? 0;
    if ((c?.max ?? 0) <= 0 || available <= 0) continue;
    if (!best || available > best.available) best = { key, available };
  }
  return best?.key ?? null;
}

/** Biggest-gap component's route if the year may see it, else the roadmap,
 *  else paths. */
export function defaultAction(ctx: Context, mode: Mode): CoachAction {
  const allowed = routesForMode(mode);
  const key = biggestGapKey(ctx);
  const gap = key ? componentRoute(key) : null;
  const route: CoachRoute = gap && allowed.includes(gap)
    ? gap
    : allowed.includes("roadmap")
    ? "roadmap"
    : "paths";
  return { route, label: labelFor(route, mode) };
}

/** One raw action, as a model or a router rule proposes it. */
export interface RawAction {
  route: string;
  slug?: string;
  title?: string;
}

/**
 * The chips that are stored and shown: allowed for the year, no repeats, at
 * most two, labels written here. If none survive, the default is added, so
 * every reply points somewhere.
 */
export function finaliseActions(
  raw: unknown,
  mode: Mode,
  ctx: Context,
): CoachAction[] {
  const allowed = routesForMode(mode);
  const out: CoachAction[] = [];
  const seen = new Set<string>();
  for (const item of Array.isArray(raw) ? raw : []) {
    if (out.length === 2) break;
    if (typeof item !== "object" || item === null) continue;
    const { route, slug, title } = item as RawAction;
    if (typeof route !== "string") continue;
    if (!allowed.includes(route as CoachRoute)) continue;
    const r = route as CoachRoute;
    if (r === "path") {
      if (typeof slug !== "string" || !SLUG.test(slug)) continue;
      const key = `path:${slug}`;
      if (seen.has(key)) continue;
      seen.add(key);
      out.push({ route: r, slug, label: labelFor(r, mode, title) });
      continue;
    }
    if (seen.has(r)) continue;
    seen.add(r);
    out.push({ route: r, label: labelFor(r, mode) });
  }
  if (out.length === 0) out.push(defaultAction(ctx, mode));
  return out;
}
