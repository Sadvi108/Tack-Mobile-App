/**
 * The interview prep brief's evidence gate.
 *
 * Borrowed from the insurance intake team in awesome-llm-apps
 * (voice_ai_agents/insurance_claim_live_agent_team/policies.py,
 * `prepare_claim`): whatever the model says it has, only what the system was
 * actually given counts. A talking point is the student's case for the job,
 * so it is kept only when its evidence names a skill or a project the student
 * really has. Anything else is the model being generous on their behalf, and
 * a student who repeats it in an interview pays for it.
 */

export interface PrepBrief {
  talking_points: { point: string; evidence: string }[];
  likely_questions: { question: string; why: string }[];
  questions_to_ask: string[];
  gaps: { skill: string; how_to_prepare: string }[];
}

export interface StudentEvidence {
  skills: string[];
  projects: string[];
}

/** Fewer backed points than this is not worth an AI action. */
export const MIN_GROUNDED_POINTS = 2;

const CAPS = {
  talking_points: 5,
  likely_questions: 5,
  questions_to_ask: 4,
  gaps: 4,
} as const;

function normalise(text: string): string {
  return text.toLowerCase().replace(/\s+/g, " ").trim();
}

function escape(text: string): string {
  return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/**
 * Whether `text` names `name` as a whole word, ignoring case and spacing.
 * "Go" is not in "Good", "SQL" is not in "SQLite", "C++" is in "C++ daily" —
 * and a shorter name never vouches for a longer one: "C" is not in "C++" or
 * "C#", and "Node" is not in "Node.js".
 */
export function mentions(text: string, name: string): boolean {
  const needle = normalise(name);
  if (!needle) return false;
  return new RegExp(
    `(?<![\\p{L}\\p{N}])${
      escape(needle)
    }(?![\\p{L}\\p{N}+#]|\\.[\\p{L}\\p{N}])`,
    "u",
  ).test(normalise(text));
}

/**
 * Project titles too ordinary to prove anything: "your project for the
 * course" names "Project" without naming a project.
 */
const GENERIC_TITLES = new Set([
  "project",
  "projects",
  "app",
  "website",
  "assignment",
  "thesis",
  "internship",
  "coursework",
]);

/**
 * What this checks is the citation: that a point's evidence names a skill or
 * project the student really listed. It cannot check that the point is a fair
 * reading of that skill — the prompt asks for that, and the student reads the
 * proof line under every point before using it.
 */
export function groundBrief(
  brief: PrepBrief,
  evidence: StudentEvidence,
): { brief: PrepBrief; dropped: number } {
  const names = [
    ...evidence.skills,
    ...evidence.projects.filter((p) => !GENERIC_TITLES.has(normalise(p))),
  ];
  const backed = brief.talking_points.filter((p) =>
    names.some((n) => mentions(p.evidence, n))
  );
  const gaps = brief.gaps.filter((g) =>
    !evidence.skills.some((s) =>
      normalise(s) === normalise(g.skill) || mentions(g.skill, s)
    )
  );

  return {
    brief: {
      talking_points: backed.slice(0, CAPS.talking_points),
      likely_questions: brief.likely_questions.slice(0, CAPS.likely_questions),
      questions_to_ask: brief.questions_to_ask.slice(0, CAPS.questions_to_ask),
      gaps: gaps.slice(0, CAPS.gaps),
    },
    dropped: brief.talking_points.length - backed.length,
  };
}

export function isGrounded(brief: PrepBrief): boolean {
  return brief.talking_points.length >= MIN_GROUNDED_POINTS;
}
