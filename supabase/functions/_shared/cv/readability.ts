/**
 * How a CV reads on a phone, and the phrases that undersell it. Free: pure
 * functions of the text, added to the CV check alongside `findings.ts`.
 *
 * The phone arithmetic is First Reader's skim gate (awesome-llm-apps,
 * agent_skills/first-reader/scripts/skim.py): about 38 characters to a line
 * and 14 lines to a screen. A recruiter who opens a CV on a phone and decides
 * on the first screen has read 532 characters of it.
 *
 * Kept apart from `metrics.ts` on purpose: `score_cv_fit` reads that shape,
 * and nothing here should move a score.
 */
import type { Finding } from "./findings.ts";
import { redact } from "../ai/redact.ts";

const CHARS_PER_LINE = 38;
const LINES_PER_SCREEN = 14;

/** More than this many screens and the strongest line had better be first. */
const LONG_FOR_PHONE = 4;

/**
 * Phrases that say the student was near the work rather than that they did
 * it. Matched as whole words, case-insensitively.
 */
const WEAK = [
  "responsible for",
  "familiar with",
  "helped with",
  "helped to",
  "assisted in",
  "assisted with",
  "basic knowledge of",
  "exposure to",
  "involved in",
  "participated in",
];

export function phoneScreens(text: string): number {
  const reading = text.replace(/\s+/g, " ").trim();
  return Math.max(
    1,
    Math.ceil(reading.length / (CHARS_PER_LINE * LINES_PER_SCREEN)),
  );
}

export function weakPhrases(text: string): { phrase: string; line: string }[] {
  const found: { phrase: string; line: string }[] = [];
  for (const raw of text.split("\n")) {
    const line = raw.trim();
    if (!line) continue;
    const lower = line.toLowerCase();
    const phrase = WEAK.find((w) =>
      new RegExp(`(?<![\\p{L}\\p{N}])${w}(?![\\p{L}\\p{N}])`, "u").test(lower)
    );
    if (phrase) found.push({ phrase, line });
  }
  return found;
}

// The finding is stored and shown again later, so a quoted line goes in
// with any contact details on it taken out.
const quote = (raw: string) => {
  const line = redact(raw).text;
  return `“${line.length > 70 ? `${line.slice(0, 67).trimEnd()}…` : line}”`;
};

export function readabilityFindings(text: string): Finding[] {
  const out: Finding[] = [];

  const screens = phoneScreens(text);
  if (screens > LONG_FOR_PHONE) {
    out.push({
      kind: "long-for-phone",
      severity: "improve",
      title: "Long to read on a phone",
      detail: `On a phone this is about ${screens} screens. Many recruiters ` +
        "open a CV on their phone and decide on the first one, so put your " +
        "strongest result in the first few lines.",
    });
  }

  const weak = weakPhrases(text);
  if (weak.length > 0) {
    const examples = weak.slice(0, 2).map((w) => quote(w.line)).join(" and ");
    out.push({
      kind: "weak-phrases",
      severity: "improve",
      title: weak.length === 1
        ? "One line undersells you"
        : `${weak.length} lines undersell you`,
      detail: `Phrases like “${weak[0].phrase}” say you were near the work, ` +
        "not that you did it. Start with what you did — “Built”, “Led”, " +
        `“Cut” — and keep the result. For example ${examples}.`,
    });
  }

  return out;
}
