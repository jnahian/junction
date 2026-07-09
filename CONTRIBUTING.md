# Contributing to Junction

Thanks for helping! Two contribution paths, one of which needs no Swift at all.

## The easy path: add a deep-link rewriter (JSON only)

Rewriters turn web URLs into native app URLs (e.g. `https://zoom.us/j/123` → `zoommtg://zoom.us/join?confno=123`). They live in [`Sources/JunctionCore/Resources/rewriters.json`](Sources/JunctionCore/Resources/rewriters.json).

Each entry:

```json
{
  "id": "myapp",
  "name": "My App",
  "patterns": ["^https?://myapp\\.com/thing/([A-Za-z0-9]+)"],
  "template": "myapp://thing/$1",
  "scheme": "myapp",
  "bundleID": "com.example.myapp"
}
```

- `patterns` — regexes over the full URL; first match wins. Capture what the template needs.
- `template` — output URL; `$1`–`$9` insert capture groups. Query params whose value ends up empty are dropped automatically (handy for optional groups like meeting passwords).
- `scheme` — the app's URL scheme. The rewriter only activates when an installed app claims this scheme, so shipping niche rewriters is safe.
- `bundleID` — optional, improves UI labels.

Checklist for the PR:

1. Add the entry to `rewriters.json` (keep alphabetical-ish grouping).
2. Add a test case in `Tests/JunctionCoreTests/TransformTests.swift` (copy an existing `RewriterTests` case — it's three lines).
3. In the PR description, note how you verified the scheme URL opens the right place in the native app.

CI validates JSON syntax, required keys, unique IDs, and that every pattern compiles.

## Code contributions

- `Sources/JunctionCore` — pure Foundation rule engine. This is where matchers, transforms, and config handling live. Fully unit-tested; please keep it AppKit-free (it compiles on Linux).
- `Sources/JunctionMacKit` — NSWorkspace dispatch, browser/profile discovery, source-app resolution.
- `Sources/JunctionApp` — menu bar app, settings UI, picker, onboarding.
- `Sources/JunctionCLI` — the `junction` command.

Workflow:

```sh
swift test                # run engine tests
swift build               # build everything
Scripts/bundle-app.sh     # assemble a runnable dist/Junction.app
```

Please include tests for engine changes. UI changes: a screenshot in the PR is enough.

## Reporting bugs

`junction test <url> --source <bundle-id>` output plus your (redacted) config file makes routing bugs trivially reproducible — include both when relevant.
