import { assert, assertEquals, assertThrows } from "@std/assert";
import { assertClean, redact } from "./redact.ts";

Deno.test("email addresses never reach the model", () => {
  const { text, found } = redact(
    "Contact me at rafiq.hossain@du.ac.bd for details.",
  );
  assertEquals(text, "Contact me at [email] for details.");
  assertEquals(found.emails, ["rafiq.hossain@du.ac.bd"]);
});

Deno.test("Bangladeshi phone numbers are caught however they are written", () => {
  const variants = [
    "+8801712345678",
    "8801712345678",
    "01712345678",
    "+880 1712 345 678",
    "01912-345678",
  ];
  for (const variant of variants) {
    const { text, found } = redact(`Call ${variant} any time.`);
    assert(!text.includes("345"), `${variant} survived redaction as "${text}"`);
    assertEquals(found.phones.length, 1, `${variant} was not detected`);
  }
});

Deno.test("national ID style numbers are removed", () => {
  const { text, found } = redact("NID 1990123456789 issued in Dhaka.");
  assert(!text.includes("1990123456789"));
  assertEquals(found.nationalIds.length, 1);
});

Deno.test("links are pulled out rather than sent as free text", () => {
  const { text, found } = redact("Portfolio: https://rafiq.dev/work and more.");
  assertEquals(text, "Portfolio: [link] and more.");
  assertEquals(found.urls, ["https://rafiq.dev/work"]);
});

Deno.test("a CV with everything in it comes out clean", () => {
  const cv = `
    Rafiq Hossain
    rafiq@example.com | 01712345678 | https://github.com/rafiq
    NID 1990123456789

    Final-year computer science student at the University of Dhaka.
    Built a shop inventory app in React and Node.
  `;
  const { text } = redact(cv);
  assertClean(text);
  assert(
    text.includes("Final-year computer science student"),
    "redaction must keep the part the model actually needs",
  );
});

Deno.test("assertClean refuses text that still contains contact details", () => {
  assertThrows(() => assertClean("reach me at rafiq@example.com"));
  assertThrows(() => assertClean("call 01712345678"));
  assertThrows(() => assertClean("NID 1990123456789"));
});

Deno.test("redaction leaves ordinary text alone", () => {
  const input =
    "Three years of Python and SQL, plus a 2024 internship at a bank.";
  const { text } = redact(input);
  assertEquals(text, input);
});
