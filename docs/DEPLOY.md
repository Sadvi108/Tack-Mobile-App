# Deploying Tack

Two things ship independently: the Flutter app to the stores, and the Supabase
backend (migrations, Edge Functions, secrets).

Nothing in this file contains a secret value, and nothing here should ever be
edited to contain one.

## What is already live

The database is fully migrated against the project in `supabase/.env`:
19 migrations, Row Level Security on all 40 tables, reference data seeded, and
two cron jobs scheduled (`tack-worker` every two minutes, `tack-nightly` at
18:20 UTC — just after midnight in Dhaka).

The cron bearer secret and the functions base URL are in Supabase Vault under
`tack_cron_secret` and `tack_functions_url`. They are read at call time, so
rotating the secret is a Vault update and needs no code change:

```bash
node tool/set_vault_secrets.js
```

## Still to do by a human

**Edge Functions are written and type-checked but not yet deployed.** They
need the Supabase CLI authenticated against the project, which requires a
personal access token that only you can create.

```bash
brew install supabase/tap/supabase
```

```bash
supabase login
```

```bash
supabase link --project-ref uvwmjeqymychlsybekxz
```

Set the function secrets. These are names only — take the values from your own
`supabase/.env`, and do not paste them into a chat, a commit, or a ticket:

```bash
supabase secrets set GEMINI_API_KEY AI_PROVIDER CRON_SECRET
```

Then deploy:

```bash
supabase functions deploy analyze-jd worker interview
```

`AI_PROVIDER` should stay `mock` until you deliberately want live model calls.
Flip it to `gemini` for a single test, then set it back.

Google sign-in also needs enabling in the Supabase dashboard under
Authentication → Providers → Google, with `com.tack.app://auth-callback` added
to the allowed redirect URLs.

## The app

Build configuration comes from `--dart-define-from-file`, so no key is ever
read from a file on the device.

```bash
cd app && flutter build apk --release --dart-define-from-file=env/prod.json
```

```bash
cd app && flutter build appbundle --release --dart-define-from-file=env/prod.json
```

`env/prod.json` is gitignored. Copy `env/dev.example.json`, fill it in, and
keep it off version control.

Android release signing needs `android/key.properties` and a keystore, both
gitignored. iOS needs a team id in Xcode.

## Checks before shipping

```bash
cd app && flutter analyze && flutter test
```

```bash
cd supabase/functions && deno check analyze-jd/index.ts worker/index.ts interview/index.ts && deno test _shared/
```

```bash
node tool/verify_db.js && node tool/verify_storage.js
```

The last one creates two throwaway users, tries to make one read the other's
data, and deletes them again. Run it after any migration that touches a
policy.

## Rolling back

Migrations are append-only. To undo one, write a new migration that reverses
it — never edit or delete a file that has already run, because
`schema_migrations` records what was applied and by name.
