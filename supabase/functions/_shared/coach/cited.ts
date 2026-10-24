/**
 * The coach, answering a question about a career path from Tack's own guides,
 * citing them, or saying it cannot.
 *
 * Borrowed from Typed RAG in awesome-llm-apps
 * (rag_tutorials/agentic_typed_rag_pydanticai/agent.py): evidence first and
 * only evidence; every citation copies a chunk id and a verbatim span of that
 * chunk; an answer and its citations must agree; and a question the evidence
 * is too weak to carry is refused before a model is called (`grounded`), so a
 * refusal costs the student nothing. What the model returns is checked here,
 * in code, before a student sees it (`validateCitations`).
 */

export interface Evidence {
  chunk_id: string;
  path_slug: string;
  path_title: string;
  text: string;
  /** Share of the question's words the chunk covers, 0 to 1. */
  score: number;
  /** The question said the path's whole title. */
  title_hit: boolean;
}

export interface CitedAnswer {
  answered: boolean;
  text: string;
  citations: { chunk_id: string; quote: string }[];
  confidence: number;
}

export interface Citation {
  chunk_id: string;
  path_slug: string;
  path_title: string;
  quote: string;
}

export const REFUSAL =
  "Tack's career guides do not cover that yet. Try asking about one of the " +
  "paths in Explore — what the work is like day to day, what it pays, or how " +
  "to start.";

const MIN_QUOTE = 8;

/** Asking what a kind of work is like: its pay, its days, how to get in. */
const ASKS_ABOUT_WORK =
  /\b(salary|salaries|earn|earns|paid|pay|day[- ]to[- ]day|every day|what does an? \w+|what do \w+s do|become an?|career as|job as|work as|good fit)\b/i;

/** A word that names a kind of job. Without one, it is not a career question. */
const ROLE =
  /\b\w*(developer|engineer|analyst|designer|manager|officer|executive|accountant|marketer|writer|scientist|consultant|teacher|lawyer|doctor|nurse|pharmacist|architect|biologist|chemist|physicist|astronaut|pilot|banker|auditor|journalist|researcher|technician|specialist|administrator|programmer|tester|economist|statistician|planner|editor|photographer|artist|chef|entrepreneur)s?\b/i;

/**
 * A question about what a named kind of job is like. Only these are refused
 * when the guides do not cover them; anything else the guides cannot answer
 * goes to the ordinary coach, as before. "What does a good CV look like?"
 * and "How can I earn more points?" ask about work, but name no job.
 */
export function careerQuestion(question: string): boolean {
  return ASKS_ABOUT_WORK.test(question) && ROLE.test(question);
}

/**
 * Whether the top chunk can carry the question: it names its own path, or it
 * covers every word the question asked. Anything less and a guide for a
 * different job could answer for it.
 */
export function grounded(top: Evidence | undefined): boolean {
  return !!top && (top.title_hit || top.score >= 1);
}

const normalise = (text: string) =>
  text.toLowerCase().replace(/\s+/g, " ").trim();

/**
 * Keeps only citations whose quote is a real span of the chunk they name, from
 * the evidence actually given. An answer left with none is a refusal; so is an
 * answer the model itself marked unanswered.
 */
export function validateCitations(
  answer: CitedAnswer,
  evidence: Evidence[],
): { answered: boolean; text: string; citations: Citation[] } {
  const byId = new Map(evidence.map((e) => [e.chunk_id, e]));
  const citations: Citation[] = [];
  const seen = new Set<string>();

  for (const c of answer.citations ?? []) {
    const chunk = byId.get(c.chunk_id);
    const quote = normalise(c.quote ?? "");
    if (!chunk || quote.length < MIN_QUOTE) continue;
    if (!normalise(chunk.text).includes(quote)) continue;
    const key = `${c.chunk_id}|${quote}`;
    if (seen.has(key)) continue;
    seen.add(key);
    citations.push({
      chunk_id: chunk.chunk_id,
      path_slug: chunk.path_slug,
      path_title: chunk.path_title,
      quote: c.quote.trim(),
    });
  }

  if (!answer.answered || citations.length === 0 || !answer.text?.trim()) {
    return { answered: false, text: REFUSAL, citations: [] };
  }

  // The answer and its citations must agree. Words are hard to hold a model
  // to; numbers are not. Every figure in the answer has to appear in one of
  // the quotes it kept — a salary the guides never gave is not an answer.
  const quoted = citations.map((c) => digits(c.quote)).join(" ");
  for (const n of answer.text.match(/\d[\d,.]*\d|\d/g) ?? []) {
    if (!quoted.includes(digits(n))) {
      return { answered: false, text: REFUSAL, citations: [] };
    }
  }

  return { answered: true, text: answer.text.trim(), citations };
}

/** 45,000 and 45000 are the same number. */
const digits = (text: string) => text.replace(/(\d),(?=\d{3})/g, "$1");

export function citedPrompt(question: string, evidence: Evidence[]): string {
  const lines = evidence.map((e) =>
    `[${e.chunk_id}] (${e.path_title}) ${e.text}`
  );
  return `Evidence:\n${lines.join("\n")}\n\nQuestion: ${question}`;
}

export const CITED_SYSTEM = `
You are the careers coach inside Tack, an app for Bangladeshi university
students. You answer a question about a career path using only the evidence
given, which comes from Tack's own career guides.

Rules:
1. Use only the evidence. Never use background knowledge to fill a gap.
2. If the evidence does not answer the question, set answered to false, give
   no citations, and leave text empty.
3. If it does, answer in plain, short English for second-language readers, at
   most 90 words, sentence case, no headings.
4. Every claim must be backed by a citation. Each citation copies a chunk_id
   exactly from the evidence, and quote is a short span copied word for word
   from that chunk's text.
5. confidence is a number from 0 to 1; lower it when the evidence is partial.
6. Never blame the student. Never use the words deadline or apply.
`.trim();
