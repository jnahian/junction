---
title: Open Spotify Links in the Spotify App on Mac
order: 8
summary: Play Spotify and Apple Music links in their apps, open App Store links in the App Store, and keep YouTube in its own browser. Junction routes them all.
related: [deeplinks, actions, rules]
---

# Open Spotify, Apple Music, and App Store links in their apps

Junction is a free, open-source macOS app that becomes your default browser and routes each link by your rules. Its deep links start a shared song in Spotify or Music instead of a web player, and open an App Store link in the App Store.

## How do I make Spotify links open in the Spotify app?

Turn on **Spotify** in **Settings → Deep Links**, or add a rule with the `spotify` deep link. Tracks, albums, artists, playlists, shows, and episodes open in the app.

```json rule
{
  "name": "Spotify → app",
  "match": { "patterns": ["open.spotify.com/*"] },
  "action": { "deepLink": "spotify" }
}
```

If Spotify isn't installed, the link opens in your fallback browser instead.

## How do I open Apple Music links in the Music app?

Turn on **Apple Music** in **Settings → Deep Links**, or add a rule. A song link opens on that song, not just its album.

```json rule
{
  "name": "Apple Music → Music",
  "match": { "patterns": ["music.apple.com/*"] },
  "action": { "deepLink": "apple-music" }
}
```

```text junction test
$ junction test "https://music.apple.com/us/album/abbey-road/1441164426?i=1441164430"
input:       https://music.apple.com/us/album/abbey-road/1441164426?i=1441164430
rule:        [1] Apple Music → Music
action:      deep link (apple-music)
url:         music://music.apple.com/us/album/abbey-road/1441164426?i=1441164430
```

## How do I open App Store links in the App Store app?

Turn on **App Store** in **Settings → Deep Links**, or add a rule for `apps.apple.com`.

```json rule
{
  "name": "App Store → app",
  "match": { "patterns": ["apps.apple.com/*"] },
  "action": { "deepLink": "app-store" }
}
```

```text junction test
$ junction test "https://apps.apple.com/us/app/xcode/id497799835"
input:       https://apps.apple.com/us/app/xcode/id497799835
rule:        [1] App Store → app
action:      deep link (app-store)
url:         macappstore://apps.apple.com/us/app/xcode/id497799835
```

## Can YouTube open in a different browser?

Yes. YouTube has no deep link, but a rule can send it to its own browser, such as Brave.

```json rule
{
  "name": "YouTube → Brave",
  "match": { "patterns": ["*.youtube.com/*", "youtu.be/*"] },
  "action": { "app": "com.brave.Browser" }
}
```

`*.youtube.com/*` covers `www.youtube.com`, `m.youtube.com`, and `youtube.com` itself.

## Which other apps have built-in deep links?

Chat apps are in [Slack, Discord and Telegram links](slack-discord-links.md), and design tools in [Figma, Notion and Linear links](figma-notion-linear-links.md). The [docs list every one](/docs#deeplinks).

## Get Junction

Junction is free and MIT-licensed, for macOS 13 or later on Apple silicon and Intel. [Install it](/#install) with Homebrew or the DMG, then follow the [first-launch steps](/docs#quickstart).
