/**
 * What a model's coach reply must pass, in code, before a student reads it.
 *
 * The prompt asks for all of this (`ai/coach_prompt.ts`); this is where it is
 * enforced. A reply with problems is sent back once with the codes, and a
 * second failure becomes a free fallback answer (`jobs/conversation_handlers`).
 */
import { isEarly, type Mode, MODE_WORDS, routesForMode } from "./actions.ts";

export interface CoachModelReply {
  body: string;
  actions: { route: string }[];
}

const MAX_WORDS = 160;

/** 45,000 and 45000 are the same number: the rule cited.ts uses. */
const digits = (text: string) => text.replace(/(\d),(?=\d{3})/g, "$1");

const NUMBER = /\d[\d,.]*\d|\d/g;
const PERCENT_AFTER = /^\s*(%|per ?cent)/i;
const MONEY_AFTER = /^\s*(taka|tk\b|৳|bdt)/i;
const MONEY_BEFORE = /(taka|tk\.?|৳|bdt)\s*$/i;

/** "41 out of 100" and "6 out of 10" are how a score is said, not a claim. */
const SCALE = /\bout of 10{1,2}\b/gi;

function unknownNumber(body: string, facts: string): boolean {
  const text = body.replace(SCALE, "out of");
  for (const m of text.matchAll(NUMBER)) {
    const raw = m[0];
    const at = m.index ?? 0;
    const after = text.slice(at + raw.length, at + raw.length + 12);
    const before = text.slice(Math.max(0, at - 6), at);
    const value = Number(digits(raw).replace(/,/g, ""));
    const money = MONEY_AFTER.test(after) || MONEY_BEFORE.test(before);
    const percent = PERCENT_AFTER.test(after);
    if (!(value > 10 || percent || money)) continue;
    if (!facts.includes(digits(raw))) return true;
  }
  return false;
}

/** Problem codes only, never input text: they go into the retry prompt and
 *  the logs. An empty list means the reply may be stored. */
export function checkCoachReply(
  reply: CoachModelReply,
  opts: { mode: Mode; factsText: string },
): string[] {
  const problems: string[] = [];
  const body = typeof reply?.body === "string" ? reply.body : "";
  if (isEarly(opts.mode) && MODE_WORDS.test(body)) {
    problems.push("body_mode_word");
  }
  if (body.trim().split(/\s+/).filter(Boolean).length > MAX_WORDS) {
    problems.push("body_too_long");
  }
  if (unknownNumber(body, digits(opts.factsText))) {
    problems.push("body_unknown_number");
  }
  const allowed = routesForMode(opts.mode) as string[];
  const actions = Array.isArray(reply?.actions) ? reply.actions : [];
  if (!actions.some((a) => allowed.includes(a?.route))) {
    problems.push("no_allowed_action");
  }
  return problems;
}
