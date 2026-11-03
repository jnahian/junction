---
title: Open Links in a Specific Vivaldi Profile on Mac
order: 7
summary: Send one client's links, or every link from one app, to the right Vivaldi profile on your Mac. Junction picks the Vivaldi profile for each link you click.
related: [actions, rules, troubleshooting]
icons: [vivaldi]
---

# Open links in the right Vivaldi profile on your Mac

Junction is a free, open-source macOS app that becomes your default browser and routes each link by your rules. A rule can send one client's sites, or every link you click in one app, to its own Vivaldi profile.

## How do I open a link in a specific Vivaldi profile?

Write a rule that matches the link and opens it in Vivaldi with a `profile`. Vivaldi's bundle ID is `com.vivaldi.Vivaldi`, and the profile is its name as **Settings → Browsers** lists it.

```json rule
{
  "name": "Acme → Vivaldi Acme profile",
  "match": { "patterns": ["*.acme-corp.com/*", "acme.slack.com/*"] },
  "action": { "app": "com.vivaldi.Vivaldi", "profile": "Acme" }
}
```

```text junction test
$ junction test "https://portal.acme-corp.com/invoices"
input:       https://portal.acme-corp.com/invoices
rule:        [1] Acme → Vivaldi Acme profile
action:      open in com.vivaldi.Vivaldi profile "Acme"
url:         https://portal.acme-corp.com/invoices
```

## How do I find my Vivaldi profile's name?

**Settings → Browsers** in Junction lists every Vivaldi profile with its name and directory, and the rule editor offers them when you pick Vivaldi. Listing them needs **Full Disk Access**, which Junction uses only to read Vivaldi's list of profiles. See [why you can't choose a browser profile](links-open-wrong-browser.md#why-cant-i-choose-a-browser-profile).

Without Full Disk Access, a Vivaldi profile rule still works if you type the profile's directory (`Default` for the first, then `Profile 1`, `Profile 2`) into the config file.

## Can every link from one app open in a Vivaldi profile?

Yes. Match on the app you clicked in with `sourceApps`, and every link from that app goes to the profile. Put the rule first: rules run top to bottom and the first match wins.

```json rule
{
  "name": "Links from Mail → Vivaldi Personal",
  "match": { "sourceApps": ["com.apple.mail"] },
  "action": { "app": "com.vivaldi.Vivaldi", "profile": "Personal" }
}
```

```text junction test
$ junction test "https://example.com/receipt" --source com.apple.mail
input:       https://example.com/receipt
source:      com.apple.mail
rule:        [1] Links from Mail → Vivaldi Personal
action:      open in com.vivaldi.Vivaldi profile "Personal"
url:         https://example.com/receipt
```

More on app-based rules: [routing links by the app you click them in](links-from-apps.md).

## What if the Vivaldi profile isn't on this Mac?

The link opens in your fallback browser rather than in the wrong profile. That matters when you [sync your rules across Macs](sync-rules-across-macs.md): give the profile the same name on each Mac, and the rule finds it on all of them.

## Get Junction

Junction is free and MIT-licensed, for macOS 13 or later on Apple silicon and Intel. [Install it](/#install) with Homebrew or the DMG, then follow the [first-launch steps](/docs#quickstart).
