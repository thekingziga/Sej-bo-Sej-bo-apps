# API request: the marketplace, natively in the app

Paste this whole file into the website chat. It asks for a JSON API over the
marketplace that already exists on the site (1.39.0), plus the one genuinely
new piece: a way for the app to log in.

The app side is already built against this contract and runs on demo data
until the endpoints exist. **Field names, paths and status codes below are the
contract** - change one and the app breaks quietly.

---

## Before you deploy this - read first

**The app turns the marketplace on by itself.** At launch it asks
`GET /api/v1/listings?per_page=1`; while that is not JSON (as today), there
is no marketplace tab at all. The moment it answers, every installed copy
shows the tab on its next launch - **no app update in between**.

That makes the deploy itself the moment the app starts collecting an email
address and private messages, so two things must already be done **before**
these endpoints go live:

1. **Play Console → Data safety** updated: *Email address* (collected, for
   account management, linked to the user) and *Other in-app messages*
   (collected, app functionality, linked). The account-deletion URL is
   `https://sejbosejbo.fyi/account`.
2. **The privacy policy** says the app can sign in to a marketplace account by
   emailed code and stores the session token on the device.

The site's own marketplace already collects both on the web, so this is a
paperwork step for the app, not new data. But Play judges the app by what the
app does, and a form that is wrong on the day matters more than one that is
late by a week.

---

## The one rule that matters most

**Do not reimplement any marketplace rule.** Every rule already lives in
`lib/marketplace.js` and `lib/accounts.js` - `createListing`, `markSold`,
`removeOwn`, `startConversation`, `postMessage`, `respondToOffer`,
`openThread`, `reportConversation`, `report`, `setName`, `deleteAccount`.
The JSON routes are thin wrappers: authenticate, call the existing function,
serialise the result. The website and the app must never be able to disagree
about what is allowed, and the only way to guarantee that is one owner.

`conversationForUser` stays the authorisation for every conversation route,
exactly as the HTML routes use it.

---

## 1. App login (new)

The website's emailed **link** cannot work for the app: it opens in the
browser and sets a cookie there, and the App Links filter must stay on
`/post` only (widening it would hand the website's login links to the app,
which cannot handle them, and nobody could log in on the web). So the app
logs in with an emailed **code** instead.

### `POST /api/v1/auth/code`

```json
{ "email": "someone@example.com", "lang": "sl" }
```

Emails a **6-digit code**, valid **15 minutes**, single use. Same email
template family as the login link, wording along the lines of *"Your
sejbosejbo code is 482913. Type it into the app. If you did not ask for it,
ignore this email."*

- `200 {"ok": true}` - **always the same answer** whether or not the address
  has an account, exactly like `requestLogin`, so the endpoint cannot be used
  to find out who has one.
- `400` invalid address, `429` (+ `Retry-After`) - reuse `MAX_RECENT_LINKS`
  (3 per address per 15 min) and add a per-IP limit, `503` SMTP not configured.
- A new code for an address invalidates any older unused one.

### `POST /api/v1/auth/verify`

```json
{ "email": "someone@example.com", "code": "482913" }
```

- `200` → `{ "token": "<opaque>", "user": <Me> }`. Creates the account on
  first success, through the same `upsertUserOnLogin` the link flow uses.
- `400 {"error": "...", "code": "bad_code"}` - wrong, expired or used.

**A 6-digit code is guessable, so attempts must be capped:** after **5 wrong
tries** the code is dead and a new one has to be requested. Count attempts on
the code row, not in memory. Add a per-IP limit on verify as well.

Store only hashes, as `login_tokens` already does: the code's hash, and the
session token's hash. A database read must not hand anyone a working login.

### Sessions

The web's session is a stateless signed cookie, which cannot be revoked. An
app token lives for months on a phone that can be lost, so it **must** be
revocable:

```sql
CREATE TABLE IF NOT EXISTS app_sessions (
  token_hash   text PRIMARY KEY,
  user_id      integer NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at   timestamptz NOT NULL DEFAULT now(),
  last_used_at timestamptz NOT NULL DEFAULT now()
);
```

- Token: 32 random bytes, base64url. Sent as `Authorization: Bearer <token>`.
- Bearer tokens are accepted **only** on `/api/v1`, and never set a cookie.
- Purge sessions unused for 90 days.
- **Using a session must count as logging in** for the one-year purge in
  `accounts.purge()`: bump `users.last_login_at` when a session is used (at
  most once a day is plenty). Otherwise someone who only ever uses the app has
  their account - and all their listings and messages - deleted after a year
  while using it daily.

### `POST /api/v1/auth/logout` → `204`, deletes that session row.

Every authenticated route answers a missing, unknown or revoked token with
`401 {"error": "...", "code": "unauthorized"}`. **That code is what makes the
app sign out locally** - please do not use 401 for anything else.

The public routes (`GET /listings`, `GET /listings/:id`, reports) also accept
a token, which the app sends when signed in so `is_mine` can be filled. On
those routes a revoked token may 401 like anywhere else - the app signs out
and retries as a visitor - but it must never make a public route fail for a
*valid* token.

Unknown `/api/v1/*` paths currently 302 to the HTML 404 page. The app copes
(it reads any non-JSON answer as "not deployed yet"), but an API should
answer `404 {"error": "...", "code": "not_found"}` in JSON.

---

## 2. The account

`Me`:

```json
{ "email": "someone@example.com", "name": "ziga", "lang": "sl", "notify": true, "unread_count": 2 }
```

`name` is `null` until picked. `email` appears **only** here - it is the
user's own address. No other response ever contains anyone's email.

| | | |
|---|---|---|
| `GET /api/v1/me` | → `Me` | |
| `PATCH /api/v1/me` | `{"name"?, "notify"?, "lang"?}` → `Me` | name through `setName`: `400 code:"invalid"`, `409 code:"taken"` |
| `DELETE /api/v1/me` | → `204` | `deleteAccount`, which already removes the photos from storage first. Sessions go with it by cascade. |

`DELETE /api/v1/me` is not optional: **Play requires in-app account deletion**
for any app that lets people create an account. The existing web route
`/account/delete` covers Play's other requirement, a deletion path that works
without the app.

Selling and messaging need a name, as on the web (`requireNamedUser`). Without
one: `403 {"error": "...", "code": "name_required"}`.

---

## 3. Listings

`Listing`:

```json
{
  "id": 12,
  "title": "Old bike",
  "description": "Rides. Mostly.",
  "price_cents": 2500,
  "image_url": "https://.../uploads/....jpg",
  "status": "active",
  "seller": { "name": "ziga" },
  "created_at": "2026-10-01T10:00:00.000Z",
  "expires_at": "2026-10-31T10:00:00.000Z",
  "is_mine": false,
  "my_conversation_id": null
}
```

- `price_cents`: `null` = "make an offer", `0` = free - same meaning as
  `formatPrice`. The app formats it; send the integer, not a string.
- `status`: `active` | `sold`. Removed, hidden and expired listings are never
  returned by the public routes.
- `seller` carries the display name only.
- `is_mine` and `my_conversation_id` are only meaningful with a token; without
  one they are `false` / `null`. `my_conversation_id` is the caller's own
  buyer thread on this listing, if any, so "message seller" can reopen it.

### `GET /api/v1/listings?page=&per_page=&q=&sort=`

Public. Same envelope as posts, plus echoes:

```json
{ "items": [...], "page": 1, "per_page": 24, "total": 61, "has_next": true, "sort": "new", "q": "" }
```

- The same set `liveListings` shows on the website: active and sold, not
  expired, not hidden. Sold ones stay visible with their stamp, as on the site.
- `sort`: `new` (default) | `price_asc` | `price_desc`. For price sorts,
  `null` prices go last. Unknown values fall back to `new`.
- `q`: case-insensitive match on title and description.
- **Echo what was actually applied** in `sort` and `q`. The website has no
  search or sort yet; if you ship the list before them, echo `"sort": "new"`
  and `"q": ""` and the app will show that the filter was not applied rather
  than pretending it was.
- `per_page` clamps to 50.

### `GET /api/v1/listings/:id` → `Listing`, `404` if not public.

### `POST /api/v1/listings` → `201 Listing`

Bearer, named user, `multipart/form-data`, the **same field names as the web
form**: `title`, `description`, `price`, `photo`.

- `price` is the text the web form takes, passed straight to `parsePrice`:
  `""` = make an offer, `"0"` = free, `"12.50"` an amount. The app always sends
  a dot.
- `photo` is required: images only, the web form's types.
- `400 code:"missing"|"price"`, `413`, `415`, `429`, `503 code:"storage"`.
  Reuse `listingCreateLimit`.

### `POST /api/v1/listings/:id/sold` → `Listing` (owner, `markSold`)
### `DELETE /api/v1/listings/:id` → `204` (owner, `removeOwn`)
### `GET /api/v1/me/listings` → `{"items": [Listing]}` - mine, including sold and expired, excluding removed.
### `POST /api/v1/listings/:id/report` → `204`

`{"reason": "scam"|"prohibited"|"spam"|"harassment"|"other", "details": "..."}`.
No token needed, same as reporting a post. Reuse `listingReportLimit`.

Non-owner on sold/delete: `403`. Unknown listing: `404`.

---

## 4. Conversations and offers

`Message`:

```json
{
  "id": 301,
  "mine": true,
  "body": "Would you take 20?",
  "offer_cents": 2000,
  "offer_status": "pending",
  "created_at": "2026-10-01T10:05:00.000Z"
}
```

- `mine` is computed server-side. **Never send sender ids.**
- `offer_status`: `pending` | `accepted` | `declined` | `superseded`, or
  `null` for a plain message.

`Conversation` (a row in the inbox, and the header of a thread):

```json
{
  "id": 44,
  "role": "buyer",
  "other": { "name": "ana" },
  "listing": { "id": 12, "title": "Old bike", "price_cents": 2500, "image_url": "...", "status": "active" },
  "last_message": { "body": "Would you take 20?", "offer_cents": 2000, "mine": true, "created_at": "..." },
  "unread": false,
  "last_message_at": "..."
}
```

| | | |
|---|---|---|
| `GET /api/v1/conversations` | → `{"items": [Conversation]}` | newest first; threads with blocked users left out |
| `POST /api/v1/listings/:id/messages` | `{"body"?, "offer"?}` → `201 {"conversation_id", "message"}` | `startConversation`. Creates the buyer's thread or appends to it. |
| `GET /api/v1/conversations/:id?after=<message_id>` | → `{"conversation", "messages": [Message]}` | oldest first. Marks read (`openThread`). |
| `POST /api/v1/conversations/:id/messages` | `{"body"?, "offer"?}` → `201 Message` | `postMessage` |
| `POST /api/v1/conversations/:id/offers/:message_id` | `{"accept": true\|false}` → `Message` | `respondToOffer` |
| `POST /api/v1/conversations/:id/report` | `{"reason", "details"}` → `204` | `reportConversation` |

- `offer` is text through `parsePrice`, like the web form; the app sends a dot.
- `?after=` returns only messages newer than that id - **the app polls with it
  every few seconds while a thread is open**, so it must be cheap, and it
  should not bump anything when there is nothing new.
- `?after=` cannot see an *old* message changing - the other side accepting
  or declining your offer. The app relies on `conversation.last_message_at`
  for that: when it moves and no new messages came with it, the app reloads
  the whole thread. `respondToOffer` already sets `last_message_at = now()`
  ("an answer is news ... so it moves the thread"); **keep it that way**, and
  return `last_message_at` on the conversation in this response.
- Errors: `400 code:"empty"|"offer"`, `403 code:"own"` (messaging your own
  listing), `409 code:"closed"` (listing no longer active), `409 code:"stale"`
  (offer already answered or superseded), `404` not a participant, `429`
  (reuse `messageLimit`).

---

## 5. Blocking (new)

Apple's guideline 1.2 requires that users can block abusive users in any app
with user-to-user messaging, and Play's user-generated-content policy expects
it too. The site has reporting but no blocking.

```sql
CREATE TABLE IF NOT EXISTS blocks (
  blocker_id integer NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blocked_id integer NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (blocker_id, blocked_id)
);
```

| | |
|---|---|
| `POST /api/v1/conversations/:id/block` → `204` | blocks the other participant |
| `GET /api/v1/me/blocks` → `{"items": [{"user_id", "name", "blocked_at"}]}` | |
| `DELETE /api/v1/me/blocks/:user_id` → `204` | |

Effect, in both directions: a blocked user cannot start a conversation on the
blocker's listings or post in a thread with them, and gets the ordinary
`409 code:"closed"` - not a message saying they were blocked. The blocker's
inbox omits those threads. Enforce it inside `startConversation` /
`postMessage` so the website respects blocks made in the app too.

---

## 6. Everywhere

- `?lang=sl|en` on every call; error messages in `{"error"}` are shown to the
  user verbatim, so they must be localised.
- Errors are `{"error": "<localised>", "code": "<machine>"}`. The app branches
  on `code` and on status, never on the wording.
- `429` carries `Retry-After` and `retry_after_seconds`, as the existing API does.
- `503 {"code": "unconfigured"}` on auth when SMTP is missing, so the app can
  say "selling and messaging are off right now" instead of a raw error.
- No route returns another user's email, ever.
- The App Links filter stays `pathPrefix="/post"` and
  `apple-app-site-association` stays `/post/*`. The app now has a test that
  fails if its own filter ever widens.

## Not needed

- No changes to any existing `/api/v1` route.
- No push notifications in this round. The site already emails "you have a
  new message"; the app shows an unread badge and polls open threads. Push for
  messages can come later on top of the existing FCM setup.
- No listing editing: the website has none, and adding it to the app alone
  would let the two disagree. Mark sold, delete, or post a new one.
