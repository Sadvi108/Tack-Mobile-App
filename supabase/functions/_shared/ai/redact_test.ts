import { assert, assertEquals, assertThrows } from "@std/assert";
import {
  assertClean,
  containsContactDetails,
  redact,
  redactJson,
} from "./redact.ts";

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

Deno.test("redactJson cleans every string leaf and keeps the shape", () => {
  const value = {
    title: "Mail rafiq@example.com",
    nested: {
      list: ["see https://rafiq.dev/work", "call 01712345678", 7, null, true],
      deeper: [{ note: "plain words" }],
    },
    count: 3,
  };
  const out = redactJson(value);
  assertEquals(out, {
    title: "Mail [email]",
    nested: {
      list: ["see [link]", "call [phone]", 7, null, true],
      deeper: [{ note: "plain words" }],
    },
    count: 3,
  });
  // The input is left as it was.
  assertEquals(value.title, "Mail rafiq@example.com");
});

Deno.test("a link inside a field no longer breaks the JSON around it", () => {
  // Redacting the stringified object let the URL pattern run on through the
  // closing quote and the next field.
  const ctx = {
    upcoming: [{ title: "Read https://example.com/guide", on: "2026-11-08" }],
    roadmap: { next: "Email me at x@y.co" },
  };
  const whole = redact(JSON.stringify(ctx)).text;
  let brokeBefore = false;
  try {
    JSON.parse(whole);
  } catch {
    brokeBefore = true;
  }
  assert(brokeBefore, "the old way should have broken this");

  const text = JSON.stringify(redactJson(ctx));
  const back = JSON.parse(text);
  assertEquals(back.upcoming[0], { title: "Read [link]", on: "2026-11-08" });
  assertEquals(back.roadmap.next, "Email me at [email]");
  assertClean(text);
});

Deno.test("a question with contact details in it is caught before anything", () => {
  for (
    const q of [
      "Is rafiq@example.com a good email for my CV?",
      "Can you call me on 01712345678?",
      "My NID is 1990123456789, is that on my CV?",
      "write to rifat. hasan @example.com",
    ]
  ) {
    assert(containsContactDetails(q), q);
  }
  for (
    const q of [
      "How do I explain a gap year in an interview?",
      "Is https://rafiq.dev a good portfolio link?",
      "What should I do in 2027?",
    ]
  ) {
    assert(!containsContactDetails(q), q);
  }
});
