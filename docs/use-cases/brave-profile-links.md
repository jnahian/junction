---
title: Open Links in a Specific Brave Profile on Mac
order: 6
summary: Send personal links to your Brave profile and work links to your work browser, automatically. Junction picks the Brave profile for each link you click on a Mac.
related: [actions, rules, troubleshooting]
icons: [brave]
---

# Open links in the right Brave profile on your Mac

Junction is a free, open-source macOS app that becomes your default browser and routes each link by your rules. If Brave is where you browse privately, one rule keeps your personal sites in your Brave profile, wherever you clicked them.

## How do I open a link in a specific Brave profile?

Write a rule that matches the link and opens it in Brave with a `profile`. Brave's bundle ID is `com.brave.Browser`, and the profile is its name as **Settings → Browsers** lists it.

```json rule
{
  "name": "Personal sites → Brave",
  "match": { "patterns": ["*.reddit.com/*", "news.ycombinator.com/*"] },
  "action": { "app": "com.brave.Browser", "profile": "Personal" }
}
```

```text junction test
$ junction test "https://news.ycombinator.com/item?id=1"
input:       https://news.ycombinator.com/item?id=1
rule:        [1] Personal sites → Brave
action:      open in com.brave.Browser profile "Personal"
url:         https://news.ycombinator.com/item?id=1
```

## How do I find my Brave profile's name?

**Settings → Browsers** in Junction lists every Brave profile with its name and directory, and the rule editor offers them when you pick Brave. Listing them needs **Full Disk Access**, which Junction uses only to read Brave's list of profiles. See [why you can't choose a browser profile](links-open-wrong-browser.md#why-cant-i-choose-a-browser-profile).

Without Full Disk Access, a Brave profile rule still works if you type the profile's directory (`Default` for the first, then `Profile 1`, `Profile 2`) into the config file. A rule that names a profile that doesn't exist on this Mac opens the link in your fallback browser instead.

## Can Brave be my personal browser and Chrome my work one?

Yes. Make Brave the fallback, so every link no rule matches opens there:

```json config
{
  "fallback": { "app": "com.brave.Browser" }
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

## Does Junction remove tracking parameters too?

Yes, with `stripTrackingParams` set to `true`. Junction then drops tracking parameters like `utm_source` from every link before routing it, so the link reaches Brave already clean.

```json config
{
  "stripTrackingParams": true
}
```

```text junction test
$ junction test "https://www.reddit.com/r/macapps/?utm_source=newsletter"
input:       https://www.reddit.com/r/macapps/?utm_source=newsletter
transformed: https://www.reddit.com/r/macapps/
rule:        [1] Personal sites → Brave
action:      open in com.brave.Browser profile "Personal"
url:         https://www.reddit.com/r/macapps/
```

More in [removing tracking parameters](privacy-link-rules.md#how-do-i-remove-tracking-parameters-from-links-on-mac).

## Does this work with Brave Beta?

Yes. Brave Beta's bundle ID is `com.brave.Browser.beta`, and Junction lists its profiles the same way. Chrome, Edge, Vivaldi, and Helium work the same as well — see [Chrome profiles](chrome-profile-links.md).

## Get Junction

Junction is free and MIT-licensed, for macOS 13 or later on Apple silicon and Intel. [Install it](/#install) with Homebrew or the DMG, then follow the [first-launch steps](/docs#quickstart).
