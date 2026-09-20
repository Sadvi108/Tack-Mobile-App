import { assert, assertEquals } from "@std/assert";
import { jsearch, normalizeJsearch } from "./jsearch.ts";

const row = {
  job_id: "bd-1",
  job_title: "Graduate accountant",
  employer_name: "Example employer",
  job_apply_link: "https://example.com/jobs?id=1",
  job_country: "BD",
  job_city: "Dhaka",
  job_is_remote: false,
  job_employment_type: "Full-time",
  job_description: "<p>Excel and accounting</p>",
};

Deno.test("Bangladesh on-site roles carry salary, description, and employment type", () => {
  const jobs = normalizeJsearch([{
    ...row,
    job_min_salary: 20000,
    job_max_salary: 30000,
    job_salary_currency: "BDT",
    job_salary_period: "MONTH",
    job_posted_at_datetime_utc: "bad date",
  }], { remote: false });
  assertEquals(jobs.length, 1);
  assertEquals(jobs[0].location, "Dhaka, BD, Bangladesh");
  assertEquals(jobs[0].salaryText, "BDT 20000–30000 / month");
  assertEquals(jobs[0].description, "Excel and accounting");
  assertEquals(jobs[0].employmentType, "Full-time");
  assertEquals(jobs[0].postedAt, null);
});

Deno.test("in-person results exclude remote, overseas, and unstated arrangements", () => {
  assertEquals(
    normalizeJsearch([
      { ...row, job_is_remote: true },
      { ...row, job_country: "US" },
      { ...row, job_is_remote: null },
      { ...row, job_is_remote: "false" },
      row,
    ], { remote: false }).length,
    1,
  );
});

Deno.test("invalid rows and unsafe links cannot poison valid results", () => {
  assertEquals(
    normalizeJsearch([
      null,
      {},
      { ...row, job_apply_link: "javascript:alert(1)" },
      { ...row, job_id: "" },
      row,
    ], {}).length,
    1,
  );
});

Deno.test("missing currency does not invent a salary or currency", () => {
  assertEquals(
    normalizeJsearch([{ ...row, job_min_salary: 100 }], {})[0].salaryText,
    null,
  );
});

Deno.test("JSearch is optional, sends Bangladesh filters, and reuses a warm request", async () => {
  const originalFetch = globalThis.fetch;
  const oldKey = Deno.env.get("JSEARCH_API_KEY");
  let calls = 0;
  try {
    Deno.env.delete("JSEARCH_API_KEY");
    assertEquals((await jsearch({})).problem, "not configured");
    Deno.env.set("JSEARCH_API_KEY", "fixture-only");
    globalThis.fetch = (input, init) => {
      calls++;
      const url = new URL(String(input));
      assertEquals(url.origin, "https://api.openwebninja.com");
      assertEquals(url.searchParams.get("country"), "bd");
      assertEquals(
        url.searchParams.get("query"),
        "accountant in Dhaka, Bangladesh",
      );
      assertEquals(url.searchParams.get("employment_types"), "FULLTIME");
      assertEquals(url.searchParams.get("work_from_home"), null);
      assertEquals(new Headers(init?.headers).get("x-api-key"), "fixture-only");
      assert(init?.signal);
      return Promise.resolve(
        Response.json({
          status: "OK",
          data: [row, { ...row, job_is_remote: true }],
        }),
      );
    };
    const query = {
      q: "accountant",
      location: "Dhaka",
      remote: false,
      kind: "full_time",
    };
    const results = await Promise.all([jsearch(query), jsearch(query)]);
    assertEquals(results[0].listings.length, 1);
    await jsearch(query);
    assertEquals(calls, 1);
  } finally {
    globalThis.fetch = originalFetch;
    if (oldKey == null) Deno.env.delete("JSEARCH_API_KEY");
    else Deno.env.set("JSEARCH_API_KEY", oldKey);
  }
});

Deno.test("provider failures stay isolated and are not cached", async () => {
  const originalFetch = globalThis.fetch;
  const oldKey = Deno.env.get("JSEARCH_API_KEY");
  try {
    Deno.env.set("JSEARCH_API_KEY", "fixture-only");
    globalThis.fetch = () =>
      Promise.resolve(new Response("rate limited", { status: 429 }));
    assertEquals((await jsearch({ q: "nurse" })).problem, "http 429");
    globalThis.fetch = () =>
      Promise.resolve(Response.json({ status: "OK", data: [row] }));
    assertEquals((await jsearch({ q: "nurse" })).listings.length, 1);
    globalThis.fetch = () =>
      Promise.resolve(Response.json({ status: "ERROR", data: [] }));
    assertEquals((await jsearch({ q: "teacher" })).problem, "invalid response");
    globalThis.fetch = () => {
      throw new Error("private upstream detail");
    };
    assertEquals((await jsearch({ q: "retail" })).problem, "unreachable");
  } finally {
    globalThis.fetch = originalFetch;
    if (oldKey == null) Deno.env.delete("JSEARCH_API_KEY");
    else Deno.env.set("JSEARCH_API_KEY", oldKey);
  }
});
