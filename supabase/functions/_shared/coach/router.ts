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
 * are arithmetic, never a model. The coach does not get an exception.
 */

export interface Context {
  mode?: string;
  target_role?: string | null;
  target_path?: { title: string; slug: string } | null;
  score?: { total?: number; components?: Record<string, Component> };
  skills_held?: string[];
  skill_gap?: string[];
  roadmap?: { done?: number; total?: number; next?: string | null };
  applications?: Record<string, number>;
  has_cv?: boolean;
  streak?: number;
}

interface Component {
  earned?: number;
  max?: number;
  available?: number;
}

export interface Answer {
  body: string;
  answeredBy: "data" | "model";
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

function biggestGaps(
  ctx: Context,
  n = 3,
): { label: string; available: number }[] {
  const components = ctx.score?.components ?? {};
  return Object.entries(components)
    .filter(([, c]) => (c?.max ?? 0) > 0 && (c?.available ?? 0) > 0)
    .map(([key, c]) => ({
      label: LABELS[key] ?? key.replace(/_/g, " "),
      available: c.available ?? 0,
    }))
    .sort((a, b) => b.available - a.available)
    .slice(0, n);
}

/** Discover, explore and build: not job hunting yet, whatever the mode string
 *  says. Anything unrecognised counts as early, which is the safe side. */
function isEarly(mode: string | undefined): boolean {
  return !["prove", "launch", "graduate"].includes(mode ?? "");
}

function list(items: string[]): string {
  if (items.length === 0) return "";
  if (items.length === 1) return items[0];
  return `${items.slice(0, -1).join(", ")} and ${items[items.length - 1]}`;
}

/** Matches on intent, not keywords alone: every pattern needs a verb or a noun
 *  that pins the question to one of Tack's own figures. */
const RULES: {
  id: string;
  test: RegExp;
  answer: (ctx: Context) => string | null;
}[] = [
  {
    id: "next",
    test:
      /\b(what (should|do) i (do|work on|focus)|next step|what next|where (do i|should i) start)\b/i,
    // Total: "what should I do next" always gets an answer. A student with
    // nothing measured yet is the one who most needs one.
    answer: (ctx) => {
      const gaps = biggestGaps(ctx);
      const next = ctx.roadmap?.next;
      if (gaps.length === 0) {
        return next
          ? `On your roadmap, the next step is "${next}".`
          : "Pick a target path first. It turns your score into a plan.";
      }
      const lead = `The biggest win right now is ${gaps[0].label} — worth ${
        gaps[0].available
      } points.`;
      const rest = gaps.length > 1
        ? ` After that, ${
          list(gaps.slice(1).map((g) => `${g.label} (${g.available})`))
        }.`
        : "";
      const task = next
        ? `\n\nOn your roadmap, the next step is "${next}".`
        : "";
      return lead + rest + task;
    },
  },
  {
    id: "score",
    test:
      /\b(my (score|readiness)|how (am i doing|ready am i)|readiness score)\b/i,
    answer: (ctx) => {
      const total = ctx.score?.total ?? 0;
      const gaps = biggestGaps(ctx, 2);
      const where = gaps.length
        ? ` The two areas with the most left in them are ${
          list(gaps.map((g) => `${g.label} (${g.available} points)`))
        }.`
        : "";
      return `You are on ${total} out of 100.${where}`;
    },
  },
  {
    id: "weakest",
    test: /\b(weak(est)?|worst|lowest|missing most|behind on)\b/i,
    answer: (ctx) => {
      const gaps = biggestGaps(ctx, 1);
      if (gaps.length === 0) return null;
      return `${gaps[0].label[0].toUpperCase()}${
        gaps[0].label.slice(1)
      } has the most left in it — ${gaps[0].available} points still available.`;
    },
  },
  {
    id: "skills",
    test:
      /\b(what skills|which skills|skills (do i need|am i missing)|skill gap)\b/i,
    answer: (ctx) => {
      const gap = ctx.skill_gap ?? [];
      const path = ctx.target_path?.title;
      if (!path) {
        return "You have not picked a target path yet, so there is nothing to measure your skills against. Choosing one is what turns your score into a plan.";
      }
      if (gap.length === 0) {
        return `You already have every core skill ${path} asks for.`;
      }
      return `${path} asks for ${gap.length} core ${
        gap.length === 1 ? "skill" : "skills"
      } you have not added yet: ${list(gap)}.`;
    },
  },
  {
    id: "roadmap",
    // Not a bare "progress": "my interview progress" is about interviews.
    test: /\b(my roadmap|how far|(roadmap|my) progress|how much left)\b/i,
    answer: (ctx) => {
      const done = ctx.roadmap?.done ?? 0;
      const total = ctx.roadmap?.total ?? 0;
      if (total === 0) {
        return "You do not have a roadmap yet. Picking a target path builds one.";
      }
      const next = ctx.roadmap?.next;
      return `You have finished ${done} of ${total} steps.${
        next ? ` The next one is "${next}".` : ""
      }`;
    },
  },
  {
    id: "applications",
    test:
      /\b(my applications|how many.*(applied|applications)|application (status|count))\b/i,
    answer: (ctx) => {
      // Early years are not job hunting, so their count is not the point.
      if (isEarly(ctx.mode)) {
        const focus = ctx.mode === "build"
          ? "building skills"
          : "exploring paths";
        return `Right now your focus is on ${focus}. Tracking jobs comes later, in your final year.`;
      }
      const counts = ctx.applications ?? {};
      const total = Object.values(counts).reduce((a, b) => a + b, 0);
      if (total === 0) return "You have not tracked any applications yet.";
      const parts = Object.entries(counts).map(([k, v]) => `${v} ${k}`);
      return `You are tracking ${total}: ${list(parts)}.`;
    },
  },
];

/**
 * Answers from Tack's own data where it can, and returns null where the
 * question genuinely needs language.
 */
export function answerFromData(question: string, ctx: Context): Answer | null {
  for (const rule of RULES) {
    if (!rule.test.test(question)) continue;
    const body = rule.answer(ctx);
    if (body) return { body, answeredBy: "data" };
  }
  return null;
}
