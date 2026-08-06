# API request for the website chat

Two small server changes. Paste below the line.

---

Two changes needed for the app, both small.

## 1. `sort=newest` should ignore `pinned`

Right now `/api/v1/posts?sort=newest` orders by `pinned DESC, created_at DESC`.
That means a pinned post from 19 days ago sits above one from today, in a tab
literally labelled NEWEST. It looks broken even though it is doing what was
asked.

Change `newest` to order purely by date:

```sql
ORDER BY datetime(created_at) DESC, id DESC
```

Keep `pinned` in the Post JSON — the app shows a PINNED badge; it just should
not affect this ordering.

## 2. Add `sort=pinned`

Pinned posts get their own tab in the app instead of jumping the queue.

```
GET /api/v1/posts?sort=pinned
```

Only `pinned = 1`, newest first, same response shape and pagination as every
other sort. Same as the existing `sort=featured`, just on the other column.

So the full set becomes: `newest` | `top` | `featured` | `pinned`, with an
unknown value still falling back to `newest`.

**Note the website's own gallery** presumably still wants pinned-first. That is
fine — just make sure the *API* behaves as above, and keep the website's HTML
ordering separate if it differs.

## 3. While you're there: `assetlinks.json` is 404

`https://sejbosejbo.fyi/.well-known/assetlinks.json` returns 404, so Android
App Links do not verify and shared links keep opening the browser instead of
the app. The app side is done and tested — this is the only thing missing.

It needs `ANDROID_CERT_SHA256` set. **Include both fingerprints**, not just one:

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "com.thekingziga.sejbosejbo",
      "sha256_cert_fingerprints": [
        "55:B5:A8:A8:F3:17:5A:EE:C2:1A:46:F4:48:01:3C:8B:2C:94:E8:36:84:A4:BC:48:FC:2B:4D:DF:E5:20:71:29",
        "F5:0E:41:67:4B:01:45:4C:5A:11:05:F0:7F:B4:D2:52:CE:09:23:62:49:11:19:90:8F:80:59:DA:98:99:16:C9"
      ]
    }
  }
]
```

- The first is the **Play App Signing** certificate — what installs from Play
  are signed with.
- The second is the **upload key** — what directly-installed test APKs are
  signed with.

With only the first, sideloaded test builds never verify and you cannot check
the feature works before release. Listing both is normal and safe: these are
public certificates, not keys.

Verify after deploying:

```bash
curl -sI https://sejbosejbo.fyi/.well-known/assetlinks.json
```

Must be `200`, `Content-Type: application/json`, and **no redirect** — Android
does not follow redirects when fetching this file.
