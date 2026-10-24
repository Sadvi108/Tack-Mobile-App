import { assertEquals } from "@std/assert";
import {
  careerQuestion,
  type CitedAnswer,
  citedPrompt,
  type Evidence,
  grounded,
  REFUSAL,
  validateCitations,
} from "./cited.ts";

const evidence: Evidence[] = [
  {
    chunk_id: "data-analyst:day:1",
    path_slug: "data-analyst",
    path_title: "Data analyst",
    text: "Day to day: Pull data with SQL",
    score: 1,
    title_hit: true,
  },
  {
    chunk_id: "data-analyst:salary:1",
    path_slug: "data-analyst",
    path_title: "Data analyst",
    text:
      "Salary: a starting data analyst usually earns 30,000 to 45,000 taka a month.",
    score: 0.75,
    title_hit: true,
  },
];

const answer = (over: Partial<CitedAnswer> = {}): CitedAnswer => ({
  answered: true,
  text: "Mostly pulling data with SQL, and it pays 30,000 to 45,000 taka.",
  citations: [
    { chunk_id: "data-analyst:day:1", quote: "Pull data with SQL" },
    {
      chunk_id: "data-analyst:salary:1",
      quote: "30,000 to 45,000 taka a month",
    },
  ],
  confidence: 0.8,
  ...over,
});

Deno.test("a question about a named kind of job is a career question", () => {
  for (
    const q of [
      "What is the salary of a marine biologist?",
      "What does a pharmacist do day to day?",
      "How much does a software engineer earn?",
      "How do I become an astronaut?",
    ]
  ) {
    assertEquals(careerQuestion(q), true, q);
  }
});

Deno.test("everyday questions the coach already answers are not hijacked", () => {
  for (
    const q of [
      "What should I do next?",
      "What does a good CV look like?",
      "How can I earn more points?",
      "How do I become a better speaker?",
      "Are internships paid?",
      "What are the steps to improve my CV?",
      "How do I pay for interview practice?",
    ]
  ) {
    assertEquals(careerQuestion(q), false, q);
  }
});

Deno.test("the guides answer when the question names the path or every word is covered", () => {
  assertEquals(grounded(evidence[0]), true);
  assertEquals(grounded({ ...evidence[0], title_hit: false, score: 1 }), true);
  assertEquals(
    grounded({ ...evidence[0], title_hit: false, score: 0.67 }),
    false,
  );
  assertEquals(grounded(undefined), false);
});

Deno.test("an answer with real quotes keeps them", () => {
  const out = validateCitations(answer(), evidence);
  assertEquals(out.answered, true);
  assertEquals(out.citations.map((c) => c.chunk_id), [
    "data-analyst:day:1",
    "data-analyst:salary:1",
  ]);
  assertEquals(out.citations[0].path_slug, "data-analyst");
  assertEquals(out.citations[0].path_title, "Data analyst");
});

Deno.test("a forged quote is dropped, and with none left it is a refusal", () => {
  const out = validateCitations(
    answer({
      citations: [{
        chunk_id: "data-analyst:day:1",
        quote: "Build machine learning models daily",
      }],
    }),
    evidence,
  );
  assertEquals(out.answered, false);
  assertEquals(out.text, REFUSAL);
  assertEquals(out.citations, []);
});

Deno.test("a real quote cited to the wrong chunk does not count", () => {
  const out = validateCitations(
    answer({
      citations: [{
        chunk_id: "data-analyst:salary:1",
        quote: "Pull data with SQL",
      }],
    }),
    evidence,
  );
  assertEquals(out.answered, false);
});

Deno.test("a chunk that was never retrieved cannot be cited", () => {
  const out = validateCitations(
    answer({
      citations: [{ chunk_id: "astronaut:day:1", quote: "Pull data with SQL" }],
    }),
    evidence,
  );
  assertEquals(out.answered, false);
});

Deno.test("a quote too short to mean anything does not count", () => {
  const out = validateCitations(
    answer({ citations: [{ chunk_id: "data-analyst:day:1", quote: "SQL" }] }),
    evidence,
  );
  assertEquals(out.answered, false);
});

Deno.test("a refusal stays a refusal, citations or not", () => {
  const out = validateCitations(answer({ answered: false }), evidence);
  assertEquals(out.answered, false);
  assertEquals(out.text, REFUSAL);
});

Deno.test("spacing and case do not stop a true quote", () => {
  const out = validateCitations(
    answer({
      text: "Mostly pulling data with SQL.",
      citations: [{
        chunk_id: "data-analyst:day:1",
        quote: "pull  DATA with sql",
      }],
    }),
    evidence,
  );
  assertEquals(out.answered, true);
});

Deno.test("the prompt carries every chunk with its id", () => {
  const prompt = citedPrompt("What does a data analyst do?", evidence);
  assertEquals(prompt.includes("[data-analyst:day:1]"), true);
  assertEquals(prompt.includes("Pull data with SQL"), true);
  assertEquals(prompt.includes("Question: What does a data analyst do?"), true);
});

Deno.test("a number the quotes do not carry turns the answer into a refusal", () => {
  const out = validateCitations(
    answer({
      text: "Data analysts earn 90,000 taka a month.",
      citations: [{
        chunk_id: "data-analyst:day:1",
        quote: "Pull data with SQL",
      }],
    }),
    evidence,
  );
  assertEquals(out.answered, false);
});

Deno.test("numbers that come from the quotes are fine, commas or not", () => {
  const out = validateCitations(
    answer({
      text: "A starting analyst earns 30000 to 45,000 taka.",
      citations: [{
        chunk_id: "data-analyst:salary:1",
        quote: "30,000 to 45,000 taka a month",
      }],
    }),
    evidence,
  );
  assertEquals(out.answered, true);
});
