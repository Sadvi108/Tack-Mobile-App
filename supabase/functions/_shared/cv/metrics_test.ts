import { assert, assertEquals } from "@std/assert";

import { latestDate, measure } from "./metrics.ts";
import {
  extractDocument,
  isExtractable,
  normalise,
  UnreadableDocument,
} from "./extract.ts";
import { looksLikeImage, repairOcrText } from "./ocr.ts";
import { assertClean, redact } from "../ai/redact.ts";
import { SAMPLE_CV_PDF_BASE64 } from "./fixture_pdf.ts";

const TODAY = new Date("2026-08-29T00:00:00Z");
const opts = { pages: 1, truncated: false, extractor: "unpdf", today: TODAY };

const GOOD_CV = `Rifat Hasan
rifat.hasan@example.com +8801712345678

SKILLS
JavaScript, React, CSS, Git

EXPERIENCE
Frontend intern, bKash, Jan 2026 - Jun 2026
Built React screens against REST APIs and cut load time by 40 percent.
Shipped responsive breakpoints across 12 templates using CSS.

PROJECTS
Campus marketplace, 2025
Wrote a JavaScript front end serving 300 weekly users on campus.

EDUCATION
BSc Computer Science, BUET, 2022 - 2026`;

Deno.test("sections are found from their headings", () => {
  const m = measure(GOOD_CV, opts);
  for (
    const s of ["skills", "experience", "projects", "education", "contact"]
  ) {
    assert(m.sections.includes(s), `missing ${s} in ${m.sections.join(",")}`);
  }
});

Deno.test("contact is detected from the details themselves, not just a heading", () => {
  const m = measure("Rifat Hasan\nrifat@example.com\n\nSKILLS\nGit", opts);
  assertEquals(m.has_contact, true);
  assert(m.sections.includes("contact"));
});

Deno.test("a CV with no email and no phone has no contact", () => {
  const m = measure("Rifat Hasan\n\nSKILLS\nGit and React and CSS", opts);
  assertEquals(m.has_contact, false);
});

Deno.test("bullets are the prose lines and nothing else", () => {
  const m = measure(GOOD_CV, opts);
  // Three prose lines. Headings and the name are too short; the skills list,
  // the role header and the degree line are all excluded on purpose.
  assertEquals(m.bullets, 3);
  assertEquals(m.bullets_action_led, 3);
  assertEquals(m.bullets_quantified, 3);
});

Deno.test("a skills list is not counted as three failed bullets", () => {
  const m = measure(
    "SKILLS\nJavaScript, React, CSS, Git, TypeScript, SQL",
    opts,
  );
  assertEquals(m.bullets, 0);
});

Deno.test("an entry header is not a bullet, but a verb-led line with a year is", () => {
  const text = [
    "EXPERIENCE",
    "Frontend intern, bKash, Jan 2026 - Jun 2026",
    "Led the 2025 orientation programme for 200 new students.",
  ].join("\n");
  const m = measure(text, opts);
  assertEquals(m.bullets, 1);
  assertEquals(m.bullets_action_led, 1);
});

Deno.test("a year is not a metric", () => {
  const text =
    "EXPERIENCE\nBuilt the college website during 2024 and into 2025.";
  const m = measure(text, opts);
  assertEquals(m.bullets, 1);
  assertEquals(m.bullets_quantified, 0);
});

Deno.test("'was responsible for' is not an action verb", () => {
  // The phrasing action_language exists to discourage. It is not in the verb
  // list, so a CV written entirely this way scores zero on that component.
  const m = measure(
    "EXPERIENCE\nWas responsible for the payments integration.",
    opts,
  );
  assertEquals(m.bullets, 1);
  assertEquals(m.bullets_action_led, 0);
});

Deno.test("a real number is a metric", () => {
  const text =
    "EXPERIENCE\nCut the page load time by 40 percent during 2024 overall.";
  const m = measure(text, opts);
  assertEquals(m.bullets_quantified, 1);
});

Deno.test("bullets opening with a verb are counted, others are not", () => {
  const text = [
    "EXPERIENCE",
    "Built a React front end for the campus marketplace.",
    "Was responsible for the React front end of the marketplace.",
  ].join("\n");
  const m = measure(text, opts);
  assertEquals(m.bullets, 2);
  assertEquals(m.bullets_action_led, 1);
});

Deno.test("a bullet glyph does not hide the verb behind it", () => {
  const m = measure(
    "EXPERIENCE\n• Shipped the new checkout flow to production.",
    opts,
  );
  assertEquals(m.bullets_action_led, 1);
});

Deno.test("entries under a dated section are counted as dated or undated", () => {
  const text = [
    "EXPERIENCE",
    "Frontend intern, bKash, Jan 2026 - Jun 2026",
    "Built React screens against the payments API.",
    "",
    "Volunteer, campus club",
    "Ran the weekly coding session for first years.",
  ].join("\n");
  const m = measure(text, opts);
  assertEquals(m.dated_entries, 1);
  assertEquals(m.undated_entries, 1);
});

Deno.test("placeholders left in a CV are counted", () => {
  const m = measure("Your name here\nTBD\nLorem ipsum dolor sit amet.", opts);
  assertEquals(m.placeholder_hits, 3);
});

Deno.test("an ordinary CV trips no placeholder", () => {
  assertEquals(measure(GOOD_CV, opts).placeholder_hits, 0);
});

Deno.test("the newest month wins", () => {
  assertEquals(latestDate("Jan 2024 and Mar 2026 and 2019", TODAY), "2026-03");
});

Deno.test("a future date is a plan, not the newest entry", () => {
  // Expected graduation in 2028 must not hand a blank CV a perfect recency.
  assertEquals(
    latestDate("Expected graduation 2028. Worked Jun 2024.", TODAY),
    "2024-06",
  );
});

Deno.test("only-future dates leave no date at all", () => {
  assertEquals(latestDate("Expected graduation 2028.", TODAY), null);
});

Deno.test("a running role counts as today", () => {
  assertEquals(
    latestDate("Frontend intern, Jan 2024 - Present", TODAY),
    "2026-08",
  );
});

Deno.test("present with no other date is still no date", () => {
  assertEquals(
    latestDate("Available to start. Present address in Dhaka.", TODAY),
    null,
  );
});

Deno.test("no dates at all", () => {
  assertEquals(latestDate("Rifat Hasan, frontend developer.", TODAY), null);
});

Deno.test("measuring is a pure function of its inputs", () => {
  assertEquals(
    JSON.stringify(measure(GOOD_CV, opts)),
    JSON.stringify(measure(GOOD_CV, opts)),
  );
});

Deno.test("normalise keeps line breaks and drops runs of blank lines", () => {
  assertEquals(normalise("a  b\r\n\n\n\nc   d  "), "a b\n\nc d");
});

Deno.test("a real PDF is read down to its text", async () => {
  const bytes = Uint8Array.from(
    atob(SAMPLE_CV_PDF_BASE64),
    (c) => c.charCodeAt(0),
  );
  const out = await extractDocument(bytes, "application/pdf");

  assertEquals(out.extractor, "unpdf");
  assertEquals(out.pages, 1);
  assertEquals(out.truncated, false);
  assert(out.text.includes("Rifat Hasan"), out.text.slice(0, 200));
  assert(out.text.includes("React"));

  const m = measure(out.text, {
    pages: out.pages,
    truncated: out.truncated,
    extractor: out.extractor,
    today: TODAY,
  });
  assertEquals(m.has_contact, true);
  assert(m.sections.includes("experience"), m.sections.join(","));
  assert(m.bullets_quantified >= 1, `quantified ${m.bullets_quantified}`);
  assert(m.bullets_action_led >= 1, `action ${m.bullets_action_led}`);
});

Deno.test("a file Tack cannot read says what to do instead", async () => {
  // A legacy binary .doc: nothing here can open it, and OCR cannot help.
  const doc = new Uint8Array([0xd0, 0xcf, 0x11, 0xe0]);
  try {
    await extractDocument(doc, "application/msword");
    throw new Error("should have thrown");
  } catch (e) {
    assert(e instanceof UnreadableDocument);
    assert(e.studentMessage.includes("PDF"), e.studentMessage);
  }
});

Deno.test("photo feedback is deferred without starting the hosted OCR engine", () => {
  for (const type of ["image/jpeg", "image/png", "image/heic"]) {
    assert(!isExtractable(type), type);
  }
  assert(isExtractable("application/pdf"));
  assert(
    isExtractable(
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ),
  );
  assert(!isExtractable("application/msword"));
  assert(!isExtractable(null));
});

Deno.test("an image it cannot decode fails in words a student can act on", async () => {
  const broken = new Uint8Array([0x89, 0x50, 0x4e, 0x47]);
  try {
    await extractDocument(broken, "image/png");
    throw new Error("should have thrown");
  } catch (e) {
    assert(e instanceof UnreadableDocument, String(e));
    assert(
      e.studentMessage.includes("photo") || e.studentMessage.includes("image"),
      e.studentMessage,
    );
  }
});

Deno.test("a PDF with no text layer is refused rather than scored on nothing", async () => {
  // A valid, parseable PDF whose only page carries no text.
  const empty = new TextEncoder().encode(
    "%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n" +
      "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n" +
      "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>\nendobj\n" +
      "trailer\n<< /Size 4 /Root 1 0 R >>\n%%EOF\n",
  );
  try {
    await extractDocument(empty, "application/pdf");
    throw new Error("should have thrown");
  } catch (e) {
    assert(e instanceof UnreadableDocument, String(e));
  }
});

// ---------------------------------------------------------------- OCR repair
//
// These guard a privacy hole, not a formatting nicety. Tesseract reads
// "rifat.hasan@example.com" as "rifat. hasan @example.com", which the redaction
// regexes do not match — so before the repair existed the address survived
// redact(), survived assertClean(), and would have gone to the model.

Deno.test("OCR spacing inside an address is closed up", () => {
  assertEquals(
    repairOcrText("rifat. hasan @example.com"),
    "rifat.hasan@example.com",
  );
  assertEquals(repairOcrText("rifat @ example . com"), "rifat@example.com");
});

Deno.test("and the repaired address is then actually redacted", () => {
  const raw = "rifat. hasan @example.com +8801712345678";

  // What used to happen: nothing found, and the address went out as written.
  assertEquals(redact(raw).found.emails.length, 0);

  const repaired = repairOcrText(raw);
  const cleaned = redact(repaired);
  assertEquals(cleaned.found.emails, ["rifat.hasan@example.com"]);
  assert(!cleaned.text.includes("example.com"), cleaned.text);
  assertClean(cleaned.text);
});

Deno.test("a spaced address the repair missed still refuses to be sent", () => {
  // The backstop. A heuristic that fails quietly is not a safeguard.
  let threw = false;
  try {
    assertClean("contact me at rifat @ example . com any time");
  } catch {
    threw = true;
  }
  assert(threw, "assertClean let a spaced address through");
});

Deno.test("but an at-sign in ordinary prose is not an address", () => {
  // Each of these was a false positive at some point while writing the check,
  // and each would have refused a perfectly good CV.
  assertClean("Handled 50 @ 3.5 hours per week and 12 @ 2.5 on weekends");
  assertClean("Reduced cost @ scale. Shipped 4 features.");
  assertClean("Worked @ bKash. Built the payments screen.");
  assertClean("Rated 5 @ 2.0 average. Improved it.");
});

Deno.test("and prose containing an at-sign survives the repair unchanged", () => {
  const prose = "Reduced cost @ scale. Shipped 4 features.";
  assertEquals(repairOcrText(prose), prose);
});

Deno.test("a link is put back together too", () => {
  assertEquals(
    repairOcrText("github . com / rifat"),
    "github.com/rifat",
  );
});

Deno.test("ordinary sentences are left alone", () => {
  const prose =
    "Built React screens. Shipped responsive breakpoints. Cut load time by 40 percent.";
  assertEquals(repairOcrText(prose), prose);
});

Deno.test("metrics record whether the text was read or guessed at", () => {
  const fromPdf = measure(GOOD_CV, opts);
  assertEquals(fromPdf.ocr_confidence, null);

  const fromPhoto = measure(GOOD_CV, {
    ...opts,
    extractor: "ocr",
    confidence: 92,
  });
  assertEquals(fromPhoto.ocr_confidence, 92);
  assertEquals(fromPhoto.extractor, "ocr");
});

Deno.test("what does and does not look like a photograph", () => {
  const pad = (head: number[]) =>
    Uint8Array.from([...head, ...new Array(2048).fill(0)]);

  assert(looksLikeImage(pad([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])));
  assert(looksLikeImage(pad([0xff, 0xd8, 0xff])));

  // Four bytes that begin like a PNG and then stop. Tesseract throws from
  // inside its own worker on this, which is not catchable at the call site.
  assert(!looksLikeImage(Uint8Array.from([0x89, 0x50, 0x4e, 0x47])));
  assert(
    !looksLikeImage(pad([0x25, 0x50, 0x44, 0x46])),
    "a PDF is not an image",
  );
  assert(!looksLikeImage(new Uint8Array(0)));
});
