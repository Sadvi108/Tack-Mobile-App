import { assert, assertEquals, assertRejects } from "@std/assert";
import {
  bdjobsDeadline,
  latestBdjobsRun,
  normalizeBdjobs,
  readBdjobsPage,
} from "./bdjobs.ts";

const finishedAt = "2026-10-25T02:00:00.000Z";
const row = {
  result_type: "bdjobs-job-search",
  status: "success",
  id: "1535802",
  url: "https://bdjobs.com/h/details/1535802?ln=1",
  title: "Graduate accountant",
  company_name: "Example employer",
  location: "Dhaka",
  salary: "Tk. 18000 - 20000 (Monthly)",
  employment_type: "FullTime",
  description: null,
  education: "<p>BBA in accounting</p>",
  experience: "Excel, fresh graduates welcome",
  posted_at: "2026-10-24T11:05:00Z",
  deadline: "2026-11-30T00:00:00Z",
  workplace: "",
};

Deno.test("Bdjobs preserves source, salary and unknown workplace without inventing facts", () => {
  const [job] = normalizeBdjobs([row], finishedAt);
  assertEquals(job.externalId, row.id);
  assertEquals(job.source, "bdjobs");
  assertEquals(job.url, "https://bdjobs.com/h/details/1535802");
  assertEquals(job.salaryText, row.salary);
  assertEquals(job.workplaceKnown, false);
  assertEquals(
    job.description,
    "BBA in accounting Excel, fresh graduates welcome",
  );
  assertEquals(job.seenAt, finishedAt);
  assertEquals(job.expiresAt, "2026-11-30T18:00:00.000Z");
});

Deno.test("Bdjobs only marks explicit remote and office workplaces as known", () => {
  for (
    const [workplace, known, remote] of [
      ["Work at office", true, false],
      ["Work from home", true, true],
      ["Hybrid", false, false],
      [null, false, false],
    ] as const
  ) {
    const [job] = normalizeBdjobs([{ ...row, workplace }], finishedAt);
    assertEquals(job.workplaceKnown, known);
    assertEquals(job.isRemote, remote);
  }
});

Deno.test("Bdjobs rejects malformed, unsafe, mismatched and other-mode rows independently", () => {
  const jobs = normalizeBdjobs([
    null,
    {},
    { ...row, status: "failed" },
    { ...row, result_type: "bdjobs-company-directory" },
    { ...row, url: "javascript:alert(1)" },
    { ...row, url: "https://bdjobs.com.attacker.test/h/details/1535802" },
    { ...row, url: "https://bdjobs.com/h/details/9999999" },
    { ...row, deadline: "2026-02-30" },
    row,
    row,
  ], finishedAt);
  assertEquals(jobs.length, 1);
});

Deno.test("date-only Bdjobs deadlines cover the whole advertised day in Dhaka", () => {
  assertEquals(bdjobsDeadline("2026-10-25"), "2026-10-25T18:00:00.000Z");
  assertEquals(
    bdjobsDeadline("2026-10-25T00:00:00Z"),
    "2026-10-25T18:00:00.000Z",
  );
  assertEquals(
    bdjobsDeadline("2026-10-25T12:30:00+06:00"),
    "2026-10-25T06:30:00.000Z",
  );
  assertEquals(bdjobsDeadline("2026-02-30"), null);
  assertEquals(bdjobsDeadline("not a date"), null);
  assertEquals(bdjobsDeadline(null), null);
});

Deno.test("closed postings are returned with an expired time so cache entries close too", () => {
  const now = Date.parse(finishedAt);
  const [job] = normalizeBdjobs([{ ...row, closed: true }], finishedAt, now);
  assertEquals(job.expiresAt, finishedAt);
});

Deno.test("Apify reads one dedicated successful search task and paginates with a private header", async () => {
  const original = globalThis.fetch;
  const seen: URL[] = [];
  try {
    globalThis.fetch = (input, init) => {
      const url = new URL(String(input));
      seen.push(url);
      assertEquals(init?.method, undefined); // GET only: never charge for a run.
      assertEquals(url.searchParams.get("token"), null);
      assertEquals(
        new Headers(init?.headers).get("authorization"),
        "Bearer fixture-only",
      );
      assertEquals(init?.redirect, "error");
      assert(init?.signal);
      if (url.pathname.includes("actor-tasks")) {
        assertEquals(url.pathname, "/v2/actor-tasks/Task123/runs/last");
        assertEquals(url.searchParams.get("status"), "SUCCEEDED");
        return Promise.resolve(Response.json({
          data: {
            id: "Run123",
            actId: "fHgKbgS18BmU9mLGL",
            status: "SUCCEEDED",
            defaultDatasetId: "Dataset123",
            finishedAt: new Date().toISOString(),
          },
        }));
      }
      assertEquals(url.pathname, "/v2/datasets/Dataset123/items");
      assertEquals(url.searchParams.get("offset"), "100");
      assertEquals(url.searchParams.get("limit"), "100");
      return Promise.resolve(Response.json([row]));
    };
    const run = await latestBdjobsRun("fixture-only", "Task123");
    assertEquals(
      (await readBdjobsPage("fixture-only", { ...run, offset: 100 })).length,
      1,
    );
    assertEquals(seen.length, 2);
    await assertRejects(() => latestBdjobsRun("fixture-only", "../evil"));
    assertEquals(seen.length, 2);
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("Apify rejects stale, failed, other-actor runs and provider errors", async () => {
  const original = globalThis.fetch;
  try {
    for (
      const patch of [
        { finishedAt: "2020-01-01T00:00:00Z" },
        { status: "RUNNING" },
        { actId: "8uLZNfTd32GMjuNEt" },
      ]
    ) {
      globalThis.fetch = () =>
        Promise.resolve(Response.json({
          data: {
            id: "Run123",
            actId: "fHgKbgS18BmU9mLGL",
            status: "SUCCEEDED",
            defaultDatasetId: "Dataset123",
            finishedAt: new Date().toISOString(),
            ...patch,
          },
        }));
      await assertRejects(() => latestBdjobsRun("fixture-only", "Task123"));
    }
    globalThis.fetch = () =>
      Promise.resolve(new Response("provider detail", { status: 429 }));
    await assertRejects(
      () => latestBdjobsRun("fixture-only", "Task123"),
      Error,
      "bdjobs_http_429",
    );
    globalThis.fetch = () =>
      Promise.reject(new Error("fixture-only sensitive provider detail"));
    const failure = await assertRejects(() =>
      latestBdjobsRun("fixture-only", "Task123")
    );
    assert(failure instanceof Error);
    assertEquals(failure.message, "bdjobs_unreachable");
  } finally {
    globalThis.fetch = original;
  }
});
