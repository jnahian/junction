---
title: Open Links in a Firefox Profile on Mac
order: 4
summary: Keep each client's logins and cookies apart by opening their links in their own Firefox profile. Junction picks the profile from the link, with one rule each.
related: [actions, rules, troubleshooting]
icons: [firefox]
---

# Open each client's links in their own Firefox profile

Junction is a free, open-source macOS app that becomes your default browser and routes each link by your rules. With one rule per client, their links open in that client's Firefox profile, with that client's logins, cookies, and extensions.

## How do I open a link in a specific Firefox profile?

Write a rule that matches the client's sites and opens Firefox with that profile's *name*. Junction launches Firefox with the profile however you clicked the link.

```json rule
{
  "name": "Acme → Acme profile",
  "match": { "patterns": ["*.acme-corp.com/*"] },
  "action": { "app": "org.mozilla.firefox", "profile": "Acme" }
}
```

```text junction test
$ junction test "https://portal.acme-corp.com/tickets"
input:       https://portal.acme-corp.com/tickets
rule:        [1] Acme → Acme profile
action:      open in org.mozilla.firefox profile "Acme"
url:         https://portal.acme-corp.com/tickets
```

`*.acme-corp.com/*` matches every subdomain of `acme-corp.com` and the bare domain too, at any path.

## What name does Firefox's profile need?

Use the profile name exactly as `firefox -P` lists it. Junction also lists Firefox profiles under **Settings → Browsers**.

| Browser family | What `profile` takes | Example |
| --- | --- | --- |
| Firefox | The profile **name** | `Acme` |
| Chrome, Edge, Brave | The profile **directory** | `Profile 1` |

Listing profiles needs **Full Disk Access**, which Junction uses only to read Firefox's `profiles.ini`. Unlike Chrome, a Firefox profile rule *needs* that access: without it, the link opens in your fallback browser instead.

## How do I set up one profile per client?

Add one rule per client, each with that client's domains and profile. Rules run top to bottom and the first match wins, so a client rule only needs to sit above any broader rule that would also match.

```json rule
{
  "name": "Globex → Globex profile",
  "match": { "patterns": ["*.globex.io/*", "globex.atlassian.net/*"] },
  "action": { "app": "org.mozilla.firefox", "profile": "Globex" }
}
```

A client's own Jira or Slack workspace usually has its own subdomain, so it can go in that client's rule.

## What happens if a profile is deleted?

The link still opens. If a rule names a Firefox profile that no longer exists, Junction opens the link in your fallback browser rather than dropping it or opening the wrong profile.

## Can I use Firefox containers instead?

No. Containers are a Firefox extension feature with no launch option Junction could use. Firefox *profiles* are supported, and Chrome profiles work the same way — see [Chrome profiles](chrome-profile-links.md).

If you'd rather choose a profile per click than per rule, [let the picker ask](choose-browser-per-link.md).

## Get Junction

Junction is free and MIT-licensed, for macOS 13 or later on Apple silicon and Intel. [Install it](/#install) with Homebrew or the DMG, then follow the [first-launch steps](/docs#quickstart).
