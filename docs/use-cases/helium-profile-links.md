---
title: Open Links in a Specific Helium Profile on Mac
order: 8
summary: Make Helium your everyday browser and still send each link to the right Helium profile or to your work browser. Junction routes every link you click on a Mac.
related: [actions, rules, troubleshooting]
icons: [helium]
---

# Open links in the right Helium profile on your Mac

Junction is a free, open-source macOS app that becomes your default browser and routes each link by your rules. Helium is built on Chromium, so Junction opens its profiles the same way it opens Chrome's: one rule per set of sites, and each link lands in its profile.

## How do I open a link in a specific Helium profile?

Write a rule that matches the link and opens it in Helium with a `profile`. Helium's bundle ID is `net.imput.helium`, and the profile is its name as **Settings → Browsers** lists it.

```json rule
{
  "name": "Research → Helium",
  "match": { "patterns": ["*.wikipedia.org/*", "arxiv.org/*"] },
  "action": { "app": "net.imput.helium", "profile": "Research" }
}
```

```text junction test
$ junction test "https://en.wikipedia.org/wiki/Chromium_(web_browser)"
input:       https://en.wikipedia.org/wiki/Chromium_(web_browser)
rule:        [1] Research → Helium
action:      open in net.imput.helium profile "Research"
url:         https://en.wikipedia.org/wiki/Chromium_(web_browser)
```

## Why doesn't Junction list my Helium profiles?

Either macOS is blocking Junction from reading them, or your Junction is older than 0.11.1, the first version that recognizes Helium.

| Cause | Fix |
| --- | --- |
| Junction lacks Full Disk Access | Turn it on — see [why you can't choose a browser profile](links-open-wrong-browser.md#why-cant-i-choose-a-browser-profile) |
| Junction is older than 0.11.1 | Update from the menu bar with **Check for Updates…** |

Without Full Disk Access, a Helium profile rule still works if you type the profile's directory (`Default` for the first, then `Profile 1`, `Profile 2`) into the config file.

## Can Helium be my everyday browser and Chrome my work one?

Yes. Make Helium the fallback, so every link no rule matches opens there:

```json config
{
  "fallback": { "app": "net.imput.helium" }
}
```

Then send your work sites to your work Chrome profile with a rule:

```json rule
{
  "name": "Work sites → Chrome work profile",
  "match": { "patterns": ["*.atlassian.net/*", "docs.google.com/*"] },
  "action": { "app": "com.google.Chrome", "profile": "Work" }
}
```

More on splitting the two: [work and personal browsing](work-personal-browsing.md).

## Get Junction

Junction is free and MIT-licensed, for macOS 13 or later on Apple silicon and Intel. [Install it](/#install) with Homebrew or the DMG, then follow the [first-launch steps](/docs#quickstart).
