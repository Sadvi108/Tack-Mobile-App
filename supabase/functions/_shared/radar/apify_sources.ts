import { z } from "zod";
import type { Listing } from "./providers.ts";
import { APIFY_JOB_ACTORS } from "./apify_actors.ts";
import { bdjobsDeadline, normalizeBdjobs } from "./bdjobs.ts";

const text = z.string().trim().max(50000).nullish().catch(null);
const flag = z.boolean().nullish().catch(null);
const amount = z.number().finite().positive().nullish().catch(null);
const strings = z.array(z.string().trim().max(500)).max(100).nullish().catch(
  null,
);

// Posting location, never searchLocation/searchTerm, establishes country.
// Districts and common city aliases cover records without a country field.
const places = [
  "Bangladesh",
  "Dhaka",
  "Chattogram",
  "Chittagong",
  "Cumilla",
  "Comilla",
  "Cox's Bazar",
  "Coxs Bazar",
  "Brahmanbaria",
  "Chandpur",
  "Feni",
  "Khagrachhari",
  "Lakshmipur",
  "Laxmipur",
  "Noakhali",
  "Rangamati",
  "Bandarban",
  "Faridpur",
  "Gazipur",
  "Gopalganj",
  "Kishoreganj",
  "Madaripur",
  "Manikganj",
  "Munshiganj",
  "Narayanganj",
  "Narsingdi",
  "Rajbari",
  "Shariatpur",
  "Tangail",
  "Bagerhat",
  "Chuadanga",
  "Jashore",
  "Jessore",
  "Jhenaidah",
  "Khulna",
  "Kushtia",
  "Magura",
  "Meherpur",
  "Narail",
  "Satkhira",
  "Jamalpur",
  "Mymensingh",
  "Netrokona",
  "Sherpur",
  "Bogra",
  "Bogura",
  "Joypurhat",
  "Naogaon",
  "Natore",
  "Chapainawabganj",
  "Pabna",
  "Rajshahi",
  "Sirajganj",
  "Dinajpur",
  "Gaibandha",
  "Kurigram",
  "Lalmonirhat",
  "Nilphamari",
  "Panchagarh",
  "Rangpur",
  "Thakurgaon",
  "Habiganj",
  "Moulvibazar",
  "Sunamganj",
  "Sylhet",
  "Barguna",
  "Barishal",
  "Barisal",
  "Bhola",
  "Jhalokati",
  "Patuakhali",
  "Pirojpur",
  "Savar",
  "Tongi",
  "Dhanmondi",
  "Gulshan",
  "Banani",
  "Tejgaon",
  "Agrabad",
];
const placePattern = new RegExp(
  `(?:^|[^\\p{L}\\p{N}])(?:${places.join("|")})(?:$|[^\\p{L}\\p{N}])`,
  "iu",
);
export function isBangladeshPosting(
  location: string | null,
  country?: string | null,
  allowDistrict = true,
): boolean {
  if (country?.trim()) return /^(bd|bangladesh)$/i.test(country.trim());
  if (!allowDistrict) return /\bbangladesh\b/iu.test(location ?? "");
  return placePattern.test(location ?? "");
}

function plain(value: string | null | undefined, max = 4000): string | null {
  return value?.replace(/<[^>]*>/g, " ").replace(
    /&(?:nbsp|amp|quot|lt|gt);/gi,
    " ",
  )
    .replace(/\s+/g, " ").trim().slice(0, max) || null;
}

function publicUrl(value: string): URL | null {
  try {
    const url = new URL(value);
    return url.protocol === "https:" && !url.username && !url.password &&
        !url.port
      ? url
      : null;
  } catch {
    return null;
  }
}

/** Old and new Bdjobs links share the same source/job identity. */
export function canonicalBdjobsUrl(
  value: string,
  expectedId?: string,
): { id: string; url: string } | null {
  const url = publicUrl(value);
  if (
    !url ||
    !["bdjobs.com", "www.bdjobs.com", "jobs.bdjobs.com"].includes(url.hostname)
  ) return null;
  let id = /^\/h\/details\/(\d+)\/?$/.exec(url.pathname)?.[1];
  if (!id && /^\/jobdetails\.asp$/i.test(url.pathname)) {
    const ids = [...url.searchParams.entries()].filter(([key]) =>
      /^(id|jobid)$/i.test(key)
    );
    if (ids.length === 1 && /^\d+$/.test(ids[0][1])) id = ids[0][1];
  }
  return id && (!expectedId || id === expectedId)
    ? { id, url: `https://bdjobs.com/h/details/${id}` }
    : null;
}

function canonicalLinkedinUrl(
  value: string,
): { id: string; url: string } | null {
  const url = publicUrl(value);
  if (
    !url ||
    !["www.linkedin.com", "linkedin.com", "bd.linkedin.com"].includes(
      url.hostname,
    )
  ) return null;
  const id = /^\/jobs\/view\/(?:[^/]*-)?(\d+)\/?$/.exec(url.pathname)?.[1];
  return id ? { id, url: `https://www.linkedin.com/jobs/view/${id}` } : null;
}

type Fields = {
  source: "bdjobs" | "linkedin";
  identity: { id: string; url: string };
  title: string;
  location: string | null;
  company?: string | null;
  workplace?: string | null;
  remote?: boolean | null;
  employment?: string | null;
  description?: string | null;
  salary?: string | null;
  posted?: string | null;
  deadline?: string | null;
  experience?: string | null;
  closed?: boolean | null;
};

function listing(
  fields: Fields,
  finishedAt: string,
  now: number,
): Listing | null {
  const expiry = bdjobsDeadline(fields.deadline);
  if (fields.deadline && !expiry) return null;
  const workplace = fields.workplace?.trim().toLowerCase() ?? "";
  const remote = fields.remote === true ||
    /^(remote|work from home|work at home)$/.test(workplace);
  // false remote flags can also mean hybrid or unstated; do not infer onsite.
  const known = remote ||
    /^(on[ -]?site|office|work at office)$/.test(workplace);
  const date = Date.parse(fields.posted ?? "");
  return {
    source: fields.source,
    externalId: fields.identity.id,
    title: fields.title,
    url: fields.identity.url,
    applyUrl: fields.identity.url,
    company: plain(fields.company, 500),
    location: plain(fields.location, 500),
    isRemote: remote,
    workplaceKnown: known,
    employmentType: plain(fields.employment, 120),
    description: plain(fields.description),
    salaryText: plain(fields.salary, 500),
    level: plain(fields.experience, 500),
    category: null,
    postedAt: Number.isFinite(date) ? new Date(date).toISOString() : null,
    expiresAt: fields.closed ? new Date(now).toISOString() : expiry,
    seenAt: finishedAt,
  };
}

const hipersoftSchema = z.object({
  jobId: z.union([
    z.number().int().positive().safe(),
    z.string().regex(/^\d+$/),
  ]).transform(String),
  url: z.string().url(),
  title: z.string().trim().min(1).max(500),
  company: text,
  location: text,
  workplace: text,
  jobType: text,
  experience: text,
  education: text,
  description: text,
  summary: text,
  salary: text,
  salaryRange: text,
  postedAt: text,
  deadline: text,
});
const veroSchema = z.object({
  id: z.string().regex(/^\d+$/),
  url: z.string().url(),
  title: z.string().trim().min(1).max(500),
  company: z.object({ name: text }).nullish().catch(null),
  location: z.object({ formatted: text, city: text, country: text }),
  isRemote: flag,
  jobType: strings,
  postedDate: text,
  deadline: text,
  experienceRange: text,
  description: text,
  skills: strings,
  salary: z.object({ min: amount, max: amount, currency: text, interval: text })
    .nullish().catch(null),
});
const multiSchema = z.object({
  site: z.enum(["bdjobs", "linkedin"]),
  jobUrl: z.string().url(),
  title: z.string().trim().min(1).max(500),
  company: text,
  location: text,
  country: text,
  datePosted: text,
  jobType: text,
  isRemote: flag,
  workplace: text,
  salaryMin: amount,
  salaryMax: amount,
  salaryCurrency: text,
  salaryInterval: text,
  description: text,
});

function salary(
  min: number | null | undefined,
  max: number | null | undefined,
  currency: string | null | undefined,
  interval: string | null | undefined,
): string | null {
  if (!currency || ![min, max].some((value) => value != null)) return null;
  if (min != null && max != null && min > max) return null;
  const range = min != null && max != null
    ? `${currency} ${min === max ? min : `${min}–${max}`}`
    : min != null
    ? `From ${currency} ${min}`
    : `Up to ${currency} ${max}`;
  return `${range}${interval ? ` / ${interval}` : ""}`;
}

export function hasSupportedApifyRows(
  actorId: string,
  rows: unknown[],
  finishedAt: string,
): boolean {
  if (actorId === APIFY_JOB_ACTORS.scrapingmonkey) {
    return normalizeBdjobs(rows, finishedAt).length > 0;
  }
  const schema = actorId === APIFY_JOB_ACTORS.hipersoft
    ? hipersoftSchema
    : actorId === APIFY_JOB_ACTORS.vero
    ? veroSchema
    : actorId === APIFY_JOB_ACTORS.multiboard
    ? multiSchema
    : null;
  return schema != null && rows.some((row) => schema.safeParse(row).success);
}

/** Actor-specific validation: wrong schemas, unsafe links and overseas rows are skipped. */
export function normalizeApifyJobs(
  actorId: string,
  rows: unknown[],
  finishedAt: string,
  now = Date.now(),
): Listing[] {
  if (actorId === APIFY_JOB_ACTORS.scrapingmonkey) {
    return normalizeBdjobs(rows, finishedAt, now).filter((job) =>
      isBangladeshPosting(job.location)
    );
  }
  const jobs = new Map<string, Listing>();
  for (const raw of rows) {
    let fields: Fields | null = null;
    if (actorId === APIFY_JOB_ACTORS.hipersoft) {
      const parsed = hipersoftSchema.safeParse(raw);
      if (!parsed.success) continue;
      const r = parsed.data, identity = canonicalBdjobsUrl(r.url, r.jobId);
      if (!identity || !isBangladeshPosting(r.location ?? null)) continue;
      fields = {
        source: "bdjobs",
        identity,
        title: r.title,
        location: r.location ?? null,
        company: r.company,
        workplace: r.workplace,
        employment: r.jobType,
        description: [r.description ?? r.summary, r.education, r.experience]
          .filter(Boolean).join("\n"),
        salary: r.salary ?? r.salaryRange,
        posted: r.postedAt,
        deadline: r.deadline,
        experience: r.experience,
      };
    } else if (actorId === APIFY_JOB_ACTORS.vero) {
      const parsed = veroSchema.safeParse(raw);
      if (!parsed.success) continue;
      const r = parsed.data, identity = canonicalBdjobsUrl(r.url, r.id);
      const location = r.location.formatted ?? r.location.city ??
        r.location.country ?? null;
      if (!identity || !isBangladeshPosting(location, r.location.country)) {
        continue;
      }
      fields = {
        source: "bdjobs",
        identity,
        title: r.title,
        location,
        company: r.company?.name,
        remote: r.isRemote,
        employment: r.jobType?.join(" "),
        description: [
          r.description,
          r.skills?.length ? `Skills: ${r.skills.join(", ")}` : null,
          r.experienceRange,
        ].filter(Boolean).join("\n"),
        salary: salary(
          r.salary?.min,
          r.salary?.max,
          r.salary?.currency,
          r.salary?.interval,
        ),
        posted: r.postedDate,
        deadline: r.deadline,
        experience: r.experienceRange,
      };
    } else if (actorId === APIFY_JOB_ACTORS.multiboard) {
      const parsed = multiSchema.safeParse(raw);
      if (!parsed.success) continue;
      const r = parsed.data;
      const identity = r.site === "bdjobs"
        ? canonicalBdjobsUrl(r.jobUrl)
        : canonicalLinkedinUrl(r.jobUrl);
      if (
        !identity ||
        !isBangladeshPosting(r.location ?? null, r.country, r.site === "bdjobs")
      ) {
        continue;
      }
      fields = {
        source: r.site,
        identity,
        title: r.title,
        location: r.location ?? null,
        company: r.company,
        workplace: r.workplace,
        remote: r.isRemote,
        employment: r.jobType,
        description: r.description,
        posted: r.datePosted,
        salary: salary(
          r.salaryMin,
          r.salaryMax,
          r.salaryCurrency,
          r.salaryInterval,
        ),
      };
    }
    if (fields) {
      const job = listing(fields, finishedAt, now);
      if (job) jobs.set(`${job.source}:${job.externalId}`, job);
    }
  }
  return [...jobs.values()];
}
