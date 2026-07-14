# <img src="docs/logo.png" alt="" width="40" align="absmiddle"> Junction

**A rule-based link router for macOS.** Junction sits as your default browser and routes every link you click to the right browser, browser profile, or native app, based on rules you define.

Open source (MIT) · GUI **and** a version-controllable JSON config file · CLI included · zero telemetry.

## Why

macOS allows exactly one default browser. If you juggle work and personal Chrome profiles, want Zoom links in the Zoom app instead of a tab, or want Terminal links in a different browser than Mail links, you need a router in between. Choosy is paid, Velja is closed source, Finicky has no GUI. Junction is the open-source option with a first-class GUI *and* a human-readable config file you can check into your dotfiles.

## How it works

1. Junction registers as your default browser (it's a menu bar app: no windows, no Dock icon).
2. Every clicked `http(s)` link goes through your ordered rule list; **first match wins**.
3. Rules match on URL wildcards (`*.atlassian.net/*`), regex, and/or the **source app** the click came from.
4. Actions: open in a browser, open in a specific **browser profile** (Chromium or Firefox), rewrite to a **native app deep link** (17 built in, including Zoom, Spotify, Slack, Figma, Notion, Teams, Discord, Linear, Telegram, WhatsApp, Apple Music), show a **picker**, or copy to clipboard.
5. Anything unmatched opens in your fallback browser. A link is never lost.

Hold **⌥ Option** while clicking any link to force the picker.

## Config file

Rules live in `~/.config/junction/config.json` (respects `$XDG_CONFIG_HOME`). Edit them in the GUI or in your editor. The file is watched and hot-reloads with validation: invalid edits keep the last-good rules and show a menu bar warning. Comments and trailing commas are accepted on read; the GUI writes strict, stably-sorted JSON so git diffs stay clean.

```jsonc
{
  "version": 1,
  "fallback": { "app": "com.apple.Safari" },
  "stripTrackingParams": true,
  "rules": [
    {
      "name": "Work links → Chrome work profile",
      "match": { "patterns": ["*.atlassian.net/*", "app.clickup.com/*"] },
      "action": { "app": "com.google.Chrome", "profile": "Profile 1" }
    },
    {
      "name": "Zoom → native app",
      "match": { "patterns": ["*.zoom.us/j/*", "*.zoom.us/w/*"] },
      "action": { "deepLink": "zoom" }
    },
    {
      "name": "Personal → Firefox profile",
      "match": { "patterns": ["reddit.com/*", "news.ycombinator.com/*"] },
      "action": { "app": "org.mozilla.firefox", "profile": "personal" }
    },
    {
      "name": "Links from Terminal → Chrome",
      "match": { "sourceApps": ["com.googlecode.iterm2", "com.apple.Terminal"] },
      "action": { "app": "com.google.Chrome" }
    }
  ]
}
```

`profile` is a Chromium profile *directory* (`Default`, `Profile 1`) or a Firefox profile *name* (the one `firefox -P` takes, listed in **Settings → Browsers**). If a rule names a profile that no longer exists, the link degrades to your fallback browser rather than opening in the wrong one.

Pattern semantics: matched against `host/path`, scheme ignored unless written. `*` stays within a segment, `**` (or a trailing `*`) crosses segments, `*.example.com` includes the apex domain, bare `example.com` matches all subpaths. Host is case-insensitive, path case-sensitive, query ignored (use `regex` when the query matters).

## CLI

The app bundle ships a companion CLI (Homebrew links it automatically):

```sh
junction test "https://mycorp.atlassian.net/browse/X-1" --source com.tinyspeck.slackmacgap
junction open "https://example.com"
junction config path
junction config validate
```

## Install

**Requirements:** macOS 13 Ventura or later. Builds are universal — Apple silicon and Intel.

Junction is not yet notarized by Apple (no Developer ID account yet), so macOS quarantines it and refuses the first launch. **Whichever way you install, clear the quarantine flag afterward:**

```sh
xattr -dr com.apple.quarantine /Applications/Junction.app
```

### Homebrew (recommended)

This repo is its own tap, so point Homebrew straight at it. The cask lives outside Homebrew's
official taps, so trust it before installing:

```sh
brew tap jnahian/junction https://github.com/jnahian/junction
brew trust --cask jnahian/junction/junction
brew install --cask junction
xattr -dr com.apple.quarantine /Applications/Junction.app
```

Homebrew also symlinks the bundled `junction` CLI onto your PATH.

### Manual DMG

1. Download `Junction.dmg` from the [latest release](https://github.com/jnahian/junction/releases/latest).
2. Open it and drag **Junction** into Applications.
3. Run the `xattr` command above (or **right-click Junction.app → Open → Open**).

With the manual install, link the CLI yourself if you want it:

```sh
ln -sf "/Applications/Junction.app/Contents/Helpers/junction" /usr/local/bin/junction
```

### First launch

Junction is a menu-bar app — no Dock icon, no window. It opens a short setup: pick a fallback browser, set Junction as your **default browser** (the one step it can't work without, since that's how it sees every clicked link), and optionally enable a few starter rules. After that it lives in the menu bar; click the icon for recent links, settings, and updates.

### Updates

Junction checks for updates on its own via [Sparkle](https://sparkle-project.org), and you can trigger a check from the menu bar or **Settings → General → Updates**. Updates are EdDSA-signed, so the app only installs builds signed with the maintainer's key. Homebrew users can also `brew upgrade`; each release bumps the cask.

### Uninstall

```sh
brew uninstall --zap --cask junction     # Homebrew: also removes config + prefs
rm -rf /Applications/Junction.app        # manual install
```

Your rules live at `~/.config/junction/config.json` (honors `$XDG_CONFIG_HOME`); delete that too on a manual uninstall if you want a clean slate.

### From source

Requires macOS 13+ and Xcode 15+:

```sh
git clone https://github.com/jnahian/junction && cd junction
Scripts/bundle-app.sh
open dist/Junction.app
```

## Building & testing

```sh
swift test              # engine unit tests (also run on Linux CI)
swift build             # debug build of app + CLI
Scripts/bundle-app.sh   # assemble dist/Junction.app
Scripts/make-dmg.sh     # build the drag-to-Applications dist/Junction.dmg
```

Releases are cut locally, not by CI: `Scripts/release.sh` signs the DMG, generates the Sparkle appcast, publishes the GitHub release, and bumps the Homebrew cask. It needs the maintainer's signing key, so only the maintainer can publish.

The routing engine (`Sources/JunctionCore`) is a pure, UI-free Swift package: matchers, transforms, rewriters, and config I/O are fully unit-tested and have no AppKit dependency.

## Deep-link apps

Junction ships rewriters for common apps (Zoom, Spotify, Slack, Figma, Notion…), all off until you enable them in **Settings → Deep Links**.

Your app isn't in the list? Add it yourself — **Deep Links → Add App…** takes a name, the app's URL scheme, a regex for the web URL, and a template for the app URL, with a test field to check it before saving. It lands in `customRewriters` in your config and behaves exactly like a built-in (including as a `deepLink` rule action). Naming yours after a built-in replaces that built-in.

Capture only the part of the link the app needs: `^https?://linear\.app/([^?#]*)` → `linear://$1`. A catch-all `(.*)` also hands the app whatever query string or fragment a link carries, and links arrive from anywhere.

Rewriters are data, not code: [`Sources/JunctionCore/Resources/rewriters.json`](Sources/JunctionCore/Resources/rewriters.json). Contributing one for everyone is a JSON-only PR — see [CONTRIBUTING.md](CONTRIBUTING.md).

## Privacy

Zero telemetry, zero analytics. Junction makes exactly one kind of network request: the Sparkle update check against this repository's release feed. The links you route are never sent anywhere and never logged to disk; the recent-links list is in-memory, capped at 10, and cleared on quit.

Being the default browser is a high-trust position. That's the argument for open source, for CI that builds and tests every commit, and for updates that only install if they carry a valid EdDSA signature from the maintainer's key.

## Status & roadmap

MVP under active development. Explicitly planned for v1.1+: redirect/shortener unwrapping (opt-in), `mailto:` routing, time- and network-based conditions, Shortcuts actions.

Firefox containers are an extension feature with no launch-flag equivalent, so they are unsupported; Firefox *profiles* are supported. Arc spaces have no public API and are documented as unsupported.

## License

MIT
