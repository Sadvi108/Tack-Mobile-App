/**
 * Firebase Cloud Messaging, HTTP v1.
 *
 * The legacy `key=<server key>` endpoint is gone, so this does the real thing:
 * sign a JWT with the service account's private key, exchange it for an access
 * token, and post to the v1 endpoint. About sixty lines, no dependency, and no
 * npm package pulled into the Edge Runtime for it.
 *
 * Configured entirely through `FCM_SERVICE_ACCOUNT` — the whole service-account
 * JSON, set with `supabase secrets set`. With it unset this module reports
 * itself unconfigured and the caller skips, which is how the queue behaves
 * sensibly on a project where push has not been set up yet rather than
 * dead-lettering a job every time somebody has a step due.
 */

const TOKEN_URL = "https://oauth2.googleapis.com/token";
const SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

export interface PushMessage {
  title: string;
  body?: string | null;
  /** Small string map delivered alongside; used to route the tap. */
  data?: Record<string, string>;
}

/** What happened to one token. `stale` means: stop sending to it. */
export type PushOutcome = { ok: true } | {
  ok: false;
  stale: boolean;
  error: string;
};

export function serviceAccount(): ServiceAccount | null {
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as ServiceAccount;
    if (!parsed.project_id || !parsed.client_email || !parsed.private_key) {
      return null;
    }
    return parsed;
  } catch {
    return null;
  }
}

export const isConfigured = () => serviceAccount() !== null;

function base64url(bytes: Uint8Array | string): string {
  const raw = typeof bytes === "string"
    ? btoa(bytes)
    : btoa(String.fromCharCode(...bytes));
  return raw.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** PEM (PKCS#8) to a Web Crypto key. */
async function importKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    // Service-account JSON carries the newlines escaped.
    .replace(/\\n/g, "")
    .replace(/\s/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

// Access tokens last an hour. Re-minting one per push would add a round trip
// to every notification in a digest run.
let cached: { token: string; expiresAt: number } | null = null;

async function accessToken(account: ServiceAccount): Promise<string> {
  if (cached && cached.expiresAt > Date.now() + 60_000) return cached.token;

  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64url(JSON.stringify({
    iss: account.client_email,
    scope: SCOPE,
    aud: TOKEN_URL,
    iat: now,
    exp: now + 3600,
  }));

  const key = await importKey(account.private_key);
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  const jwt = `${header}.${claims}.${base64url(new Uint8Array(signature))}`;

  const res = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!res.ok) {
    throw new Error(
      `FCM token exchange failed: ${res.status} ${await res.text()}`,
    );
  }

  const body = await res.json() as { access_token: string; expires_in: number };
  cached = {
    token: body.access_token,
    expiresAt: Date.now() + body.expires_in * 1000,
  };
  return cached.token;
}

/**
 * Sends to one device token.
 *
 * Never throws for a bad token: a phone that uninstalled the app is an
 * ordinary outcome, not a failure of the job, and treating it as one would
 * retry the whole digest three times and then dead-letter it.
 */
export async function sendTo(
  token: string,
  message: PushMessage,
): Promise<PushOutcome> {
  const account = serviceAccount();
  if (!account) return { ok: false, stale: false, error: "not configured" };

  let bearer: string;
  try {
    bearer = await accessToken(account);
  } catch (e) {
    return { ok: false, stale: false, error: (e as Error).message };
  }

  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${bearer}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: {
            title: message.title,
            body: message.body ?? undefined,
          },
          data: message.data ?? {},
          android: { priority: "normal" },
        },
      }),
    },
  );

  if (res.ok) return { ok: true };

  const text = await res.text();
  // 404 UNREGISTERED and 400 INVALID_ARGUMENT both mean this token will never
  // work again. Anything else — 429, 503 — is worth another attempt later.
  const stale = res.status === 404 ||
    (res.status === 400 && text.includes("INVALID_ARGUMENT"));
  return { ok: false, stale, error: `${res.status} ${text.slice(0, 200)}` };
}
