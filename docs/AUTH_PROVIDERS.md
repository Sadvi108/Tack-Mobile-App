# Social sign-in

Tack offers Google, Facebook and GitHub. The app side is finished and the
deep link is registered on both platforms; what remains is creating an OAuth
app with each provider and pasting two values into Supabase.

Until a provider is switched on, its button shows a plain sentence naming it
and pointing at email, rather than the server's "Unsupported provider".

## The two URLs you will need

**Callback URL** — give this to Google, Facebook and GitHub. It is the same
for all three:

```
https://uvwmjeqymychlsybekxz.supabase.co/auth/v1/callback
```

**App redirect** — already configured in Supabase's redirect allow-list and
registered in the Android manifest and iOS Info.plist:

```
com.tack.app://auth-callback
```

Add that second one under Authentication → URL Configuration → Redirect URLs
in the Supabase dashboard. Without it Supabase completes the login and then
refuses to hand the session back to the app.

## Google

1. console.cloud.google.com → create a project called Tack
2. APIs & Services → OAuth consent screen → External. Fill in the app name,
   your support email, and the developer email. Leave scopes at the defaults —
   Tack only needs email and profile.
3. Credentials → Create Credentials → OAuth client ID → **Web application**.
   Under Authorised redirect URIs add the callback URL above.
4. Copy the client ID and client secret.
5. Supabase → Authentication → Providers → Google → enable, paste both, save.

The client type is **Web application**, not Android or iOS. Supabase performs
the exchange server-side, so the mobile client types do not apply and picking
one is the usual reason this fails.

## Facebook

1. developers.facebook.com → My Apps → Create App → **Consumer**
2. Add the **Facebook Login** product
3. Facebook Login → Settings → Valid OAuth Redirect URIs → the callback URL
4. Settings → Basic → copy the App ID and App Secret
5. Supabase → Authentication → Providers → Facebook → enable, paste both, save

Facebook requires a privacy policy URL and App Review before anyone outside
your own test users can log in. Development mode works for you and testers
immediately, so this is fine for launch but needs review before real students
arrive.

## GitHub

The simplest of the three.

1. github.com/settings/developers → OAuth Apps → New OAuth App
2. Homepage URL: your site, or the GitHub repo for now
3. Authorization callback URL: the callback URL above
4. Register, then Generate a new client secret
5. Supabase → Authentication → Providers → GitHub → enable, paste both, save

## Checking it works

Run the app, tap the provider, and confirm three things:

1. The browser opens the provider's own login page
2. After approving, the browser closes and **Tack comes back to the front**
3. You land on onboarding or the dashboard, signed in

Step 2 is where this normally breaks. If the browser completes the login but
the app never reopens, the deep link is wrong — check that
`com.tack.app://auth-callback` is in Supabase's redirect allow-list, and that
the Android intent filter and iOS `CFBundleURLTypes` still carry the
`com.tack.app` scheme.

## What Tack asks for

Email and public profile only. No friends list, no posts, no repositories.
A first sign-in creates the `profiles` row through the same database trigger
that email sign-up uses, and a name supplied by the provider is used to
pre-fill onboarding — which is why sign-up itself no longer asks for one.
