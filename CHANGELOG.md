# Changelog

Every release, newest first. `versionName` tracks the website and Docker image;
the `+N` build number is Play's `versionCode` and only ever increases — Play
burns each value permanently, so it never resets when the semver part changes.

Each entry has a **Play release notes** block, already trimmed to Play's
500-character limit, ready to paste into "What's new in this release".

---

## 1.12.0+16

**Changed**
- **Device ids are now minted and signed by the server.** The app used to
  generate its own, which meant it was just a string the client chose - anyone
  could send a fresh one per request and vote as many times as they liked. The
  app now asks the server for a signed id once per install and sends that
  instead.
- Minting runs **exactly once**, guarded by checking for an id already held.
  Minting is capped at 10 per IP per hour, and a new id each launch would read
  as a new person and throw away the user's voting history.
- Any failure - offline, rate limited, malformed - silently keeps the locally
  generated id, which the server still accepts. A device id is not worth
  blocking a launch over.

**Note for existing installs**
- Upgrading swaps an unsigned id for a signed one, so votes cast under the old
  id stop being attributed. Unavoidable when moving to signed ids, and the
  lesser cost: keeping the old one breaks voting entirely once the server
  starts requiring signatures.

**Verified against production**
- A real minted id round-tripped: reads return `my_vote`, a vote registers, and
  withdrawing leaves the count where it started. 95 tests, up from 89.

```
Voting is now harder to fake, which keeps the rankings honest.
```

---

## 1.11.2+15

**Added**
- **A line explaining the odd tip amounts.** Play grosses the price up by local
  VAT and then rounds to its own price points, so a €2 tier reads €2.39 in
  Slovenia and €2.49 in Portugal. Without a word of explanation that looks like
  a bug in the app, so the Support tab now says whose doing it is - and that the
  number on the button is the whole of it, with nothing added at checkout.

**Fixed**
- **Slovenian spelling.** Several strings I added were missing their diacritics
  ("mogoce", "clovek", "razlicica", "nic", "cez"). The app's original Slovenian
  has them, so these were simply typos, and they were shipping to the audience
  most likely to notice.

```
The Support tab now explains why tip amounts are not round numbers - local tax
and Google's rounding, not us.

Fixed some Slovenian spelling.
```

---

## 1.11.1+14

**Fixed**
- **A tip tier the store has not returned no longer crashes the app.** Looking
  the product up used `firstWhere(orElse: () => throw StateError(...))`, outside
  the try block, so tapping such a tier threw out of an un-awaited path instead
  of showing a message. Hit for real: Play returned one of the three products
  and the other two were still unpriced, so two of the three buttons were live
  grenades.
- **Tiers the store cannot sell no longer show a price.** `priceFor` fell back
  to our own hardcoded €2/€5/€15 whenever Play did not return a product, so the
  screen advertised amounts that could not be charged - and made a
  half-configured console look like a working one. Unavailable tiers now show a
  dash, greyed and inert, while the Stripe rail is unaffected since its tiers
  are ours to price.

```
Fixes a crash when tapping a tip amount the store had not finished setting up.
```

---

## 1.11.0+13

Tipping, wired to the live payment endpoints - and a real money bug fixed on
the way.

**Fixed**
- **Purchases were being finished before they were verified.** `buyConsumable`
  ran with `autoConsume: true`, and the plugin consumes inside its own pipeline
  *before* our listener sees the purchase - so Google was told the transaction
  was complete before the server had ever checked the receipt. On top of that
  `verifyStorePurchase` swallowed every error, so an unreachable server looked
  exactly like a verified tip. Together that meant a forged or failed purchase
  would have been accepted permanently, and a genuine one could vanish with no
  record. Now: verify first, finish only on success.
- **Failed verification leaves the transaction unfinished, deliberately.** A
  400 receipt is invalid and Google auto-refunds it after three days, which is
  the right outcome. Anything transient - 429, 5xx, offline, 503 - is replayed
  on the next launch, so a real tip is not lost to a blip.
- **Android tips are consumed, not just acknowledged.** Acknowledging alone
  stops the three-day refund clock but leaves the product owned, so nobody
  could ever tip the same amount twice.

**Added**
- **Unfinished purchases are replayed on launch** (`restorePurchases`), for the
  app being killed between paying and verifying. Safe to repeat: the server
  ignores duplicate tokens.
- **503 hides tipping** instead of showing a red error. That is the designed
  state on Android and iOS until the store credentials are configured, and it
  is not something the user did.
- **Stripe no longer claims success.** Handing off to the browser now shows
  "finish the payment in your browser" - the webhook decides whether money
  moved, and the user can still close the tab.

**Verified against production**
- All three tiers create real `cs_live_` Stripe checkout sessions; an unknown
  tier is a 400; Google and Apple both answer 503 with a readable message. The
  store purchase flow itself cannot be tested without a license-tester purchase
  on a Play-installed build - the ordering logic is covered by tests instead.
  87 tests, up from 75.

```
Tipping now works on Windows and Linux through your browser.

On Android and iOS the tip screen stays hidden until store payments are
switched on, rather than showing buttons that cannot work yet.
```

---

## 1.10.0+12

Forced updates now trigger off Google Play itself, which is what was actually
wanted.

**Added**
- **Play in-app updates.** On launch the app asks Play whether an update is
  ready *for this device*. If so it hands straight to Play's own full-screen
  update flow - no tapping through our screen first - and there is no way into
  the app until it is done. Backing out of Play's dialog leaves our wall up
  with an UPDATE NOW button that re-runs it.

**Why this is the right trigger**
- Asking Play is strictly better than comparing against "the newest version in
  the store". Play's answer already accounts for staged rollout, device
  compatibility and country targeting, so a user is only ever blocked by an
  update they can genuinely install right now. That was the objection to
  forcing on version-exists, and it does not apply here.
- The server's `min_version` gate from 1.9.0 stays, for the different job:
  a compatibility floor when an API change breaks old builds, on every platform
  including the ones with no store. Either trigger can wall the app; neither
  needs the other.
- Still fails open on everything. A sideloaded build, a device without Play
  Services, Play rate-limiting the check, or no network all mean "carry on".

**Note for testing**
- In-app updates only work for a build **installed by Play**. Sideloading this
  APK will never show the prompt, however old it is - test it from the internal
  testing track with a lower version installed.

```
The app now checks Google Play for updates on launch and walks you through
installing one when it is available, so you are never left on a version that
no longer works properly.
```

---

## 1.9.0+11

Version numbers on screen, and a kill switch for old builds.

**Added**
- **Version shown on the Support tab** - `App v1.9.0 (11)`, read from the
  platform rather than hardcoded so it can never drift from what shipped. The
  website's version appears beneath it once the API reports one. This exists so
  a bug report can name both halves.
- **Forced-update gate.** When the server names a `min_version` newer than the
  installed build, the app shows a full-screen wall with an UPDATE NOW button
  and no way past it. The server can supply its own reason, which is shown
  instead of the generic line.

**Design notes, because this one can bite**
- The gate keys off an explicit `min_version` you raise deliberately - *not*
  off "a newer build exists". Play rolls out gradually, so for hours after an
  upload there are users who cannot get the new version yet; blocking them
  would lock people out of an app they have no way to fix.
- It **fails open** on everything: no endpoint, 404, 500, offline, HTML from a
  captive portal, junk in the field - all treated as "no opinion". A gate that
  failed closed would brick every install the moment the Pi hiccupped, and the
  only fix would be a store release.
- Versions compare numerically, segment by segment. A string compare puts
  `1.10.0` *before* `1.9.0`, which would silently stop gating at 1.10 - there
  is a test asserting exactly that trap.

**Blocked on**
- The endpoint does not exist yet, so nothing gates and no site version shows.
  Spec in `docs/API_REQUEST_version.md`. Until then the app behaves exactly as
  1.8.0 did.

```
The app now shows its version on the Support tab, which makes bug reports much
easier.

Added support for required updates, so a build that can no longer talk to the
website tells you instead of misbehaving.
```

---

## 1.8.0+10

Votes now come from the server, not from this phone.

**Fixed**
- **Votes survive a reinstall.** The app kept its own vote ledger in local
  storage, which made it wrong the moment that storage went away: reinstall, or
  clear app data, and every post read as unvoted - and you could vote on it a
  second time. The server now returns `my_vote` on every read, so the app asks
  instead of remembering. The whole local ledger is deleted.

**Added**
- **Rate limits count down.** A 429 carries `Retry-After`, so instead of a vague
  "slow down" the app disables the control and says "try again in 40s". The
  window is sliding, so retrying early pushed the reset further out - the old
  behaviour actively made things worse.
- **OLDEST / TOP toggle** on threads longer than three comments. Chronological
  stays the default, because a thread is a conversation and reordering it by
  score breaks replies that answer each other.

**Changed**
- `my_vote` is modelled as `int?`, where **null means unknown, not unvoted**.
  The server omits the field when it cannot identify the caller, and defaulting
  that to 0 would reintroduce the exact bug the field fixes. There is a test
  asserting a missing field stays null, including through the offline cache.
- The device id now goes out on reads as well as writes, since `my_vote` is
  keyed off it.
- Comment sort reads the server's echo rather than assuming the request was
  honoured.

**Verified**
- Round-tripped against production: an anonymous read returns no `my_vote` at
  all, an identified one returns 0, a vote comes back 1, and a **fresh GET
  still says 1** - which is the whole point. Also confirmed the app never
  rebuilds an image URL, so uploads can move to S3 without an app release.
  62 tests, up from 48.

```
Your votes now stick. They used to be forgotten if you reinstalled the app or
cleared its data - now the server remembers them.

Long comment threads can be sorted by top instead of oldest.

If you hit a limit, the app tells you exactly how long to wait.
```

---

## 1.7.0+9

Comments can be voted on and reported, using the same widget and the same
rules as posts.

**Added**
- **SEJ BO / SEJ NE BO on every comment.** Optimistic with rollback, and
  re-tapping the active direction withdraws - identical to post voting, because
  the semantics are identical and two subtly different vote behaviours in one
  app would be a bug waiting to happen.
- **Report a comment**, from a flag on the comment itself. Play's UGC policy
  and Apple Guideline 1.2 cover user content, and a comment is user content as
  much as a post is - so the app previously met the letter of the rule while
  leaving the newest surface unreportable.

**Changed**
- `VoteBar` now takes raw counts instead of a Post, with `forPost` / `forComment`
  constructors. One widget, one behaviour, both surfaces.
- Comment votes are persisted under their own key prefix. Comment ids and post
  ids are separate sequences, so a shared prefix would have comment 7 silently
  inherit post 7's vote.
- The vote path checks it has a device id before sending. The server requires
  one here (unlike posting a comment, where it is optional) and 400s without a
  valid one - and behind an optimistic UI, a vote that always fails is invisible.

**Verified**
- Round-tripped against production: vote up, flip to down, withdraw, with the
  counts landing back exactly where they started and no residue. The generated
  device id is asserted to match the server's `[A-Za-z0-9_-]{8,128}`. 48 tests,
  up from 37.

```
You can now vote on comments, not just posts - SEJ BO or SEJ NE BO, tap again
to take it back.

You can also report a comment if something is wrong with it. Reports go to a
human.
```

---

## 1.6.0+8

Comments, and future-proofing against the audio/video posts the server is
already sitting on.

**Added**
- **Comment threads.** Every post now has one, on the detail screen: oldest
  first (reading order, unlike the feed), with a composer, a live character
  counter, pagination once a thread passes 50, and the empty state saying so.
  Comments are anonymous - there are no accounts and the server exposes no
  author.
- **Comment counts on cards**, shown only when a thread is non-empty so a quiet
  post stays quiet rather than advertising a zero.
- **Your own comments are badged YOU.** The wire format is anonymous, so the
  app remembers the ids it created locally (capped at 300, since the list only
  drives a badge).

**Changed**
- **`kind` is now treated as an open set.** Audio and video posts are built
  server-side and waiting on a flag; when it flips, `image_url` starts pointing
  at an `.mp4` or `.m4a`. Previously anything unrecognised fell through to the
  image path, which would have made `Image.network` pull an entire video over
  mobile data before failing. An unknown kind now renders an honest "open it on
  the website" card, so installs that predate the flag degrade instead of
  breaking.

**Verified**
- Every wire shape here was captured from the live API rather than the spec -
  including the 400/404/429 bodies and the `per_page` clamp at 100 - and the
  client was then run against production to confirm it parses what the server
  actually sends. 37 tests, up from 22.

```
NEW: comments. Every Sejbosejbo now has a thread - say your piece, anonymously,
no account needed. Comment counts show on the cards.

Your own comments are marked so you can find them again.

Also groundwork for audio and video posts, so the app keeps working when they
arrive.
```

---

## 1.5.1+7

Fixes a device-support regression introduced in 1.5.0.

**Fixed**
- **Restored support for 27 devices** that 1.5.0 silently dropped. The crop
  activity added in 1.5.0 carried `android:screenOrientation="portrait"`, and
  Android turns any such attribute into an *implied hard requirement* on
  `android.hardware.screen.portrait` — which excludes every device that cannot
  do portrait: landscape-only tablets, Chromebooks, TVs. Play surfaces this as
  "this release supports fewer devices than the previous release".
- Both `screen.portrait` and `touchscreen` are now declared explicitly as
  `required="false"`, so a future activity orientation cannot quietly
  re-introduce the requirement.

Nothing else changes. The app never locked orientation anywhere else — no
`setPreferredOrientations` in Dart, no `screenOrientation` on MainActivity — so
the crop screen simply now rotates like every other screen.

```
Fixes an issue that made the app unavailable on some tablets and Chromebooks.
No other changes.
```

---

## 1.5.0+6

Photos no longer get cropped, plus a built-in editor and working deep links.

**Changed**
- Post detail shows the **whole image**. It used `BoxFit.cover`, which crops —
  and since most posts are tall phone screenshots, it was cutting off the top
  and bottom, usually where the punchline is. Now `contain`, capped at 78% of
  screen height. Uploads were never cropped; this was display-only, so nothing
  already posted was lost.
- Gallery cards show a **PINNED** badge, so a pinned post sitting above newer
  ones is explicable rather than looking like a sorting bug.

**Added**
- **Crop / rotate editor** (`image_cropper`) behind an EDIT button once an image
  is selected. Aspect ratio unlocked by default so tall screenshots are not
  forced square. Works for pasted images too, which have no file path — they are
  written to a temp file first.
- **Android App Links**: `sejbosejbo.fyi/post/<id>` opens the app instead of the
  browser. Verified on device.

**Known / blocked**
- App Links will not verify for real users until the website serves
  `/.well-known/assetlinks.json`, which currently 404s. See
  `docs/API_REQUEST_pinned.md`.
- A dedicated PINNED tab needs `sort=pinned` on the API — same document.

```
Photos are no longer cropped - tall screenshots now show in full instead of
losing their top and bottom.

New: crop and rotate your photo before posting, straight from the upload screen.

Links to sejbosejbo.fyi posts now open the app instead of the browser.

Pinned posts are labelled in the gallery, so it is clear why they sit above
newer ones.
```

---

## 1.4.0+5

Version aligned with the website and Docker image. No functional change.

```
Version number now matches the website, so it is obvious which release you are
looking at. No other changes.
```

---

## 1.1.0+4

**Added**
- **In-app reporting** on every post — five reasons plus optional detail.
  Required by Google Play's UGC policy and Apple Guideline 1.2; an app hosting
  user submissions must let users flag it from inside the app.
- Privacy policy, terms and website links on the Support tab.

```
You can now report a post from inside the app if something is wrong with it.
Reports go to a human, not an automated filter.

Privacy policy and terms are now linked from the Support tab.
```

---

## 1.0.0+3

**Fixed**
- **Image uploads always failed.** `package:http` labels every multipart file
  `application/octet-stream`, and the server only accepts real image types, so
  every upload was rejected regardless of the file. The type is now sniffed from
  the file's magic bytes rather than its name, since the picker can hand back a
  `.jpg` that is really a PNG.
- `createPost` now reuses the shared HTTP client. `BaseRequest.send()` builds its
  own one-shot client, which discarded the connection pool on every upload and
  made the path untestable.

```
Fixed uploading photos - it failed every time, whatever you picked.
```

---

## 1.0.0+2

**Fixed**
- Android package renamed to `com.thekingziga.sejbosejbo` to match the Play
  listing. Play matches the package inside the bundle manifest against the
  registered app, so uploads were being rejected and the release showed as
  having no bundle at all — with three error messages, none of which named the
  actual cause.

---

## 1.0.0+1

First build. Dashboard, gallery, upload and support, on a neo-brutalist design
carried over from the website.

- Browse the archive; upload a photo, a pasted screenshot, or a text-only story
- **SEJ BO / SEJ NE BO** voting, optimistic with rollback on failure
- Hall of Fame ranking, daily award, NEWEST / TOP / FEATURED gallery sorting
- Native share sheet, EN/SL switching, offline cache of the last feed
- Donations split by platform: store billing on mobile because Apple and Google
  require it, Stripe on desktop
