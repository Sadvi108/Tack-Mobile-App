import { assertEquals } from "@std/assert";
import { checkCoachReply } from "./reply.ts";

const facts =
  'FACTS: {"score":{"total":41,"components":{"projects":{"available":8}}},' +
  '"salary":45000,"roadmap":{"next":"Learn SQL joins"}}\n\nLATEST QUESTION:\nWhat now?';

const good = {
  body:
    "You are on 41 out of 100, and projects have 8 points left. Build one small project this week.",
  actions: [{ route: "roadmap" }],
};

Deno.test("a good reply has no problems", () => {
  assertEquals(checkCoachReply(good, { mode: "launch", factsText: facts }), []);
  assertEquals(
    checkCoachReply(good, { mode: "explore", factsText: facts }),
    [],
  );
});

Deno.test("a number the facts do not hold fails", () => {
  const reply = {
    ...good,
    body: "Most students reach 65 by June. Add a project this week.",
  };
  assertEquals(checkCoachReply(reply, { mode: "launch", factsText: facts }), [
    "body_unknown_number",
  ]);
});

Deno.test("45,000 and 45000 are the same number", () => {
  const reply = {
    ...good,
    body: "A starting salary of 45,000 taka is in your facts. Read the guide.",
  };
  assertEquals(
    checkCoachReply(reply, { mode: "launch", factsText: facts }),
    [],
  );
  assertEquals(
    checkCoachReply(reply, {
      mode: "launch",
      factsText: facts.replace("45000", "45,000"),
    }),
    [],
  );
});

Deno.test("numbers up to ten are free, but not as money or a percentage", () => {
  const small = {
    ...good,
    body: "Spend 2 hours on 3 short tasks, 10 minutes each. Start today.",
  };
  assertEquals(
    checkCoachReply(small, { mode: "launch", factsText: facts }),
    [],
  );
  // The facts hold only the digits 0, 1, 4, 5 and 8 (cited.ts's rule is a
  // digit match, so these use digits the facts do not have).
  for (
    const body of [
      "Ask for 7% more. Start today.",
      "Save 3 taka a day. Start today.",
      "It costs Tk 6. Start today.",
      "It costs ৳9. Start today.",
    ]
  ) {
    assertEquals(
      checkCoachReply({ ...good, body }, { mode: "launch", factsText: facts }),
      ["body_unknown_number"],
      body,
    );
  }
});

Deno.test("deadline fails in explore and passes in launch", () => {
  const reply = {
    ...good,
    body: "Check the deadline for the next intake. Write it down today.",
  };
  assertEquals(checkCoachReply(reply, { mode: "explore", factsText: facts }), [
    "body_mode_word",
  ]);
  assertEquals(
    checkCoachReply(reply, { mode: "launch", factsText: facts }),
    [],
  );
});

Deno.test("more than 160 words fails", () => {
  const reply = { ...good, body: "Practise every day. ".repeat(67) };
  assertEquals(checkCoachReply(reply, { mode: "launch", factsText: facts }), [
    "body_too_long",
  ]);
});

Deno.test("a reply with no chip the year may see fails", () => {
  for (
    const actions of [
      [],
      [{ route: "applications" }],
      [{ route: "nowhere" }],
    ]
  ) {
    assertEquals(
      checkCoachReply({ ...good, actions }, {
        mode: "explore",
        factsText: facts,
      }),
      ["no_allowed_action"],
      JSON.stringify(actions),
    );
  }
  assertEquals(
    checkCoachReply({ ...good, actions: [{ route: "applications" }] }, {
      mode: "launch",
      factsText: facts,
    }),
    [],
  );
});
