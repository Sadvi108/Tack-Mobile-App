import { assertEquals } from "@std/assert";
import {
  chunkCv,
  firstReadPrompt,
  READERS,
  type ReadResult,
  recallGate,
} from "./first_read.ts";
import { FIRST_READ_SYSTEM } from "../ai/first_read_prompt.ts";

const CV = [
  "Rifat Hasan",
  "Dhaka",
  "",
  "SKILLS",
  "JavaScript, React, CSS, HTML, Git, TypeScript",
  "",
  "EXPERIENCE",
  "Frontend intern, bKash, Jan 2025 - Jun 2025",
  "Built React screens against REST APIs and cut page load time by 40 percent.",
  "",
  "PROJECTS",
  "Campus marketplace, 2024",
  "Wrote a JavaScript front end serving 300 weekly users on campus.",
  "",
  "EDUCATION",
  "BSc Computer Science, BUET, 2022 - 2026",
].join("\n");

Deno.test("one chunk per section, in reading order", () => {
  const chunks = chunkCv(CV);
  assertEquals(chunks.map((c) => c.section), [
    "Top",
    "Skills",
    "Experience",
    "Projects",
    "Education",
  ]);
  assertEquals(chunks.map((c) => c.index), [1, 2, 3, 4, 5]);
  assertEquals(chunks[2].text.includes("cut page load time"), true);
});

Deno.test("a long section is cut into beats of about 85 words", () => {
  const long = "EXPERIENCE\n" +
    Array.from({ length: 30 }, (_, i) => `Did task ${i} for the team well.`)
      .join("\n");
  const chunks = chunkCv(long);
  assertEquals(chunks.length > 1, true);
  for (const c of chunks) assertEquals(c.words <= 120, true);
  assertEquals(chunks.every((c) => c.section === "Experience"), true);
});

Deno.test("never more than twelve chunks", () => {
  const huge = "PROJECTS\n" +
    Array.from({ length: 400 }, (_, i) => `Line ${i} of a very long project.`)
      .join("\n");
  assertEquals(chunkCv(huge).length <= 12, true);
});

Deno.test("the prompt numbers chunks and says how much is left", () => {
  const prompt = firstReadPrompt(chunkCv(CV));
  assertEquals(prompt.includes("CHUNK 1/5"), true);
  assertEquals(
    /CHUNK 3\/5 — Experience \(\d+ words remain after this\)/.test(prompt),
    true,
  );
});

const result = (
  over: Partial<ReadResult["readers"][number]> = {},
): ReadResult => ({
  readers: [{
    persona: "recruiter",
    needle: [{ chunk: 1, value: 1 }, { chunk: 2, value: -1 }],
    quit_chunk: 3,
    sayback: "A frontend intern who builds React screens.",
    remembered: ["cut page load time by 40 percent"],
    one_action: "Put the 40 percent result in the first line.",
    ...over,
  }],
});

Deno.test("a reader may only remember what the CV says", () => {
  const { readers, dropped } = recallGate(
    result({
      remembered: [
        "cut page load time by 40 percent",
        "led a team of twenty engineers",
        "BUET",
      ],
    }),
    chunkCv(CV),
  );
  assertEquals(readers[0].remembered, ["cut page load time by 40 percent"]);
  assertEquals(dropped, 2);
});

Deno.test("spacing and case do not stop a true quote", () => {
  const { readers } = recallGate(
    result({ remembered: ["Wrote a  JAVASCRIPT front end"], quit_chunk: 0 }),
    chunkCv(CV),
  );
  assertEquals(readers[0].remembered.length, 1);
});

Deno.test("needle values and chunk numbers are held to the read", () => {
  const { readers } = recallGate(
    result({
      needle: [
        { chunk: 1, value: 5 },
        { chunk: 2, value: -9 },
        { chunk: 9, value: 1 },
        { chunk: 2, value: 1 },
      ],
      quit_chunk: 12,
    }),
    chunkCv(CV),
  );
  assertEquals(readers[0].needle, [
    { chunk: 1, value: 2 },
    { chunk: 2, value: -2 },
  ]);
  assertEquals(readers[0].quit_chunk, 0);
});

Deno.test("only the three cast readers, once each", () => {
  const r = result();
  r.readers.push(
    { ...r.readers[0] },
    { ...r.readers[0], persona: "investor" },
    { ...r.readers[0], persona: "hr_officer" },
  );
  const { readers } = recallGate(r, chunkCv(CV));
  assertEquals(readers.map((x) => x.persona), ["recruiter", "hr_officer"]);
  assertEquals(READERS.map((x) => x.id), [
    "recruiter",
    "hiring_manager",
    "hr_officer",
  ]);
});

Deno.test("a reader cannot remember what comes after they stopped", () => {
  const { readers, dropped } = recallGate(
    result({
      quit_chunk: 2,
      remembered: [
        "JavaScript, React, CSS",
        "cut page load time by 40 percent",
      ],
    }),
    chunkCv(CV),
  );
  assertEquals(readers[0].remembered, ["JavaScript, React, CSS"]);
  assertEquals(dropped, 1);
});

Deno.test("headings, placeholders and broken words are not memories", () => {
  const cv = "Rifat Hasan\nrifat@example.com\n\nWORK EXPERIENCE\n" +
    "Frontend intern at bKash building React screens";
  const chunks = chunkCv(cv.replace("rifat@example.com", "[email]"));
  const { readers } = recallGate(
    result({
      quit_chunk: 0,
      remembered: [
        "Work experience",
        "[email]",
        "ntend intern at bK",
        "Frontend intern at bKash",
      ],
    }),
    chunks,
  );
  assertEquals(readers[0].remembered, ["Frontend intern at bKash"]);
});

Deno.test("a heading with content on the same line keeps its content", () => {
  const chunks = chunkCv(
    "Rifat Hasan\n\nEducation: BSc Computer Science, BUET\nSkills: React, Git",
  );
  const all = chunks.map((c) => c.text).join("\n");
  assertEquals(all.includes("BSc Computer Science, BUET"), true);
  assertEquals(all.includes("React, Git"), true);
  // Short enough to read as a heading, so it also opens the section.
  assertEquals(chunks.some((c) => c.section === "Skills"), true);
});

Deno.test("one very long line is still cut into beats", () => {
  const line = Array.from({ length: 400 }, (_, i) => `w${i}`).join(" ");
  const chunks = chunkCv(`PROJECTS\n${line}`);
  assertEquals(chunks.length > 1, true);
  for (const c of chunks) assertEquals(c.words <= 120, true);
});

Deno.test("a folded tail says every section it holds", () => {
  const section = (name: string) =>
    `${name}\n` +
    Array.from({ length: 4 }, (_, i) =>
      Array.from({ length: 80 }, (_, j) =>
        `${name.toLowerCase()}${i}x${j}`)
        .join(" ")).join("\n");
  const cv = [
    section("EXPERIENCE"),
    section("PROJECTS"),
    section("EDUCATION"),
    section("ACTIVITIES"),
  ].join("\n\n");
  const chunks = chunkCv(cv);
  assertEquals(chunks.length <= 12, true);
  const last = chunks[chunks.length - 1];
  // Whatever was folded in is named, so a quit point there is not
  // reported as the wrong section.
  for (const name of ["Education", "Activities"]) {
    const holds = last.text.includes(name.toLowerCase());
    assertEquals(!holds || last.section.includes(name), true, last.section);
  }
});

Deno.test("a stray reader is dropped and the rest kept", () => {
  const r = result();
  r.readers.push(
    { ...r.readers[0], persona: "Recruiter" },
    { ...r.readers[0], persona: "hiring_manager", sayback: "" },
    { ...r.readers[0], persona: "hr_officer" },
  );
  const { readers } = recallGate(r, chunkCv(CV));
  assertEquals(readers.map((x) => x.persona), ["recruiter", "hr_officer"]);
});

// A reader once retold a CV as "his degree". The CV never says how the
// student is referred to, so every reader says "they".
Deno.test("readers refer to the student as they", () => {
  assertEquals(/call the student "they"/.test(FIRST_READ_SYSTEM), true);
  assertEquals(/never "he" or "she"/.test(FIRST_READ_SYSTEM), true);
});
