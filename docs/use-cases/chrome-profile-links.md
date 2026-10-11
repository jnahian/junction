---
title: Open Links in a Specific Chrome Profile on Mac
order: 1
summary: Send work links to your work Chrome profile and everything else to your personal one, automatically. Junction picks the profile by the link, account, or app.
related: [actions, rules, menubar]
---

# Open every link in the right Chrome profile on your Mac

Junction is a free, open-source macOS app that becomes your default browser and routes each link by your rules. One rule can send Jira, Google Docs, or any other site to a specific Chrome profile, so work links stop landing in your personal browser window.

## How do I open a link in a specific Chrome profile?

Write a rule that matches the link and opens it in Chrome with a `profile`. Junction launches Chrome with that profile no matter where you clicked.

- **Match** the sites with wildcard patterns: `*.atlassian.net/*` covers every Jira subdomain and the apex domain.
- **Open** with `{ "app": "com.google.Chrome", "profile": "Profile 1" }`. The profile is Chrome's profile *directory*, not its display name.
- **Order** matters: rules run top to bottom and the first match wins, so put specific rules above broad ones.

```json rule
{
  "name": "Work tools → work profile",
  "match": { "patterns": ["*.atlassian.net/*", "app.clickup.com/*", "docs.google.com/*"] },
  "action": { "app": "com.google.Chrome", "profile": "Profile 1" }
}
```

Check it without opening anything:

```text junction test
$ junction test "https://acme.atlassian.net/browse/ENG-42"
input:       https://acme.atlassian.net/browse/ENG-42
rule:        [1] Work tools → work profile
action:      open in com.google.Chrome profile "Profile 1"
url:         https://acme.atlassian.net/browse/ENG-42
```

## How do I find a Chrome profile's directory name?

**Settings → Browsers** in Junction lists every Chrome profile with its directory name. Listing them needs **Full Disk Access**, which Junction uses only to read Chrome's list of profiles.

| Profile | Directory |
| --- | --- |
| The first one Chrome created | `Default` |
| Each one added after it | `Profile 1`, `Profile 2`, … |

Without Full Disk Access, a Chrome profile rule still works if you type the directory into the config file yourself. Chrome also shows it: open `chrome://version` in that profile and read the last part of **Profile Path**.

## Can a second Google account open in its own profile?

Yes — match the `authuser` query parameter with a `regex`. Wildcard patterns ignore the query string, so a regex is the way to tell `?authuser=1` links apart.

```json rule
{
  "name": "Google account #2 → Profile 2",
  "match": { "regex": "[?&]authuser=1(&|$)" },
  "action": { "app": "com.google.Chrome", "profile": "Profile 2" }
}
```

Put this rule *above* any broad Google rule, or the broad one wins first.

## Does this work with Edge and Brave profiles?

Yes. Edge and Brave are built on Chromium, and Junction opens their profiles the same way: name the browser by its bundle ID and the profile by its directory.

| Browser | Bundle ID |
| --- | --- |
| Google Chrome | `com.google.Chrome` |
| Microsoft Edge | `com.microsoft.edgemac` |
| Brave | `com.brave.Browser` |

A common setup sends Microsoft 365 to Edge, signed in to the company account:

```json rule
{
  "name": "Microsoft 365 → Edge",
  "match": { "patterns": ["*.sharepoint.com/*", "outlook.office.com/*"] },
  "action": { "app": "com.microsoft.edgemac" }
}
```

Firefox profiles work too, with a different kind of name — see [Firefox profiles](firefox-profile-links.md).

## Can every link from Slack open in my work profile?

Yes. A rule can match the app you clicked in instead of the link itself — see [routing links by the app you click them in](links-from-apps.md).

## Can I switch every link to a clean profile while screen sharing?

Yes. Add a catch-all rule with the pattern `*` that opens a clean profile, then turn it off in the menu bar's **Rules** list. Before a demo, tick it there; every link opens in the clean profile until you untick it.

```json rule
{
  "name": "Demo mode → clean profile",
  "match": { "patterns": ["*"] },
  "action": { "app": "com.google.Chrome", "profile": "Profile 3" }
}
```

Keep it at the top of your list, so it wins over every other rule while it's on.

## Get Junction

Junction is free and MIT-licensed, for macOS 13 or later on Apple silicon and Intel. [Install it](/#install) with Homebrew or the DMG, then follow the [first-launch steps](/docs#quickstart).
