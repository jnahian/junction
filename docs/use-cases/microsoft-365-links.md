---
title: Open Microsoft 365 Links in the Right Account
order: 5
summary: Send SharePoint, OneDrive, and Outlook links to the Edge profile signed in to your work account, and personal Microsoft links somewhere else, with Junction.
related: [actions, rules, deeplinks]
icons: [edge, teams]
---

# Open Microsoft 365 links in your work account, every time

Junction is a free, open-source macOS app that becomes your default browser and routes each link by your rules. For Microsoft 365, that means company SharePoint, OneDrive, and Outlook links open in the Edge profile signed in to your work account, instead of whichever browser happens to be the default.

## How do I open SharePoint and Outlook links in Edge?

Write a rule that matches your company's Microsoft 365 hosts and opens them in Edge. Edge's bundle ID is `com.microsoft.edgemac`.

```json rule
{
  "name": "Microsoft 365 → Edge",
  "match": { "patterns": ["*.sharepoint.com/*", "outlook.office.com/*"] },
  "action": { "app": "com.microsoft.edgemac" }
}
```

```text junction test
$ junction test "https://contoso.sharepoint.com/sites/finance"
input:       https://contoso.sharepoint.com/sites/finance
rule:        [1] Microsoft 365 → Edge
action:      open in com.microsoft.edgemac
url:         https://contoso.sharepoint.com/sites/finance
```

`*.sharepoint.com/*` covers every company's SharePoint site and its OneDrive, which lives on a `-my.sharepoint.com` subdomain.

## How do I open them in my work Edge profile?

Add a `profile` with the profile's *directory* name. Edge stores profiles the way Chrome does: `Default` for the first, then `Profile 1`, `Profile 2`, and so on. **Settings → Browsers** lists each Edge profile with its directory, once Junction has **Full Disk Access**.

```json rule
{
  "name": "Contoso 365 → Edge work profile",
  "match": { "patterns": ["contoso.sharepoint.com/*", "contoso-my.sharepoint.com/*", "outlook.office.com/*"] },
  "action": { "app": "com.microsoft.edgemac", "profile": "Profile 1" }
}
```

Naming your own tenant (`contoso`) instead of `*.sharepoint.com` keeps other companies' shared links out of your work profile.

## Can personal Microsoft links go somewhere else?

Yes. Personal Outlook and OneDrive use different hosts from work accounts, so a second rule can send them to another profile or browser.

| Account | Hosts |
| --- | --- |
| Work or school | `<tenant>.sharepoint.com`, `<tenant>-my.sharepoint.com`, `outlook.office.com` |
| Personal | `outlook.live.com`, `onedrive.live.com` |

```json rule
{
  "name": "Personal Microsoft → Edge Default",
  "match": { "patterns": ["outlook.live.com/*", "onedrive.live.com/*"] },
  "action": { "app": "com.microsoft.edgemac", "profile": "Default" }
}
```

## Can Teams links open in the Teams app?

Yes — that's a deep link rather than a browser rule. See [Zoom and Teams links](zoom-teams-links.md#how-do-i-open-microsoft-teams-links-in-the-teams-app).

## Does this work with Chrome instead of Edge?

Yes. Swap the bundle ID for `com.google.Chrome`; profiles work the same way. See [Chrome profiles](chrome-profile-links.md).

## Get Junction

Junction is free and MIT-licensed, for macOS 13 or later on Apple silicon and Intel. [Install it](/#install) with Homebrew or the DMG, then follow the [first-launch steps](/docs#quickstart).
