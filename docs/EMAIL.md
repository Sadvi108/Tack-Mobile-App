# Email delivery

Tack sends three kinds of email: confirm your address, reset your password,
and change your email. All three go through Supabase Auth.

## The problem you will hit first

Supabase's built-in mail sender is **capped at a handful of messages per hour
per project** and is explicitly not meant for production. Once the cap is hit,
sign-up returns:

```json
{"code":429,"error_code":"over_email_send_rate_limit","msg":"email rate limit exceeded"}
```

The account is still created; the email simply never goes out. Testing sign-up
a few times in a row is enough to trigger it. The app now says so in plain
words rather than "something went wrong", but the fix is to stop using the
built-in sender.

## Fixing it: bring your own SMTP

Any provider works. Resend is the least effort, and its free tier covers far
more than the built-in sender.

1. resend.com → sign up → **Domains** → add your domain, or use their sandbox
   domain to test immediately
2. Add the DNS records they show you (SPF and DKIM). Without these, Gmail will
   put your mail in spam or reject it outright.
3. **API Keys** → create one with send permission
4. Supabase dashboard → Project Settings → Authentication → **SMTP Settings**
   → enable custom SMTP:

```
Host        smtp.resend.com
Port        587
Username    resend
Password    <your Resend API key>
Sender      noreply@yourdomain.com
Sender name Tack
```

5. Project Settings → Authentication → **Rate Limits** → raise the email limit.
   It stays low until custom SMTP is configured.

Send yourself a test sign-up afterwards and confirm it lands in the inbox
rather than spam.

## The other reason an email never arrives

Supabase will not confirm or deny that an address is registered — that would
let anyone check who has an account. So signing up with an **already confirmed**
address returns a perfectly ordinary `200`, with a fabricated user id, and
sends nothing at all.

The one usable signal is that `identities` comes back empty. Tack checks for
that and tells the student the account already exists, offering to log in
instead. Without the check the app tells them to check an inbox that will stay
empty forever, which is the single most confusing thing an app can do at
sign-up.

`tool/verify_signup_email.js` covers all three cases against the live project:
a new address, the same address while still unconfirmed, and the same address
once confirmed.

## Turning confirmation off while developing

Supabase dashboard → Authentication → Providers → Email → turn off **Confirm
email**. Sign-up then returns a session immediately and no mail is sent. The
app already handles this: `SignUpOutcome.signedIn` means there is nothing to
wait for.

Turn it back on before real students arrive, or anyone can sign up as anyone.
