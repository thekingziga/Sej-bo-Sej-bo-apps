# Descriptions for testers

Two separate things:

1. **Release notes** — the "What's new" field in Play Console. Hard 500-char
   limit per language. Testers see this in the Play listing.
2. **Tester brief** — paste into your group chat. Play has no field for this,
   but testers need it or they will only poke at the home screen.

---

## 1. Release notes (Play Console, max 500 chars)

### English

```
First test build. The whole archive is here: browse every Sejbosejbo, upload
your own (photo, screenshot paste, or just a story), and vote SEJ BO / SEJ NE
BO on anything.

Also in: Hall of Fame ranking, daily award, gallery sorting, sharing, content
reporting, and full English/Slovenian switching.

This talks to the real sejbosejbo.fyi - anything you post is live and public.

Tips are not switched on yet. Everything is free.
```

### Slovenian

```
Prva testna razlicica. Cel arhiv je tu: brskaj po vseh Sejbosejbojih, naloži
svojega (slika, prilepljen posnetek zaslona ali samo zgodba) in glasuj SEJ BO
/ SEJ NE BO.

Vkljuceno tudi: lestvica Hram slavnih, dnevna nagrada, razvrscanje galerije,
deljenje, prijava vsebine in preklop med anglescino in slovenscino.

Povezano je z resnicno stranjo sejbosejbo.fyi - vse, kar objaviš, je javno.

Napitnine še niso vklopljene. Vse je brezplacno.
```

---

## 2. Tester brief — paste into the group chat

```
Sejbosejbo is on Android now. You are testing it before it goes public.

WHAT IT IS
The sejbosejbo.fyi archive as a real app. Same posts, same votes - post from
the app and it shows up on the website instantly, and the other way round.

WHAT TO TRY
- Upload something. Photo, or copy a screenshot and hit PASTE, or no picture
  at all and just write the story.
- Vote on things. SEJ BO if it qualifies, SEJ NE BO if it does not. Tap again
  to undo.
- Gallery: switch between NEWEST / TOP / FEATURED.
- Scroll the home screen down to the Hall of Fame.
- Hit the big pink SEJBOSEJBO button a few times.
- Switch ENG / SLO in the top right. Everything should translate.
- Share a post to a chat. The link should open the website.
- Open a post and try REPORT (it really does send me a report, so do not spam
  it).

IMPORTANT
Everything is live. Whatever you upload is public on sejbosejbo.fyi
immediately and everyone can see it. There are no accounts and no login -
posting is anonymous, but it is not private.

NOT WORKING YET, DO NOT REPORT
- Tips / donations on the Support tab. Not configured, they will not charge
  you and probably error.
- Tapping a sejbosejbo.fyi link does not open the app yet, only the browser.

WHAT I WANT TO HEAR
- Anything that crashes, freezes, or looks broken on your phone. Tell me which
  phone.
- Text that overflows, gets cut off, or overlaps.
- Anything in Slovenian that reads badly or is untranslated.
- Uploads that fail, and what you were uploading when they did.
```

---

## Notes

- The release notes deliberately say the data is live. Testers will otherwise
  assume a sandbox and post something they would not want public - there is no
  login and no delete button in the app, so an upload is effectively permanent
  until you remove it from `/admin`.
- The "not working yet" list matters more than it looks. Without it you get
  three reports about the tip jar and none about real bugs.
- Asking for the phone model is worth it. Almost every layout bug so far has
  been screen-size dependent.
