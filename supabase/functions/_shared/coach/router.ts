/**
 * Decides whether a question needs the model at all.
 *
 * The shared daily allowance is spent only where language is
 * genuinely required. Most of what a student asks a careers adviser is a
 * question about their own numbers — "what should I do next", "how am I
 * doing", "what am I missing" — and Tack has computed all of those already,
 * deterministically. Answering them from the data is instant, free, and more
 * accurate than a model reading the same figures out of a prompt.
 *
 * This is the same rule the rest of the codebase follows: scoring and matching
 * are arithmetic, never a model. The coach does not get an exception. No
 * model decides an intent either: every rule here is a regular expression.
 *
 * Every answer carries at least one chip the student's year may see
 * (`actions.ts`), so a free answer always points somewhere.
 */
import {
  type CoachAction,
  componentRoute,
  finaliseActions,
  isEarly,
  type Mode,
  normaliseMode,
  type RawAction,
} from "./actions.ts";

export { MODE_WORDS } from "./actions.ts";

/**
 * What `coach_context()` returns. Every field is optional, so a version 1
 * context (0053) and an old job payload still parse.
 */
export interface Context {
  version?: number;
  /** Today in Dhaka, `YYYY-MM-DD`. */
  today?: string;
  mode?: string;
  year_of_study?: number | null;
  years_total?: number | null;
  target_role?: string | null;
  target_path?: { title: string; slug: string } | null;
  score?: { total?: number; components?: Record<string, Component> };
  cohort?: { average?: number | null; size?: number | null } | null;
  skills_held?: string[];
  skill_gap?: string[];
  roadmap?: {
    done?: number;
    total?: number;
    overdue?: number;
    next?: string | null;
    next_due?: string | null;
    next_points?: number | null;
  };
  applications?: Record<string, number>;
  has_cv?: boolean;
  cv?: {
    has_cv?: boolean;
    last_check?: {
      on?: string;
      problems?: number;
      suggestions?: number;
      top?: { kind?: string; severity?: string; title?: string }[];
    } | null;
  };
  interview?: {
    sessions?: number;
    last?: { on?: string; role?: string; score?: number | null } | null;
    average?: number | null;
    by_category?: { category: string; average: number; answers: number }[];
    due_reviews?: number;
  };
  upcoming?: { kind: string; title: string; on: string }[];
  streak?: number;
}

interface Component {
  earned?: number;
  max?: number;
  available?: number;
}

/** The free answers, in the order they are tried. */
export const INTENTS = [
  "interview",
  "cv",
  "score_explain",
  "dates",
  "next",
  "score",
  "weakest",
  "skills",
  "roadmap",
  "applications",
] as const;
export type IntentId = typeof INTENTS[number];

/** Kept for callers that only need the text. */
export interface Answer {
  body: string;
  answeredBy: "data" | "model";
}

export interface DataAnswer {
  body: string;
  answeredBy: "data";
  intent: IntentId;
  actions: CoachAction[];
}

const LABELS: Record<string, string> = {
  profile_completeness: "your profile",
  academic: "your academic record",
  skills: "your skills",
  projects: "projects",
  activities: "clubs and activities",
  experience: "work experience",
  cv_quality: "your CV",
  certifications: "certificates",
  interview_practice: "interview practice",
  application_activity: "applications",
  roadmap_progress: "your roadmap",
};

interface Part {
  key: string;
  label: string;
  earned: number;
  available: number;
}

/** The score's parts this year counts. Application activity never counts
 *  for an early year, whatever the weights say. */
function parts(ctx: Context): Part[] {
  const early = isEarly(normaliseMode(ctx.mode));
  return Object.entries(ctx.score?.components ?? {})
    .filter(([key, c]) =>
      (c?.max ?? 0) > 0 && !(early && key === "application_activity")
    )
    .map(([key, c]) => ({
      key,
      label: LABELS[key] ?? key.replace(/_/g, " "),
      earned: c.earned ?? 0,
      available: c.available ?? 0,
    }));
}

function biggestGaps(ctx: Context, n = 3): Part[] {
  return parts(ctx)
    .filter((p) => p.available > 0)
    .sort((a, b) => b.available - a.available)
    .slice(0, n);
}

function list(items: string[]): string {
  if (items.length === 0) return "";
  if (items.length === 1) return items[0];
  return `${items.slice(0, -1).join(", ")} and ${items[items.length - 1]}`;
}

const capitalise = (s: string) => s ? s[0].toUpperCase() + s.slice(1) : s;

/** At most one decimal place, and none when it is whole: 5.7, 8, 6.5. */
export function formatNumber(n: number): string {
  const rounded = Math.round(n * 10) / 10;
  return Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(1);
}

const plural = (n: number, one: string, many: string) =>
  `${n} ${n === 1 ? one : many}`;

const DAY = 86_400_000;

/** Whole days from `today` to `on`, both `YYYY-MM-DD`. Null if unreadable. */
function daysFrom(today: string | undefined, on: string): number | null {
  const a = Date.parse(`${today ?? ""}T00:00:00Z`);
  const b = Date.parse(`${on}T00:00:00Z`);
  if (Number.isNaN(a) || Number.isNaN(b)) return null;
  return Math.round((b - a) / DAY);
}

const MONTHS = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];

/** today, tomorrow, yesterday, in 3 days, 3 days ago — or "on 3 November"
 *  when there is no today to count from. */
export function relativeDay(on: string, today: string | undefined): string {
  const d = daysFrom(today, on);
  if (d === null) {
    const date = new Date(`${on}T00:00:00Z`);
    return Number.isNaN(date.getTime())
      ? "recently"
      : `on ${date.getUTCDate()} ${MONTHS[date.getUTCMonth()]}`;
  }
  if (d === 0) return "today";
  if (d === 1) return "tomorrow";
  if (d === -1) return "yesterday";
  return d > 0 ? `in ${d} days` : `${-d} days ago`;
}

const COHORT_NOUN: Record<Mode, string> = {
  discover: "students choosing a subject",
  explore: "first-years",
  build: "second-years",
  prove: "third-years",
  launch: "final-years",
  graduate: "recent graduates",
};

// ------------------------------------------------------------------ matching

const MAX_WORDS = 12;

/** Lower case, trimmed, without greetings, "please" or closing punctuation. */
export function normalise(q: string): string {
  return q.toLowerCase()
    .replace(/[‘’]/g, "'")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/^(hi|hello|hey|dear)( there)?( coach)?[,!.:]?\s+/, "")
    .replace(/^coach[,!.:]?\s+/, "")
    .replace(/\bplease\b,?\s*/g, "")
    .replace(/\s+/g, " ")
    .replace(/[\s?.!,]+$/, "")
    .trim();
}

const CV = "(?:cv|resume|résumé)";
const SCORE = "(?:readiness )?score";

/** Anchored, on `normalise(q)`, at most twelve words: a long or specific
 *  question still goes to the model. */
const ANCHORED: Partial<Record<IntentId, RegExp[]>> = {
  interview: [
    /^(?:how (?:do|can|should) i|help me|i want to|i need to) (?:prepare|prep|get ready|practi[sc]e)(?: myself)? for (?:an |my |a job )?interviews?$/,
    /^(?:prepare|practi[sc]e) for (?:an |my )?interviews?$/,
    /^(?:what (?:are|is) |show me |how (?:are|is) )?my (?:last |latest |recent )?(?:practice )?interview (?:scores?|results?|progress|practice|marks?)(?: so far)?$/,
    /^how (?:did|have) i (?:do|done|been doing)(?: in| on| at)? (?:my )?(?:last |latest |recent )?(?:practice )?interviews?(?: practice)?$/,
    /^how am i doing (?:in|with|at) (?:my )?(?:practice )?interviews?(?: practice)?$/,
    /^(?:am i|how) ready (?:am i )?for (?:an |my )?interviews?(?: yet)?$/,
    /^what(?:'s| is) my weakest (?:area|part|topic|category)(?: in| for| at) (?:my )?interviews?$/,
  ],
  cv: [
    new RegExp(
      `^(?:is|does) my ${CV} (?:ok|okay|good|good enough|fine|alright|any good|look (?:ok|okay|good|fine|alright)|looking (?:ok|good))(?: now)?$`,
    ),
    new RegExp(`^(?:can you )?(?:check|review|look at|rate) my ${CV}$`),
    new RegExp(`^how(?:'s| is| does) my ${CV}(?: look| looking| doing)?$`),
    new RegExp(`^what(?:'s| is) wrong with my ${CV}$`),
    new RegExp(
      `^(?:what(?:'s| is) )?my ${CV} (?:score|check|result|results|feedback)$`,
    ),
    new RegExp(`^how (?:good|strong) is my ${CV}$`),
  ],
  score_explain: [
    new RegExp(`^(?:can you )?(?:explain|break down) my ${SCORE}(?: to me)?$`),
    new RegExp(
      `^why is my ${SCORE} (?:so |this |that )?(?:low|high|bad|not higher)$`,
    ),
    new RegExp(
      `^how is my ${SCORE} (?:calculated|worked out|made|counted|decided)$`,
    ),
    new RegExp(`^what makes up my ${SCORE}$`),
    new RegExp(`^what is my ${SCORE} made of$`),
    new RegExp(`^how does my ${SCORE} work$`),
  ],
  dates: [
    /^what(?:'s| is) (?:coming up|due)(?: (?:this|next) week| soon| today| for me)?$/,
    /^what do i have (?:coming up|due)(?: (?:this|next) week| soon)?$/,
    /^(?:my |any |show me my |what are my )?(?:upcoming|important|next) (?:deadlines|dates)(?: this week| soon)?$/,
    /^(?:any|my) deadlines(?: this week| soon| coming up)?$/,
  ],
};

/** The rules that came first. Unanchored, on the question as typed, so the
 *  questions they always answered still get answered. */
const LOOSE: Partial<Record<IntentId, RegExp>> = {
  next:
    /\b(what (should|do) i (do|work on|focus)|next step|what next|where (do i|should i) start)\b/i,
  score:
    /\b(my (score|readiness)|how (am i doing|ready am i)|readiness score)\b/i,
  weakest: /\b(weak(est)?|worst|lowest|missing most|behind on)\b/i,
  skills:
    /\b(what skills|which skills|skills (do i need|am i missing)|skill gap)\b/i,
  // Not a bare "progress": "my interview progress" is about interviews.
  roadmap: /\b(my roadmap|how far|(roadmap|my) progress|how much left)\b/i,
  applications:
    /\b(my applications|how many.*(applied|applications)|application (status|count))\b/i,
};

function matches(id: IntentId, q: string, n: string, ctx: Context): boolean {
  if (id === "dates" && isEarly(normaliseMode(ctx.mode))) return false;
  const anchored = ANCHORED[id];
  if (anchored) {
    return n.split(" ").length <= MAX_WORDS && anchored.some((r) => r.test(n));
  }
  // A target number ("my score to 80 by June") is a planning question the
  // model can answer; the free score line cannot.
  if (id === "score" && /\d/.test(n)) return false;
  return LOOSE[id]?.test(q) ?? false;
}

/** The first intent the question matches, or null. Pure; never a model. */
export function matchIntent(q: string, ctx: Context): IntentId | null {
  const n = normalise(q);
  return INTENTS.find((id) => matches(id, q, n, ctx)) ?? null;
}

// ------------------------------------------------------------------- answers

type Draft = { body: string; actions: RawAction[] } | null;

function interviewAnswer(ctx: Context, mode: Mode): Draft {
  if (mode === "discover") {
    return {
      body:
        "Interview practice comes later. For now, explore subjects and the paths they lead to.",
      actions: [{ route: "paths" }],
    };
  }
  const iv = ctx.interview ?? {};
  const sessions = iv.sessions ?? 0;
  if (sessions === 0) {
    const why = isEarly(mode)
      ? "It is a safe way to hear how you sound."
      : "It is a good way to hear how you sound.";
    return {
      body: `You have not tried a practice interview yet. ${why} ` +
        "Questions and self-checks are free; feedback on an answer uses one AI action. " +
        "Try one short practice this week.",
      actions: [{ route: "interview" }],
    };
  }
  const lines: string[] = [];
  const last = iv.last;
  if (last?.score != null) {
    const when = last.on ? `, ${relativeDay(last.on, ctx.today)},` : "";
    lines.push(
      `Your last practice interview${when} scored ${
        formatNumber(last.score)
      } out of 10.`,
    );
  } else {
    lines.push(
      `You have finished ${
        plural(sessions, "practice interview", "practice interviews")
      }.`,
    );
  }
  const weakest = (iv.by_category ?? []).find((c) => c.answers >= 2);
  if (weakest) {
    lines.push(
      `${capitalise(weakest.category)} questions are your weakest so far, at ${
        formatNumber(weakest.average)
      } on average.`,
    );
  }
  const due = iv.due_reviews ?? 0;
  if (due > 0) {
    lines.push(
      due === 1
        ? "One of your answers is ready to practise again today. That practice is free."
        : `${due} of your answers are ready to practise again today. That practice is free.`,
    );
  }
  lines.push(
    due > 0
      ? due === 1
        ? "Practise that answer again first."
        : "Practise those answers again first."
      : `Do one short practice on ${
        weakest ? weakest.category : "your role's"
      } questions.`,
  );
  return {
    body: lines.join(" "),
    actions: [
      ...(due > 0 ? [{ route: "practice" }] : []),
      { route: "interview" },
    ],
  };
}

function cvAnswer(ctx: Context, mode: Mode): Draft {
  if (mode === "discover") {
    return {
      body:
        "At school you do not need a CV yet. Keep a note of what you learn and do; it becomes your CV later.",
      actions: [{ route: "roadmap" }],
    };
  }
  const hasCv = ctx.cv?.has_cv ?? ctx.has_cv ?? false;
  if (!hasCv) {
    return {
      body:
        "You have not added a CV yet. Add it to your documents and Tack checks it for free.",
      actions: [{ route: "cv_check" }, { route: "cv_builder" }],
    };
  }
  const check = ctx.cv?.last_check;
  if (!check) {
    return {
      body:
        "Your CV is saved but has not been checked yet. The check is free. Run it from your documents.",
      actions: [{ route: "cv_check" }],
    };
  }
  const when = check.on ? `, ${relativeDay(check.on, ctx.today)},` : "";
  const problems = check.problems ?? 0;
  const suggestions = check.suggestions ?? 0;
  const lines = [
    problems + suggestions === 0
      ? `Your last CV check${when} found nothing to fix.`
      : `Your last CV check${when} found ${
        plural(problems, "problem", "problems")
      } and ${plural(suggestions, "thing", "things")} to improve.`,
  ];
  const available = ctx.score?.components?.cv_quality?.available ?? 0;
  if (available > 0) {
    lines.push(
      `Your CV can still add ${
        plural(available, "point", "points")
      } to your score.`,
    );
  }
  const first = check.top?.find((t) => t.title)?.title;
  lines.push(
    first
      ? `Start with this one: ${first.replace(/[.\s]+$/, "")}.`
      : "Check it again after your next change.",
  );
  return { body: lines.join(" "), actions: [{ route: "cv_check" }] };
}

function scoreExplainAnswer(ctx: Context, mode: Mode): Draft {
  const total = ctx.score?.total ?? 0;
  const all = parts(ctx);
  const earned = all.filter((p) => p.earned > 0)
    .sort((a, b) => b.earned - a.earned)
    .slice(0, 2);
  const gaps = biggestGaps(ctx, 2);
  const lines = [`You are on ${formatNumber(total)} out of 100.`];
  if (earned.length) {
    lines.push(`Most of it comes from ${list(earned.map((p) => p.label))}.`);
  }
  if (gaps.length) {
    const room = gaps.reduce((sum, g) => sum + g.available, 0);
    lines.push(
      `The most room left is in ${list(gaps.map((g) => g.label))} (${
        plural(room, "point", "points")
      }).`,
    );
  }
  const average = ctx.cohort?.average;
  let caughtUp = false;
  if (typeof average === "number") {
    const noun = COHORT_NOUN[mode];
    if (total >= average + 5) {
      lines.push(`That is ahead of most ${noun}.`);
    } else if (total > average - 5) {
      lines.push(`That is close to the ${noun} average.`);
    } else {
      lines.push(`Most ${noun} are a little ahead right now.`);
      if (gaps.length) {
        lines.push(
          `${capitalise(gaps[0].label)} is the quickest way to catch up.`,
        );
        caughtUp = true;
      }
    }
  }
  if (!caughtUp) {
    lines.push(
      gaps.length
        ? `Start with ${gaps[0].label} this week.`
        : "Open your score to see each part.",
    );
  }
  return { body: lines.join(" "), actions: [{ route: "score" }] };
}

const PREFIX: Record<string, string> = {
  follow_up: "Follow up: ",
  closing: "Applications close: ",
};

function datesAnswer(ctx: Context): Draft {
  const items = (ctx.upcoming ?? []).filter((i) => i?.title && i?.on)
    .slice(0, 4);
  if (items.length === 0) {
    const next = ctx.roadmap?.next;
    return {
      body: next
        ? `Nothing is due in the next two weeks. A good time for the next roadmap step: ${next}.`
        : "Nothing is due in the next two weeks. A good time to pick your next roadmap step.",
      actions: [{ route: "roadmap" }],
    };
  }
  const lines = items.map((item) => {
    const label = `${PREFIX[item.kind] ?? ""}${item.title}`;
    const when = relativeDay(item.on, ctx.today);
    const d = daysFrom(ctx.today, item.on);
    if (d !== null && d < 0) {
      return `Still open from earlier: ${label}, which was due ${when}.`;
    }
    return item.kind === "task"
      ? `${label} is due ${when}.`
      : `${label}, ${when}.`;
  });
  lines.push("Start with the first one on this list.");
  return {
    body: lines.join("\n"),
    actions: [{ route: items[0].kind === "task" ? "roadmap" : "applications" }],
  };
}

/** A follow-up or a closing date within three days, or already past. */
function urgentDate(ctx: Context): string | null {
  for (const item of ctx.upcoming ?? []) {
    if (item.kind !== "follow_up" && item.kind !== "closing") continue;
    const d = daysFrom(ctx.today, item.on);
    if (d === null || d > 3) continue;
    const when = relativeDay(item.on, ctx.today);
    if (item.kind === "follow_up") {
      return d < 0
        ? `First, a follow-up was due ${when}: ${item.title}.`
        : `First, a follow-up is due ${when}: ${item.title}.`;
    }
    return d < 0
      ? `First, check ${item.title}: applications closed ${when}.`
      : `First, applications close ${when}: ${item.title}.`;
  }
  return null;
}

function nextAnswer(ctx: Context, mode: Mode): Draft {
  const gaps = biggestGaps(ctx);
  const next = ctx.roadmap?.next;
  const lead = isEarly(mode) ? null : urgentDate(ctx);
  const actions: RawAction[] = lead ? [{ route: "applications" }] : [];
  let body: string;
  if (gaps.length === 0) {
    if (next) {
      body = `On your roadmap, the next step is "${next}".`;
      actions.push({ route: "roadmap" });
    } else {
      body = "Pick a target path first. It turns your score into a plan.";
      actions.push({ route: "paths" });
    }
  } else {
    body = `The biggest win right now is ${gaps[0].label} — worth ${
      gaps[0].available
    } points.`;
    if (gaps.length > 1) {
      body += ` After that, ${
        list(gaps.slice(1).map((g) => `${g.label} (${g.available})`))
      }.`;
    }
    if (next) body += `\n\nOn your roadmap, the next step is "${next}".`;
    actions.push({ route: componentRoute(gaps[0].key) });
    if (next) actions.push({ route: "roadmap" });
  }
  return { body: lead ? `${lead}\n\n${body}` : body, actions };
}

function scoreAnswer(ctx: Context): Draft {
  const total = ctx.score?.total ?? 0;
  const gaps = biggestGaps(ctx, 2);
  const where = gaps.length
    ? ` The two areas with the most left in them are ${
      list(gaps.map((g) => `${g.label} (${g.available} points)`))
    }.`
    : "";
  return {
    body: `You are on ${formatNumber(total)} out of 100.${where}`,
    actions: [{ route: "score" }],
  };
}

function weakestAnswer(ctx: Context): Draft {
  const gaps = biggestGaps(ctx, 1);
  if (gaps.length === 0) return null;
  return {
    body: `${capitalise(gaps[0].label)} has the most left in it — ${
      gaps[0].available
    } points still available.`,
    actions: [{ route: componentRoute(gaps[0].key) }],
  };
}

function skillsAnswer(ctx: Context): Draft {
  const gap = ctx.skill_gap ?? [];
  const path = ctx.target_path?.title;
  if (!path) {
    return {
      body:
        "You have not picked a target path yet, so there is nothing to measure your skills against. Choosing one is what turns your score into a plan.",
      actions: [{ route: "paths" }],
    };
  }
  if (gap.length === 0) {
    return {
      body: `You already have every core skill ${path} asks for.`,
      actions: [{ route: "paths" }],
    };
  }
  return {
    body: `${path} asks for ${gap.length} core ${
      gap.length === 1 ? "skill" : "skills"
    } you have not added yet: ${list(gap)}.`,
    actions: [{ route: "paths" }, { route: "profile" }],
  };
}

function roadmapAnswer(ctx: Context): Draft {
  const done = ctx.roadmap?.done ?? 0;
  const total = ctx.roadmap?.total ?? 0;
  if (total === 0) {
    return {
      body: "You do not have a roadmap yet. Picking a target path builds one.",
      actions: [{ route: "paths" }, { route: "roadmap" }],
    };
  }
  const next = ctx.roadmap?.next;
  return {
    body: `You have finished ${done} of ${total} steps.${
      next ? ` The next one is "${next}".` : ""
    }`,
    actions: [{ route: "roadmap" }],
  };
}

function applicationsAnswer(ctx: Context, mode: Mode): Draft {
  // Early years are not job hunting, so their count is not the point.
  if (isEarly(mode)) {
    const building = mode === "build";
    return {
      body: `Right now your focus is on ${
        building ? "building skills" : "exploring paths"
      }. Tracking jobs comes later, in your final year.`,
      actions: [{ route: building ? "roadmap" : "paths" }],
    };
  }
  const counts = ctx.applications ?? {};
  const total = Object.values(counts).reduce((a, b) => a + b, 0);
  if (total === 0) {
    return {
      body: "You have not tracked any applications yet.",
      actions: [{ route: "applications" }],
    };
  }
  const parts = Object.entries(counts).map(([k, v]) => `${v} ${k}`);
  return {
    body: `You are tracking ${total}: ${list(parts)}.`,
    actions: [{ route: "applications" }],
  };
}

/** The free answer for one intent, or null where the data cannot carry it. */
export function answerIntent(id: IntentId, ctx: Context): DataAnswer | null {
  const mode = normaliseMode(ctx.mode);
  let draft: Draft;
  switch (id) {
    case "interview":
      draft = interviewAnswer(ctx, mode);
      break;
    case "cv":
      draft = cvAnswer(ctx, mode);
      break;
    case "score_explain":
      draft = scoreExplainAnswer(ctx, mode);
      break;
    case "dates":
      draft = isEarly(mode) ? null : datesAnswer(ctx);
      break;
    case "next":
      draft = nextAnswer(ctx, mode);
      break;
    case "score":
      draft = scoreAnswer(ctx);
      break;
    case "weakest":
      draft = weakestAnswer(ctx);
      break;
    case "skills":
      draft = skillsAnswer(ctx);
      break;
    case "roadmap":
      draft = roadmapAnswer(ctx);
      break;
    case "applications":
      draft = applicationsAnswer(ctx, mode);
      break;
  }
  if (!draft) return null;
  return {
    body: draft.body,
    answeredBy: "data",
    intent: id,
    actions: finaliseActions(draft.actions, mode, ctx),
  };
}

/**
 * Answers from Tack's own data where it can, and returns null where the
 * question genuinely needs language. A rule that matches but has nothing to
 * say lets the next matching rule try.
 */
export function answerFromData(
  question: string,
  ctx: Context,
): DataAnswer | null {
  const n = normalise(question);
  for (const id of INTENTS) {
    if (!matches(id, question, n, ctx)) continue;
    const answer = answerIntent(id, ctx);
    if (answer) return answer;
  }
  return null;
}
