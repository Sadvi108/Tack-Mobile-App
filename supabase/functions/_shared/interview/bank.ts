import { z } from "zod";

/**
 * Interview questions for old app builds, from the hand-written bank only.
 *
 * Questions never come from a model any more (plan ruling R8). A role the
 * bank has is served as it is; any other role is resolved in the database to
 * the student's nearest role (their path, target role or field, else general
 * graduate questions) and that role's set is served instead. Pure: the
 * interview function supplies the reads.
 */

/**
 * A role name as a slug: the rule of `slugify` in
 * supabase/seed/interview_bank/validate.py and `interview_slug()` in 0096.
 * Anything that is not a latin letter or digit becomes a hyphen, so a role
 * written in Bangla slugs to "" rather than to "-".
 */
export function slugifyRole(text: string): string {
  return text.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

/** What `interview_resolve_role_for()` returns (contract C3.4). */
export interface Resolution {
  role_slug: string;
  role_title: string;
  field_slug: string;
  field_name: string;
  resolved_from: string;
  hint_matched: boolean;
}

const resolution = z.object({
  role_slug: z.string().regex(/^[a-z0-9]+(-[a-z0-9]+)*$/),
  role_title: z.string().min(1),
  field_slug: z.string().min(1),
  field_name: z.string().min(1),
  resolved_from: z.string().min(1),
  hint_matched: z.boolean(),
});

/** The resolution, or null when any field is missing or the wrong type. */
export function parseResolution(value: unknown): Resolution | null {
  const parsed = resolution.safeParse(value);
  return parsed.success ? parsed.data : null;
}

/** One question as the interview endpoint returns it. Old builds read only
 * `question` and `category`. */
export interface ServedQuestion {
  question: string;
  category: string;
  key_points?: string[];
  pool_id?: string;
}

/**
 * The first `count` usable questions of a bank set, or null when there are
 * not that many. A set is stored JSON, so nothing about it is trusted: a
 * null column, an item without a question or a stray type is skipped, never
 * thrown on.
 */
export function servedSet(
  questions: unknown,
  count: number,
): ServedQuestion[] | null {
  if (!Array.isArray(questions)) return null;
  const out: ServedQuestion[] = [];
  for (const item of questions) {
    if (out.length === count) break;
    if (item === null || typeof item !== "object") continue;
    const row = item as Record<string, unknown>;
    if (typeof row.question !== "string" || row.question.trim() === "") {
      continue;
    }
    const served: ServedQuestion = {
      question: row.question,
      category: typeof row.category === "string" && row.category.trim() !== ""
        ? row.category
        : "General",
    };
    if (Array.isArray(row.key_points)) {
      served.key_points = row.key_points.filter((p): p is string =>
        typeof p === "string" && p.trim() !== ""
      );
    }
    if (typeof row.pool_id === "string" && row.pool_id !== "") {
      served.pool_id = row.pool_id;
    }
    out.push(served);
  }
  return out.length >= count ? out : null;
}

/** The two reads the questions flow needs, supplied by the endpoint. */
export interface QuestionsPorts {
  /** The `questions` column of the bank row for this role, type and
   * difficulty, or null when there is none. */
  readSet(roleSlug: string): Promise<unknown>;
  /** `interview_resolve_role_for(<the caller>, hint)`, or null on error. */
  resolve(hint: string): Promise<unknown>;
}

export interface Served {
  questions: ServedQuestion[];
  role: string;
  resolvedFrom: string;
}

async function attempt(read: () => Promise<unknown>): Promise<unknown> {
  try {
    return await read();
  } catch {
    return null;
  }
}

/**
 * The bank set for `role` if there is one, else the set of the student's
 * nearest role, else null. `role` is the redacted role text; `hint` is what
 * the student sent, passed to the database as a resolution hint.
 */
export async function questionsFor(
  ports: QuestionsPorts,
  role: string,
  hint: string,
  count: number,
): Promise<Served | null> {
  const slug = slugifyRole(role);
  if (slug !== "") {
    const exact = servedSet(await attempt(() => ports.readSet(slug)), count);
    if (exact) return { questions: exact, role: slug, resolvedFrom: "exact" };
  }
  const nearest = parseResolution(await attempt(() => ports.resolve(hint)));
  if (!nearest) return null;
  const set = servedSet(
    await attempt(() => ports.readSet(nearest.role_slug)),
    count,
  );
  return set
    ? {
      questions: set,
      role: nearest.role_slug,
      resolvedFrom: nearest.resolved_from,
    }
    : null;
}
