---
title: Remove Tracking Parameters From Links on Mac
order: 10
summary: Strip utm_ and other tracking parameters from every link, keep banking in one browser, and copy risky links instead of opening them, all on your Mac.
related: [privacy, config, actions]
---

# Strip tracking from links and keep risky ones under control

Junction is a free, open-source macOS app that becomes your default browser and routes each link by your rules. It can remove tracking parameters from every link before it opens, send sensitive sites to one browser, and copy a link instead of opening it.

## How do I remove tracking parameters from links on Mac?

Set `stripTrackingParams` to `true`. Junction then drops tracking parameters from every link before it routes it, and leaves the rest of the query alone.

```json config
{
  "stripTrackingParams": true
}
```

```text junction test
$ junction test "https://example.com/post?utm_source=newsletter&id=7"
input:       https://example.com/post?utm_source=newsletter&id=7
transformed: https://example.com/post?id=7
rule:        none
action:      fallback → com.apple.Safari
url:         https://example.com/post?id=7
```

The `transformed` line shows the link after stripping; rules match against that version.

## Does Junction send my links anywhere?

No. Junction has zero telemetry and zero analytics, and the links you route are never sent anywhere or written to disk.

| What | Where it goes |
| --- | --- |
| Links you click | Nowhere — routed on your Mac |
| Recent links list | Memory only, last 10, cleared on quit |
| Network requests | Only the update check against Junction's GitHub release feed |

## How do I keep banking sites in one browser?

Write a rule that sends your bank's domains to the browser you keep for money — Safari with no extensions, say — whichever app the link came from.

```json rule
{
  "name": "Banks → Safari",
  "match": { "patterns": ["*.chase.com/*", "*.paypal.com/*", "*.wise.com/*"] },
  "action": { "app": "com.apple.Safari" }
}
```

## Can I copy a link instead of opening it?

Yes. The `clipboard` action copies the link rather than opening it. Pair it with `sourceApps` so every link clicked in Mail is copied, and read the full address before deciding to open it:

```json rule
{
  "name": "From Mail → clipboard",
  "match": { "sourceApps": ["com.apple.mail"] },
  "action": { "clipboard": true }
}
```

```text junction test
$ junction test "https://example.com/verify-account" --source com.apple.mail
input:       https://example.com/verify-account
source:      com.apple.mail
rule:        [1] From Mail → clipboard
action:      copy to clipboard
url:         https://example.com/verify-account
```

Put it first in your list: rules run top to bottom, so a rule above it would still open the link. More on app-based rules in [routing links by app](links-from-apps.md).

## Can short links ask before they open?

Yes — send them to the picker, so you choose where they open after seeing the link. See [choosing a browser per link](choose-browser-per-link.md#can-only-some-links-ask).

## Get Junction

Junction is free and MIT-licensed, for macOS 13 or later on Apple silicon and Intel. [Install it](/#install) with Homebrew or the DMG, then follow the [first-launch steps](/docs#quickstart).
