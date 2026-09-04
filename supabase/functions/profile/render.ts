/**
 * The published page, as HTML.
 *
 * Server-rendered rather than a Flutter web build: the page has to open
 * instantly on a mid-range Android over 3G in Dhaka, and a 2MB engine download
 * before any text appears would defeat the point of having a link at all. This
 * is about 4KB, inlines its own styles, loads no font and no script, and works
 * with images off.
 *
 * Everything it receives has already been filtered by `public_profile()`. It
 * never sees a phone number, so it cannot print one.
 */

export interface PublicProfile {
  name?: string | null;
  handle: string;
  headline?: string | null;
  location?: string | null;
  education: Array<Record<string, unknown>>;
  experiences: Array<Record<string, unknown>>;
  projects: Array<Record<string, unknown>>;
  certifications: Array<Record<string, unknown>>;
  skills: string[];
  activities: Array<Record<string, unknown>>;
  links: Array<{ kind: string; url: string }>;
}

/** Everything interpolated goes through this. */
function esc(value: unknown): string {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

/**
 * A URL safe to put in an href.
 *
 * Students paste what is in the address bar, so a missing scheme is normal and
 * gets one. Anything that is not http or https — `javascript:` above all — is
 * refused outright rather than escaped, because an escaped `javascript:` URL
 * is still a `javascript:` URL.
 */
function safeUrl(raw: unknown): string | null {
  const value = String(raw ?? "").trim();
  if (!value) return null;
  const candidate = /^[a-z][a-z0-9+.-]*:/i.test(value)
    ? value
    : `https://${value}`;
  try {
    const url = new URL(candidate);
    if (url.protocol !== "http:" && url.protocol !== "https:") return null;
    return url.toString();
  } catch {
    return null;
  }
}

const MONTHS = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
];

function month(value: unknown): string {
  const raw = String(value ?? "");
  if (!raw || raw === "null") return "";
  const date = new Date(raw);
  if (Number.isNaN(date.getTime())) return "";
  return `${MONTHS[date.getMonth()]} ${date.getFullYear()}`;
}

function range(from: unknown, to: unknown, current: unknown): string {
  const start = month(from);
  if (current) return start ? `${start} – now` : "now";
  const end = month(to);
  if (start && end) return `${start} – ${end}`;
  return start || end;
}

function section(heading: string, body: string): string {
  return body.trim()
    ? `<section><h2>${esc(heading)}</h2>${body}</section>`
    : "";
}

function entry(
  title: string,
  meta: string,
  sub?: string | null,
  body?: string | null,
): string {
  return `<article>
      <div class="row"><h3>${esc(title)}</h3>${
    meta ? `<span class="when">${esc(meta)}</span>` : ""
  }</div>
      ${sub ? `<p class="sub">${sub}</p>` : ""}
      ${body ? `<p class="body">${esc(body)}</p>` : ""}
    </article>`;
}

export function renderProfile(p: PublicProfile, origin: string): string {
  const title = p.name ? `${p.name} — Tack` : `@${p.handle} — Tack`;
  const description = [p.headline, p.location].filter(Boolean).join(" · ") ||
    "A student profile on Tack.";

  const experiences = p.experiences.map((x) =>
    entry(
      [x.title, x.company].filter(Boolean).map(esc).join(" · "),
      range(x.start_date, x.end_date, x.is_current),
      null,
      x.description as string | null,
    )
  ).join("");

  const projects = p.projects.map((pr) => {
    const repo = safeUrl(pr.repo_url);
    const site = safeUrl(pr.url);
    const facts: string[] = [];
    if (pr.verified) {
      // The whole point of the feature: a claim with something behind it.
      facts.push(
        `<span class="ok">✓ repository verified</span>`,
      );
      if (pr.language) facts.push(esc(pr.language));
      if (typeof pr.stars === "number" && pr.stars > 0) {
        facts.push(`${pr.stars} ★`);
      }
    }
    const links = [
      repo ? `<a href="${esc(repo)}" rel="nofollow noopener">Code</a>` : "",
      site ? `<a href="${esc(site)}" rel="nofollow noopener">Live</a>` : "",
    ].filter(Boolean).join(" ");

    return entry(
      String(pr.title ?? "Project"),
      pr.completed_on
        ? String(new Date(String(pr.completed_on)).getFullYear())
        : "",
      [facts.join(" · "), links].filter(Boolean).join(" &nbsp; "),
      pr.summary as string | null,
    );
  }).join("");

  const education = p.education.map((e) =>
    entry(
      String(e.institution ?? ""),
      [e.start_year, e.graduation_year].filter(Boolean).join(" – "),
      [e.degree, e.field_of_study].filter(Boolean).map(esc).join(", ") || null,
    )
  ).join("");

  const certifications = p.certifications.map((c) => {
    const url = safeUrl(c.credential_url);
    return entry(
      String(c.title ?? ""),
      c.issued_on ? String(new Date(String(c.issued_on)).getFullYear()) : "",
      [
        esc(c.issuer ?? ""),
        url ? `<a href="${esc(url)}" rel="nofollow noopener">Verify</a>` : "",
      ].filter(Boolean).join(" &nbsp; ") || null,
    );
  }).join("");

  const activities = p.activities.map((a) =>
    entry(
      String(a.title ?? ""),
      "",
      [a.role, a.organisation].filter(Boolean).map(esc).join(" · ") || null,
    )
  ).join("");

  const skills = p.skills.length
    ? `<p class="skills">${p.skills.map(esc).join(" · ")}</p>`
    : "";

  const links = p.links
    .map((l) => ({ ...l, href: safeUrl(l.url) }))
    .filter((l) => l.href)
    .map((l) =>
      `<a href="${esc(l.href)}" rel="nofollow noopener">${esc(l.kind)}</a>`
    )
    .join("");

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<meta name="description" content="${esc(description)}">
<meta property="og:title" content="${esc(p.name ?? p.handle)}">
<meta property="og:description" content="${esc(description)}">
<meta property="og:type" content="profile">
<meta property="og:url" content="${esc(origin)}/${esc(p.handle)}">
<style>
  :root { color-scheme: light dark; }
  * { box-sizing: border-box; }
  body {
    margin: 0; padding: 28px 20px 56px;
    font: 16px/1.55 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    color: #23181c; background: #f1efe8;
    max-width: 680px; margin-inline: auto;
    -webkit-text-size-adjust: 100%;
  }
  h1 { font-size: 27px; margin: 0; letter-spacing: -0.02em; }
  .headline { color: #7a1b34; margin: 3px 0 0; font-weight: 600; }
  .where { color: #6e5b61; margin: 3px 0 0; font-size: 14.5px; }
  .links { margin-top: 10px; display: flex; flex-wrap: wrap; gap: 12px; }
  .links a { font-size: 14.5px; }
  h2 {
    font-size: 11.5px; letter-spacing: 0.09em; text-transform: uppercase;
    color: #7a1b34; margin: 30px 0 10px;
  }
  article { margin-bottom: 15px; }
  .row { display: flex; gap: 12px; align-items: baseline; }
  h3 { font-size: 16px; margin: 0; flex: 1; }
  .when { color: #6e5b61; font-size: 13.5px; white-space: nowrap; }
  .sub { color: #6e5b61; margin: 1px 0 0; font-size: 14.5px; }
  .body { margin: 5px 0 0; }
  .skills { margin: 0; line-height: 1.9; }
  .ok { color: #1a6b50; font-weight: 600; }
  a { color: #7a1b34; }
  footer {
    margin-top: 42px; padding-top: 16px; border-top: 1px solid #dcd4cf;
    color: #6e5b61; font-size: 13.5px;
  }
  @media (prefers-color-scheme: dark) {
    body { color: #f2edea; background: #141110; }
    .headline, h2, a { color: #ee8fa3; }
    .where, .when, .sub, footer { color: #a9999e; }
    .ok { color: #7fd8b6; }
    footer { border-top-color: #2e2825; }
  }
</style>
</head>
<body>
<header>
  <h1>${esc(p.name ?? `@${p.handle}`)}</h1>
  ${p.headline ? `<p class="headline">${esc(p.headline)}</p>` : ""}
  ${p.location ? `<p class="where">${esc(p.location)}</p>` : ""}
  ${links ? `<nav class="links">${links}</nav>` : ""}
</header>
${section("Experience", experiences)}
${section("Projects", projects)}
${section("Education", education)}
${section("Skills", skills)}
${section("Certifications", certifications)}
${section("Activities", activities)}
<footer>Built with Tack — a careers app for students in Bangladesh.</footer>
</body>
</html>`;
}

export function renderNotFound(): string {
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Not found — Tack</title>
<style>
  body { margin:0; padding:80px 24px; text-align:center; background:#f1efe8;
    color:#23181c; font:16px/1.55 -apple-system, BlinkMacSystemFont, "Segoe UI",
    Roboto, sans-serif; }
  p { color:#6e5b61; }
  @media (prefers-color-scheme: dark) {
    body { background:#141110; color:#f2edea; } p { color:#a9999e; }
  }
</style></head>
<body><h1>Nothing here</h1><p>This page does not exist.</p></body></html>`;
}
