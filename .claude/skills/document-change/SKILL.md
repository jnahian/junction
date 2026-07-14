---
name: document-change
description: Record a shipped change in the changelog and the docs — use after implementing, fixing, or removing a user-visible behavior in Sources/, before committing. Triggers on "document this", "update the changelog", "update the docs", "I finished the feature", or when a change to Sources/ is about to be committed without a CHANGELOG entry.
---

# Document a change

A change that users can see but can't read about is half-shipped: the Sparkle
update dialog shows them `CHANGELOG.md`, and the website is generated from this
repo. **Create one todo per numbered step** and work them in order.

First, answer one question — it decides how much of this applies:

> **Can a user tell the difference?**

If no (a refactor, a test, a build script, an internal rename), stop. Nothing
here applies; say so and move on. Documenting invisible changes is noise in a
file users read.

If yes, continue.

## 1. Add the changelog entry

Entries go under `## Unreleased` at the top of `CHANGELOG.md`, above the newest
released section. Create that heading if it isn't there — no date on it; the
[release skill](../release/SKILL.md) renames it to `## X.Y.Z — DATE` when it ships.

The format is parsed, not decorative (`web/src/lib/repo.js` reads it):

```md
## Unreleased

- Added: Route links to a specific Firefox profile.
- Fixed: Slack deep links now open the right channel.
```

- The marker is `Added:`, `Changed:`, or `Fixed:` — nothing else parses, and the
  build's `npm test` in `web/` fails on a bullet without one.
- **Write it for a user, not for a reviewer.** They don't know your function
  names. Say what changed for them and, if it fixes something, what the broken
  behavior looked like — that's how someone recognizes their own bug. The 0.5.1
  entry is the model: "If 0.5.0 did nothing when you opened it, this is why."
- One bullet per user-visible change, not per commit.

## 2. Update the docs that are now wrong

Ask which of these the change touched, and edit only those:

| Changed | Update |
| --- | --- |
| A rule field, action, or match semantic | `web/src/data/docs.json` (`patterns`, `actions`, `samples`) and the `README.md` config section |
| A CLI command or flag | `web/src/data/docs.json` → `cliCommands`, and `README.md` → CLI |
| A Settings screen or menu-bar item | `web/src/data/docs.json` → `menubarActions` |
| A new failure mode users will hit | `web/src/data/docs.json` → `troubleshooting` |
| Install requirements or steps | `README.md`, `web/src/data/site.json` (commands), `web/src/components/landing/Install.astro` |
| A headline capability | `web/src/data/landing.json` → `features.cards` |
| Something previously documented as unsupported | `web/src/data/docs.json` → `unsupported`, `roadmap` |

**Do not touch** the version, the release list, or the deep-link app list. Those
are read from `App/Info.plist`, `CHANGELOG.md`, and `rewriters.json` at build
time — editing a copy of them is the exact drift this setup exists to prevent.
A new rewriter in `rewriters.json` is already on the website.

Prose lives in the JSON data files, not in the components. If you find yourself
editing an `.astro` file to change wording, you're in the wrong place — check
`web/src/data/` first.

## 3. Verify

```sh
cd web && npm test && npm run build
```

`npm test` parses `CHANGELOG.md` and asserts the newest *shipped* entry matches
`App/Info.plist` — so it catches an unmarked bullet, a malformed heading, and a
release with no notes. The build catches a broken reference in the data.

If the change touched routing, also run `swift test` from the repo root.

## 4. Report what you did and didn't

Say which files you changed, and name anything you deliberately left alone
("no docs change — this is internal"). A silent no-op reads the same as a
forgotten one.
