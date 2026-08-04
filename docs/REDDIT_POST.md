# Reddit posts for finding testers

Replace `[OPT-IN LINK]` with the Play Console internal-testing link before
posting (Play Console → Testing → Internal testing → Testers → Copy link).

---

## Main post

Best for r/SideProject, r/androidapps, r/InternetIsBeautiful, r/Slovenia.

**Title options:**

```
I made an app around a Slovenian phrase that has no English equivalent, and now I need 12 people to test it
```

```
My friends and I kept saying one specific phrase at dumb stuff, so I built an archive of it. Need testers.
```

**Body:**

```
So there's this phrase we say in Slovenia - "sej bo sej bo".

It doesn't really translate. Closest I can get is "well, that's something", or
"damn, that's crazy", or that noise you make when someone tells you something
so stupid you don't have an actual response. Someone microwaves ice. Someone
installs Chrome just to download Edge. Sej bo sej bo.

At some point my friends and I were saying it constantly, so I made a website
where we could dump screenshots of the stupidest things people say. It runs on
a Raspberry Pi in my cupboard. It got out of hand and now there are a couple
hundred posts on it.

Now it's an Android app.

What it does:
- Browse the whole archive
- Upload your own - a photo, a pasted screenshot, or just the story
- Vote on everything. Two options only: SEJ BO (yes this qualifies) or
  SEJ NE BO (no it doesn't)
- Hall of Fame for the worst of all time
- English and Slovenian, switch any time

No accounts, no login, no ads, no tracking, no analytics. You don't hand over
an email to look at a picture of someone microwaving a salad. Posting is
anonymous.

Here's the thing though - Google now makes you have 12 testers opted in for 14
days straight before a personal developer account can publish anything. So I
genuinely need people. If you join and then leave early it resets, which is
mildly devastating.

Opt in here: [OPT-IN LINK]

It's free and it stays free. There's a tip jar in there but it's not even
switched on yet and it unlocks nothing.

Fair warning: it's connected to the live site, so anything you post is public
immediately. Post accordingly.

Happy to answer anything about how it's built - it's Flutter talking to a
stupidly simple Node server on a Pi.
```

---

## Short version

For r/AndroidClosedTesting, r/TestMyApp, r/alphaandbetausers — those subs are
transactional and a wall of text gets scrolled past.

```
Sejbosejbo - an archive of the dumbest things people say.

"Sej bo sej bo" is a Slovenian phrase with no clean English translation.
Roughly: "well, that's something". You say it when someone tells you they
microwaved ice.

Started as a website on a Raspberry Pi in my cupboard. Now an Android app.
Upload screenshots or stories, vote SEJ BO / SEJ NE BO on everything, browse
the Hall of Fame.

No accounts, no ads, no tracking. Free forever.

Need 12 testers for 14 days for Google's requirement. Opt in: [OPT-IN LINK]

Happy to test yours back.
```

---

## Where to post

| Subreddit | Notes |
|---|---|
| r/SideProject | Best fit. Likes the story, likes self-hosted things. |
| r/androidapps | Check the rules — some days only allow self-promo threads. |
| r/Slovenia | Home crowd. They already know the phrase; lead with that. |
| r/selfhosted | The Raspberry Pi angle lands here. Don't lead with "please test". |
| r/AndroidClosedTesting | Purely transactional. Use the short version. |
| r/TestMyApp | Same. |
| r/alphaandbetausers | Same. |

## Worth knowing before you post

- **Post at different times, not all at once.** Reddit's spam filters notice
  the same link across several subs within minutes.
- **Read each sub's rules first.** r/androidapps in particular removes
  self-promo outside its designated thread, and a removal can cost you the
  account's standing.
- **The reciprocal-testing subs are a trade.** People expect you to install and
  keep their app too. That's fine, just budget for it — and Google does want
  testers to be real people actually opting in, not just names on a list.
- **Answer comments.** The build questions ("why a Pi?", "why not Firebase?")
  are where these posts actually gain traction, and you have good answers.
- **The 14 days are continuous.** If someone opts out on day 9 and you drop
  below 12, the clock restarts. Worth over-recruiting — aim for 15-20.
