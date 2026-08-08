# Request to the website chat: turn on `/.well-known/assetlinks.json`

Paste everything below the line into the website chat. It is written to be
self-contained — that chat does not need any of the app context.

Short version for our own records: **no code change is needed.** The route
already exists and is already deployed. It 404s only because
`ANDROID_CERT_SHA256` is unset in the Pi's `.env`, and `lib/wellKnown.js`
deliberately 404s rather than serve a half-built association file.

---

## Android App Links are broken in production — `assetlinks.json` returns 404

`https://sejbosejbo.fyi/post/<id>` links open the browser instead of the
installed Android app. The app side is fine; the site is not serving the
Digital Asset Links statement, so Android has nothing to verify against and
falls back to the browser.

### Evidence

```
$ curl -sS -o /dev/null -w "%{http_code}\n" https://sejbosejbo.fyi/.well-known/assetlinks.json
404
```

Google's verifier agrees:

```
$ curl -s "https://digitalassetlinks.googleapis.com/v1/statements:list?\
source.web.site=https://sejbosejbo.fyi&\
relation=delegate_permission/common.handle_all_urls"

"* Error: unavailable: Error fetching statements from
 https://sejbosejbo.fyi./.well-known/assetlinks.json: 404 Not Found"
```

### This is config, not code — please don't patch `lib/wellKnown.js`

The route is already written and already deployed. `lib/wellKnown.js:39`
returns 404 when `ANDROID_CERT_SHA256` is empty, on purpose: an absent file
makes links fall back to the website, whereas a malformed one can get Android
to cache a bad verification result. The env var is simply not set on the Pi.

The current image is up to date — `GET /api/v1/posts?sort=pinned` returns 200,
which is the most recent API change — so **nothing needs rebuilding or
pushing.** This is an `.env` edit plus `docker compose up -d`.

### The fix

On the Pi, in `/home/pidocker/sejbosejbo/.env`, add one line — both
fingerprints, comma-separated, no spaces:

```
ANDROID_CERT_SHA256=55:B5:A8:A8:F3:17:5A:EE:C2:1A:46:F4:48:01:3C:8B:2C:94:E8:36:84:A4:BC:48:FC:2B:4D:DF:E5:20:71:29,F5:0E:41:67:4B:01:45:4C:5A:11:05:F0:7F:B4:D2:52:CE:09:23:62:49:11:19:90:8F:80:59:DA:98:99:16:C9
```

Then:

```
cd /home/pidocker/sejbosejbo && docker compose up -d
```

`deploy/docker-compose.yml:30` already passes the variable through, and
`deploy/.env.example:33` already documents this exact value — the running
`.env` was just never updated to match.

### Why both fingerprints, not one

Both are required, and listing only one silently half-breaks App Links —
they keep opening the browser on whichever install path was omitted, with no
error anywhere.

| Fingerprint | Which build carries it |
|---|---|
| `55:B5:A8:…:71:29` | **Play App Signing (deployment) cert.** Play re-signs every build it distributes, so this is what users installing from Play actually have. |
| `F5:0E:41:…:16:C9` | **Upload key.** What a directly-installed / sideloaded test build is signed with. Verified against the real signed APK: `CN=ziga vodnjov frelih, OU=thekingziga, O=thekingziga, L=ljubljana, ST=domzale, C=SI`. |

The package name is `com.thekingziga.sejbosejbo` — this is the Android
package, which is *not* the same as the iOS bundle id. `lib/wellKnown.js`
already defaults to it, so `ANDROID_PACKAGE_NAME` does not need setting.

### How to confirm it worked

```
curl -s https://sejbosejbo.fyi/.well-known/assetlinks.json
```

Expected: HTTP 200, `Content-Type: application/json`, a JSON **array** whose
single object has `relation: ["delegate_permission/common.handle_all_urls"]`
and both fingerprints under `target.sha256_cert_fingerprints`.

Then re-run the Google verifier command above — it must come back with no
`ERRORS` block. That is the authoritative check; a 200 from curl only proves
the file is served, not that Android will accept it. Note the verifier caches
for ~10 minutes (`maxAge: 599s`), so allow for that.

### Please leave `apple-app-site-association` 404ing

It needs a real `APPLE_TEAM_ID`, and there is no Apple Developer account yet.
A guessed or placeholder team id is worse than a 404, because iOS caches the
failed association. It is correctly gated behind the same pattern already.

### Not part of this request, but still open on the site

Two test rows from earlier debugging want cleaning up in `/admin`: post id
`32` ("MIME test - delete me"), and the test report filed against post `#23`.
