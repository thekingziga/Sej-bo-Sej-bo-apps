# Sejbosejbo — app

Native app for [sejbosejbo.fyi](https://sejbosejbo.fyi). One Flutter codebase,
compiled to real native binaries for **iOS, Android, macOS and Windows** — not a
web view.

## Status

| Piece | State |
|---|---|
| UI — dashboard, gallery, upload, support | done, tested |
| Design system (`lib/theme.dart`) | done |
| API client (`lib/api.dart`) | written against a contract that does not exist server-side yet |
| Demo mode | on by default, so the app runs today |
| Donations — Stripe rail | code done, needs the server endpoint |
| Donations — Apple/Google rail | code done, needs store products + server verification |
| iOS / Android / macOS / Windows builds | **not built** — toolchains not installed on this Mac |

## Run it

```bash
flutter run
```

With no `API_BASE_URL` it starts in **demo mode** on bundled sample posts and
shows a banner saying so. Point it at the real API once the endpoints exist:

```bash
flutter run --dart-define=API_BASE_URL=https://sejbosejbo.fyi
```

`--dart-define=START_TAB=2` opens straight onto a given tab, for screenshots.

```bash
flutter test
```

The widget tests pump every screen at 360×640 and fail on any `RenderFlex`
overflow — that is what caught the gallery and upload layout bugs. Run them
before shipping a layout change.

## What you still need to install

Nothing here can build iOS, Android, macOS or Windows binaries yet:

- **iOS + macOS** — Xcode from the App Store (~15 GB), then
  `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`,
  `sudo xcodebuild -runFirstLaunch`, and CocoaPods (`brew install cocoapods`).
- **Android** — Android Studio, which brings the SDK and a JDK.
- **Windows** — cannot be cross-compiled from macOS. Needs a Windows machine
  with Visual Studio and the "Desktop development with C++" workload.

`flutter doctor` tells you what is still missing.

## Architecture

```
lib/
  theme.dart      design system: palette, hard shadows, BrutalBox/BrutalButton
  widgets.dart    PostCard, PostMedia, BrandHeader, loading + error states
  models.dart     wire models — must match docs/API_PROMPT.md exactly
  api.dart        HTTP client, plus the bundled demo feed
  donations.dart  platform-split billing (see below)
  main.dart       app shell and the custom bottom nav
  screens/        home, gallery, upload, donate, detail
```

State is deliberately plain — `StatefulWidget` plus `Future`. There is no state
management package because nothing here needs one.

## Donations, and why they work differently per platform

Apple and Google both require that anything resembling a digital tip to the
developer goes through their billing. Linking out to Stripe from inside the iOS
or Android app is a rejection, not a grey area. So:

| Platform | Rail | Cut |
|---|---|---|
| iOS, Android, macOS (App Store) | StoreKit / Play Billing | 15–30% |
| Windows, macOS (direct download) | Stripe Checkout in the browser | ~3% |

`DonationGateway` picks the rail at runtime; the UI is identical either way, and
the screen tells the user which one is in play.

Before store billing works you need to:

1. Create three **consumable** products, priced €2 / €5 / €15, with these ids in
   both App Store Connect and Google Play Console:
   ```
   fyi.sejbosejbo.tip.small
   fyi.sejbosejbo.tip.medium
   fyi.sejbosejbo.tip.large
   ```
2. Implement the server verification endpoints from `docs/API_PROMPT.md`.
   The app already posts receipts to them. **Never treat a client-reported
   purchase as real** — only the store's own verification response counts.

Tips are consumables, so `completePurchase` is always called; skipping that
makes the store replay the purchase on every launch and blocks repeat tipping.

## The API

The server side does not exist yet. `docs/API_PROMPT.md` is a self-contained
prompt — paste it into a Claude Code session opened on the website repo and it
will build the endpoints this app already expects.

Bundle id / application id is `fyi.sejbosejbo` on every platform.

## Assets

- `assets/fonts/` — Comic Neue (SIL Open Font License, `OFL.txt` included).
  Bundled rather than relying on the system, because the website's Comic Sans
  does not exist on phones — that bug is exactly why this is here.
- `assets/img/logo.png`, `icon.png` — the cat. Launcher icons for all five
  platforms are generated from `icon.png` via
  `dart run flutter_launcher_icons`.
