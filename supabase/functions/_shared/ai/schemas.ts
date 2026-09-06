/**
 * Response schemas.
 *
 * Every model reply is validated against one of these before it is stored. An
 * unvalidated reply is untrusted input that would otherwise land straight in
 * the database and then on a student's screen.
 */

export const jdAnalysisSchema = {
  type: "object",
  properties: {
    job_title: { type: "string" },
    seniority: { type: "string" },
    skills: { type: "array", items: { type: "string" } },
    qualifications: { type: "array", items: { type: "string" } },
    responsibilities: { type: "array", items: { type: "string" } },
    experience: { type: "string" },
  },
  required: ["job_title", "skills", "qualifications", "responsibilities"],
} as const;

export const cvParseSchema = {
  type: "object",
  properties: {
    headline: { type: "string" },
    summary: { type: "string" },
    skills: { type: "array", items: { type: "string" } },
    education: {
      type: "array",
      items: {
        type: "object",
        properties: {
          degree: { type: "string" },
          institution: { type: "string" },
          year: { type: "integer" },
        },
      },
    },
    experience: {
      type: "array",
      items: {
        type: "object",
        properties: {
          title: { type: "string" },
          organisation: { type: "string" },
          months: { type: "integer" },
        },
      },
    },
    projects: {
      type: "array",
      items: {
        type: "object",
        properties: { title: { type: "string" }, summary: { type: "string" } },
      },
    },
    quality_score: { type: "integer" },
    warnings: { type: "array", items: { type: "string" } },
  },
  required: ["skills", "quality_score"],
} as const;

export const interviewQuestionsSchema = {
  type: "object",
  properties: {
    questions: {
      type: "array",
      items: {
        type: "object",
        properties: {
          question: { type: "string" },
          category: { type: "string" },
        },
        required: ["question"],
      },
    },
  },
  required: ["questions"],
} as const;

export const answerFeedbackSchema = {
  type: "object",
  properties: {
    score: { type: "number" },
    went_well: { type: "array", items: { type: "string" } },
    to_improve: { type: "array", items: { type: "string" } },
    model_answer: { type: "string" },
  },
  required: ["score", "went_well", "to_improve"],
} as const;

type Shape = Record<string, "string" | "number" | "string[]" | "object[]">;

/**
 * Minimal structural validation. Deliberately not a schema library: this runs
 * on every model reply and the shapes above are small and fixed.
 */
export function validate(
  value: unknown,
  shape: Shape,
  required: string[],
): string[] {
  const problems: string[] = [];
  if (typeof value !== "object" || value === null) {
    return ["reply was not an object"];
  }
  const record = value as Record<string, unknown>;

  for (const key of required) {
    if (record[key] === undefined || record[key] === null) {
      problems.push(`missing ${key}`);
    }
  }

  for (const [key, kind] of Object.entries(shape)) {
    const actual = record[key];
    if (actual === undefined || actual === null) continue;
    const ok = kind === "string"
      ? typeof actual === "string"
      : kind === "number"
      ? typeof actual === "number" && Number.isFinite(actual)
      : Array.isArray(actual) &&
        actual.every((item) =>
          kind === "string[]"
            ? typeof item === "string"
            : typeof item === "object" && item !== null && !Array.isArray(item)
        );
    if (!ok) problems.push(`${key} was not ${kind}`);
  }

  return problems;
}

export const jdAnalysisShape: Shape = {
  job_title: "string",
  seniority: "string",
  skills: "string[]",
  qualifications: "string[]",
  responsibilities: "string[]",
  experience: "string",
};

export const cvParseShape: Shape = {
  headline: "string",
  summary: "string",
  skills: "string[]",
  education: "object[]",
  experience: "object[]",
  projects: "object[]",
  quality_score: "number",
  warnings: "string[]",
};

export const answerFeedbackShape: Shape = {
  score: "number",
  went_well: "string[]",
  to_improve: "string[]",
  model_answer: "string",
};
