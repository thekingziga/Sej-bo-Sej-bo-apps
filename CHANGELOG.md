# Changelog

Every release, newest first. `versionName` tracks the website and Docker image;
the `+N` build number is Play's `versionCode` and only ever increases — Play
burns each value permanently, so it never resets when the semver part changes.

Each entry has a **Play release notes** block, already trimmed to Play's
500-character limit, ready to paste into "What's new in this release".

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
