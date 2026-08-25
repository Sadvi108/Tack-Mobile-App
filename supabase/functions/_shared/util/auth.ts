import { createClient, SupabaseClient } from "@supabase/supabase-js";

/**
 * The caller's identity, established from their own bearer token.
 *
 * Never trusts a user id sent in a request body. A function that took the id
 * from the payload would let any signed-in student act as any other.
 */
export async function requireUser(
  req: Request,
): Promise<{ userId: string; client: SupabaseClient } | null> {
  const authorization = req.headers.get("Authorization");
  if (!authorization) return null;

  const client = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authorization } } },
  );

  const { data, error } = await client.auth.getUser();
  if (error || !data.user) return null;

  return { userId: data.user.id, client };
}

/**
 * The service-role client. Bypasses Row Level Security, so it is only ever
 * used for work the student is not allowed to do directly: writing quota
 * counters, the job queue, and usage records.
 */
export function serviceClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );
}

/** Guards the worker endpoint. Constant-time compare, no early return. */
export function isWorkerAuthorised(req: Request): boolean {
  const secret = Deno.env.get("CRON_SECRET");
  if (!secret) return false;

  const provided = (req.headers.get("Authorization") ?? "").replace(
    /^Bearer\s+/i,
    "",
  );
  if (provided.length !== secret.length) return false;

  let diff = 0;
  for (let i = 0; i < secret.length; i++) {
    diff |= provided.charCodeAt(i) ^ secret.charCodeAt(i);
  }
  return diff === 0;
}
