# Publishing Brainrot3d

This document is deliberately honest about what it takes to put this app on the App Store,
because two real blockers stand between this repo and a live listing.

## The submission package (done)

Everything Apple asks for *as assets* is prepared in this repo:

- **App icon** — `assets/icon/` (visionOS layered Back/Middle/Front, wired into
  `Brainrotter3D/Assets.xcassets/AppIcon.solidimagestack`) plus the flat 1024x1024 marketing
  icon `assets/icon/flat1024.png`.
- **Screenshots** — five 3840x2160 visionOS frames in `marketing/` (also staged for fastlane
  in `fastlane/screenshots/en-US/`).
- **Metadata** — name, subtitle, promo text, description, keywords, categories, release notes,
  and URLs in `fastlane/metadata/`.
- **Privacy policy** — `PRIVACY.md`.
- **fastlane** — `fastlane/Appfile` + `fastlane/Deliverfile`, so a single
  `fastlane deliver` can stage the listing once an account exists.

## Blocker 1: you need a paid Apple Developer Program account

The Mac is currently signing with a **free personal team** (`6PPS68Y9RP`, "Apple Development").
A free team can build and sideload to your own device for 7 days, but it **cannot**:

- create an app record in App Store Connect,
- produce an `Apple Distribution` signing certificate, or
- upload a build for review.

That requires the **Apple Developer Program** ($99/year). With it you get a paid team id (put it
in `fastlane/Appfile`), can register `com.brainrotter.reels`, and can archive a Release build.

## Blocker 2: App Review will almost certainly reject this app

This is the honest part. Brainrot3d works by speaking Instagram's **private** mobile API while
impersonating the official Instagram iOS app (its app id, user-agent, Bloks version, and device
identifiers), and it displays third-party content and the Instagram name/marks. App Review
screens for exactly this. The relevant App Store Review Guidelines:

- **5.2.5 — Apps using third-party services** must comply with their terms; using a private/
  unauthorized API and impersonating another app's client violates Instagram's Terms of Service.
- **5.2.1 / 5.2.2 — Intellectual property** — you may not build a business around another
  company's service/content/marks without authorization.
- **4.0 / 2.3 — Design & accurate metadata** — a reskinned client of another service.

A submission would very likely be rejected, and could put the developer account at risk. None of
this is fixable by editing the build; it's a policy decision, not a packaging problem.

## What actually works (recommended)

1. **Personal sideload (today).** This is what the repo already does — build and install to your
   own Vision Pro. Free signing lasts 7 days; a paid account extends it to a year.
2. **TestFlight, small + private.** With a paid account you can run internal TestFlight builds.
   External/public TestFlight still goes through App Review, so the same rejection risk applies.
3. **Open source.** Keep it as a build-it-yourself project (this repo). No review, no takedown
   surface, and the reverse-engineering write-up is the point.

## If you still want to stage a listing (paid account)

```sh
# 1) put your PAID team id in fastlane/Appfile, then register the app id + record:
#    App Store Connect -> Apps -> + -> New App (platform: visionOS, bundle com.brainrotter.reels)

# 2) archive a Release build (needs an Apple Distribution cert from the paid account)
xcodebuild -project Brainrotter3D.xcodeproj -scheme Brainrotter3D \
  -configuration Release -destination 'generic/platform=visionOS' \
  -archivePath build/Brainrot3d.xcarchive archive

# 3) upload the build (Xcode Organizer, Transporter, or):
xcrun altool --upload-app -f build/Brainrot3d.ipa -t visionos \
  --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>

# 4) stage metadata + screenshots (does NOT submit for review):
fastlane deliver
```

Then finish the App Privacy questionnaire in App Store Connect (this app: "Data Not Collected"
by the developer; the session lives on-device — see `PRIVACY.md`) and set the age rating to 17+.
