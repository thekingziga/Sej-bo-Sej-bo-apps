# Setting up tipping payments

Three separate systems, in the order they can actually be done.

| Platform | Payment rail | Status |
|---|---|---|
| Windows / Linux | Stripe Checkout | **Live and working today.** Nothing to do. |
| Android | Google Play Billing | Needs the steps below |
| iOS / macOS | StoreKit | Blocked: no Apple Developer account |

The app side is finished for all three. What is missing is account
configuration, and for Android one credential the server needs.

---

## Google Play

### Step 1 — Payments profile (do this first, it gates everything)

**Play Console → Setup → Payments profile.**

Until a merchant account exists, Play will not let you set a price on anything,
so every later step is blocked behind this one. It wants a legal name and
address, tax details, and a bank account for payouts. Google verifies the bank
account with a small test deposit, which typically takes a few days.

Play takes **15%** of the first $1M/year, so a €5 tip nets about €4.25 before
the currency spread. That is the cost of Google's rule that digital tips must
use their billing - it is not something the app can opt out of.

### Step 2 — Make sure a build with Billing is uploaded

Already true: 1.11.0 declares `com.android.vending.BILLING`, verified in the
bundle. Play only exposes in-app product creation once it has seen a build on
some track that includes the Billing library, which internal testing satisfies.

### Step 3 — Create the three products

**Play Console → Monetise with Play → Products → In-app products.**
(Newer consoles label these "one-time products". Same thing.)

Create one per row, then **activate** each - a product left inactive is invisible
to the app and `queryProductDetails` silently returns nothing for it.

| Product ID | Name | Price |
|---|---|---|
| `fyi.sejbosejbo.tip.small` | Small Sejbo | €2.00 |
| `fyi.sejbosejbo.tip.medium` | Certified Sejbo | €5.00 |
| `fyi.sejbosejbo.tip.large` | Maximum Sejbo | €15.00 |

The IDs must match **character for character**. The server maps them by literal
string and rejects anything else with a 400, and the app queries for exactly
these three. A typo shows up as a tip button that does nothing.

There is no consumable/non-consumable choice here - that is an Apple concept.
On Play, a product is repeatable because the app consumes it after verifying,
which `DonationGateway._finish` does. Nothing to set.

Set the price in EUR and let Play auto-convert the rest, unless you want to
hand-pick per-country prices.

### Step 4 — License testers (test purchases with no money)

**Play Console → Setup → License testing.** Add the Gmail addresses that should
be able to buy without being charged, including your own.

A license tester making a purchase gets a real, valid purchase token - which is
what makes it possible to test the whole verification chain end to end before
any real money is involved. The account must also be on the testing track, and
must be the account signed into the Play Store on the device.

Test purchases are auto-refunded and auto-cancelled; you will see them in the
console marked as test orders.

### Step 5 — Service account, for server-side verification

This is the last blocker for Android tips, and it is the website's half.

1. **Google Cloud Console** → the project linked to your Play account →
   **APIs & Services** → enable **Google Play Android Developer API**.
2. **IAM & Admin → Service Accounts → Create service account.** No project
   roles are needed - permission is granted on the Play side, not here.
3. On that service account: **Keys → Add key → Create new key → JSON.**
   Download it.
4. **Play Console → Users and permissions → Invite new user**, using the
   service account's email address. Grant **View financial data, orders, and
   cancellation survey responses** for this app. That is the permission
   `purchases.products.get` needs; without it verification returns a 401 that
   is easy to mistake for a bad token.
5. Hand the JSON key to the website side to install on the Pi.

Permission changes can take a few hours to propagate. A 401 immediately after
granting access usually means "wait", not "wrong".

> **The JSON key is a credential.** It must never go into the app repo, which
> is public - it belongs in the Pi's `.env` or a file referenced from it,
> alongside the Stripe keys. Treat it like the keystore: if it leaks, revoke it
> in Cloud Console and issue a new one.

### Step 6 — Prove it works

With the service account installed, `POST /api/v1/donations/google/verify`
stops returning 503. Then, on a device signed in as a license tester with the
app installed **from Play** (not sideloaded):

1. Tip €2 in the app.
2. The tip screen should show the thanks card - that only happens after the
   server returned 200, so seeing it means verification genuinely passed.
3. Tip €2 **again**. It must work a second time. If it fails with "already
   owned", the purchase was acknowledged but not consumed.
4. Kill the app mid-purchase and reopen it. The pending purchase should be
   picked up and verified on launch.

---

## Apple (iOS / macOS)

Blocked until there is an **Apple Developer Program** membership (€99/year).
Once there is:

1. **App Store Connect → Agreements, Tax, and Banking.** The *Paid
   Applications* agreement must be active, with banking and tax filled in.
   In-app purchases cannot be created, let alone sold, until it says Active.
2. **Your app → In-App Purchases → Create.** Type: **Consumable** - this is
   where the consumable choice actually exists. Use the same three product IDs.
3. Each product needs a display name, a review screenshot, and review notes, and
   is reviewed alongside a build. They can sit in "Ready to Submit" until then.
4. For server verification, generate an **App Store Server API key**
   (Users and Access → Integrations → In-App Purchase) and give the key, key ID
   and issuer ID to the website side.

The app already sends Apple receipts to `/api/v1/donations/apple/verify`, which
returns 503 until those credentials exist.

---

## Stripe (Windows / Linux)

Already live. Verified against production: all three tiers create real
`cs_live_` checkout sessions, and an unknown tier is rejected with a 400.

Nothing to configure. Worth knowing how it differs: the app opens Stripe in the
system browser and its job ends there. Stripe calls the server's webhook
directly, so the app never learns whether the payment completed - which is why
it says "finish the payment in your browser" rather than thanking you up front.

Fees are roughly 1.5% + €0.25 for European cards, so a €5 tip nets about €4.50 -
noticeably better than the store rails, which is exactly why desktop uses it.

---

## Order of work

1. Payments profile. Everything else waits on it. Start it today; the bank
   verification is the long pole.
2. Create and activate the three products.
3. Add yourself as a license tester.
4. Service account + JSON key → website side.
5. Test purchase, then a second one, then the kill-mid-purchase case.
6. Apple, whenever the developer account happens.
