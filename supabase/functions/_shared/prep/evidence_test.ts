import { assertEquals } from "@std/assert";
import {
  groundBrief,
  isGrounded,
  mentions,
  type PrepBrief,
} from "./evidence.ts";

const evidence = {
  skills: ["SQL", "Excel", "Go", "C++", "Node.js"],
  projects: ["Shop inventory app", "Flood map"],
};

function brief(overrides: Partial<PrepBrief> = {}): PrepBrief {
  return {
    talking_points: [],
    likely_questions: [{ question: "Why this role?", why: "Always asked." }],
    questions_to_ask: ["What does a first month look like?"],
    gaps: [],
    ...overrides,
  };
}

Deno.test("a point backed by one of the student's skills is kept", () => {
  const { brief: kept } = groundBrief(
    brief({
      talking_points: [{
        point: "You can build their dashboards",
        evidence: "You built reports in SQL and Excel",
      }],
    }),
    evidence,
  );
  assertEquals(kept.talking_points.length, 1);
});

Deno.test("a point backed by one of the student's projects is kept", () => {
  const { brief: kept } = groundBrief(
    brief({
      talking_points: [{
        point: "You have shipped something real",
        evidence: "Your shop inventory app tracks stock for a real shop",
      }],
    }),
    evidence,
  );
  assertEquals(kept.talking_points.length, 1);
});

Deno.test("a point the student cannot back up is dropped", () => {
  const { brief: kept, dropped } = groundBrief(
    brief({
      talking_points: [{
        point: "You have led large teams",
        evidence: "You led a team of twenty at a bank",
      }],
    }),
    evidence,
  );
  assertEquals(kept.talking_points.length, 0);
  assertEquals(dropped, 1);
});

Deno.test("a skill has to appear as a whole word", () => {
  assertEquals(mentions("Good communication with clients", "Go"), false);
  assertEquals(mentions("You wrote the API in Go", "Go"), true);
  assertEquals(mentions("Three years of C++ at university", "C++"), true);
  assertEquals(mentions("The service runs on Node.js", "Node.js"), true);
  assertEquals(mentions("You know SQLite", "SQL"), false);
});

Deno.test("a shorter skill never vouches for a longer one", () => {
  assertEquals(mentions("Three years of C++ at university", "C"), false);
  assertEquals(mentions("You know C# well", "C"), false);
  assertEquals(mentions("The service runs on Node.js", "Node"), false);
  assertEquals(mentions("You wrote it in C, then in Python", "C"), true);
  assertEquals(mentions("You know SQL.", "SQL"), true);
});

Deno.test("knowing C does not erase a C# gap", () => {
  const { brief: kept } = groundBrief(
    brief({ gaps: [{ skill: "C#", how_to_prepare: "Build one small API" }] }),
    { skills: ["C"], projects: [] },
  );
  assertEquals(kept.gaps.map((g) => g.skill), ["C#"]);
});

Deno.test("a generic project title is not evidence", () => {
  const { brief: kept } = groundBrief(
    brief({
      talking_points: [{
        point: "You have shipped real work",
        evidence: "Your project for the course",
      }],
    }),
    { skills: [], projects: ["Project", "App"] },
  );
  assertEquals(kept.talking_points.length, 0);
});

Deno.test("case and spacing do not matter", () => {
  assertEquals(mentions("built in  sql", "SQL"), true);
  assertEquals(mentions("The FLOOD   MAP project", "Flood map"), true);
});

Deno.test("a gap the student already has is not a gap", () => {
  const { brief: kept } = groundBrief(
    brief({
      gaps: [
        { skill: "sql", how_to_prepare: "Practise joins" },
        { skill: "Power BI", how_to_prepare: "Rebuild one report" },
      ],
    }),
    evidence,
  );
  assertEquals(kept.gaps.map((g) => g.skill), ["Power BI"]);
});

Deno.test("fewer than two backed points is not a brief worth an action", () => {
  const one = groundBrief(
    brief({
      talking_points: [
        { point: "a", evidence: "You used SQL" },
        { point: "b", evidence: "You won a hackathon" },
      ],
    }),
    evidence,
  ).brief;
  assertEquals(isGrounded(one), false);

  const two = groundBrief(
    brief({
      talking_points: [
        { point: "a", evidence: "You used SQL" },
        { point: "b", evidence: "Your flood map project" },
      ],
    }),
    evidence,
  ).brief;
  assertEquals(isGrounded(two), true);
});

Deno.test("lists are capped so a long reply cannot flood the screen", () => {
  const many = Array.from({ length: 12 }, (_, i) => ({
    point: `p${i}`,
    evidence: "You used SQL",
  }));
  const { brief: kept } = groundBrief(
    brief({
      talking_points: many,
      questions_to_ask: Array.from({ length: 12 }, (_, i) => `q${i}`),
    }),
    evidence,
  );
  assertEquals(kept.talking_points.length, 5);
  assertEquals(kept.questions_to_ask.length, 4);
});
