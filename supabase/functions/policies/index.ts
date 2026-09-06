import { privacy, support, terms } from "./content.ts";
Deno.serve((req) => {
  if (req.method !== "GET" && req.method !== "HEAD") {
    return new Response("Use GET.", { status: 405 });
  }
  const page = new URL(req.url).pathname.split("/").filter(Boolean).pop();
  const content = page === "privacy"
    ? privacy
    : page === "terms"
    ? terms
    : page === "support"
    ? support
    : null;
  return new Response(
    req.method === "HEAD" ? null : content ?? "Page not found.",
    {
      status: content ? 200 : 404,
      headers: {
        "Content-Type": "text/plain; charset=utf-8",
        "Cache-Control": "public, max-age=3600",
        "X-Content-Type-Options": "nosniff",
      },
    },
  );
});
