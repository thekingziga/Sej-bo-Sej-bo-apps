# Going to production

Written after the closed-testing gate cleared. Two things block a clean
production release, one of them a policy matter; everything else is filling in
Play Console.

---

## Blocker 1 — the privacy policy is out of date

Play requires the Data safety declaration to match the privacy policy, and an
inaccurate policy is a policy violation whether or not anyone notices at
review. Four statements on `sejbosejbo.fyi/privacy` are no longer true:

| The policy says | What the app does now | Since |
|---|---|---|
| "The app generates a random ID on your device" | The **server** mints and signs the id; the app asks for one | 1.12.0 |
| Device id "is sent to us in one situation: when you vote" | Sent on **every request, reads included** - that is how `my_vote` works - and with comments | 1.8.0 |
| "No analytics or crash-reporting SDKs" | Still true, but the app now bundles **Firebase Cloud Messaging** and registers a push token with the server. Google processes it. The policy does not mention notifications at all | 1.13.0 |
| Uploads are "images, GIFs, titles, descriptions" | Audio and video too, up to 500MB | 1.16.0 |

Also stale: "In-app tipping isn't turned on yet" - Stripe is live on desktop.

The wording to fix this is in the reply that accompanied this file; it goes to
the website chat.

## Blocker 2 — two advertised features do not work yet

Neither stops a release, but neither should be advertised in the store listing:

- **Push notifications.** The app registers tokens correctly and the toggle
  works, but nothing is delivered until the Firebase service account is
  installed server-side. Users would switch it on and receive nothing.
- **Tipping on Android.** The Play products exist, but `/donations/google/verify`
  returns 503 without the Google service account, so the app hides the tip UI.
  Correct behaviour, but it means the Support tab shows nothing to buy.

Do not mention either in the listing text until they work. Adding them to a
later listing update costs nothing.

---

## Verified in the built bundle

Checked against the artefact rather than the source, since these are the ones
that fail silently:

- `API_BASE_URL` is baked in - a build without it ships demo mode on sample
  posts, and looks completely normal until you notice the posts are fake
- Signed with the upload key (`CN=ziga vodnjov frelih`), not the debug key
- No `print` or `debugPrint` anywhere in `lib/`
- `uses-feature-not-required` intact for `screen.portrait` and `touchscreen`,
  so the device-support regression of 1.5.0 has not come back
- Permissions are exactly: `INTERNET`, `POST_NOTIFICATIONS`, `WAKE_LOCK`,
  `ACCESS_NETWORK_STATE`, `BILLING`, FCM receive, and the AndroidX dynamic
  receiver. Nothing that needs justifying - no location, contacts or storage

---

## Data safety form

The answers below match the app's actual behaviour. Where Play asks whether
data is "shared", it means transferred to a third party - storing it on our own
server is *collected*, not *shared*.

### Photos and videos
- Collected: **yes**. Shared: **no**. Optional (the user chooses to post).
- Purpose: **App functionality**.
- Note: these are published publicly by design.

### Audio files
- Collected: **yes**. Shared: **no**. Optional. Purpose: **App functionality**.

### Other user-generated content
Titles, descriptions, comments.
- Collected: **yes**. Shared: **no**. Optional. Purpose: **App functionality**.

### Device or other IDs
The signed device id and the FCM push token.
- Collected: **yes**. Shared: **no**. **Required** - the id is sent on every
  request.
- Purposes: **App functionality** (notifications, showing you your own vote)
  and **Fraud prevention, security and compliance** (stopping repeat voting).
- **Not** advertising or personalisation. The app never requests the
  advertising id.

### IP address
Not declared. Play exempts data **processed ephemerally**, and the IP is held
in memory for the rate-limit window and never written to the database. If you
would rather over-declare, put it under Device or other IDs with the security
purpose - over-declaring is never a violation.

### Other answers
- Encrypted in transit: **yes** (HTTPS only; plain HTTP returns 503).
- Users can request data deletion: **yes** - via the in-app report flow and the
  contact address in the policy. There are no accounts to delete.
- Data collection is required, not optional, only for the device id.

---

## The rest of Play Console

- **Content rating** - answer the questionnaire honestly as an *unmoderated
  user-generated content* app. It will ask about sharing, user interaction and
  moderation; the app has in-app reporting and a moderation queue, which is the
  answer it is looking for. Expect Teen or higher; do not aim low.
- **Target audience** - 13+, matching the policy. Do **not** tick any children's
  age band, or the Families policy applies and this app cannot meet it.
- **App access** - no login. Say so; reviewers reject apps whose content they
  cannot reach.
- **Ads** - none.
- **Government / financial features** - none. Tips are not a financial product.

## Rolling out

Use a **staged rollout**, not 100%. Start at 20%. The value is not caution for
its own sake - it is that Play halts a rollout you have not completed, and the
first production build is the first time the app meets devices you have never
seen. Watch Android vitals for a day before widening.

Keep the upload keystore backed up. Losing it means a Google key reset, and
there is no self-service path back.

## Worth doing after launch, not before

- **Crash reporting.** There is none. `firebase_core` is already present, so
  Crashlytics is a small addition - but it changes the privacy policy again and
  wants testing, so it is a poor thing to bolt on the day of a release.
- **R8 minification** is not enabled. It would trim the dex, but Firebase and
  billing use reflection, so it needs real-device testing of the purchase and
  notification paths. Not worth the risk this week.
