/**
 * What the worker measures about a CV, with no model involved.
 *
 * The split this file exists for: a model is good at reading prose and saying
 * "this person knows React". It is slow, expensive and unreliable at counting
 * how many bullet points contain a number. So the model extracts meaning, and
 * this counts. Everything here is a pure function of the text, which is what
 * makes the score reproducible and this file testable without a network.
 *
 * The shape returned is the contract `score_cv_fit` reads out of
 * `cv_parse_results.metrics`. Changing a key here changes the score, so it is
 * changed with a migration bumping `algo_version`, not quietly.
 */
import { redact } from "../ai/redact.ts";

export interface CvMetrics {
  chars: number;
  words: number;
  pages: number;
  bullets: number;
  bullets_quantified: number;
  bullets_action_led: number;
  sections: string[];
  has_contact: boolean;
  dated_entries: number;
  undated_entries: number;
  /** "YYYY-MM", or null when the CV carries no usable date. */
  latest_entry_date: string | null;
  placeholder_hits: number;
  extractor: string;
  truncated: boolean;
}

const SECTIONS: Array<[string, RegExp]> = [
  ["contact", /^(contact|personal)\b.{0,24}$/i],
  ["summary", /^(summary|profile|objective|about)\b.{0,24}$/i],
  ["education", /^(education|academic|qualifications?)\b.{0,24}$/i],
  [
    "experience",
    /^((work|professional|industry)\s+)?(experience|employment|history|internships?)\b.{0,24}$/i,
  ],
  ["projects", /^((personal|academic|selected)\s+)?projects?\b.{0,24}$/i],
  [
    "skills",
    /^((technical|core|key|professional)\s+)?(skills|competenc(y|ies)|technologies)\b.{0,24}$/i,
  ],
  [
    "certifications",
    /^(certificat(e|ion)s?|licen[cs]es?|courses?|training)\b.{0,24}$/i,
  ],
  [
    "activities",
    /^(activities|extra[- ]?curricular|volunteering|leadership|clubs?|awards?|achievements?)\b.{0,24}$/i,
  ],
];

/** Sections whose blocks are entries a reader expects to carry a date. */
const DATED_SECTIONS = new Set([
  "experience",
  "projects",
  "education",
  "certifications",
  "activities",
]);

/**
 * Verbs a CV line can open with. Both forms are listed rather than stemmed:
 * a stemmer would be another thing to get subtly wrong, and this list is
 * short, fixed and inspectable.
 */
const ACTION_VERBS = new Set([
  "achieved",
  "achieve",
  "analysed",
  "analyzed",
  "analyse",
  "analyze",
  "automated",
  "automate",
  "built",
  "build",
  "collaborated",
  "collaborate",
  "conducted",
  "conduct",
  "coordinated",
  "coordinate",
  "created",
  "create",
  "cut",
  "delivered",
  "deliver",
  "designed",
  "design",
  "developed",
  "develop",
  "diagnosed",
  "diagnose",
  "documented",
  "document",
  "drove",
  "drive",
  "expanded",
  "expand",
  "facilitated",
  "facilitate",
  "fixed",
  "fix",
  "founded",
  "found",
  "grew",
  "grow",
  "implemented",
  "implement",
  "improved",
  "improve",
  "increased",
  "increase",
  "initiated",
  "initiate",
  "integrated",
  "integrate",
  "introduced",
  "introduce",
  "launched",
  "launch",
  "led",
  "lead",
  "maintained",
  "maintain",
  "managed",
  "manage",
  "measured",
  "measure",
  "mentored",
  "mentor",
  "migrated",
  "migrate",
  "negotiated",
  "negotiate",
  "optimised",
  "optimized",
  "optimise",
  "optimize",
  "organised",
  "organized",
  "organise",
  "organize",
  "planned",
  "plan",
  "presented",
  "present",
  "produced",
  "produce",
  "published",
  "publish",
  "raised",
  "raise",
  "ran",
  "run",
  "rebuilt",
  "rebuild",
  "reduced",
  "reduce",
  "refactored",
  "refactor",
  "researched",
  "research",
  "resolved",
  "resolve",
  "reviewed",
  "review",
  "shipped",
  "ship",
  "simplified",
  "simplify",
  "solved",
  "solve",
  "streamlined",
  "streamline",
  "supported",
  "support",
  "taught",
  "teach",
  "tested",
  "test",
  "trained",
  "train",
  "translated",
  "translate",
  "wrote",
  "write",
]);

const PLACEHOLDERS = [
  /lorem ipsum/i,
  // One pattern, not two: "Your name here" is a single mistake and should be
  // counted once.
  /\b(your name|name here)\b/i,
  /\bxxx+\b/i,
  /\btbd\b/i,
  /to be (added|filled|completed)/i,
  /\bplaceholder\b/i,
  /dd\s*[\/-]\s*mm\s*[\/-]\s*yyyy/i,
  /\[insert[^\]]*\]/i,
];

const MONTHS: Record<string, number> = {
  jan: 1,
  feb: 2,
  mar: 3,
  apr: 4,
  may: 5,
  jun: 6,
  jul: 7,
  aug: 8,
  sep: 9,
  oct: 10,
  nov: 11,
  dec: 12,
};

const MONTH_YEAR =
  /\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s*,?\s*((?:19|20)\d{2})\b/gi;
const BARE_YEAR = /\b((?:19|20)\d{2})\b/g;
const ONGOING = /\b(present|current|ongoing|to date|now)\b/i;
const ANY_DATE =
  /\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s*,?\s*(?:19|20)\d{2}\b|\b(?:19|20)\d{2}\b|\b\d{1,2}\/\d{2,4}\b/i;

/** Years and short dates, removed so a date is never mistaken for a metric. */
const DATE_LIKE =
  /\b(?:19|20)\d{2}\b|\b\d{1,2}\s*[\/-]\s*\d{1,2}(\s*[\/-]\s*\d{2,4})?\b/g;

const BULLET_GLYPH = /^[•‣▪●·⁃\-\*–—>\s]+/;

export interface MeasureOptions {
  pages: number;
  truncated: boolean;
  extractor: string;
  /** Injectable so "how recent is this" is testable without waiting a month. */
  today?: Date;
}

export function measure(text: string, opts: MeasureOptions): CvMetrics {
  const today = opts.today ?? new Date();
  const lines = text.split("\n").map((l) => l.trim());

  const sections = new Set<string>();
  let current = "";
  let bullets = 0;
  let quantified = 0;
  let actionLed = 0;
  let dated = 0;
  let undated = 0;

  // A block is a run of non-blank lines. Entries in a CV are separated by
  // blank lines far more often than not — but an extractor that drops them
  // collapses a section into one block, which under-counts entries rather
  // than inventing undated ones. Erring that way is deliberate: hygiene must
  // not punish a student for the extractor's formatting.
  let blockLines: string[] = [];
  let blockSection = "";

  const closeBlock = () => {
    if (blockLines.length > 0 && DATED_SECTIONS.has(blockSection)) {
      const joined = blockLines.join(" ");
      if (ANY_DATE.test(joined) || ONGOING.test(joined)) dated++;
      else undated++;
    }
    blockLines = [];
  };

  for (const line of lines) {
    if (line === "") {
      closeBlock();
      continue;
    }

    const header = sectionOf(line);
    if (header) {
      closeBlock();
      sections.add(header);
      current = header;
      blockSection = header;
      continue;
    }

    if (blockLines.length === 0) blockSection = current;
    blockLines.push(line);

    const body = line.replace(BULLET_GLYPH, "");
    const words = body.split(/\s+/).filter(Boolean);
    // A heading, a name or a job title is not a bullet; neither is a
    // paragraph that ran on for half a page.
    if (words.length < 4 || words.length > 60) continue;

    // A skills section is a comma-separated list, not prose. Counting
    // "JavaScript, React, CSS, Git" as a bullet would guarantee it fails both
    // the quantification and the action-verb test, and mark a student down for
    // writing a skills list the normal way.
    if (current === "skills") continue;

    const first = words[0].toLowerCase().replace(/[^a-z]/g, "");
    const verbLed = ACTION_VERBS.has(first);

    // "Frontend intern, bKash, Jan 2026 - Jun 2026" is an entry header. It
    // carries a date and does not open with a verb, and counting it as a
    // bullet would drag down action_language on every well-formed CV. A real
    // bullet that happens to mention a year — "Led the 2025 orientation" —
    // still counts, because it opens with a verb.
    if (!verbLed && ANY_DATE.test(body)) continue;

    bullets++;
    if (/\d/.test(body.replace(DATE_LIKE, " "))) quantified++;
    if (verbLed) actionLed++;
  }
  closeBlock();

  const contact = redact(text).found;
  if (contact.emails.length > 0 || contact.phones.length > 0) {
    sections.add("contact");
  }

  return {
    chars: text.length,
    words: text.split(/\s+/).filter(Boolean).length,
    pages: Math.max(1, opts.pages),
    bullets,
    bullets_quantified: quantified,
    bullets_action_led: actionLed,
    sections: [...sections].sort(),
    has_contact: contact.emails.length > 0 || contact.phones.length > 0,
    dated_entries: dated,
    undated_entries: undated,
    latest_entry_date: latestDate(text, today),
    placeholder_hits: PLACEHOLDERS.filter((p) => p.test(text)).length,
    extractor: opts.extractor,
    truncated: opts.truncated,
  };
}

function sectionOf(line: string): string | null {
  if (line.split(/\s+/).filter(Boolean).length > 5) return null;
  const cleaned = line.replace(/^[^a-z]*/i, "").replace(/[:\-–—\s]+$/, "");
  for (const [name, pattern] of SECTIONS) {
    if (pattern.test(cleaned)) return name;
  }
  return null;
}

/**
 * The most recent thing on the CV, as "YYYY-MM".
 *
 * Future years are ignored rather than clamped to today. An expected
 * graduation in 2028 is a plan, not something the student has done, and
 * treating it as the newest entry would hand a blank CV a perfect recency
 * score. "Present" on a running role does count as today, because it is.
 */
export function latestDate(text: string, today: Date): string | null {
  const cap = today.getFullYear() * 12 + (today.getMonth() + 1);
  let best = 0;

  for (const m of text.matchAll(MONTH_YEAR)) {
    const month = MONTHS[m[1].slice(0, 3).toLowerCase()];
    const value = Number(m[2]) * 12 + month;
    if (value <= cap && value > best) best = value;
  }

  for (const m of text.matchAll(BARE_YEAR)) {
    const value = Number(m[1]) * 12 + 1;
    if (value <= cap && value > best) best = value;
  }

  if (ONGOING.test(text) && best > 0) best = cap;
  if (best === 0) return null;

  const year = Math.floor((best - 1) / 12);
  const month = best - year * 12;
  return `${year}-${String(month).padStart(2, "0")}`;
}
