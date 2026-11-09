/**
 * Removing a student's files before their account goes.
 *
 * Pure, with storage injected, so the whole flow is testable without a
 * network. The rule this file exists to keep: the account is deleted only
 * when every bucket has been listed again and found empty. A list that fails
 * is a failure, never an empty folder, and the student is told the truth
 * about whether anything has gone yet.
 */

/** One entry from a storage listing. A folder comes back with no id. */
export interface StorageEntry {
  name: string;
  id: string | null;
}

export interface StoragePort {
  list(
    bucket: string,
    prefix: string,
    page: { limit: number; offset: number },
  ): Promise<
    { data: StorageEntry[] | null; error: { message: string } | null }
  >;
  remove(
    bucket: string,
    paths: string[],
  ): Promise<{ error: { message: string } | null }>;
}

/** Entries per list page and paths per remove call. */
export const PAGE = 1000;

type Bucket = "documents" | "avatars";

/** Storage goes first in this order; see delete-account/index.ts. */
const BUCKETS: readonly Bucket[] = ["documents", "avatars"];

/**
 * Where each bucket keeps a student's files (migration 0011): documents at
 * users/<uid>/<type>/<id>, avatars at <uid>/<file>.
 */
export function prefixesFor(uid: string): Record<Bucket, string> {
  return { documents: `users/${uid}`, avatars: uid };
}

export class PurgeError extends Error {
  constructor(
    readonly stage: "list" | "remove" | "verify",
    readonly bucket: string,
    readonly removedAny: boolean,
  ) {
    super(`${stage}:${bucket}`);
    this.name = "PurgeError";
  }
}

/**
 * Every object under a prefix, recursing into folders, paging with offset
 * until a page is shorter than PAGE. Throws PurgeError("list") on any error.
 *
 * `list()` is not recursive: it returns the files at one level plus the
 * folders beneath it. A CV lives at users/<uid>/cv/<id>, so a single call
 * against users/<uid> returns the folder "cv" and no files at all.
 */
export async function listAll(
  s: StoragePort,
  bucket: string,
  prefix: string,
): Promise<string[]> {
  const found: string[] = [];
  for (let offset = 0;; offset += PAGE) {
    let page: StorageEntry[];
    try {
      const { data, error } = await s.list(bucket, prefix, {
        limit: PAGE,
        offset,
      });
      if (error || !data) throw new Error(error?.message ?? "no data");
      page = data;
    } catch (e) {
      console.error("delete-account: list", bucket, errorText(e));
      throw new PurgeError("list", bucket, false);
    }
    for (const entry of page) {
      const full = `${prefix}/${entry.name}`;
      if (entry.id === null) found.push(...await listAll(s, bucket, full));
      else found.push(full);
    }
    if (page.length < PAGE) return found;
  }
}

/**
 * For each bucket: list, remove in batches of at most PAGE, then list again
 * and throw PurgeError("verify") if anything is left. Returns how many files
 * each bucket had.
 */
export async function purgeUser(
  s: StoragePort,
  uid: string,
): Promise<Record<string, number>> {
  const prefixes = prefixesFor(uid);
  const counts: Record<string, number> = {};
  let removedAny = false;

  for (const bucket of BUCKETS) {
    const prefix = prefixes[bucket];
    const paths = await listOr(s, bucket, prefix, "list", removedAny);

    for (let i = 0; i < paths.length; i += PAGE) {
      const batch = paths.slice(i, i + PAGE);
      let failed: string | null;
      try {
        failed = (await s.remove(bucket, batch)).error?.message ?? null;
      } catch (e) {
        failed = errorText(e);
      }
      if (failed !== null) {
        console.error("delete-account: remove", bucket, failed);
        // A failed call may still have removed some of the batch, so only
        // promise "nothing removed" when a fresh listing proves it.
        const gone = removedAny || await anyGone(s, bucket, prefix, paths);
        throw new PurgeError("remove", bucket, gone);
      }
      removedAny = true;
    }

    const left = await listOr(s, bucket, prefix, "verify", removedAny);
    if (left.length > 0) {
      console.error("delete-account: verify", bucket, left.length, "left");
      throw new PurgeError("verify", bucket, removedAny);
    }
    counts[bucket] = paths.length;
  }
  return counts;
}

type Outcome = { status: number; body: Record<string, unknown> };

/** The same body `fail()` in util/http.ts sends. */
function failure(status: number, message: string, code: string): Outcome {
  return { status, body: { error: { message, code } } };
}

/** The whole flow, so the handler is a thin wrapper and the flow is testable. */
export async function runDeletion(deps: {
  storage: StoragePort;
  uid: string;
  deleteUser: (uid: string) => Promise<{ error: { message: string } | null }>;
}): Promise<Outcome> {
  let files: Record<string, number>;
  try {
    files = await purgeUser(deps.storage, deps.uid);
  } catch (e) {
    if (!(e instanceof PurgeError)) throw e;
    return e.removedAny
      ? failure(
        502,
        "Some of your files were removed, but not all. Try again to " +
          "finish deleting your account.",
        "delete_incomplete",
      )
      : failure(
        502,
        "Your account could not be deleted just now. Nothing has been " +
          "removed. Try again in a moment.",
        "delete_not_started",
      );
  }

  let authError: string | null;
  try {
    authError = (await deps.deleteUser(deps.uid)).error?.message ?? null;
  } catch (e) {
    authError = errorText(e);
  }
  if (authError !== null) {
    console.error("delete-account: auth", authError);
    return failure(
      502,
      "Your files were removed but the account itself could not be " +
        "deleted. Contact us and we will finish it.",
      "delete_account_failed",
    );
  }

  return { status: 200, body: { deleted: true, files } };
}

async function listOr(
  s: StoragePort,
  bucket: string,
  prefix: string,
  stage: "list" | "verify",
  removedAny: boolean,
): Promise<string[]> {
  try {
    return await listAll(s, bucket, prefix);
  } catch {
    throw new PurgeError(stage, bucket, removedAny);
  }
}

/** True unless a fresh listing still holds every path we tried to remove. */
async function anyGone(
  s: StoragePort,
  bucket: string,
  prefix: string,
  paths: string[],
): Promise<boolean> {
  try {
    const now = new Set(await listAll(s, bucket, prefix));
    return paths.some((p) => !now.has(p));
  } catch {
    return true;
  }
}

function errorText(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}
