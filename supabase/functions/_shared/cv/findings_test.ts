import { assert, assertEquals } from "@std/assert";
import { findings, sortFindings } from "./findings.ts";
import type { CvMetrics } from "./metrics.ts";

const base: CvMetrics = {
  chars: 2400,
  words: 420,
  pages: 1,
  bullets: 10,
  bullets_quantified: 5,
  bullets_action_led: 9,
  sections: ["contact", "education", "experience", "projects", "skills"],
  has_contact: true,
  dated_entries: 4,
  undated_entries: 0,
  latest_entry_date: "2026-01",
  placeholder_hits: 0,
  extractor: "pdf",
  truncated: false,
  ocr_confidence: null,
};

const of = (patch: Partial<CvMetrics>, skills: string[] = ["Python"]) =>
  findings({ ...base, ...patch }, skills);

const kinds = (list: ReturnType<typeof findings>) => list.map((f) => f.kind);

Deno.test("a good CV is told what is working, not only what is wrong", () => {
  const list = of({});
  assert(list.some((f) => f.severity === "good"), "nothing was praised");
  assertEquals(list.filter((f) => f.severity === "problem").length, 0);
});

Deno.test("template text is the first thing flagged", () => {
  const list = sortFindings(of({ placeholder_hits: 2 }));
  assertEquals(list[0].kind, "placeholder");
  assertEquals(list[0].severity, "problem");
});

Deno.test("no contact details is a problem, not a suggestion", () => {
  const list = of({ has_contact: false });
  const finding = list.find((f) => f.kind === "contact");
  assertEquals(finding?.severity, "problem");
});

Deno.test("no experience and no projects is one finding, not two", () => {
  const list = of({ sections: ["contact", "education", "skills"] });
  assert(kinds(list).includes("no-evidence"));
  // The generic "missing section" line must not also fire for those two, or a
  // student with neither is told the same thing three times.
  assert(!kinds(list).includes("missing-experience"));
  assert(!kinds(list).includes("missing-projects"));
});

Deno.test("bullets with no numbers are called out with the count", () => {
  const list = of({ bullets: 9, bullets_quantified: 0 });
  const finding = list.find((f) => f.kind === "no-numbers");
  assertEquals(finding?.severity, "improve");
  assert(finding!.title.includes("9"), finding!.title);
});

Deno.test("a few numbers is different advice from none", () => {
  assert(
    kinds(of({ bullets: 12, bullets_quantified: 2 })).includes("few-numbers"),
  );
  assert(kinds(of({ bullets: 12, bullets_quantified: 8 })).includes("numbers"));
});

Deno.test("a CV with no bullets says nothing about bullets", () => {
  const list = kinds(
    of({ bullets: 0, bullets_quantified: 0, bullets_action_led: 0 }),
  );
  assert(!list.includes("no-numbers"));
  assert(!list.includes("few-numbers"));
  assert(!list.includes("weak-openers"));
});

Deno.test("undated entries read as one or as many", () => {
  assert(
    of({ undated_entries: 1 }).some((f) =>
      f.title === "One entry has no dates"
    ),
  );
  assert(
    of({ undated_entries: 3 }).some((f) => f.title.startsWith("3 entries")),
  );
});

// Every number shown to a student comes from a template literal. A plain
// double-quoted string with ${...} in it compiles perfectly happily and prints
// the braces — which is exactly the bug this test was written after finding.
Deno.test("no finding leaks an uninterpolated placeholder", () => {
  const everything = [
    ...of({}),
    ...of({ words: 90, pages: 1 }),
    ...of({ pages: 4 }),
    ...of({ placeholder_hits: 1, has_contact: false, undated_entries: 2 }),
    ...of({ bullets: 3, bullets_quantified: 0, bullets_action_led: 0 }),
    ...of({ ocr_confidence: 55 }, []),
    ...of({ truncated: true }, []),
  ];
  for (const f of everything) {
    assert(!f.title.includes("${"), `title leaked: ${f.title}`);
    assert(!f.detail.includes("${"), `detail leaked: ${f.detail}`);
  }
});

Deno.test("a thin CV says how thin", () => {
  const finding = of({ words: 90 }).find((f) => f.kind === "too-thin");
  assert(finding!.detail.includes("90"), finding!.detail);
});

Deno.test("a badly read photograph says so, so the rest is not misread", () => {
  assert(kinds(of({ ocr_confidence: 40 })).includes("poor-scan"));
  assert(!kinds(of({ ocr_confidence: 95 })).includes("poor-scan"));
  assert(!kinds(of({ ocr_confidence: null })).includes("poor-scan"));
});

Deno.test("recognising no skills is advice, recognising some is praise", () => {
  assertEquals(
    of({}, []).find((f) => f.kind === "no-skills-found")?.severity,
    "improve",
  );
  const good = of({}, ["Python", "SQL"]).find((f) => f.kind === "skills-found");
  assertEquals(good?.severity, "good");
  assert(good!.detail.includes("Python"));
});

Deno.test("problems come before suggestions before praise", () => {
  const list = sortFindings(of({
    placeholder_hits: 1,
    bullets: 10,
    bullets_quantified: 8,
    undated_entries: 2,
  }));
  const order = list.map((f) => f.severity);
  assertEquals(
    order,
    [...order].sort((a, b) =>
      ({ problem: 0, improve: 1, good: 2 })[a] -
      ({ problem: 0, improve: 1, good: 2 })[b]
    ),
  );
});
