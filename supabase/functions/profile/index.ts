import { serviceClient } from "../_shared/util/auth.ts";
import { PublicProfile, renderNotFound, renderProfile } from "./render.ts";

/**
 * Serves a student's published page to anybody, signed in or not.
 *
 * Deployed with `--no-verify-jwt` — the same mechanism the worker uses — so a
 * person following a link from a CV or a WhatsApp message reaches it without
 * an account. That is the whole point: a page only Tack users can read is not
 * a page a student can send to an employer.
 *
 * It reads with the service client and calls `public_profile()`, which is
 * where the filtering lives. Nothing in this file decides what is public;
 * doing it in SQL means the filter is enforced by the query rather than by
 * remembering to delete keys here.
 *
 * That also keeps the invariant from 0065 intact: no function of ours is
 * callable by `anon`, and `tool/verify_rpc_surface.js` still passes.
 */
Deno.serve(async (req) => {
  const url = new URL(req.url);

  // Supabase routes /functions/v1/profile/<handle> here, so the handle is the
  // last non-empty segment.
  const segments = url.pathname.split("/").filter(Boolean);
  const handle = segments[segments.length - 1] ?? "";

  const html = (body: string, status: number) =>
    new Response(body, {
      status,
      headers: {
        "Content-Type": "text/html; charset=utf-8",
        // Public and cacheable: the page changes when a student edits their
        // profile, and a few minutes of staleness costs nothing next to
        // hitting the database for every share.
        "Cache-Control": "public, max-age=300",
        // The page carries no script of its own, so everything is denied. If
        // a stored value ever escaped the HTML escaper, this is the second
        // thing that has to fail before it can execute.
        "Content-Security-Policy":
          "default-src 'none'; style-src 'unsafe-inline'; img-src https: data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
        "X-Content-Type-Options": "nosniff",
        "Referrer-Policy": "no-referrer",
      },
    });

  if (req.method !== "GET" && req.method !== "HEAD") {
    return html(renderNotFound(), 405);
  }

  // `profile` alone, with no handle, is not a page.
  if (!handle || handle === "profile") return html(renderNotFound(), 404);

  const { data, error } = await serviceClient()
    .rpc("public_profile", { p_handle: handle });

  if (error) {
    console.error("profile:", error.message);
    return html(renderNotFound(), 500);
  }

  // Null covers both "no such handle" and "not published". Deliberately the
  // same answer: distinguishing them would confirm that a handle belongs to
  // somebody, which is exactly what a person checking up on a classmate wants
  // to know.
  if (!data) return html(renderNotFound(), 404);

  return html(
    renderProfile(data as PublicProfile, `${url.origin}/functions/v1/profile`),
    200,
  );
});
