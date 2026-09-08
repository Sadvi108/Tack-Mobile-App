# Putting Tack on a real phone

The goal this exists for: scan a code, install Tack, upload a CV from the phone
that has the CV on it.

A QR cannot install an app on its own — it can only carry a link, and the link
has to point at something Apple will install from. TestFlight is that
something. So the QR is the last step here, not the first.

Almost all of this needs your Apple account, and none of it can be done for
you. Where a step is yours alone it says so.

---

## What has to be true first

**Two of these are blockers for the thing you actually want to test.**

| | Status |
|---|---|
| A paid Apple Developer Program membership | **Yours to do.** The free tier signs builds onto a phone you have plugged in, and cannot use TestFlight. |
| Bundle id `com.tack.tack` registered to your team | **Yours to do**, in the developer portal. It is already set in the project. |
| Edge Functions deployed | **Blocker.** Without them a CV uploads and then says Tack could not start reading it. See [DEPLOY.md](DEPLOY.md). |
| `app/env/prod.json` filled in | **Blocker.** It is gitignored and holds the Supabase URL and anon key the build talks to. A build with the dev values is a build pointed at your dev data. |

---

## 1. Sign the app — yours to do

Open the workspace:

```bash
open app/ios/Runner.xcworkspace
```

Select the **Runner** target, then **Signing & Capabilities**, tick *Automatically
manage signing*, and pick your team. The project is already on automatic
signing with the right bundle id, so this sets `DEVELOPMENT_TEAM` and nothing
else changes.

## 2. Give the build a number

TestFlight refuses a build number it has already seen, and it is the one thing
that has to move every single upload.

`app/pubspec.yaml` carries both:

```
version: 0.1.0+1
```

`0.1.0` is what a tester sees. `+1` is the build number. Bump the build number
on every upload, and the version when the app has meaningfully changed.

## 3. Build the archive

```bash
cd app && flutter build ipa --dart-define-from-file=env/prod.json
```

That writes `app/build/ios/archive/Runner.xcarchive` and, if signing is set up,
an `.ipa` beside it. The `--dart-define-from-file` is not optional: without it
the app boots with no Supabase URL and fails its own configuration check on the
first screen, by design.

## 4. Upload it — yours to do

Either open the archive in Xcode's Organizer and use **Distribute App → App Store
Connect**, or use Apple's Transporter app with the `.ipa`. Both need you signed
in to an account with upload rights.

Processing on Apple's side takes ten minutes or so, and they email you when it
is ready to test.

## 5. Turn on the public link — yours to do

In App Store Connect: **TestFlight → your build → Test Information**, fill in
what the build changed and an email they can reach you at, then under **Groups**
create a public group and enable its link.

The link looks like:

```
https://testflight.apple.com/join/XXXXXXXX
```

Anyone who opens it installs TestFlight and then Tack. It works on any iPhone,
not only ones you have registered.

## 6. Make the QR

```bash
swift tool/make_qr.swift "https://testflight.apple.com/join/XXXXXXXX" tack-testflight.png
```

Uses only macOS system frameworks, so it adds nothing to the project. Two
things are checked before the file is written, because a bad QR is
indistinguishable from a good one by eye:

- **It decodes back to the text given.** A code that encodes the wrong thing
  looks exactly like one that does not.
- **The join link resolves.** A code pointing at a beta that does not exist
  opens TestFlight and gets *"beta not found"*, which reads as a broken code
  when the link is what is missing. Apple answers 404 for a link that was never
  switched on, so the tool refuses rather than handing you a code that will
  embarrass you in front of testers.

Either check failing means it writes nothing and exits non-zero. To make a code
for a link that is not live yet, pass `--skip-link-check`.

Error correction is set to H, which is what survives being printed,
photographed at an angle, or half covered by a thumb. A four-module quiet zone
is included; do not crop it, and do not put the code on a dark background.

Third argument sets the pixel size, default 1024:

```bash
swift tool/make_qr.swift "https://testflight.apple.com/join/XXXXXXXX" poster.png 2048
```

---

## Uploading a CV once it is installed

`file_picker` and `image_picker` are already dependencies, so on a real phone
the vault offers Files, iCloud Drive and the camera. Tap an uploaded document
to open a local copy with the phone's document options. This needs the updated
native build, and the installed-reader flow still needs a physical-device test.

CV feedback currently accepts text PDFs and Word `.docx` files. Photo OCR
exceeded the hosted worker's CPU limit during the live test. Photos can be
stored and opened, but feedback on them is deferred with instructions to use a
text document. See [production progress](PRODUCTION_PROGRESS_2026-09-08.md).

## The shorter route, if you only want it on your own phone

TestFlight is for putting a build in other people's hands. For your own phone,
plug it in and:

```bash
cd app && flutter run --dart-define-from-file=env/dev.json -d <your-iphone>
```

A free Apple ID is enough for that. The build expires after seven days and has
to be reinstalled, which is why it is not the answer for testers.
