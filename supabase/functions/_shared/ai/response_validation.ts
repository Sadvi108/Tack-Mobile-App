import { z } from "zod";

const text = z.string().max(8000);
const label = z.string().trim().min(1).max(500);
const list = z.array(label).max(100);
const schemas: Record<string, z.ZodType> = {
  analyse_jd: z.strictObject({
    job_title: label,
    seniority: text.optional(),
    skills: list,
    qualifications: list,
    responsibilities: list,
    experience: text.optional(),
  }),
  parse_cv: z.strictObject({
    headline: text.optional(),
    summary: text.optional(),
    skills: list,
    education: z.array(
      z.strictObject({
        degree: label,
        institution: label,
        year: z.number().int().min(1900).max(2100).optional(),
      }),
    ).max(30).optional(),
    experience: z.array(
      z.strictObject({
        title: label,
        organisation: label,
        months: z.number().int().min(0).max(1200).optional(),
      }),
    ).max(50).optional(),
    projects: z.array(z.strictObject({ title: label, summary: text })).max(50)
      .optional(),
    quality_score: z.number().int().min(0).max(100),
    warnings: list.optional(),
  }),
  interview_questions: z.strictObject({
    questions: z.array(z.strictObject({
      question: label,
      category: z.enum(["technical", "behavioural", "mixed"]).optional(),
    })).min(3).max(10),
  }),
  evaluate_answer: z.strictObject({
    score: z.number().min(0).max(10),
    went_well: list,
    to_improve: list,
    model_answer: text.optional(),
  }),
  coach_chat: z.strictObject({ reply: z.string().trim().min(1).max(2000) }),
  // Lenient on purpose: one stray reader should be dropped by recallGate
  // (_shared/cv/first_read.ts), not sink the other two.
  cv_first_read: z.strictObject({
    readers: z.array(z.strictObject({
      persona: z.string().max(100),
      needle: z.array(z.strictObject({
        chunk: z.number().int(),
        value: z.number(),
      })).max(40),
      quit_chunk: z.number().int(),
      sayback: z.string().max(2000),
      remembered: z.array(z.string().max(2000)).max(10),
      one_action: z.string().max(2000),
    })).min(1).max(8),
  }),
  interview_prep: z.strictObject({
    talking_points: z.array(z.strictObject({ point: label, evidence: label }))
      .max(10),
    likely_questions: z.array(z.strictObject({ question: label, why: label }))
      .max(10),
    questions_to_ask: z.array(label).max(10),
    gaps: z.array(z.strictObject({ skill: label, how_to_prepare: label }))
      .max(10),
  }),
};

/** No input values in errors: these codes are safe to record in telemetry. */
export function validateResponse(feature: string, value: unknown): string[] {
  const schema = schemas[feature];
  if (!schema) return ["unknown_response_schema"];
  return schema.safeParse(value).success ? [] : ["invalid_model_reply"];
}
