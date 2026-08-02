# Prompt for the website chat

Paste everything below the line into a new Claude Code session opened in
`/Users/ziga/Projects/PROJECT/sejbosejbo.fyi`. It is written to be self-contained.

---

I need to add a JSON API to this website so a Flutter app (iOS, Android, macOS,
Windows) can talk to it. The app is already built against the exact contract
below — **do not change field names, types, or URLs**, or the app breaks.

## How this thing is deployed (read first)

- Node + Express, no framework, HTML generated as template strings in
  `server.js`. SQLite via Node's built-in `node:sqlite`.
- Runs in Docker on a Raspberry Pi. `data/` (SQLite) and `uploads/` (images) are
  bind mounts on the host — never inside the container, never delete them.
- **Public on `https://sejbosejbo.fyi` behind Cloudflare.** TLS is already
  working; plain HTTP returns 503. Nothing to do for certificates.

Everything lives on the **same origin**, `https://sejbosejbo.fyi/api/v1`. Do not
move the API to a subdomain: the app's deep links point at `sejbosejbo.fyi/post/…`,
and the association files that make those work must be served from that exact
host, so a subdomain would only add a second thing to configure.

### Cloudflare gotchas that will bite

1. **`req.ip` is Cloudflare's IP, not the user's.** Rate limiting as-is would
   throttle every user as one. Add `app.set('trust proxy', true)` and read the
   real address from the `CF-Connecting-IP` header, falling back to `req.ip`.
   Get this right or the vote and upload limits below are worse than useless —
   one busy user would lock out everyone.
2. **Send `Cache-Control: no-store` on all `/api/v1` responses.** Cloudflare
   currently reports `cf-cache-status: DYNAMIC`, but any future caching rule
   would serve stale vote counts and feeds.
3. `/.well-known/*` must be served directly, uncached, with
   `Content-Type: application/json`, and must not redirect.

## Ground rules

- Everything lives under `/api/v1`. The existing HTML routes must keep working
  exactly as they do now; this is additive.
- Responses are JSON with `Content-Type: application/json; charset=utf-8`.
- Errors return the right HTTP status and a body of `{"error": "human readable"}`.
- All timestamps are **ISO 8601 UTC with a `Z` suffix**. The DB currently stores
  SQLite `CURRENT_TIMESTAMP` as `YYYY-MM-DD HH:MM:SS` in UTC, so convert on the
  way out — do not send the raw column.
- All image URLs are **absolute** (`https://sejbosejbo.fyi/uploads/…`), never
  relative. The app has no base URL to resolve them against.
- `lang` query param accepts `en` or `sl` and drives the localised strings
  (quotes, phrases) using the existing `i18n` object. Default `en`.
- Add permissive CORS (`Access-Control-Allow-Origin: *`) on `/api/v1` only.
  Native apps do not need it, but the Flutter web build does, and it keeps
  browser testing possible.
- Do not require auth for reads or uploads — the site is anonymous by design.
  Do add basic rate limiting on the write endpoints (see below).

## The Post object

Used everywhere a post appears:

```json
{
  "id": 12,
  "title": "Microwaved a salad",
  "description": "It was warm. It was wrong.",
  "kind": "image",
  "image_url": "https://sejbosejbo.fyi/uploads/1784413785433-82067194ba2c0f24.jpg",
  "featured": false,
  "pinned": false,
  "created_at": "2026-07-19T00:29:00Z",
  "upvotes": 128,
  "downvotes": 6
}
```

- `kind` is `"image"` or `"story"`.
- `image_url` is `null` for text-only posts.
- `featured` / `pinned` are real booleans, not the 0/1 the DB stores.
- Hidden posts (`hidden = 1`) must never appear in any endpoint.
- `upvotes` / `downvotes` are the raw counts. Do **not** send a pre-computed
  score; the app derives it as `upvotes - downvotes`.

## Endpoints

### `GET /api/v1/feed?lang=en`

Everything the app dashboard needs in one round trip.

```json
{
  "stats": { "visits": 1337, "uploads": 42, "days_since_last": 3 },
  "quote": "That's a certified Sejbosejbo.",
  "daily": { /* Post, or null */ },
  "posts": [ /* 4 newest visible Posts, newest first */ ],
  "top": [ /* 3 highest-scoring Posts of all time, best first */ ]
}
```

`top` drives the Hall of Fame block and is ordered by `upvotes - downvotes`
descending, tie-broken by `upvotes` descending then newest first.

- `days_since_last` is whole days since the newest visible post's `created_at`,
  or `null` if there are no posts. This already exists in `server.js` as the
  `daysSince()` helper — reuse it.
- `quote` is a random entry from the language's `quotes` array.
- `daily` is the existing `getDailyUpload()` (deterministic per calendar day).
- `posts` is the 4 newest, honouring `pinned DESC` like the website does.
- Hitting this endpoint should **not** increment the visitor counter — that
  counter is for humans on the website. Add a separate app counter if you want
  one, but do not inflate `visits`.

### `GET /api/v1/posts?page=1&per_page=24&lang=en&sort=newest`

Paginated gallery.

```json
{ "items": [ /* Posts */ ], "page": 1, "per_page": 24, "has_next": true }
```

`sort` is one of:

| value | ordering |
|---|---|
| `newest` (default) | `pinned DESC`, then newest first — same as the website |
| `top` | `(upvotes - downvotes) DESC`, then `upvotes DESC`, then newest |
| `featured` | only `featured = 1`, newest first |

An unknown `sort` value falls back to `newest` rather than erroring.

Clamp `per_page` to a max of 50. `page` is 1-based; page beyond the end returns
an empty `items` and `has_next: false`, not a 404.

**Pagination and `top` do not mix safely by accident**: if someone votes while a
user is paging, rows shift between pages. Order by a fully deterministic key —
include `id` as the final tie-break — so the sort is at least stable.

### `GET /api/v1/posts/:id`

A single Post object, or `404` with `{"error": "..."}` if missing or hidden.

### `POST /api/v1/posts`

`multipart/form-data`, mirroring the existing upload route's rules:

- `title` — required, trimmed, max 120 chars
- `description` — optional, trimmed, max 1200 chars
- `image` — optional file; jpeg/png/gif/webp only, max 8 MB

Must have a title, and at least one of description or image — same validation as
the current `POST /upload`. Reuse the existing multer config.

Returns `201` with the created Post object. On validation failure return `400`
with `{"error": "..."}`.

**Rate limit this**: max ~5 uploads per IP per 10 minutes, returning `429` with
`{"error": "..."}`. Right now there is nothing stopping someone scripting a
flood of uploads straight into the Pi's SD card, and the app makes that easier.

### `POST /api/v1/posts/:id/vote`

The "sej bo / sej ne bo" vote. Body:

```json
{ "value": 1 }
```

`value` is `1` (sej bo — yes, this is Sejbosejbo), `-1` (sej ne bo), or `0` to
withdraw a previous vote. Reject anything else with `400`.

Returns the **full updated Post object** with fresh counts, so the app can
replace its optimistic guess with the truth.

#### Identifying the voter without accounts

The app sends a random id it generated on first launch:

```
X-Device-Id: 3f9a1c...
```

Store one row per `(post_id, device_id)`. A repeat call for the same pair
**updates** the existing row rather than inserting — that is what makes
switching from sej bo to sej ne bo, or undoing, work.

Be clear-eyed about what this is: **soft protection, not security.** Anyone can
clear app data or forge the header and vote again. Do not present these counts
as trustworthy. Additionally:

- Rate-limit votes per IP (say 60/minute) so a script cannot trivially inflate a post.
- Treat a missing or malformed `X-Device-Id` as `400`, not as a shared bucket —
  otherwise every such caller collides on one row.
- Never let `value` be summed from the client. Recompute `upvotes`/`downvotes`
  from the votes table.

#### Votes table

```sql
CREATE TABLE IF NOT EXISTS votes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  post_id INTEGER NOT NULL REFERENCES uploads(id) ON DELETE CASCADE,
  device_id TEXT NOT NULL,
  value INTEGER NOT NULL CHECK (value IN (-1, 1)),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (post_id, device_id)
);

CREATE INDEX IF NOT EXISTS idx_votes_post ON votes(post_id);
```

A `value` of `0` deletes the row rather than storing a zero — the `CHECK`
constraint enforces that.

`ON DELETE CASCADE` matters: the admin page can delete uploads, and orphaned
votes would otherwise keep counting toward totals.

Counts can be derived with a join, but if the archive grows, denormalise
`upvotes`/`downvotes` onto `uploads` and update them in the same transaction as
the vote. Do not compute them with a subquery per row in a list endpoint.

### `GET /api/v1/random-phrase?lang=en`

```json
{ "phrase": "Certified Sejbosejbo" }
```

Same phrase pool as the existing `/api/random-phrase`.

## Donations

The app supports the platform each store requires:

- **iOS / Android / macOS** → Apple StoreKit and Google Play Billing. Required
  by store policy; linking out to Stripe from those apps is a rejection.
- **Windows** → Stripe Checkout in the browser.

### `POST /api/v1/donations/stripe/session`

Body `{"tier_id": "small" | "medium" | "large"}`. Creates a Stripe Checkout
Session for a one-off payment and returns:

```json
{ "url": "https://checkout.stripe.com/c/pay/..." }
```

Amounts: `small` = €2.00, `medium` = €5.00, `large` = €15.00. **Take the amount
from a server-side map keyed by `tier_id` — never from the request body**, or
anyone can donate one cent and claim the large tier. Use `STRIPE_SECRET_KEY`
from env; never hardcode it or commit it.

### `POST /api/v1/webhooks/stripe`

Standard Stripe webhook. Verify the signature with `STRIPE_WEBHOOK_SECRET`,
handle `checkout.session.completed`, and record the donation. This endpoint
needs the **raw** request body, so mount it before `express.json()`.

### `POST /api/v1/donations/apple/verify` and `/api/v1/donations/google/verify`

Body `{"product_id": "...", "token": "..."}`. The app sends the store receipt
here after a purchase. Verify server-side — Apple's App Store Server API,
Google's Play Developer API — then record the donation. **Never trust the client
that a purchase happened**; a receipt is only meaningful once the store confirms
it. Return `200` on success, `400` on an invalid receipt.

Product IDs the app already uses:

```
fyi.sejbosejbo.tip.small
fyi.sejbosejbo.tip.medium
fyi.sejbosejbo.tip.large
```

### Donations table

Add a table to record confirmed donations so there is a record independent of
Stripe/Apple/Google dashboards:

```sql
CREATE TABLE IF NOT EXISTS donations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source TEXT NOT NULL,          -- 'stripe' | 'apple' | 'google'
  tier_id TEXT,
  amount_minor INTEGER,          -- cents, never a float
  currency TEXT DEFAULT 'EUR',
  external_id TEXT UNIQUE,       -- session id / transaction id, for idempotency
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

`external_id` being `UNIQUE` is what makes webhook retries and purchase replays
idempotent — Stripe and Apple both redeliver, and without it you double-count.

## Deployment reminders

- The site ships as a Docker image (`thekingziga/sejbosejbo`) that runs on a
  Raspberry Pi. `data/` and `uploads/` are bind mounts and must not be touched.
- New env vars (`STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, Apple/Google
  credentials) need adding to `deploy/docker-compose.yml` and `.env.example` —
  with **placeholders only** in the committed example file.
- Bump the version and rebuild per the README's build section.

## Deep links

The app registers `https://sejbosejbo.fyi/post/<id>` so tapping a shared link
opens the app instead of the browser. That requires two files served from this
site, over HTTPS, with `Content-Type: application/json`, no redirect, no auth:

### `/.well-known/apple-app-site-association`

No file extension. Serve it as JSON anyway.

```json
{
  "applinks": {
    "details": [
      { "appIDs": ["TEAMID.fyi.sejbosejbo"], "components": [{ "/": "/post/*" }] }
    ]
  }
}
```

### `/.well-known/assetlinks.json`

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "fyi.sejbosejbo",
      "sha256_cert_fingerprints": ["SIGNING_CERT_SHA256"]
    }
  }
]
```

**Both files need values that do not exist yet** — `TEAMID` comes from an Apple
Developer account, and `SIGNING_CERT_SHA256` from the Android signing key. Build
the routes now and read the values from env vars (`APPLE_TEAM_ID`,
`ANDROID_CERT_SHA256`), returning 404 when unset. Until they are filled in,
shared links simply open the website — which is a perfectly fine fallback, so
do not block anything else on this.

## Website UI changes (not just the API)

The app is not the only client. Do these on the site itself too, or the two
will visibly disagree:

### 1. Paste an image from the clipboard on the upload form

Screenshot → Cmd/Ctrl+V → done, without saving a file first. The app already
does this; the website should match.

Listen for `paste` on the document, pull the image out of
`event.clipboardData.items`, and attach it to the existing file input via a
`DataTransfer` so the normal multipart submit keeps working unchanged:

```js
document.addEventListener('paste', (e) => {
  const item = [...(e.clipboardData?.items || [])].find((i) => i.type.startsWith('image/'));
  if (!item) return;
  const file = item.getAsFile();
  if (!file) return;
  const dt = new DataTransfer();
  dt.items.add(file);
  document.querySelector('input[name="image"]').files = dt.files;
  // then show a preview so it is obvious the paste landed
});
```

Two things to get right:
- Pasted files are often named `image.png` with no extension variety. The
  existing multer `filename` callback derives the extension from
  `originalname`, so a paste can produce an extensionless file — fall back to
  the MIME type when the extension is empty.
- Show a visible preview. A paste with no feedback feels broken, and the user
  cannot tell whether it worked before submitting.

### 2. Vote buttons on the website

Add SEJ BO / SEJ NE BO to the post page and the gallery cards, hitting the same
`POST /api/v1/posts/:id/vote`. The browser has no app-generated device id, so
mint one and keep it in a cookie or `localStorage`, then send it in the same
`X-Device-Id` header.

### 3. A "top" view

The gallery already paginates; add `?sort=top` and a link, matching the app's
NEWEST / TOP / FEATURED switch. Reuse the same ordering rules as the API so a
post cannot rank differently in the two places.

## Order of work

Do it in this order so I can point the app at a working API as early as
possible:

1. `GET /feed`, `GET /posts`, `GET /posts/:id`, `GET /random-phrase` — read-only,
   unblocks the whole app immediately.
2. `POST /posts` — upload, with the rate limit.
3. Voting: the `votes` table, `POST /posts/:id/vote`, and `sort=top`.
4. Website UI: clipboard paste, vote buttons, top view.
5. Donations (Stripe + receipt verification) and the deep-link files last —
   both need external accounts that may not exist yet.

## When you are done

- Tell me the base URL to point the app at. I will build with
  `--dart-define=API_BASE_URL=https://sejbosejbo.fyi`.
- Confirm each endpoint with a real `curl` against the live site, showing actual
  output — not a local-only test. Cloudflare sits in front, so something can
  pass locally and still fail in production.
- Confirm `CF-Connecting-IP` is being used for rate limiting, by showing that
  two different clients are counted separately.
- Bump the version and rebuild the Docker image per the README, then deploy with
  `docker compose pull && docker compose up -d` on the Pi. Uploads and the
  visit counter must survive — they are bind mounts, so they will, but verify.
