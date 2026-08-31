import { assert, assertEquals } from "@std/assert";
import { broaden, dedupe, hashUrl, type Listing } from "./providers.ts";

function listing(url: string, title = "Backend developer"): Listing {
  return {
    source: "aijobs",
    externalId: url,
    title,
    company: "Acme",
    location: "Dhaka",
    isRemote: false,
    employmentType: null,
    description: null,
    url,
    applyUrl: null,
    salaryText: null,
    category: null,
    level: null,
    postedAt: null,
  };
}

Deno.test("the same opening from two boards is shown once", () => {
  const out = dedupe([
    listing("https://jobs.example/1"),
    listing("https://jobs.example/1"),
  ]);
  assertEquals(out.length, 1);
});

Deno.test("tracking parameters do not make an opening look new", () => {
  // Boards append their own referrer junk. Without stripping it, the same job
  // arrives every refresh forever and the feed fills with duplicates.
  const out = dedupe([
    listing("https://jobs.example/1"),
    listing("https://jobs.example/1?utm_source=careerjet"),
    listing("https://jobs.example/1#apply"),
    listing("https://jobs.example/1/"),
    listing("https://JOBS.example/1"),
  ]);
  assertEquals(out.length, 1);
});

Deno.test("genuinely different openings are all kept", () => {
  const out = dedupe([
    listing("https://jobs.example/1"),
    listing("https://jobs.example/2"),
    listing("https://other.example/1"),
  ]);
  assertEquals(out.length, 3);
});

Deno.test("the first board asked wins, so the order is stable", () => {
  const a = listing("https://jobs.example/1", "From board A");
  const b = listing("https://jobs.example/1", "From board B");
  assertEquals(dedupe([a, b])[0].title, "From board A");
  assertEquals(dedupe([b, a])[0].title, "From board B");
});

Deno.test("a board with no id still gets a stable one", async () => {
  const first = await hashUrl("https://jobs.example/1");
  const again = await hashUrl("https://jobs.example/1");
  const other = await hashUrl("https://jobs.example/2");

  assertEquals(first, again, "the same url must hash the same every time");
  assert(first !== other);
  assertEquals(first.length, 32);
});

Deno.test("a target role becomes a query a board can answer", () => {
  // The bug this exists to stop: "Backend developer" returned 2 results from
  // the board and "Frontend developer" returned 0, because boards match the
  // phrase. The distinctive word returns fifty.
  assertEquals(broaden("Backend developer"), "backend");
  assertEquals(broaden("Frontend developer"), "frontend");
  assertEquals(broaden("Senior Data Engineer"), "data");
  assertEquals(broaden("Junior Software Developer"), "software");
});

Deno.test("a query with nothing distinctive is left alone", () => {
  // Better to search the whole board for "graduate trainee" than to send an
  // empty query and return everything.
  assertEquals(broaden("Graduate trainee"), "Graduate trainee");
  assertEquals(broaden("intern"), "intern");
});

Deno.test("short words are dropped, not treated as distinctive", () => {
  assertEquals(broaden("UX designer"), "designer");
});
