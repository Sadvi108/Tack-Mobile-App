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
  assertEquals(validateResponse("coach_chat", { reply: null }).length, 1);
  assertEquals(
    validateResponse("coach_chat", { reply: "a".repeat(2001) }).length,
    1,
  );
  assertEquals(
    validateResponse("coach_chat", { reply: "Try a small project this week." }),
    [],
  );
});
