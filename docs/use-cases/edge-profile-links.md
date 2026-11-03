---
title: Open Links in a Specific Edge Profile on Mac
order: 5
summary: Send work links to your work Microsoft Edge profile and everything else to another browser or profile, automatically. Junction picks the Edge profile per link.
related: [actions, rules, troubleshooting]
icons: [edge]
---

# Open links in the right Microsoft Edge profile on your Mac

Junction is a free, open-source macOS app that becomes your default browser and routes each link by your rules. One rule can send your work sites to the Edge profile signed in to your work account, so they stop opening in whichever window you used last.

## How do I open a link in a specific Edge profile?

Write a rule that matches the link and opens it in Edge with a `profile`. Edge's bundle ID is `com.microsoft.edgemac`, and the profile is its name as **Settings → Browsers** lists it.

```json rule
{
  "name": "Work sites → Edge work profile",
  "match": { "patterns": ["*.atlassian.net/*", "app.asana.com/*"] },
  "action": { "app": "com.microsoft.edgemac", "profile": "Work" }
}
```

```text junction test
$ junction test "https://acme.atlassian.net/browse/ENG-42"
input:       https://acme.atlassian.net/browse/ENG-42
rule:        [1] Work sites → Edge work profile
action:      open in com.microsoft.edgemac profile "Work"
url:         https://acme.atlassian.net/browse/ENG-42
```

Rules run top to bottom and the first match wins, so put specific rules above broad ones.

## How do I find my Edge profile's name?

**Settings → Browsers** in Junction lists every Edge profile with its name and directory, and the rule editor offers them when you pick Edge. Listing them needs **Full Disk Access**, which Junction uses only to read Edge's list of profiles. See [why you can't choose a browser profile](links-open-wrong-browser.md#why-cant-i-choose-a-browser-profile).

| Profile | Directory |
| --- | --- |
| The first one Edge created | `Default` |
| Each one added after it | `Profile 1`, `Profile 2`, and so on |

Without Full Disk Access, an Edge profile rule still works if you type the directory into the config file. The rule editor saves the name, because the same directory can be a different profile on another Mac.

## Can Microsoft 365 links open in my work Edge profile?

Yes. SharePoint, OneDrive, and Outlook links can go to the Edge profile signed in to your company account, and personal Microsoft links somewhere else. See [Microsoft 365 links](microsoft-365-links.md).

## Can Edge open work links and another browser everything else?

Yes. Keep the Edge rule above for your work sites, and make your everyday browser the fallback, where every link no rule matches goes:

```json config
{
  "fallback": { "app": "com.apple.Safari" }
}
```

For one browser per site without profiles, see [a default browser per website](default-browser-per-website.md).

## Does this work with Edge Beta?

Yes. Edge Beta's bundle ID is `com.microsoft.edgemac.Beta`, and Junction lists its profiles the same way. Chrome, Brave, Vivaldi, and Helium work the same as well — see [Chrome profiles](chrome-profile-links.md).

## Get Junction

Junction is free and MIT-licensed, for macOS 13 or later on Apple silicon and Intel. [Install it](/#install) with Homebrew or the DMG, then follow the [first-launch steps](/docs#quickstart).
