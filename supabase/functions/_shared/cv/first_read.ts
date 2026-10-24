/**
 * The CV first read: three readers go through a CV in order, say where their
 * interest rose and fell and where they would have stopped, then say what they
 * remember.
 *
 * Borrowed from First Reader in awesome-llm-apps (agent_skills/first-reader):
 * personas with a situation, a patience budget and a stake, who must disagree
 * (references/personas.md); the text served in beats of about 85 words, each
 * told how much is left (scripts/feed.py); an interest needle from -2 to +2
 * with the quit point as the sharpest number (SKILL.md); and a recall quiz —
 * say it back, quote what stuck, name one action (scripts/recall.py).
 *
 * What the model returns is held to the read here, in code: a reader may only
 * "remember" words the CV actually contains (the citation check from Typed
 * RAG, rag_tutorials/agentic_typed_rag_pydanticai/agent.py), needles stay in
 * range, and only the three cast readers count.
 */
import { sectionOf } from "./metrics.ts";

export const READERS = [
  {
    id: "recruiter",
    name: "Recruiter at a Dhaka software company",
    situation: "skimming forty CVs on a phone between calls",
    patience: "about eight seconds for the first screen",
    stake: "has three junior roles to fill this month",
  },
  {
    id: "hiring_manager",
    name: "Hiring manager for the role",
    situation:
      "reads experience and projects first, sceptical of copied projects",
    patience: "a minute at most, and only if the top earns it",
    stake: "needs someone who can ship in the first month",
  },
  {
    id: "hr_officer",
    name: "HR officer at a large local company",
    situation: "screening for a graduate programme, checking basics and dates",
    patience: "about thirty seconds",
    stake: "cannot pass a CV with gaps or mistakes up the chain",
  },
] as const;

export type ReaderId = typeof READERS[number]["id"];

export interface Chunk {
  index: number;
  section: string;
  text: string;
  words: number;
}

export interface ReaderResult {
  persona: string;
  needle: { chunk: number; value: number }[];
  /** The chunk the reader stopped at, or 0 for read to the end. */
  quit_chunk: number;
  sayback: string;
  remembered: string[];
  one_action: string;
}

export interface ReadResult {
  readers: ReaderResult[];
}

const TARGET_WORDS = 85;
const MAX_CHUNKS = 12;

const countWords = (text: string) => text.split(/\s+/).filter(Boolean).length;
const title = (section: string) =>
  section.charAt(0).toUpperCase() + section.slice(1);
const listOf = (names: string[]) =>
  names.length <= 1
    ? names.join("")
    : `${names.slice(0, -1).join(", ")} and ${names[names.length - 1]}`;

/** A heading with nothing after it: letters, spaces, a colon at most. */
const HEADING_ONLY = /^[\p{L} &/'-]+:?$/u;

/** A paragraph pasted as one line is still read in beats. */
function splitLongLine(line: string): string[] {
  const words = line.split(/\s+/).filter(Boolean);
  if (words.length <= TARGET_WORDS) return [line];
  const out: string[] = [];
  for (let i = 0; i < words.length; i += TARGET_WORDS) {
    out.push(words.slice(i, i + TARGET_WORDS).join(" "));
  }
  return out;
}

/**
 * One chunk per CV section, in reading order, with a long section cut into
 * beats of about 85 words at line breaks. Everything before the first heading
 * — the name and the summary a reader sees first — is "Top".
 */
export function chunkCv(text: string): Chunk[] {
  const groups: { section: string; lines: string[] }[] = [];
  let current = { section: "Top", lines: [] as string[] };

  for (const raw of text.split("\n")) {
    const line = raw.trim();
    if (!line) continue;
    const header = sectionOf(line);
    if (header) {
      if (current.lines.length > 0) groups.push(current);
      current = { section: title(header), lines: [] };
      // "Education: BSc, BUET" opens a section and is also its first line.
      // Only a bare heading is dropped; anything after it is read.
      if (!HEADING_ONLY.test(line)) current.lines.push(line);
      continue;
    }
    current.lines.push(line);
  }
  if (current.lines.length > 0) groups.push(current);

  const beats: { section: string; text: string }[] = [];
  for (const group of groups) {
    let lines: string[] = [];
    let words = 0;
    for (const line of group.lines.flatMap(splitLongLine)) {
      const w = countWords(line);
      if (words > 0 && words + w > TARGET_WORDS) {
        beats.push({ section: group.section, text: lines.join("\n") });
        lines = [];
        words = 0;
      }
      lines.push(line);
      words += w;
    }
    if (lines.length > 0) {
      beats.push({ section: group.section, text: lines.join("\n") });
    }
  }

  // A reader who has not stopped by the twelfth beat will not stop at the
  // thirtieth; the rest is folded into the last one rather than sent.
  // It is labelled with every section it holds, and each section's name is
  // kept in its text, so a quit point there is reported truthfully.
  if (beats.length > MAX_CHUNKS) {
    const tail = beats.splice(MAX_CHUNKS - 1);
    const sections = [...new Set(tail.map((b) => b.section))];
    let previous = beats[beats.length - 1]?.section;
    const parts: string[] = [];
    for (const b of tail) {
      if (b.section !== previous) parts.push(`${b.section}:`);
      parts.push(b.text);
      previous = b.section;
    }
    beats.push({ section: listOf(sections), text: parts.join("\n") });
  }

  return beats.map((b, i) => ({
    index: i + 1,
    section: b.section,
    text: b.text,
    words: countWords(b.text),
  }));
}

export function firstReadPrompt(chunks: Chunk[]): string {
  const total = chunks.reduce((sum, c) => sum + c.words, 0);
  let read = 0;
  return chunks.map((c) => {
    read += c.words;
    return `CHUNK ${c.index}/${chunks.length} — ${c.section} (${
      total - read
    } words remain after this)\n${c.text}`;
  }).join("\n\n");
}

const normalise = (text: string) =>
  text.toLowerCase().replace(/\s+/g, " ").trim();

const escape = (text: string) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/** What redact() puts where contact details were. Never a memory. */
const PLACEHOLDER = /\[(email|phone|id|link)\]/i;

/**
 * A real memory: at least two words and eight characters, whole words from
 * text the reader actually reached, and not a redaction placeholder.
 */
function isMemory(quote: string, source: string): boolean {
  const q = normalise(quote);
  if (q.length < 8 || q.split(" ").length < 2 || PLACEHOLDER.test(q)) {
    return false;
  }
  return new RegExp(`(?<![\\p{L}\\p{N}])${escape(q)}(?![\\p{L}\\p{N}])`, "u")
    .test(source);
}

/**
 * Holds the model to the read: only the cast readers, once each, with a
 * retelling and an action; needles in range and on real chunks; a quit point
 * inside the CV or 0; and nothing "remembered" that the reader did not reach,
 * word for word, before they stopped.
 */
export function recallGate(
  result: ReadResult,
  chunks: Chunk[],
): { readers: ReaderResult[]; dropped: number } {
  const ids = new Set<string>(READERS.map((r) => r.id));
  const seen = new Set<string>();
  const n = chunks.length;
  let dropped = 0;
  const readers: ReaderResult[] = [];

  for (const r of result.readers ?? []) {
    if (!ids.has(r.persona) || seen.has(r.persona)) continue;
    if (!r.sayback?.trim() || !r.one_action?.trim()) continue;
    seen.add(r.persona);

    const reached = new Set<number>();
    const needle = (r.needle ?? [])
      .filter((x) =>
        Number.isInteger(x.chunk) && x.chunk >= 1 && x.chunk <= n &&
        !reached.has(x.chunk) && (reached.add(x.chunk), true)
      )
      .map((x) => ({
        chunk: x.chunk,
        value: Math.max(-2, Math.min(2, Math.round(x.value))),
      }));

    const quit = Number.isInteger(r.quit_chunk) && r.quit_chunk >= 1 &&
        r.quit_chunk <= n
      ? r.quit_chunk
      : 0;
    const source = normalise(
      chunks.filter((c) => quit === 0 || c.index <= quit)
        .map((c) => c.text).join(" "),
    );

    const remembered = (r.remembered ?? []).filter((q) => {
      const kept = typeof q === "string" && isMemory(q, source);
      if (!kept) dropped++;
      return kept;
    }).slice(0, 3);

    readers.push({
      persona: r.persona,
      needle,
      quit_chunk: quit,
      sayback: r.sayback.trim(),
      remembered,
      one_action: r.one_action.trim(),
    });
  }

  return { readers, dropped };
}
