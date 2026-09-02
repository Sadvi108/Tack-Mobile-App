import { requireUser, serviceClient } from "../_shared/util/auth.ts";
import { fail, json, preflight } from "../_shared/util/http.ts";
import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * Deleting an account, for good.
 *
 * Google Play requires an in-app route to this for any app that lets you sign
 * up, and it is the first thing a student looks for when they stop trusting
 * something. There was no way to do it at all before this.
 *
 * The identity comes from the caller's own bearer token and nothing else. A
 * function that took a user id from the body would let any signed-in student
 * delete any other student's account, which is the worst version of the bug
 * migration 0024 was written to close.
 *
 * Order matters. `profiles.id references auth.users(id) on delete cascade` and
 * every table cascades from profiles, so removing the auth user takes the
 * whole database side with it in one statement. Storage is not part of that
 * graph — `storage.objects` has no foreign key to auth.users — so the files
 * have to go first. Deleting the user first would orphan every CV in the
 * bucket with no owner left to attribute them to, and no way for the student
 * to ask for them again.
 */

const BUCKETS = ["documents", "avatars"];

/**
 * Every object under a prefix, including nested ones.
 *
 * `list()` is not recursive: it returns the files at one level plus the
 * folders beneath it. A CV lives at users/<uid>/cv/<id>, so a single call
 * against users/<uid> returns the folder "cv" and no files at all.
 */
async function listAll(
  service: SupabaseClient,
  bucket: string,
  prefix: string,
): Promise<string[]> {
  const found: string[] = [];
  const { data, error } = await service.storage.from(bucket).list(prefix, {
    limit: 1000,
  });
  if (error || !data) return found;

  for (const entry of data) {
    const full = `${prefix}/${entry.name}`;
    // A folder comes back with no id. Anything with one is a real object.
    if (entry.id === null) {
      found.push(...await listAll(service, bucket, full));
    } else {
      found.push(full);
    }
  }
  return found;
}

Deno.serve(async (req) => {
  const early = preflight(req);
  if (early) return early;

  if (req.method !== "POST") return fail("Use POST.", 405);

  const auth = await requireUser(req);
  if (!auth) return fail("Sign in first.", 401);

  const service = serviceClient();
  const removed: Record<string, number> = {};

  try {
    for (const bucket of BUCKETS) {
      const paths = await listAll(service, bucket, `users/${auth.userId}`);
      removed[bucket] = paths.length;
      if (paths.length === 0) continue;

      const { error } = await service.storage.from(bucket).remove(paths);
      if (error) {
        // Stop rather than press on. A half-deleted account with the auth user
        // gone and the files still there is worse than one that failed
        // cleanly and can be retried.
        console.error("delete-account: storage", bucket, error.message);
        return fail(
          "Your account could not be deleted just now. Nothing has been " +
            "removed. Try again in a moment.",
          502,
        );
      }
    }

    const { error } = await service.auth.admin.deleteUser(auth.userId);
    if (error) {
      console.error("delete-account: auth", error.message);
      return fail(
        "Your files were removed but the account itself could not be " +
          "deleted. Contact us and we will finish it.",
        502,
      );
    }
  } catch (e) {
    console.error("delete-account:", e);
    return fail("Your account could not be deleted just now.", 500);
  }

  // Deliberately not logged to analytics_events: the row would cascade away
  // with the account a moment later, and counting people as they leave is not
  // worth keeping a record of somebody who asked to be forgotten.
  return json({ deleted: true, files: removed });
});
