import { assertEquals } from "@std/assert";
import { APIFY_JOB_ACTORS as actors } from "./apify_actors.ts";
import {
  canonicalBdjobsUrl,
  hasSupportedApifyRows,
  isBangladeshPosting,
  normalizeApifyJobs,
} from "./apify_sources.ts";

const at = "2026-10-25T02:00:00Z";
const hiper = {
  jobId: 1542126,
  url: "https://bdjobs.com/h/details/1542126",
  title: "Project accountant",
  company: "Fixture employer",
  location: "Munshiganj",
  jobType: "FullTime",
  workplace: "Work at office",
  experience: "At least 3 years",
  education: "Master's in accounting",
  postedAt: "2026-10-24T04:52:00Z",
  deadline: "2026-11-14",
  description: "Excel and accounting",
  salary: "Negotiable",
};
const vero = {
  id: "1542126",
  url: "https://jobs.bdjobs.com/jobdetails.asp?id=1542126",
  title: "Graduate accountant",
  company: { name: "Fixture employer" },
  location: {
    formatted: "Dhaka, Bangladesh",
    city: "Dhaka",
    country: "Bangladesh",
  },
  isRemote: false,
  postedDate: "2026-10-24",
  jobType: ["Full-time"],
  salary: { min: 40000, max: 60000, currency: "BDT", interval: "monthly" },
  skills: ["Excel", "Accounting"],
  description: "Prepare monthly accounts",
};
const multi = {
  id: "li-hash",
  site: "linkedin",
  title: "Graduate analyst",
  company: "Fixture employer",
  location: "Dhaka, Bangladesh",
  datePosted: "2026-10-24",
  jobType: "fulltime",
  isRemote: false,
  jobUrl:
    "https://bd.linkedin.com/jobs/view/graduate-analyst-1234567?trackingId=public",
  applyUrl: "javascript:alert(1)",
  searchLocation: "Bangladesh",
};

Deno.test("Hipersoft maps the published numeric-jobId schema to Bdjobs identity", () => {
  const [job] = normalizeApifyJobs(actors.hipersoft, [hiper], at);
  assertEquals(job.source, "bdjobs");
  assertEquals(job.externalId, "1542126");
  assertEquals(job.workplaceKnown, true);
  assertEquals(job.isRemote, false);
  assertEquals(job.salaryText, "Negotiable");
  assertEquals(job.expiresAt, "2026-11-14T18:00:00.000Z");
});

Deno.test("Vero preserves structured currency/period and does not infer onsite from false", () => {
  const [job] = normalizeApifyJobs(actors.vero, [vero], at);
  assertEquals(job.externalId, "1542126");
  assertEquals(job.url, "https://bdjobs.com/h/details/1542126");
  assertEquals(job.salaryText, "BDT 40000–60000 / monthly");
  assertEquals(job.workplaceKnown, false);
  assertEquals(
    job.description,
    "Prepare monthly accounts Skills: Excel, Accounting",
  );
});

Deno.test("different Bdjobs Actor schemas produce identical source/job identity", () => {
  const [a] = normalizeApifyJobs(actors.hipersoft, [hiper], at);
  const [b] = normalizeApifyJobs(actors.vero, [vero], at);
  assertEquals([a.source, a.externalId, a.url], [
    b.source,
    b.externalId,
    b.url,
  ]);
  assertEquals(normalizeApifyJobs(actors.vero, [vero, vero], at).length, 1);
});

Deno.test("multi-board imports only Bangladesh Bdjobs/LinkedIn postings with canonical links", () => {
  const jobs = normalizeApifyJobs(actors.multiboard, [
    multi,
    {
      ...multi,
      site: "indeed",
      jobUrl: "https://www.indeed.com/viewjob?jk=123",
    },
    { ...multi, location: "New York, US", searchLocation: "Bangladesh" },
    {
      ...multi,
      location: "Remote",
      searchLocation: "Bangladesh",
      isRemote: true,
    },
    { ...multi, location: "Gopalganj, India", searchLocation: "Bangladesh" },
    { ...multi, site: "bdjobs", jobUrl: hiper.url },
  ], at);
  assertEquals(jobs.length, 2);
  assertEquals(jobs[0].source, "linkedin");
  assertEquals(jobs[0].externalId, "1234567");
  assertEquals(jobs[0].applyUrl, "https://www.linkedin.com/jobs/view/1234567");
  assertEquals(jobs[1].source, "bdjobs");
});

Deno.test("country evidence is taken from the vacancy, with explicit foreign country winning", () => {
  assertEquals(isBangladeshPosting("Sylhet"), true);
  assertEquals(isBangladeshPosting("Dhaka", "US"), false);
  assertEquals(isBangladeshPosting("Unknown city", "BD"), true);
  assertEquals(isBangladeshPosting("Dhakasomething"), false);
  assertEquals(isBangladeshPosting("Gopalganj", undefined, false), false);
  assertEquals(
    normalizeApifyJobs(actors.vero, [{
      ...vero,
      location: { formatted: "Dhaka", country: "United States" },
    }], at).length,
    0,
  );
  assertEquals(
    normalizeApifyJobs(actors.hipersoft, [{ ...hiper, location: "Dubai" }], at)
      .length,
    0,
  );
});

Deno.test("invalid URLs, unsupported actors, invalid rows and mismatched IDs are isolated", () => {
  assertEquals(
    normalizeApifyJobs(actors.hipersoft, [
      null,
      {},
      { ...hiper, url: "https://bdjobs.com.attacker.test/h/details/1542126" },
      { ...hiper, url: "https://bdjobs.com/h/details/9999999" },
      { ...hiper, deadline: "2026-02-30" },
      hiper,
    ], at).length,
    1,
  );
  assertEquals(normalizeApifyJobs("unknown", [vero], at), []);
  assertEquals(
    canonicalBdjobsUrl("https://jobs.bdjobs.com/jobdetails.asp?id=1&id=2"),
    null,
  );
  assertEquals(canonicalBdjobsUrl("http://bdjobs.com/h/details/1"), null);
  assertEquals(
    canonicalBdjobsUrl("https://user:password@bdjobs.com/h/details/1"),
    null,
  );
});

Deno.test("missing currency or zero placeholders do not invent compensation", () => {
  for (const salary of [{ min: 0, max: 0, currency: "BDT" }, { min: 100 }]) {
    assertEquals(
      normalizeApifyJobs(actors.vero, [{ ...vero, salary }], at)[0].salaryText,
      null,
    );
  }
  assertEquals(
    normalizeApifyJobs(actors.vero, [{
      ...vero,
      salary: { max: 50000, currency: "BDT", interval: "monthly" },
    }], at)[0].salaryText,
    "Up to BDT 50000 / monthly",
  );
  assertEquals(
    normalizeApifyJobs(actors.vero, [{
      ...vero,
      salary: { min: 50000, currency: "BDT", interval: "monthly" },
    }], at)[0].salaryText,
    "From BDT 50000 / monthly",
  );
});

Deno.test("country-filtered pages can continue while schema drift fails visibly", () => {
  assertEquals(
    hasSupportedApifyRows(
      actors.multiboard,
      [{ ...multi, location: "US" }],
      at,
    ),
    true,
  );
  assertEquals(
    hasSupportedApifyRows(actors.vero, [{ wrong: "schema" }], at),
    false,
  );
});
