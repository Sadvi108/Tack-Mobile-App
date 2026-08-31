import { assert, assertEquals } from "@std/assert";
import { answerFromData, type Context } from "./router.ts";

const ctx: Context = {
  mode: "launch",
  target_role: "Backend developer",
  target_path: { title: "Frontend developer", slug: "frontend-developer" },
  score: {
    total: 13,
    components: {
      projects: { earned: 0, max: 10, available: 10 },
      skills: { earned: 6, max: 12, available: 6 },
      cv_quality: { earned: 0, max: 13, available: 13 },
      application_activity: { earned: 0, max: 0, available: 0 },
    },
  },
  skills_held: ["Python"],
  skill_gap: ["CSS", "HTML", "JavaScript"],
  roadmap: { done: 4, total: 23, next: "Learn TypeScript basics" },
  applications: { applied: 1, interview: 1 },
  has_cv: false,
  streak: 2,
};

Deno.test("a question about what to do next is answered from the numbers", () => {
  const a = answerFromData("What should I do next?", ctx);
  assert(a, "should not need the model");
  assertEquals(a.answeredBy, "data");
  // cv_quality has the most available, so it leads.
  assert(a.body.includes("your CV"), a.body);
  assert(a.body.includes("13 points"), a.body);
  assert(a.body.includes("Learn TypeScript basics"), a.body);
});

Deno.test("a component this mode does not count is never offered", () => {
  // application_activity is weighted zero here; suggesting it would be the
  // same bug the dashboard had.
  const a = answerFromData("what should I work on", ctx);
  assert(a);
  assert(!a.body.includes("applications"), a.body);
});

Deno.test("the score question quotes the real total", () => {
  const a = answerFromData("how am I doing?", ctx);
  assert(a);
  assert(a.body.startsWith("You are on 13 out of 100."), a.body);
});

Deno.test("the skill gap names the target path, not the typed role", () => {
  // The path is what the roadmap and score are built from. Saying "Backend
  // developer" here would repeat the bug the dashboard had.
  const a = answerFromData("what skills am I missing?", ctx);
  assert(a);
  assert(a.body.includes("Frontend developer"), a.body);
  assert(a.body.includes("CSS, HTML and JavaScript"), a.body);
});

Deno.test("no target path is said plainly rather than guessed at", () => {
  const a = answerFromData("what skills do I need?", {
    ...ctx,
    target_path: null,
  });
  assert(a);
  assert(a.body.includes("not picked a target path"), a.body);
});

Deno.test("roadmap progress comes from the count, not a guess", () => {
  const a = answerFromData("how far through my roadmap am I?", ctx);
  assert(a);
  assert(a.body.includes("4 of 23"), a.body);
});

Deno.test("an empty roadmap says so instead of reporting zero of zero", () => {
  const a = answerFromData("my roadmap progress", {
    ...ctx,
    roadmap: { done: 0, total: 0, next: null },
  });
  assert(a);
  assert(a.body.includes("do not have a roadmap yet"), a.body);
});

Deno.test("a real question still goes to the model", () => {
  // The allowance exists for these.
  for (
    const q of [
      "How do I explain a gap year in an interview?",
      "Is a to-do app good enough to put on my CV?",
      "Write me a message to send a recruiter on LinkedIn",
      "Should I take an unpaid internship?",
    ]
  ) {
    assertEquals(answerFromData(q, ctx), null, q);
  }
});

Deno.test("a question that matches but has no data falls through to the model", () => {
  // Rather than answering "your weakest area is undefined".
  const empty: Context = { score: { total: 0, components: {} } };
  assertEquals(answerFromData("what is my weakest area?", empty), null);
});
