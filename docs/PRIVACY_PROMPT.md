# Prompt for the website chat — privacy policy page

Paste everything below the line into the Claude Code session for
`/Users/ziga/Projects/PROJECT/sejbosejbo.fyi`.

---

Google Play requires a publicly reachable privacy policy URL before the app can
be published. Add one to this website.

## What to build

A `GET /privacy` route rendered with the existing `layout()` helper, so it picks
up the topbar, footer, styles and the EN/SL language switch like every other
page. Add the strings to the existing `i18n` object in both `en` and `sl` — do
not hardcode English.

Link it from the footer on every page.

Also serve it at `/privacy.html` or make sure `/privacy` is stable — Play stores
the URL and rechecks it periodically. A dead link later can get the app pulled.

## What the policy must actually say

Write it from these facts. **Do not invent anything, and do not pad it with
boilerplate about services this site does not use.** An inaccurate policy is
worse than a short one, and Play's Data safety form has to match it.

### Data the site and app collect

1. **Uploaded content** — images, GIFs, titles and descriptions that users
   submit. Stored on the server indefinitely and shown publicly to everyone. No
   author identity is recorded with them; uploads are anonymous.
2. **An anonymous device identifier** — a random string the app generates on
   first launch, stored locally on the device, sent as the `X-Device-Id` header
   only when voting. Its sole purpose is to stop the same device voting twice on
   the same post. It is not linked to any account, name, email or advertising
   identifier, and it is not used for tracking or profiling. Clearing app data
   generates a new one.
3. **IP addresses** — processed transiently to rate-limit uploads and votes and
   to count visits. Not shown publicly and not used to identify individuals.
   State the retention honestly (say how long server logs are kept; if they are
   not retained beyond the request, say that).
4. **A visitor counter** — an aggregate number only. No per-visitor records.

### What is NOT collected

Be explicit, because it is genuinely unusual and it is what the Data safety form
will be checked against:

- No accounts, sign-up, email addresses, names or passwords.
- No advertising ID. The app does not request `AD_ID`.
- No analytics or crash-reporting SDKs.
- No third-party trackers.
- No location, contacts, camera roll scanning, or device fingerprinting.
- Nothing is sold or shared with third parties.

### Third parties actually involved

- **Cloudflare** sits in front of the site and processes requests (including IP
  addresses) as a CDN/proxy.
- **Google Play** and **Apple** handle in-app tips if the user chooses to send
  one; payment details go to them, never to this site. **Stripe** handles the
  same on desktop. The site stores only a record that a donation happened —
  never card details.
- If tips are not enabled yet, say so rather than describing a flow that does
  not exist.

### Children

The archive is user-submitted and unmoderated at submission time, so it is not
directed at children. Say what the intended audience is; this must agree with
the Target audience answers in Play Console.

### Content removal

Anyone must be able to ask for an upload to be taken down. Give a working
contact address and say uploads are deleted on request. Play increasingly checks
that a deletion route exists — this is the part people forget, and it is the one
users actually need.

### Effective date and changes

Include a "last updated" date and a line saying the policy may change.

## Tone

Match the site: plain, direct, no legalese theatre. Short and true beats long
and vague. It should be readable in under two minutes.

## When you are done

Give me the live URL (`https://sejbosejbo.fyi/privacy`), confirm it returns 200
without a redirect, and confirm the Slovenian version renders. I need to paste
that URL into Play Console.
