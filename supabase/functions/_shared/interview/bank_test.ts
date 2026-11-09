import { assertEquals } from "@std/assert";
import {
  parseResolution,
  questionsFor,
  type QuestionsPorts,
  servedSet,
  slugifyRole,
} from "./bank.ts";

// The same table is in test_build.py and in 0096's checks: a role slugged
// differently in TypeScript, Python and SQL is a bank miss for no reason.
Deno.test("slugifyRole matches the generator and the database", () => {
  const cases: Record<string, string> = {
    "Frontend developer": "frontend-developer",
    "Backend developer": "backend-developer",
    "Data analyst": "data-analyst",
    "Digital marketer": "digital-marketer",
    "HR executive": "hr-executive",
    "Business analyst": "business-analyst",
    "Graphic designer": "graphic-designer",
    "QA engineer": "qa-engineer",
    "Accountant": "accountant",
    "Content writer": "content-writer",
    "UI and UX designer": "ui-and-ux-designer",
    "C++ developer": "c-developer",
    "  Data   analyst  ": "data-analyst",
    "  বাংলা  ": "",
    "": "",
    "undecided": "undecided",
  };
  for (const [text, slug] of Object.entries(cases)) {
    assertEquals(slugifyRole(text), slug, text);
  }
});

const resolution = {
  role_slug: "civil-site-engineer",
  role_title: "Civil site engineer",
  field_slug: "civil-engineering",
  field_name: "Civil engineering",
  resolved_from: "your_path",
  hint_matched: false,
};

Deno.test("parseResolution accepts the shape of contract C3.4", () => {
  assertEquals(parseResolution(resolution), resolution);
  assertEquals(
    parseResolution({ ...resolution, extra: "ignored" }),
    resolution,
  );
});

Deno.test("parseResolution rejects anything malformed", () => {
  const { field_name: _, ...missing } = resolution;
  assertEquals(parseResolution(missing), null);
  assertEquals(parseResolution({ ...resolution, role_slug: 7 }), null);
  assertEquals(parseResolution({ ...resolution, role_slug: "" }), null);
  assertEquals(parseResolution({ ...resolution, role_title: null }), null);
  assertEquals(parseResolution({ ...resolution, hint_matched: "false" }), null);
  for (const value of [null, undefined, "x", 3, [resolution]]) {
    assertEquals(parseResolution(value), null);
  }
});

const five = [
  {
    question: "One?",
    category: "Basics",
    key_points: ["A", "B"],
    pool_id: "p1",
  },
  { question: "Two?", category: "Basics" },
  { question: "Three?", category: "Practice" },
  { question: "Four?", category: "Practice" },
  { question: "Five?", category: "Judgement" },
];

Deno.test("servedSet slices to the count and keeps key points and pool ids", () => {
  const served = servedSet(five, 3);
  assertEquals(served, [
    {
      question: "One?",
      category: "Basics",
      key_points: ["A", "B"],
      pool_id: "p1",
    },
    { question: "Two?", category: "Basics" },
    { question: "Three?", category: "Practice" },
  ]);
});

Deno.test("servedSet drops items without a question and defaults the category", () => {
  const served = servedSet(
    [
      null,
      { category: "Basics" },
      { question: 4 },
      { question: "  " },
      {
        question: "Kept?",
        category: 9,
        key_points: ["Yes", 2, ""],
        pool_id: 1,
      },
      ...five,
    ],
    2,
  );
  assertEquals(served, [
    { question: "Kept?", category: "General", key_points: ["Yes"] },
    {
      question: "One?",
      category: "Basics",
      key_points: ["A", "B"],
      pool_id: "p1",
    },
  ]);
});

Deno.test("servedSet returns null for no set or too few questions", () => {
  // A null questions column used to throw and fail the whole request.
  assertEquals(servedSet(null, 3), null);
  assertEquals(servedSet(undefined, 3), null);
  assertEquals(servedSet({ questions: five }, 3), null);
  assertEquals(servedSet(five, 6), null);
  assertEquals(servedSet([{ category: "x" }, ...five.slice(0, 2)], 3), null);
});

/** Fake ports that record what they were asked. */
function ports(
  sets: Record<string, unknown>,
  resolved: unknown = resolution,
) {
  const reads: string[] = [];
  const hints: string[] = [];
  const port: QuestionsPorts = {
    readSet: (slug) => {
      reads.push(slug);
      return Promise.resolve(sets[slug] ?? null);
    },
    resolve: (hint) => {
      hints.push(hint);
      return Promise.resolve(resolved);
    },
  };
  return { port, reads, hints };
}

Deno.test("a role in the bank is served as it is", async () => {
  const { port, reads, hints } = ports({ "qa-engineer": five });
  const got = await questionsFor(port, "QA engineer", "QA engineer", 5);
  assertEquals(got?.role, "qa-engineer");
  assertEquals(got?.resolvedFrom, "exact");
  assertEquals(got?.questions.length, 5);
  assertEquals(reads, ["qa-engineer"]);
  assertEquals(hints, []);
});

Deno.test("a role not in the bank gets the student's nearest role", async () => {
  const { port, reads, hints } = ports({ "civil-site-engineer": five });
  const got = await questionsFor(
    port,
    "Structural engineer",
    "Structural engineer",
    5,
  );
  assertEquals(got?.role, "civil-site-engineer");
  assertEquals(got?.resolvedFrom, "your_path");
  assertEquals(reads, ["structural-engineer", "civil-site-engineer"]);
  assertEquals(hints, ["Structural engineer"]);
});

Deno.test("a role written in Bangla resolves instead of crashing", async () => {
  // It used to slug to "-" and miss; now it never reads an empty slug.
  const { port, reads, hints } = ports({ "civil-site-engineer": five });
  const got = await questionsFor(port, "সিভিল ইঞ্জিনিয়ার", "সিভিল ইঞ্জিনিয়ার", 5);
  assertEquals(got?.role, "civil-site-engineer");
  assertEquals(reads, ["civil-site-engineer"]);
  assertEquals(hints, ["সিভিল ইঞ্জিনিয়ার"]);
});

Deno.test("a set with a null questions column falls through to the nearest role", async () => {
  const { port } = ports({ "qa-engineer": null, "civil-site-engineer": five });
  const got = await questionsFor(port, "QA engineer", "QA engineer", 5);
  assertEquals(got?.role, "civil-site-engineer");
});

Deno.test("nothing to serve is a miss, never a model call", async () => {
  // No set for the resolved role.
  assertEquals(
    await questionsFor(ports({}).port, "QA engineer", "QA engineer", 5),
    null,
  );
  // A resolution that is not the contract's shape.
  assertEquals(
    await questionsFor(
      ports({ "civil-site-engineer": five }, { role_slug: 1 }).port,
      "QA engineer",
      "QA engineer",
      5,
    ),
    null,
  );
  // Too few questions for the count asked.
  assertEquals(
    await questionsFor(
      ports({ "qa-engineer": five }).port,
      "QA engineer",
      "QA engineer",
      10,
    ),
    null,
  );
});

Deno.test("a failing read is a miss, not a crash", async () => {
  const port: QuestionsPorts = {
    readSet: () => Promise.reject(new Error("network")),
    resolve: () => Promise.reject(new Error("network")),
  };
  assertEquals(await questionsFor(port, "QA engineer", "QA engineer", 5), null);
});
