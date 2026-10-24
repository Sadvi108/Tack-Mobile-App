#!/usr/bin/env node
// Read-only configuration preflight. Creates no accounts, sends no emails,
// invokes no workers, and never prints credentials or configuration bodies.
// This is one release gate; device journeys and the audit's other gates remain.
const fs = require('fs');
const path = require('path');
require('dotenv').config({
  path: path.join(__dirname, '..', 'supabase', '.env'),
  quiet: true,
});

const checks = [];
const record = (status, name, detail) => checks.push({ status, name, detail });
const check = (condition, name, detail) => record(condition ? 'PASS' : 'FAIL', name, detail);
const warn = (condition, name, detail) => record(condition ? 'PASS' : 'WARN', name, detail);

async function readJson(url, headers) {
  const response = await fetch(url, { headers, signal: AbortSignal.timeout(15000) });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.json();
}

async function main() {
  const base = process.env.SUPABASE_URL;
  const anon = process.env.SUPABASE_ANON_KEY;
  const token = process.env.SUPABASE_ACCESS_TOKEN;
  if (!base || !anon || !token) {
    record('UNKNOWN', 'Configuration access',
      'Set SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_ACCESS_TOKEN securely.');
    return;
  }
  const backend = new URL(base);
  if (backend.protocol !== 'https:' || !backend.hostname.endsWith('.supabase.co')) {
    record('UNKNOWN', 'Project identity', 'This preflight expects a hosted supabase.co project URL.');
    return;
  }
  const project = backend.hostname.split('.')[0];
  const management = `https://api.supabase.com/v1/projects/${project}`;
  const headers = { Authorization: `Bearer ${token}` };
  const results = await Promise.allSettled([
    readJson(`${base}/auth/v1/settings`, { apikey: anon }),
    readJson(`${management}/config/auth`, headers),
    readJson(`${management}/functions`, headers),
    readJson(`${management}/secrets`, headers),
  ]);
  const names = ['Public auth settings', 'Auth configuration', 'Function deployment', 'Secret metadata'];
  for (let i = 0; i < results.length; i++) {
    if (results[i].status === 'rejected') {
      record('UNKNOWN', names[i], 'Could not read this source. Check network and access permissions.');
    }
  }

  if (results[0].status === 'fulfilled') {
    const settings = results[0].value;
    check(settings.mailer_autoconfirm === false, 'Email confirmation required',
      'Email/password signup must require confirmation.');
    check(settings.external?.google === true && settings.external?.github === true,
      'Visible OAuth providers enabled', 'The release UI offers Google and GitHub.');
    check(settings.external?.anonymous_users === false, 'Anonymous accounts disabled',
      'The app expects identified accounts.');
  }

  if (results[1].status === 'fulfilled') {
    const auth = results[1].value;
    check(Boolean(auth.smtp_host && auth.smtp_user && auth.smtp_admin_email),
      'Custom SMTP configured', 'A production sender and sender address are required; delivery still needs an inbox test.');
    check(Number(auth.rate_limit_email_sent) > 2, 'Email capacity configured',
      'Raise the default two-per-hour limit after SMTP setup; size capacity for the pilot.');
    const redirects = Array.isArray(auth.uri_allow_list)
      ? auth.uri_allow_list
      : String(auth.uri_allow_list || '').split(',').map(value => value.trim());
    check(redirects.includes('com.tack.app://auth-callback'), 'Mobile callback allow-listed',
      'Allow the exact callback registered by both native apps.');
    let validSite = false;
    try {
      const site = new URL(auth.site_url);
      validSite = site.protocol === 'https:' && !/^(localhost|127\.|\[::1\])/.test(site.hostname);
    } catch { /* Invalid or missing site URL is a failed gate. */ }
    check(validSite, 'Production site URL', 'Set a reachable HTTPS fallback URL controlled by Tack.');
    check(Number(auth.password_min_length) >= 8, 'Server password minimum matches app',
      'The server must enforce the app minimum of eight characters.');
    warn(auth.password_hibp_enabled === true, 'Leaked-password protection',
      'Enable when available, or document the chosen alternative.');
    warn(auth.security_captcha_enabled === true, 'Authentication abuse protection',
      'Define and test signup/recovery abuse controls before the public launch.');
    warn(auth.security_update_password_require_reauthentication === true,
      'Server password-change reauthentication', 'Client-only reauthentication can be bypassed by a direct API caller.');
    warn(auth.mailer_notifications_password_changed_enabled === true,
      'Password-change security email', 'Enable and verify the account security notification.');
    check(auth.refresh_token_rotation_enabled === true, 'Refresh-token rotation',
      'Keep refresh-token rotation enabled.');
    check(Number(auth.mailer_otp_exp) > 0 && Number(auth.mailer_otp_exp) <= 3600,
      'Email token expiry bounded', 'Email verification tokens should expire within an hour.');
  }

  if (results[2].status === 'fulfilled') {
    const functions = results[2].value;
    if (!Array.isArray(functions)) throw new Error('Unexpected function metadata');
    const source = path.join(__dirname, '..', 'supabase', 'functions');
    const expected = fs.readdirSync(source, { withFileTypes: true })
      .filter(entry => entry.isDirectory() && !entry.name.startsWith('_') &&
        fs.existsSync(path.join(source, entry.name, 'index.ts')))
      .map(entry => entry.name);
    const absent = expected.filter(name => !functions.some(fn => fn.slug === name && fn.status === 'ACTIVE'));
    check(absent.length === 0, 'Required Edge Functions active',
      absent.length ? `Missing or inactive: ${absent.join(', ')}` : `${expected.length} expected functions active; source parity is a separate check.`);
  }

  if (results[3].status === 'fulfilled') {
    const secrets = results[3].value;
    if (!Array.isArray(secrets)) throw new Error('Unexpected secret metadata');
    const present = name => secrets.some(secret => secret.name === name);
    check(present('AI_PROVIDER') && present('GEMINI_API_KEY'), 'AI configuration present',
      'Presence only: verify the deployed provider value and successful real-model requests separately.');
    warn(present('FCM_SERVICE_ACCOUNT'), 'Push server configuration',
      'Required if push is in release scope; mobile registration and APNs also need verification.');
    warn(present('JSEARCH_API_KEY') || present('CAREERJET_API_KEY') ||
      (present('APIFY_API_TOKEN') && present('APIFY_BDJOBS_TASK_ID')), 'Bangladesh search source configured',
      'Local sourcing needs a configured provider and a relevance/freshness review.');
  }
}

main().catch(() => {
  // Never print raw errors: network/configuration exceptions can carry secrets.
  record('UNKNOWN', 'Preflight execution', 'Could not complete the preflight; inspect access and configuration locally.');
}).finally(() => {
  const summary = Object.fromEntries(['PASS', 'FAIL', 'WARN', 'UNKNOWN'].map(status =>
    [status.toLowerCase(), checks.filter(item => item.status === status).length]));
  console.log(JSON.stringify({ checkedAt: new Date().toISOString(), scope: 'Read-only configuration checks; not full production approval', summary, checks }, null, 2));
  process.exitCode = summary.fail ? 1 : summary.unknown ? 2 : 0;
});
