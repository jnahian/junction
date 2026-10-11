---
title: Sync Browser Routing Rules Across Macs
order: 14
summary: Keep your link rules in one plain JSON file you can commit to dotfiles, sync between Macs, and share with a team. Junction reloads and checks it on every edit.
related: [config, cli, rules]
---

# Sync your link rules across Macs with one config file

Junction is a free, open-source macOS app that becomes your default browser and routes each link by your rules. Those rules live in one plain-text JSON file you own, so you can version it, sync it to another Mac, or share it with your team.

## Where is Junction's config file?

At `~/.config/junction/config.json`. If you set `$XDG_CONFIG_HOME`, Junction uses that directory instead of `~/.config`. To print the path Junction is actually using:

```text Terminal
$ junction config path
```

## Can I keep my Junction rules in git?

Yes. The config file is plain JSON, so commit it to your dotfiles like any other config. Settings writes strict JSON with **sorted keys**, so a change made in the app shows up as a small, clean diff.

```json config
{
  "version": 1,
  "fallback": { "app": "com.apple.Safari" },
  "stripTrackingParams": true,
  "rules": [{ "name": "Work tools → work profile", "match": { "patterns": ["*.atlassian.net/*", "docs.google.com/*"] }, "action": { "app": "com.google.Chrome", "profile": "Profile 1" } }]
}
```

## Can the config file have comments?

Yes, when you edit it by hand: Junction accepts comments and trailing commas when it reads the file. Settings saves strict JSON, though, so keep the comments only if you make your changes in the file rather than in the app.

## What happens when the config file changes?

Junction watches the file and reloads it as soon as it changes — a `git pull` takes effect without restarting anything.

- **A valid edit** goes live immediately.
- **An invalid edit** doesn't break routing: Junction keeps the last rules that worked and shows a warning in the menu bar until you fix the file.

## How do I check a config before committing it?

Run `junction config validate`. It runs the same validation the app and the file watcher use, so a config that passes is a config Junction will load. To see which rule a link hits, run `junction test` with the link — see [why links open in the wrong browser](links-open-wrong-browser.md).

## Can a team share one rules file?

Yes, with one caveat: rules name browsers by bundle ID, which is the same on every Mac, but browser **profile** directories (`Profile 1`, `Profile 2`) depend on the order each person created their profiles. Check profile rules on each Mac with **Settings → Browsers**.

| Part of a rule | Same on every Mac? |
| --- | --- |
| Patterns, regex, source apps | Yes |
| Browser bundle IDs | Yes |
| Chrome / Edge profile directories | No — check each Mac |
| Firefox profile names | Only if everyone uses the same names |

## Does the config file contain my browsing history?

No. It holds rules and settings only. Junction never writes the links you click to disk — the recent-links list lives in memory and is cleared when you quit. See [link privacy](privacy-link-rules.md#does-junction-send-my-links-anywhere).

## Get Junction

Junction is free and MIT-licensed, for macOS 13 or later on Apple silicon and Intel. [Install it](/#install) with Homebrew or the DMG, then follow the [first-launch steps](/docs#quickstart).
