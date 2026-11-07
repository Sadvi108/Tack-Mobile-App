import { requireUser, serviceClient } from "../_shared/util/auth.ts";
import { fail, json, preflight } from "../_shared/util/http.ts";
import { runDeletion, type StoragePort } from "../_shared/account/purge.ts";

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
 *
 * The flow lives in _shared/account/purge.ts so it can be tested. It fails
 * closed: a listing that errors is never read as an empty folder, and the auth
 * user is deleted only after every bucket lists empty a second time.
 */

Deno.serve(async (req) => {
  const early = preflight(req);
  if (early) return early;

  if (req.method !== "POST") return fail("Use POST.", 405);

  const auth = await requireUser(req);
  if (!auth) return fail("Sign in first.", 401);

  const service = serviceClient();
  const storage: StoragePort = {
    list: (bucket, prefix, page) =>
      service.storage.from(bucket).list(prefix, page),
    remove: (bucket, paths) => service.storage.from(bucket).remove(paths),
  };

  try {
    const result = await runDeletion({
      storage,
      uid: auth.userId,
      deleteUser: (uid) => service.auth.admin.deleteUser(uid),
    });
    // Deliberately not logged to analytics_events: the row would cascade away
    // with the account a moment later, and counting people as they leave is
    // not worth keeping a record of somebody who asked to be forgotten.
    return json(result.body, result.status);
  } catch (e) {
    console.error("delete-account:", e);
    return fail("Your account could not be deleted just now.", 500);
  }
});
