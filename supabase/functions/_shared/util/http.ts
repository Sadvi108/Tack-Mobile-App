// Shared HTTP helpers for every Tack Edge Function.

export const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

/**
 * Errors the student will read.
 *
 * Never leaks a provider message, a stack trace or a database detail: those go
 * to the function log, and the student gets a sentence saying what happened
 * and what to do next.
 */
export function fail(message: string, status = 400, code?: string): Response {
  return json({ error: { message, code } }, status);
}

export function preflight(req: Request): Response | null {
  return req.method === 'OPTIONS' ? new Response('ok', { headers: cors }) : null;
}
