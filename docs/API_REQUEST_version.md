# Request to the website chat: `/api/v1/app-version` + a version in the footer

Paste everything below the line into the website chat.

The app side is already built and shipped in 1.9.0. It calls this endpoint on
launch, and **does nothing at all** until the endpoint exists — no gate, no
nag, no error. So this can land whenever.

---

## Two small things: a version footer, and an app-version endpoint

### 1. Show the site's version in the footer

Put the running version somewhere unobtrusive at the bottom of the page —
`v1.13.0` is enough. Read it from `package.json` at startup rather than
hardcoding a string, or it will drift the first time someone forgets.

The point is bug reports: right now neither of us can tell which build a user
is on. The app now shows its own version on the Support tab and will show the
site's next to it once the endpoint below exists.

### 2. `GET /api/v1/app-version`

```json
{
  "min_version": "1.5.0",
  "latest_version": "1.9.0",
  "server_version": "1.13.0",
  "message": "Voting moved to the server; older builds show wrong counts."
}
```

All four fields optional. Same conventions as the rest of `/api/v1`: JSON,
CORS-open, `Cache-Control: no-store`, no auth.

| field | meaning |
|---|---|
| `min_version` | Oldest app version still allowed to run. Anything older gets a full-screen "update required" wall it cannot dismiss. |
| `latest_version` | Newest version in the store. Non-blocking. |
| `server_version` | The website's own version, shown beside the app's. |
| `message` | Optional one-liner shown on the wall explaining why. Keep it short and factual. |

Drive them from env vars (`APP_MIN_VERSION`, `APP_LATEST_VERSION`,
`APP_UPDATE_MESSAGE`) so forcing an update is an `.env` edit plus
`docker compose up -d`, with no rebuild. Leave `APP_MIN_VERSION` **unset** by
default — that is the safe state and it means "block nobody".

### The one thing to get right

**`min_version` is a loaded gun.** Setting it to a version that is not yet
downloadable locks every user out of an app they have no way to fix — the app
cannot ship its own escape hatch, only the store can. So:

- Only raise it **after** a release is fully rolled out in Play, never at the
  same time as an upload. Play rolls out gradually; for hours after publishing
  there are users who literally cannot get the new build yet.
- Raise it to the **oldest version that still works**, not to the newest one
  that exists. It is a compatibility floor, not a "please upgrade" nag — that
  is what `latest_version` is for.
- Serving no value at all is always safe.

The app is deliberately paranoid on its side to match: an absent, empty, or
unparseable `min_version` never blocks, and any failure to reach this endpoint
(404, 500, offline, HTML from a captive portal) is treated as "no opinion" and
lets the user straight through. A version gate that fails closed would brick
every install the moment the Pi hiccupped.

Versions are compared numerically, segment by segment, so `1.10.0` correctly
counts as newer than `1.9.0` — please compare the same way if you ever validate
server-side, rather than with a string compare.

### Not part of this request

Nothing else changes. Do not add a version to any other response, and do not
gate any existing endpoint on the app's version — the app sends no version
header, and this endpoint is the only place the check belongs.
