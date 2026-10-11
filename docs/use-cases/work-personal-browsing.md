---
title: Keep Work and Personal Browsing Separate on Mac
order: 2
summary: Send work links to your work browser or profile and keep everything else personal, without thinking about it. Junction sorts each link by site and by app.
related: [rules, actions, quickstart]
icons: [briefcase, chrome]
---

# Keep work and personal browsing apart on your Mac

Junction is a free, open-source macOS app that becomes your default browser and routes each link by your rules. A few rules are enough to keep work in a work browser or profile — signed in to work accounts, with work extensions — and everything else in your personal one.

## How do I keep work and personal browsing separate on a Mac?

Pick one place for each: say, a work Chrome profile and personal Safari. Then make personal the **fallback** and add rules that send work links to the work profile. Any link no rule claims stays personal.

```json config
{
  "fallback": { "app": "com.apple.Safari" }
}
```

```json rule
{
  "name": "Work tools → work profile",
  "match": { "patterns": ["*.atlassian.net/*", "app.clickup.com/*", "docs.google.com/*"] },
  "action": { "app": "com.google.Chrome", "profile": "Profile 1" }
}
```

```text junction test
$ junction test "https://acme.atlassian.net/browse/ENG-42"
input:       https://acme.atlassian.net/browse/ENG-42
rule:        [1] Work tools → work profile
action:      open in com.google.Chrome profile "Profile 1"
url:         https://acme.atlassian.net/browse/ENG-42
```

## Which is better, a separate browser or a separate profile?

Either works; Junction handles both the same way.

| Setup | Work opens in | Rule action |
| --- | --- | --- |
| Two browsers | Chrome, personal in Safari | `{ "app": "com.google.Chrome" }` |
| Two Chrome profiles | Chrome's work profile | `{ "app": "com.google.Chrome", "profile": "Profile 1" }` |
| Two Firefox profiles | Firefox's work profile | `{ "app": "org.mozilla.firefox", "profile": "Work" }` |

Profile details are in [Chrome profiles](chrome-profile-links.md) and [Firefox profiles](firefox-profile-links.md).

## Can every link from work apps open in the work browser?

Yes. Match the app the link was clicked in with `sourceApps`, and links from Slack — whatever site they point to — open in the work profile.

```json rule
{
  "name": "From Slack → work profile",
  "match": { "sourceApps": ["com.tinyspeck.slackmacgap"] },
  "action": { "app": "com.google.Chrome", "profile": "Profile 1" }
}
```

```text junction test
$ junction test "https://example.com/quarterly-report" --source com.tinyspeck.slackmacgap
input:       https://example.com/quarterly-report
source:      com.tinyspeck.slackmacgap
rule:        [1] From Slack → work profile
action:      open in com.google.Chrome profile "Profile 1"
url:         https://example.com/quarterly-report
```

Keep app rules near the top: rules run top to bottom and the first match wins. More in [routing links by app](links-from-apps.md).

## What about sites I use for both work and personal?

Let them ask. A rule with the `prompt` action shows the picker for those sites, so you choose at click time.

```json rule
{
  "name": "Google Drive → ask",
  "match": { "patterns": ["drive.google.com/*"] },
  "action": { "prompt": true }
}
```

For one-off exceptions, hold **⌥ Option** while you click any link to pick the browser yourself. More in [choosing a browser per link](choose-browser-per-link.md).

## Can I pause the work rules after hours?

Yes. Turn a rule off in the menu bar's **Rules** list and its links fall through to your personal fallback until you turn it back on — see [menu-bar rule toggles](menu-bar-rule-toggles.md).

## Get Junction

Junction is free and MIT-licensed, for macOS 13 or later on Apple silicon and Intel. [Install it](/#install) with Homebrew or the DMG, then follow the [first-launch steps](/docs#quickstart).
