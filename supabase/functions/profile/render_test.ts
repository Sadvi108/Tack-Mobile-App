import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import { PublicProfile, renderProfile } from "./render.ts";

const base: PublicProfile = {
  name: "Rafiq Hossain",
  handle: "rafiq",
  headline: "Backend developer",
  location: "Dhaka, Bangladesh",
  education: [],
  experiences: [],
  projects: [],
  certifications: [],
  skills: [],
  activities: [],
  links: [],
};

const render = (p: Partial<PublicProfile>) =>
  renderProfile({ ...base, ...p }, "https://tack.test");

Deno.test("renders the student's own details", () => {
  const html = render({ skills: ["Python", "PostgreSQL"] });
  assertStringIncludes(html, "Rafiq Hossain");
  assertStringIncludes(html, "Backend developer");
  assertStringIncludes(html, "Python · PostgreSQL");
});

// Everything on this page was typed by a student, and the page is served to
// strangers. Escaping is the whole security boundary of the renderer.
Deno.test("escapes anything a student typed", () => {
  const html = render({
    name: "<script>alert(1)</script>",
    headline: 'Backend "developer" & friend',
    projects: [{
      title: "<img src=x onerror=alert(1)>",
      summary: "A summary with <b>tags</b> in it",
    }],
  });

  assert(!html.includes("<script>alert(1)</script>"), "script tag survived");
  assert(!html.includes("<img src=x"), "img tag survived");
  assertStringIncludes(html, "&lt;script&gt;");
  assertStringIncludes(html, "&amp;");
  assertStringIncludes(html, "&quot;developer&quot;");
});

// An escaped javascript: URL is still a javascript: URL. These have to be
// dropped, not encoded.
Deno.test("refuses a link that is not http or https", () => {
  const html = render({
    projects: [{
      title: "Nasty",
      repo_url: "javascript:alert(document.cookie)",
      url: "data:text/html,<script>alert(1)</script>",
    }],
    links: [
      { kind: "github", url: "javascript:alert(1)" },
      { kind: "site", url: "https://example.com/ok" },
    ],
  });

  assert(!html.includes("javascript:"), "a javascript: url reached the page");
  assert(!html.includes("data:text/html"), "a data: url reached the page");
  assertStringIncludes(html, "https://example.com/ok");
});

Deno.test("a pasted address with no scheme still becomes a link", () => {
  const html = render({ links: [{ kind: "github", url: "github.com/rafiq" }] });
  assertStringIncludes(html, 'href="https://github.com/rafiq"');
});

Deno.test("an empty section is left out entirely", () => {
  const html = render({});
  assert(!html.includes(">Experience<"), "an empty section printed a heading");
  assert(!html.includes(">Projects<"));
});

Deno.test("a verified repository says so, an unverified one stays quiet", () => {
  const verified = render({
    projects: [{
      title: "Bus tracker",
      repo_url: "https://github.com/rafiq/bus-tracker",
      verified: true,
      language: "Dart",
      stars: 12,
    }],
  });
  assertStringIncludes(verified, "repository verified");
  assertStringIncludes(verified, "Dart");
  assertStringIncludes(verified, "12 ★");

  const unverified = render({
    projects: [{
      title: "Bus tracker",
      repo_url: "https://github.com/rafiq/bus-tracker",
      verified: false,
    }],
  });
  assert(
    !unverified.includes("repository verified"),
    "an unverified project claimed verification",
  );
});

// The rule the whole feature rests on. There is no toggle for this and no code
// path that adds it, because public_profile() never selects it — this asserts
// the renderer could not print one even if it arrived.
Deno.test("never prints a phone number", () => {
  const html = renderProfile(
    {
      ...base,
      // Deliberately smuggled in, as though the filter upstream had failed.
      ...({ phone: "+880 1711111111" } as Partial<PublicProfile>),
    } as PublicProfile,
    "https://tack.test",
  );
  assert(!html.includes("1711111111"), "a phone number reached the page");
});

Deno.test("zero stars is not shown as an achievement", () => {
  const html = render({
    projects: [{ title: "New", verified: true, stars: 0, language: "Dart" }],
  });
  assert(!html.includes("0 ★"), "a repository with no stars boasted about it");
  assertStringIncludes(html, "Dart");
});

Deno.test("dates read as months, not as timestamps", () => {
  const html = render({
    experiences: [{
      title: "Intern",
      company: "Pathao",
      start_date: "2025-06-01",
      end_date: "2025-09-01",
    }],
  });
  assertStringIncludes(html, "Jun 2025 – Sep 2025");
});

Deno.test("a current job says now", () => {
  const html = render({
    experiences: [{
      title: "Engineer",
      company: "bKash",
      start_date: "2026-01-01",
      is_current: true,
    }],
  });
  assertStringIncludes(html, "Jan 2026 – now");
});

Deno.test("the page carries no script of its own", () => {
  const html = render({ skills: ["Python"] });
  assertEquals(html.includes("<script"), false);
});
