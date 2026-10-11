---
title: Turn Link Rules On and Off From the Menu Bar
order: 15
summary: Switch a link rule off for the weekend or on for a screen share without opening Settings. Junction lists every rule in its menu bar menu, each one a click away.
related: [menubar, rules, privacy]
icons: [toggle-right]
---

# Switch link rules on and off from the menu bar

Junction is a free, open-source macOS app that becomes your default browser and routes each link by your rules. It lives in the menu bar — no windows, no Dock icon — and its menu lists every rule, so you can turn one off or on with a single click.

![Junction's Rules menu: five rules checked on, the demo-mode rule off, and Edit Rules… at the bottom](../assets/screenshots/menu-bar-rule-toggles/01-rules-menu.png)

## How do I turn a rule off without opening Settings?

Click Junction's menu-bar icon, open **Rules**, and click the rule. A checkmark means the rule is on; click it again to turn it back on.

- Rules are listed in match order, the order Junction checks them.
- **Edit Rules…** at the bottom opens the Rules pane in Settings.

## What happens to links while a rule is off?

Junction skips it. A link the rule would have caught goes to the next rule that matches, or to your fallback browser if none does — exactly as if the rule weren't there.

## Can I switch every link to a clean profile while screen sharing?

Yes. Add a catch-all rule with the pattern `*` that opens a clean browser profile, then turn it off in the **Rules** menu. Before a demo, tick it there: every link opens in the clean profile, with no personal tabs or history on screen, until you untick it.

```json rule
{
  "name": "Demo mode → clean profile",
  "match": { "patterns": ["*"] },
  "action": { "app": "com.google.Chrome", "profile": "Profile 3" }
}
```

```text junction test
$ junction test "https://example.com/"
input:       https://example.com/
rule:        [1] Demo mode → clean profile
action:      open in com.google.Chrome profile "Profile 3"
url:         https://example.com/
```

Keep it at the top of your list, so it wins over every other rule while it's on. Profile directories are explained in [Chrome profiles](chrome-profile-links.md#how-do-i-find-a-chrome-profiles-directory-name).

## Can I pause my work rules on weekends?

Yes. Turn the work rule off in the **Rules** menu on Friday and back on on Monday; its links open in your fallback browser in between.

```json rule
{
  "name": "Work tools → work profile",
  "match": { "patterns": ["*.atlassian.net/*", "app.clickup.com/*", "docs.google.com/*"] },
  "action": { "app": "com.google.Chrome", "profile": "Profile 1" }
}
```

To send *everything* to one place for a while, a catch-all rule like the demo one above is quicker than switching rules off one by one.

## What else is in Junction's menu?

| Item | What it does |
| --- | --- |
| **Recent Links** | The last 10 links Junction routed. In memory only — never written to disk. |
| **Rules** | Every rule, checked when it's on. |
| **Settings…** | Fallback, rules, browsers and profiles, deep links, updates. |
| **Update to …** | Appears, and the icon gets a dot, when an update is ready. |

The icon also warns you when the config file has an error; the last rules that worked stay live until you fix it. More in [syncing rules across Macs](sync-rules-across-macs.md#what-happens-when-the-config-file-changes).

## Get Junction

Junction is free and MIT-licensed, for macOS 13 or later on Apple silicon and Intel. [Install it](/#install) with Homebrew or the DMG, then follow the [first-launch steps](/docs#quickstart).
