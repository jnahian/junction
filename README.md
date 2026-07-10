# Junction

**A rule-based link router for macOS.** Junction sits as your default browser and routes every link you click to the right browser, browser profile, or native app, based on rules you define.

Open source (MIT) · GUI **and** a version-controllable JSON config file · CLI included · zero telemetry.

## Why

macOS allows exactly one default browser. If you juggle work and personal Chrome profiles, want Zoom links in the Zoom app instead of a tab, or want Terminal links in a different browser than Mail links, you need a router in between. Choosy is paid, Velja is closed source, Finicky has no GUI. Junction is the open-source option with a first-class GUI *and* a human-readable config file you can check into your dotfiles.

## How it works

1. Junction registers as your default browser (it's a menu bar app: no windows, no Dock icon).
2. Every clicked `http(s)` link goes through your ordered rule list; **first match wins**.
3. Rules match on URL wildcards (`*.atlassian.net/*`), regex, and/or the **source app** the click came from.
4. Actions: open in a browser, open in a specific **Chromium profile**, rewrite to a **native app deep link** (17 built in, including Zoom, Spotify, Slack, Figma, Notion, Teams, Discord, Linear, Telegram, WhatsApp, Apple Music), show a **picker**, or copy to clipboard.
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
      "name": "Links from Terminal → Chrome",
      "match": { "sourceApps": ["com.googlecode.iterm2", "com.apple.Terminal"] },
      "action": { "app": "com.google.Chrome" }
    }
  ]
}
```

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

**GitHub Releases:** grab `Junction.dmg` from the [latest release](https://github.com/jnahian/junction/releases), open it, drag **Junction** into Applications. Current builds are not yet notarized, so right-click → Open on first launch, or:

```sh
xattr -dr com.apple.quarantine /Applications/Junction.app
```

**Homebrew** (this repo is its own tap):

```sh
brew tap jnahian/junction https://github.com/jnahian/junction
brew install --cask --no-quarantine junction
```

Upgrades arrive automatically: each release bumps the cask, so `brew upgrade` picks it up.

**Auto-update:** Junction checks for updates on its own via [Sparkle](https://sparkle-project.org). You can trigger a check any time from the menu bar, or from **Settings → General → Updates**. Updates are EdDSA-signed, so the app only installs builds signed with the maintainer's private key.

**From source** (macOS 13+, Xcode 15+):

```sh
git clone https://github.com/jnahian/junction && cd junction
Scripts/bundle-app.sh
open dist/Junction.app
```

On first launch, Junction walks you through picking a fallback browser and setting itself as default.

## Building & testing

```sh
swift test              # engine unit tests (also run on Linux CI)
swift build             # debug build of app + CLI
Scripts/bundle-app.sh   # assemble dist/Junction.app
Scripts/make-dmg.sh     # build the drag-to-Applications dist/Junction.dmg
```

Releases are cut locally, not by CI: `Scripts/release.sh` signs the DMG, generates the Sparkle appcast, publishes the GitHub release, and bumps the Homebrew cask. It needs the maintainer's signing key, so only the maintainer can publish.

The routing engine (`Sources/JunctionCore`) is a pure, UI-free Swift package: matchers, transforms, rewriters, and config I/O are fully unit-tested and have no AppKit dependency.

## Contributing deep-link rewriters

Rewriters are data, not code: [`Sources/JunctionCore/Resources/rewriters.json`](Sources/JunctionCore/Resources/rewriters.json). Adding support for a new app is a JSON-only PR. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Privacy

Zero telemetry, zero analytics. Junction makes exactly one kind of network request: the Sparkle update check against this repository's release feed. The links you route are never sent anywhere and never logged to disk; the recent-links list is in-memory, capped at 10, and cleared on quit.

Being the default browser is a high-trust position. That's the argument for open source, for CI that builds and tests every commit, and for updates that only install if they carry a valid EdDSA signature from the maintainer's key.

## Status & roadmap

MVP under active development. Explicitly planned for v1.1+: redirect/shortener unwrapping (opt-in), `mailto:` routing, Firefox profiles/containers, time- and network-based conditions, Shortcuts actions. Arc spaces have no public API and are documented as unsupported.

## License

MIT
