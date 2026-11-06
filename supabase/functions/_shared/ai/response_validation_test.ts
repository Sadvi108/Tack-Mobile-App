import { assertEquals } from "@std/assert";
import { validateResponse } from "./response_validation.ts";
Deno.test("nested CV entries and numeric ranges are enforced", () => {
  for (
    const education of [[null], [{ degree: 42, institution: "University" }], [{
      degree: "BSc",
      institution: "University",
      year: 5,
    }]]
  ) {
    assertEquals(
      validateResponse("parse_cv", { skills: [], quality_score: 60, education })
        .length,
      1,
    );
  }
  assertEquals(
    validateResponse("parse_cv", { skills: [], quality_score: 101 }).length,
    1,
  );
  assertEquals(
    validateResponse("parse_cv", {
      skills: [],
      quality_score: 60,
      education: [{ degree: "BSc", institution: "University", year: 2027 }],
    }),
    [],
  );
});
Deno.test("invalid feedback and coach output cannot be stored", () => {
  assertEquals(
    validateResponse("evaluate_answer", {
      score: 15,
      went_well: [],
      to_improve: [],
    }).length,
    1,
  );
});

Deno.test("a coach reply is a body and route ids, nothing else", () => {
  const body = "Try a small project this week.";
  const valid = { body, actions: [{ route: "roadmap" }] };
  assertEquals(validateResponse("coach_chat", valid), []);
  assertEquals(
    validateResponse("coach_chat", { body, actions: [] }),
    [],
    "an empty list is caught later, by checkCoachReply",
  );
  for (
    const [what, value] of [
      ["the old {reply} shape", { reply: body }],
      ["an unknown route", { body, actions: [{ route: "nowhere" }] }],
      ["path, which needs Tack's slug", { body, actions: [{ route: "path" }] }],
      ["an extra key", { ...valid, extra: true }],
      ["a label written by the model", {
        body,
        actions: [{ route: "roadmap", label: "Go" }],
      }],
      ["four actions", {
        body,
        actions: ["roadmap", "score", "paths", "profile"].map((route) => ({
          route,
        })),
      }],
      ["a 1201-character body", { ...valid, body: "a".repeat(1201) }],
      ["an empty body", { ...valid, body: "   " }],
    ] as const
  ) {
    assertEquals(validateResponse("coach_chat", value).length, 1, what);
  }
});
