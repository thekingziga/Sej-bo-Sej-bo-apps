# Prompt for the website chat

Paste everything below the line into a new Claude Code session opened in
`/Users/ziga/Projects/PROJECT/sejbosejbo.fyi`. It is written to be self-contained.

---

I need to add a JSON API to this website so a Flutter app (iOS, Android, macOS,
Windows) can talk to it. The app is already built against the exact contract
below — **do not change field names, types, or URLs**, or the app breaks.

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
  "created_at": "2026-07-19T00:29:00Z"
}
```

- `kind` is `"image"` or `"story"`.
- `image_url` is `null` for text-only posts.
- `featured` / `pinned` are real booleans, not the 0/1 the DB stores.
- Hidden posts (`hidden = 1`) must never appear in any endpoint.

## Endpoints

### `GET /api/v1/feed?lang=en`

Everything the app dashboard needs in one round trip.

```json
{
  "stats": { "visits": 1337, "uploads": 42, "days_since_last": 3 },
  "quote": "That's a certified Sejbosejbo.",
  "daily": { /* Post, or null */ },
  "posts": [ /* 4 newest visible Posts, newest first */ ]
}
```

- `days_since_last` is whole days since the newest visible post's `created_at`,
  or `null` if there are no posts. This already exists in `server.js` as the
  `daysSince()` helper — reuse it.
- `quote` is a random entry from the language's `quotes` array.
- `daily` is the existing `getDailyUpload()` (deterministic per calendar day).
- `posts` is the 4 newest, honouring `pinned DESC` like the website does.
- Hitting this endpoint should **not** increment the visitor counter — that
  counter is for humans on the website. Add a separate app counter if you want
  one, but do not inflate `visits`.

### `GET /api/v1/posts?page=1&per_page=24&lang=en`

Paginated gallery, newest first, same ordering as the website.

```json
{ "items": [ /* Posts */ ], "page": 1, "per_page": 24, "has_next": true }
```

Clamp `per_page` to a max of 50. `page` is 1-based; page beyond the end returns
an empty `items` and `has_next: false`, not a 404.

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

## When you are done

Tell me the base URL to point the app at, and confirm each endpoint with a
`curl` example showing real output.
