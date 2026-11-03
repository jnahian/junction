---
title: Open Links in a Chrome Web App on Mac
order: 12
summary: Send a site's links to a Chrome web app such as ClickUp, so they open in the web app's own window and profile instead of in a new browser tab on your Mac.
related: [actions, rules, troubleshooting]
icons: [chrome, clickup]
---

# Open links in a Chrome web app's own window

Junction is a free, open-source macOS app that becomes your default browser and routes each link by your rules. A rule can send a site's links to a Chrome web app, one you installed with **Install page as app**, so they open in the web app's own window instead of a browser tab.

## Can a link open in a Chrome web app instead of a tab?

Yes. Point the rule's `app` at the web app's bundle ID, and matching links open in the web app's window. In the rule editor, choose the web app under **Web apps** in the **Browser** menu.

```json rule
{
  "name": "ClickUp → ClickUp web app",
  "match": { "patterns": ["app.clickup.com/*"] },
  "action": { "app": "com.google.Chrome.app.edcmabgkbicempmpgmniellhbjopafjh" }
}
```

```text junction test
$ junction test "https://app.clickup.com/t/86abc123"
input:       https://app.clickup.com/t/86abc123
rule:        [1] ClickUp → ClickUp web app
action:      open in com.google.Chrome.app.edcmabgkbicempmpgmniellhbjopafjh
url:         https://app.clickup.com/t/86abc123
```

This works for any web app you installed from Chrome with **Install page as app**, such as ClickUp or Google Chat. Keep the pattern to the web app's own site: see [links from other sites](#what-happens-to-a-link-from-a-different-site).

## How do I find a Chrome web app's bundle ID?

Usually you don't need to: the rule editor lists every installed web app under **Web apps**. To write the rule in the config file, ask macOS for the ID by the app's name:

```text Terminal
$ osascript -e 'id of app "ClickUp"'
com.google.Chrome.app.edcmabgkbicempmpgmniellhbjopafjh
```

## Which Chrome profile does the web app open in?

The profile you installed the web app in. Junction reads that from Chrome, which needs **Full Disk Access**, the same access that lists your profiles. A `profile` on the rule takes over when this Mac has that profile.

| Rule's `profile` | With Full Disk Access | Without it |
| --- | --- | --- |
| None | The profile the web app is installed in | Your fallback browser |
| A profile name | That profile, or the web app's own if this Mac has no such profile | Your fallback browser |
| A profile directory (`Profile 1`) | That profile, or the web app's own if this Mac has no such profile | That directory |

So without Full Disk Access, put the profile's directory on the rule in the config file. The rule editor saves names, and [Chrome shows each profile's directory](chrome-profile-links.md#how-do-i-find-a-chrome-profiles-directory-name). To turn the access on, see [why you can't choose a browser profile](links-open-wrong-browser.md#why-cant-i-choose-a-browser-profile).

```json rule
{
  "name": "ClickUp → web app in Profile 1",
  "match": { "patterns": ["app.clickup.com/*"] },
  "action": { "app": "com.google.Chrome.app.edcmabgkbicempmpgmniellhbjopafjh", "profile": "Profile 1" }
}
```

## What happens to a link from a different site?

It opens in your fallback browser. A web app would drop a link from another site and show its own page instead, so Junction doesn't hand it one.

Keep the rule's patterns to the web app's own site: `app.clickup.com/*`, not `*.clickup.com/*`. Links to the rest of the site then go through your other rules as usual. For a site with a Mac app rather than a web app, use a [deep link](custom-app-deep-links.md) instead.

## Get Junction

Junction is free and MIT-licensed, for macOS 13 or later on Apple silicon and Intel. [Install it](/#install) with Homebrew or the DMG, then follow the [first-launch steps](/docs#quickstart).
