# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Junction is a macOS menu-bar app that registers as the default browser and routes every clicked
http(s) link to a browser, browser profile, or native app via an ordered, first-match-wins rule
list. Swift Package Manager, no Xcode project. Rules live in `~/.config/junction/config.json`
(honors `$XDG_CONFIG_HOME`).

## Commands

```sh
swift test                                    # engine unit tests (XCTest; also run on Linux CI)
swift test --filter RoutingEngineTests        # one test class
swift test --filter RoutingEngineTests/testFirstMatchWins  # one test
swift build                                   # debug build of app + CLI
Scripts/bundle-app.sh                         # release build → runnable dist/Junction.app
Scripts/make-dmg.sh                           # dist/Junction.dmg
Scripts/release.sh                            # sign, appcast, GitHub release, cask bump (maintainer-only)
```

There is no lint step. CI (`.github/workflows/ci.yml`) runs `swift test` on macOS and Linux,
bundles the app, smoke-tests the CLI, and validates `rewriters.json` with a Python script.

Releasing has its own skill (`.claude/skills/release/SKILL.md`) — use it; the version bump, the tag,
and the signed appcast must stay in lockstep or updates break silently.

## Target layout and the one hard rule

Four SPM targets, and the dependency direction matters:

- **`JunctionCore`** — pure Foundation. Config, matching, rewriters, transforms, routing.
  **Must stay AppKit-free** — it compiles and is tested on Linux CI. Platform needs are injected
  (see `RoutingEngine.isSchemeHandled`). This is where nearly all logic and all tests live.
- **`JunctionMacKit`** — the AppKit glue: `Dispatcher` (executes decisions via NSWorkspace),
  `BrowserDiscovery` (installed browsers + Chromium/Firefox profiles), `SourceAppResolver`.
  Shared by the app and the CLI. Every file is wrapped in `#if canImport(AppKit)`.
- **`JunctionApp`** — menu-bar app (SwiftUI in AppKit windows). No Dock icon, no main window.
- **`JunctionCLI`** — the `junction` binary, shipped inside the app bundle at
  `Contents/Helpers/junction`. Named `junction-cli` as an SPM product only because APFS is
  case-insensitive and would collide with the `Junction` app binary.

## How a link flows

1. `AppDelegate.handleGetURL` receives the `kAEGetURL` Apple Event. It resolves the sender PID to a
   source-app bundle ID, checks the ⌥ modifier, and builds a `LinkEvent`. Note this handler is
   registered in `applicationWillFinishLaunching`, not `didFinishLaunching` — when the app is
   *launched by* a link click, the event arrives before the latter.
2. `AppState.handle` runs `RoutingEngine.trace(event)`.
3. `RoutingEngine` (Sources/JunctionCore/Engine/RoutingEngine.swift) is the heart: strip tracking
   params → ⌥ forces picker → ordered rules, first match wins → enabled built-in rewriters →
   fallback browser. It returns a `RoutingDecision` (open / deepLink / prompt / clipboard / fallback)
   wrapped in a `RoutingTrace` that explains *why* — the trace powers both the rule-tester UI and
   `junction test`.
4. `Dispatcher.dispatch` executes the decision.

Rules are compiled to `CompiledRule` (regexes, wildcard patterns) once per config load, never on the
click path.

**A link is never lost.** Every failure path — missing browser, missing deep-link app, deleted
Firefox profile, unknown rewriter, invalid rule — degrades to the fallback browser with a
`degradedToFallback(reason:)` outcome rather than dropping the link or opening the wrong thing.
Preserve that property in any change to routing or dispatch.

## Config handling

`ConfigStore` loads, validates, saves, and watches the file. Reads tolerate JSONC (comments,
trailing commas, via `JSONC.swift`); writes emit strict JSON with sorted keys so git diffs stay
clean. An invalid external edit keeps the last-good config in memory and surfaces a menu-bar warning
rather than breaking routing. `ConfigStore.validate` is the single source of truth for what a valid
config is — the GUI, the CLI (`junction config validate`), and the file watcher all go through it.

`Rule.id` is a GUI-only UUID: not persisted, and excluded from `Rule`'s `==`.

## Deep-link rewriters are data, not code

`Sources/JunctionCore/Resources/rewriters.json` — regex patterns plus a `$1`-style template and the
target app's URL scheme. Adding an app is a JSON-only change (see CONTRIBUTING.md); it should not
require touching Swift. A rewriter only fires if an app claiming its `scheme` is installed. `@1`-style
template refs look the capture up in a table instead of substituting it (Slack: workspace subdomain →
team ID from `config.slackTeams`); an unmapped `@N` fails the rewrite into the browser fallback rather
than opening the app on the wrong screen.

Built-in rewriters are opt-in per user (`config.enabledRewriters`); an explicit `deepLink` rule action
always works regardless.

## Gotchas

- `CoreResources.swift` hand-rolls resource-bundle lookup instead of using SPM's `Bundle.module`,
  which `fatalError`s when the bundle isn't found — fatal for the CLI running outside the app bundle.
  Adding a resource to `JunctionCore` means it must resolve in all four deployment shapes listed there.
- Profile switching is per browser family: Chromium takes `--profile-directory=`, Firefox takes `-P`.
  Both require `createsNewApplicationInstance = true`, because NSWorkspace only honors `arguments` for
  a new process. Never infer the family from whether profiles were found — derive it from the bundle ID
  (`BrowserDiscovery.family`).
- `CFBundleVersion` is stamped at build time from `date +%Y%m%d%H%M` by `bundle-app.sh`. Only
  `CFBundleShortVersionString` in `App/Info.plist` is hand-bumped.
- Zero telemetry, zero logging of routed links — the recent-links list is in-memory, capped at 10, and
  dies with the process. Don't add persistence to it.
