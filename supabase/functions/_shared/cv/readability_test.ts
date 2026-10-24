import { assertEquals } from "@std/assert";
import {
  phoneScreens,
  readabilityFindings,
  weakPhrases,
} from "./readability.ts";

const filler = (words: number) =>
  Array.from({ length: words }, (_, i) => `word${i % 10}`).join(" ");

Deno.test("a phone screen holds about 38 by 14 characters", () => {
  assertEquals(phoneScreens("short"), 1);
  assertEquals(phoneScreens("x".repeat(38 * 14)), 1);
  assertEquals(phoneScreens("x".repeat(38 * 14 + 1)), 2);
});

Deno.test("line breaks do not count as reading", () => {
  assertEquals(phoneScreens("a\n\n\n\n\nb"), phoneScreens("a b"));
});

Deno.test("a long CV is called out, a short one is not", () => {
  const long = readabilityFindings(filler(900));
  assertEquals(long.some((f) => f.kind === "long-for-phone"), true);
  const short = readabilityFindings(filler(120));
  assertEquals(short.some((f) => f.kind === "long-for-phone"), false);
});

Deno.test("weak phrases are found with the line they sit on", () => {
  const found = weakPhrases(
    "Built a React app\nResponsible for the team website\nFamiliar with SQL and Excel\n",
  );
  assertEquals(found.map((f) => f.phrase), [
    "responsible for",
    "familiar with",
  ]);
  assertEquals(found[0].line, "Responsible for the team website");
});

Deno.test("a quoted line starts with its words, not the bullet before them", () => {
  const found = weakPhrases(
    "• Assisted in the annual report\n- Helped with stock counts\n▪ Exposure to Python",
  );
  assertEquals(found.map((f) => f.line), [
    "Assisted in the annual report",
    "Helped with stock counts",
    "Exposure to Python",
  ]);
  const finding = readabilityFindings("  •  Assisted in the annual report")
    .find((f) => f.kind === "weak-phrases")!;
  assertEquals(
    finding.detail.includes("“Assisted in the annual report”"),
    true,
  );
});

Deno.test("a weak phrase inside another word is not one", () => {
  assertEquals(weakPhrases("Unfamiliar withdrawals were fixed").length, 0);
});

Deno.test("the finding quotes at most two lines, each kept short", () => {
  const text = [
    "Helped with " + "a very long description of the task ".repeat(6),
    "Assisted in the annual report",
    "Exposure to Python",
  ].join("\n");
  const finding = readabilityFindings(text).find((f) =>
    f.kind === "weak-phrases"
  )!;
  assertEquals(finding.severity, "improve");
  assertEquals(finding.title, "3 lines undersell you");
  assertEquals(finding.detail.includes("Assisted in the annual report"), true);
  assertEquals(finding.detail.includes("Exposure to Python"), false);
  assertEquals(finding.detail.includes("…”"), true);
  assertEquals(finding.detail.length < 420, true);
});

Deno.test("a CV without weak phrases has no such finding", () => {
  assertEquals(
    readabilityFindings("Built a dashboard\nLed a team of four").some((f) =>
      f.kind === "weak-phrases"
    ),
    false,
  );
});

Deno.test("a quoted line never carries contact details", () => {
  const finding = readabilityFindings(
    "Responsible for support, write to rifat@example.com or 01712345678",
  ).find((f) => f.kind === "weak-phrases")!;
  assertEquals(finding.detail.includes("rifat@example.com"), false);
  assertEquals(finding.detail.includes("01712345678"), false);
});
