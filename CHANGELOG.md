# Changelog

Every release, newest first. `versionName` tracks the website and Docker image;
the `+N` build number is Play's `versionCode` and only ever increases — Play
burns each value permanently, so it never resets when the semver part changes.

Each entry has a **Play release notes** block, already trimmed to Play's
500-character limit, ready to paste into "What's new in this release".

---

## 1.18.0+25

**Fixed**
- **Android's back button closed the app from any opened screen.** Open a post
  from Home or the Gallery, press back, and you were on the launcher. Every
  tab has its own navigator, but the system back button is delivered to the
  root one, which only holds the tab bar - so it had nothing to go back to but
  out. It is routed into the tab you are on now. That needed one more guard:
  Flutter calls every tab's back handler on every press, disabled ones
  included, so without checking which tab is showing, one press would have
  closed an open post on every tab at once. Both are tested and
  mutation-checked; the first is how the app has behaved since tabs got their
  own navigators.
- **A button given a bounded height grew to fill it.** `BrutalButton` centred
  its label with no height factor, which never showed in scrolling lists but
  turned a floating button into a pink column down one side of the screen.

**Added - dormant until the website ships its API**
- **The marketplace, natively in the app**, in the website's own style: a
  two-column grid with search and sort, the yellow price tag and the rotated
  red SOLD stamp, listing pages, selling with a photo, an inbox where unread
  threads are yellow, chat with offers that turn green when accepted, block
  and report, and an account page with in-app account deletion, which Play
  requires of any app that creates accounts.
- **Login by emailed code**, because the website's emailed *link* signs in a
  browser, and claiming those links for the app would break login on the web.
- **The tab appears on its own when the server has the marketplace.** The app
  asks once at launch; against today's server there is no tab at all. This
  release ships with the marketplace invisible, and lights up without another
  update once `docs/API_REQUEST_marketplace.md` is implemented - which is why
  Data safety has to be updated *before* that deploy, not after it.
- Until then the whole thing runs against a built-in demo marketplace in
  debug builds, which is what the 25 new tests and the on-device walkthrough
  exercised: browse, log in, reopen an existing thread rather than start a
  duplicate, accept an offer, see a reply arrive by polling, sell, delete the
  account.

The website shipped the API on 2026-10-04, before this release went out, so
these notes announce the marketplace after all. Checked against the live
server: the tab appears on its own, real listings and photos load, and every
error the app branches on comes back exactly as the contract says.

```
New: Sejbo Market. Buy and sell stuff right in the app - browse listings, message sellers and make offers. Log in with a code sent to your email, no password.

Also: Android's back button now goes back one screen instead of closing the app.
```

Slovenian:

```
Novo: Sejbo tržnica. Kupuj in prodajaj kar v aplikaciji - brskaj po oglasih, piši prodajalcem in daj ponudbo. Prijava s kodo, ki jo dobiš po e-pošti, brez gesla.

Poleg tega: gumb za nazaj na Androidu zdaj gre en zaslon nazaj, namesto da zapre aplikacijo.
```

---

## 1.17.0+24

**Added**
- **The website's marketplace, from the Support tab.** Server 1.39.0 added
  classified ads with messaging and offers at `/marketplace`. There is no JSON
  API for it, so this is a link rather than a screen - it sits above the policy
  links, because it is somewhere to go rather than fine print, and it carries
  the app's own language so the page opens in the one you are already reading.

**Deliberately not done**
- **Not a WebView.** Signing in there is an emailed link, which opens in the
  system browser and sets the session cookie *there* - a WebView keeps its own
  cookie jar, so the user would sign in somewhere the app cannot see and still
  look signed out inside it. A WebView would also make everything collected on
  those pages count as collected by the app, which would change the Play data
  safety answers. The external browser leaves them exactly as they were.
- **The App Links filter was not widened**, and there is now a test holding it
  to `/post`. If it ever claimed `/login` or `/marketplace`, Android would hand
  the sign-in email's link to an app with no screen for it, and the account
  would be unreachable.

```
The sejbosejbo marketplace is now one tap away, in the Support tab. It opens in
your browser, where your account and messages already live.
```

---

## 1.16.3+23

**Fixed**
- **Every upload from the app failed.** Not just video, not just large files -
  every one, including a story with no file at all, since 1.16.0. The upload
  progress bar was added in that release, and it swaps the multipart request
  for a re-streamed one so the bytes can be counted. It copied the headers
  across *before* finalising the request - and a multipart request does not
  know its own boundary until it is finalised, because that is the line where
  it writes `content-type: multipart/form-data; boundary=...`. So the request
  went out with no content type at all. The whole file was uploaded, the
  progress bar ran to 100%, and then the server could not parse a single field
  out of the body and answered "Add a title and either an image/GIF or a
  story." - which reads like a validation bug and is not one.

  Reproduced against a real socket rather than a mock: 2,721,678 bytes
  received, `content-type: null`. The tests missed it because none of them
  passed a progress callback, so none of them took that path; the new one does,
  and checks that the boundary in the header is the one the body actually uses.

```
Fixes uploading. Photos, GIFs, audio, video and stories all failed to post -
the file was sent but the server could not read it. Sorry about that.
```

---

## 1.16.2+22

Play's release dashboard raised three "recommended actions" against 1.16.1.
One was worth acting on, one was a false positive, one was declined.

**Changed**
- **The status bar sits on paper on every Android version, not just 15 and up.**
  Android 15 forces an app to draw behind the system bars; below that an app has
  to ask, and this one never did - so the same screen had a grey band across the
  top on Android 14 and paper on Android 16. It now asks at startup. Verified on
  both: API 34 goes from grey band to paper, API 36 is pixel-for-pixel unchanged.
- **The window is paper before Flutter's first frame**, rather than white in
  light mode and near-black in dark mode. That was a flash of the wrong colour
  on every cold start.

**Fixed**
- **A tip that could not be verified is no longer treated the same as one the
  store rejected.** The server now answers `400` only when the store itself
  rejects a receipt - final, nothing to retry - and `5xx` when it never got a
  verdict at all. The app had one branch for both, which is wrong in opposite
  directions: on Apple a permanent rejection was left unfinished, and StoreKit
  redelivers an unfinished transaction on every launch for the life of the
  install, so it replayed the same rejection for ever; a transient outage, on
  either rail, risked being read as a rejection. Now a `400` is finished on
  Apple and deliberately left alone on Google, where an unconsumed purchase is
  revoked and refunded after three days - which is the right outcome for a bad
  receipt, and also the safe one for a *pending* Google purchase, which the
  server currently answers `400` to as well. Anything else is left unfinished
  and retried on the next launch, as before.

**Not changed, and why**
- **"Uses deprecated edge-to-edge APIs" is not this app's code.** Play named five
  call sites in minified classes; the R8 mapping resolves all five to
  `androidx.activity.EdgeToEdgeApi23/26/28/29/35` - AndroidX's own helper, at the
  current 1.12.4, where the deprecated calls live in the branches that exist to
  support Android 6 to 10 and are skipped on 15+. `FlutterActivity` extends plain
  `Activity`, not `ComponentActivity`, so this app never even calls into them.
  There is no version to upgrade to and nothing to rewrite.
- **The navigation bar stays black on Android 14 and below.** Android 10+ takes
  the gesture bar's colour into its own hands. Transparent, paper, and the window
  theme were all tried and all measured black; its white pill is legible as it is,
  and asking for dark icons over it would have made things worse, not better.
- **Picture-in-picture** was declined. It is native plumbing on both sides of the
  platform channel for a feed of joke clips nobody watches while doing something
  else.

```
The status bar now matches the app on every Android version instead of only the
newest ones, and the app no longer flashes the wrong colour when it starts.
```

---

## 1.16.1+21

**Fixed**
- **A rejected upload kept complaining after you fixed it.** The error box
  holds the server's own words - "Add a title and either an image/GIF or a
  story." - and it was cleared when you picked a file or pressed submit, but
  never when you typed. So a failed attempt left its complaint on screen while
  you supplied exactly what it asked for, which reads as the app refusing input
  it has already accepted. Editing either field now retracts it.

```
Fixed an error message that stayed on the upload screen after you had already
fixed the problem.
```

---

## 1.16.0+20

Uploading audio and video, the piece left out of 1.15.0.

**Added**
- **An AUDIO / VIDEO button on the upload screen**, alongside camera, library
  and paste. Picks mp3, m4a, ogg, wav, weba, mp4, webm and mov.
- **Real progress while uploading** - a percentage, not a spinner. A 500MB
  video is minutes of work on mobile data, and a spinner that never moves is
  how someone decides the app has hung and kills it mid-transfer. Submit stays
  disabled throughout.
- **Magic-byte sniffing extended to audio and video.** Two cases needed care:
  mp4, mov and m4a all carry `ftyp` at offset 4 and differ only by the brand
  after it, so an m4a would otherwise upload as video; and WEBP and WAV share
  the first four bytes `RIFF`, separated only at offset 8, so a sound file
  could go up labelled as a picture.

**Changed**
- **Size is checked before anything is sent**, against the ceiling for that
  type - 100MB image, 500MB audio and video. Pushing half a gigabyte up a phone
  connection only to be told it was too big is the worst way to learn it.
- **The upload timeout is now a stall timeout.** The old 60-second overall
  limit would have killed any large upload on principle; 500MB legitimately
  takes many minutes. The clock now resets on every chunk, so only genuine
  silence aborts.
- `lang` travels with the upload, so the server's 413, 415 and 429 wording
  comes back in the user's language and is shown verbatim.
- Video and audio stream from disk, never through memory. `imagePath` and
  friends are now `mediaPath` - the wire field is still `image`, which is the
  server's name for it, not a claim about the contents.

**Proof**
- Both guards mutation-tested: collapsing the per-type ceiling to one value,
  and dropping the m4a brand check, each turn the suite red. 112 tests, up
  from 101.

```
You can now post audio and video, not just photos. Uploads show a percentage
as they go, since a big video takes a while.
```

---

## 1.15.0+19

Video and audio posts now play in the app.

**Added**
- **Video posts play on the detail screen** - streamed progressively, tap to
  start, with a scrubbable progress bar. Nothing plays automatically.
- **Audio posts get a player** built on audioplayers, already present for the
  theme music rather than a second audio stack.
- **The theme music steps aside** while a post plays, and comes back when it
  finishes, is paused, or the screen closes. Two things sounding at once is
  never what anyone wanted.

**Changed**
- Rendering branches on `kind` at both sites - list and detail - and never on
  the file extension. A large video is re-encoded overnight and its extension
  can change while the kind does not.
- **A list never opens a video.** Video and audio posts show a poster in the
  feed: no controller, no connection, nothing fetched. A video can be 500MB,
  and a grid that eagerly opened each one would empty a data plan by being
  scrolled. Streaming happens only on the detail screen.
- An unrecognised kind still degrades to the "open it on the website" card, so
  whatever the server adds next cannot break an installed build.

**On the reported crash**
- Worth recording that the app was **not** crashing on these posts. Unknown
  kinds have been gated ahead of any image decode since 1.6.0, with a test
  asserting an `.mp4` never reaches `Image.network`. Audio and video rendered
  as an "open on the website" card rather than failing. This release turns that
  fallback into real playback; it was a missing feature, not a live fault.

**Not done**
- Uploading audio and video, which the brief marked optional. The upload screen
  still offers images only. Worth doing next, and it needs progress from bytes
  sent and a much longer timeout before a 500MB file is survivable on mobile.

```
Video and audio posts now play right in the app. Tap a video to start it - it
streams, so scrolling the gallery never downloads one.
```

---

## 1.14.0+18

**Added**
- **The website's theme music**, same track, same loop, same 0.3 volume, with
  an on/off switch on the Support tab that remembers your choice. The file is
  bundled rather than streamed, so it costs the Pi no bandwidth and works
  offline.
- Playback **stops when the app goes to the background** and resumes on return.
  Music that keeps going after you have left is the fastest way to earn an
  uninstall.

**Deliberate difference from the website**
- **It is off by default here, where the site defaults on.** That is less of a
  difference than it sounds: a browser refuses to start unmuted audio until the
  visitor clicks something, so the site's default is really "on once you
  interact". An app has no such brake - music at launch would cut off whatever
  the phone was already playing, which is a much ruder thing to do than in a
  tab. Say the word and I will flip it.

```
The website's theme music is now in the app too, with a switch on the Support
tab. It starts off, so it will never interrupt whatever you are listening to.
```

---

## 1.13.0+17

**Added**
- **Push notifications for new posts.** One notification when something is
  posted, and nothing else. Registration happens on every launch (the endpoint
  is idempotent) and again whenever Firebase rotates the token, since a stale
  token is a notification that goes nowhere.
- **Tapping a notification opens that post**, not the home screen - keyed off
  `data.post_id` rather than parsing the URL, and wired for all three states:
  foreground, background, and terminated via `getInitialMessage`. The last is
  the easy one to miss, since the message is delivered once at startup and
  never appears on a stream.
- **An on/off switch on the Support tab**, which unregisters the token server
  side rather than just muting locally. It puts itself back if the change did
  not take - usually a denied OS permission - instead of claiming a state we
  do not have.
- Android notification channel declared in the manifest, so it exists before
  the first message. Android 8+ drops notifications for an unknown channel
  silently, and creating it on first receipt would be too late for that
  message.

**Deliberate**
- Registration does **not** gate on `delivery_enabled`, and its being false is
  never shown to the user. Tokens collected now are kept and receive the first
  notification once the Firebase service account is installed server-side.
- Every failure is silent: no Firebase config, denied permission, offline, or
  the 30/hour register limit. Push is layered on an app that works without it.

**Verified in the built APK**
- `POST_NOTIFICATIONS` present, the Firebase project baked into resources, the
  `sejbosejbo_posts` channel declared, and `FirebaseMessagingService`
  registered. 101 tests, up from 95.

**Still needed server-side**
- The Firebase service account, until which `delivery_enabled` stays false and
  nothing is actually delivered.

```
NEW: get a notification when a new Sejbosejbo is posted. One per post, nothing
else, and you can turn it off on the Support tab.

Tapping a notification takes you straight to the post.
```

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
