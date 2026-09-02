# Privacy Policy

**Tack** — a careers app for students in Bangladesh.

Last updated: 3 September 2026

This describes what Tack actually does with your information. Every claim here
matches something in the code, and where a limit is enforced by the software
rather than by a promise, it says so.

---

## The short version

- Your data lives in one database. There is no advertising, no data broker, and
  no third-party analytics company.
- Your CVs and certificates are private. Nobody else can open them — not other
  students, and not us through the app.
- You can delete your account from inside the app, at any time, and it takes
  your files with it.
- Three things do leave our database, and each is listed below: crash reports,
  the text sent to an AI model (with your contact details stripped out first),
  and the words you type into the job search.

---

## Who we are

Tack is run by Shadman Sakib Sadvi. To ask anything about this policy, or to
ask for a copy of your data, email **shadmansadvi108@gmail.com**.

---

## What we collect

**Because you told us.** Your name, email address, phone number, country and
city; whether you are in school or at university, your institution, year, and
expected graduation; your subjects, results, skills, interests, courses and
activities; the job you are aiming at and the industries you like; anything you
type into the coach, an interview answer, or a note on an application.

**Because you uploaded it.** CVs, certificates and any other document you add
to your Vault, along with the text we extract from them in order to score them.

**Because you used the app.** Which screens you opened, which steps you ticked,
how many applications you have, and your readiness score over time.

**Automatically.** Your app version and platform (Android or iOS). Not your IP
address, not an advertising identifier, and not your location.

We do not ask for, and have no way to collect, your exact location, your
contacts, your photos beyond a file you choose to upload, or anything from
other apps.

---

## Where it is stored

In a single Supabase (PostgreSQL) project hosted in **Seoul, South Korea**
(`ap-northeast-2`). Your data therefore leaves Bangladesh and is stored abroad.

Every table has Row Level Security switched on and forced, which means the
database itself refuses to return another student's row to you, or yours to
them. That is not a filter in the app that could be bypassed — it is a rule
inside the database.

Documents are kept in a private bucket. They are never served from a public
URL. When you open one, the app asks for a signed link that **expires after
five minutes**, and only after the database has confirmed the document is
yours.

---

## What leaves our database, and what does not

### Crash reports — Sentry

If the app crashes we send the crash to Sentry so it can be fixed. That report
contains your user id — a random identifier, so that a crash affecting one
person can be told apart from one affecting everybody — and the technical
details of the failure.

It does **not** contain your name, email, phone number, IP address, or any text
you typed: no CV text, job description, note, interview answer or search term.
This is enforced in code (`sendDefaultPii = false`), not by configuration
someone could change by accident.

### AI features — Google Gemini

The coach, CV scoring, job-description analysis and interview practice send
text to Google's Gemini model. **Your contact details are removed before the
text is sent.** Email addresses, Bangladeshi phone numbers, long ID numbers and
web links are extracted locally first; they are kept in our own database and
never placed in the prompt.

You get three AI actions per day. Nothing you do in Tack sends anything to a
model unless you ask for it by using one of those features.

Google processes that text under its own terms. We do not use your data to
train any model, and we have no arrangement that would let anyone do so.

### Job search — the job boards

When you search in Radar, the words you type and the location you choose are
sent to the job boards Tack searches: artificialintelligencejobs.co,
Remotive, Arbeitnow, The Muse and Careerjet. They receive the search terms.
They do not receive your name, your account, or anything else about you.

### Sign-in — Google

If you choose "Continue with Google", Google tells us your email address and
name. If you sign up with an email and password instead, Google is not involved
at all.

---

## Analytics, and its limits

Usage analytics are stored in our own database, in the same project as
everything else, under your own account — so Row Level Security applies to them
like any other row, and deleting your account deletes them too.

We record event names and counts. The code refuses to store a property named
`name`, `email`, `phone`, `address`, `cv`, `cv_text`, `answer`, `notes`,
`description`, `text`, `title`, `summary` or `query`, and it drops **any** text
value longer than 40 characters, whatever it is called. The intent is that
nothing readable about you can end up in that table even by mistake.

There is no Google Analytics, no Firebase Analytics, no Facebook SDK, and no
advertising identifier anywhere in this app.

---

## How long we keep it

- **Your profile and your work** — until you delete your account.
- **Usage analytics and error reports** — 90 days, then deleted automatically
  by a nightly job.
- **A document you delete** — removed from your Vault at once, and erased from
  storage 30 days later. The delay exists so that deleting the wrong file is
  recoverable by asking us within that window.
- **Your whole account** — see below.

---

## Deleting your account

**Settings → Delete your account.** You type the word DELETE to confirm,
because it cannot be undone.

This removes your profile, education, skills, roadmap, applications, saved
openings, coach conversations, interview answers, analytics — and every file
you uploaded, deleted from storage rather than merely hidden. It is immediate
and permanent. We cannot restore it afterwards, even if you ask.

You do not have to email anybody or explain why.

---

## Students under 18

Tack is used by students still at school, some of whom are under 18. We collect
the same limited information from them as from anyone else, and we do not
profile them for advertising, because we do not advertise at all.

If you are under 18, please read this policy with a parent or guardian. If you
are a parent or guardian and want your child's account removed, email
**shadmansadvi108@gmail.com** and we will delete it.

Children of primary-school age cannot create an account: the app takes them to
a waiting list instead and no profile is made.

---

## Your rights

You can see everything Tack holds about you from inside the app, correct it in
your profile, or delete all of it from Settings. If you would rather have a
copy sent to you, or want anything explained, email
**shadmansadvi108@gmail.com**.

---

## Changes

If this policy changes in a way that affects what we do with your data, the app
will tell you before it takes effect. The date at the top is when this version
was written.
