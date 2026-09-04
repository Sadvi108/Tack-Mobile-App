/**
 * Reading a public GitHub repository, to turn a claim into evidence.
 *
 * A project on a CV is an assertion. A project whose repository exists, is in
 * the language it says, and was pushed to recently is a demonstration — and
 * for a student with no employment history that difference is most of what
 * they have.
 *
 * Only public repositories, only the fields shown on the page, and never at
 * render time: unauthenticated GitHub allows 60 requests an hour per address
 * and Edge Functions share addresses, so a page that called this on view would
 * rate-limit every other student's page too. The result is cached in
 * `project_verifications` and refreshed by the nightly sweep.
 */

export interface RepoFacts {
  state: "verified" | "missing" | "error";
  stars?: number;
  language?: string | null;
  lastPushAt?: string | null;
  error?: string;
}

/**
 * Pulls `owner/repo` out of whatever the student pasted.
 *
 * They paste the address bar, so it arrives with `https://`, without it, with
 * a trailing slash, with `.git`, or pointing at a file deep inside the tree.
 * Returns null for anything that is not a GitHub repository, including a
 * GitHub profile URL, which has an owner and no repo.
 */
export function parseRepo(url: string): { owner: string; repo: string } | null {
  const trimmed = (url ?? "").trim();
  if (!trimmed) return null;

  const withScheme = /^https?:\/\//i.test(trimmed)
    ? trimmed
    : `https://${trimmed}`;

  let parsed: URL;
  try {
    parsed = new URL(withScheme);
  } catch {
    return null;
  }

  if (!/(^|\.)github\.com$/i.test(parsed.hostname)) return null;

  const parts = parsed.pathname.split("/").filter(Boolean);
  if (parts.length < 2) return null;

  const owner = parts[0];
  const repo = parts[1].replace(/\.git$/i, "");
  if (!owner || !repo) return null;

  // GitHub's own rules, so an obviously invalid pair never costs a request.
  if (!/^[A-Za-z0-9](?:[A-Za-z0-9]|-(?=[A-Za-z0-9])){0,38}$/.test(owner)) {
    return null;
  }
  if (!/^[A-Za-z0-9._-]{1,100}$/.test(repo)) return null;

  return { owner, repo };
}

export async function readRepo(url: string): Promise<RepoFacts> {
  const parsed = parseRepo(url);
  if (!parsed) return { state: "error", error: "not a github repository url" };

  let res: Response;
  try {
    res = await fetch(
      `https://api.github.com/repos/${parsed.owner}/${parsed.repo}`,
      {
        headers: {
          Accept: "application/vnd.github+json",
          // GitHub refuses unidentified clients.
          "User-Agent": "tack-app",
        },
      },
    );
  } catch (e) {
    return { state: "error", error: (e as Error).message.slice(0, 200) };
  }

  // A deleted or private repository is a fact about the project, not a failure
  // of the job: the page says it could not be verified and moves on.
  if (res.status === 404) return { state: "missing" };

  if (!res.ok) {
    // 403 here is nearly always the rate limit. Worth retrying later, so it is
    // an error rather than a verdict.
    return {
      state: "error",
      error: `${res.status} ${(await res.text()).slice(0, 120)}`,
    };
  }

  const body = await res.json() as {
    stargazers_count?: number;
    language?: string | null;
    pushed_at?: string | null;
    private?: boolean;
  };

  if (body.private) return { state: "missing" };

  return {
    state: "verified",
    stars: body.stargazers_count ?? 0,
    language: body.language ?? null,
    lastPushAt: body.pushed_at ?? null,
  };
}
