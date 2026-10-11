---
title: Open Links From Slack in a Different Browser
order: 3
summary: Route links by the app you click them in. Send Slack links to your work browser, terminal links to your dev browser, and Mail links to the clipboard.
related: [rules, cli, actions]
---

# Route links by the app you click them in

Junction is a free, open-source macOS app that becomes your default browser and routes each link by your rules. A rule can match the app the click came from, so every link out of Slack, your terminal, or Mail can go somewhere different.

## How do I open every link from Slack in a different browser?

Write a rule with `sourceApps` set to Slack's bundle ID. Any link clicked in Slack then follows that rule, whatever site it points to.

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

Keep it near the top of your list. Rules run top to bottom and the first match wins, so a site rule above it would catch some of Slack's links first.

## How do I find an app's bundle ID?

Ask macOS for it in Terminal:

```text Terminal
$ osascript -e 'id of app "Slack"'
com.tinyspeck.slackmacgap
```

| App | Bundle ID |
| --- | --- |
| Slack | `com.tinyspeck.slackmacgap` |
| Mail | `com.apple.mail` |
| Terminal | `com.apple.Terminal` |
| iTerm2 | `com.googlecode.iterm2` |

## Can terminal links open in my dev browser?

Yes. List both terminals in `sourceApps`, and the URLs printed by your dev server, `gh`, or a failing build open in the browser you develop in.

```json rule
{
  "name": "From the terminal → Chrome",
  "match": { "sourceApps": ["com.googlecode.iterm2", "com.apple.Terminal"] },
  "action": { "app": "com.google.Chrome" }
}
```

More rules for developers are in [routing localhost and dev links](developer-links.md).

## Can a rule match both the app and the site?

Yes. When a rule has both `sourceApps` and `patterns`, a link has to match both. That narrows a rule to one app's links for one site.

```json rule
{
  "name": "Jira from Slack → work profile",
  "match": { "patterns": ["*.atlassian.net/*"], "sourceApps": ["com.tinyspeck.slackmacgap"] },
  "action": { "app": "com.google.Chrome", "profile": "Profile 1" }
}
```

## Can links from Mail be copied instead of opened?

Yes. Give the rule the `clipboard` action and a click in Mail copies the link rather than opening it, so you can read the whole address first. Put this rule at the top of your list: any rule above it would still open the link. More on that in [link privacy](privacy-link-rules.md).

```json rule
{
  "name": "From Mail → clipboard",
  "match": { "sourceApps": ["com.apple.mail"] },
  "action": { "clipboard": true }
}
```

## How do I test a source-app rule without that app?

Run `junction test` with `--source` and the app's bundle ID. It prints which rule wins and why, and opens nothing.

## Get Junction

Junction is free and MIT-licensed, for macOS 13 or later on Apple silicon and Intel. [Install it](/#install) with Homebrew or the DMG, then follow the [first-launch steps](/docs#quickstart).
