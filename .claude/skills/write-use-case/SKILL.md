---
name: write-use-case
description: Write or extend a use-case page on the Junction website (docs/use-cases/<slug>.md → /use-cases/<slug>). Use when asked to "write a use case", "add a use-case page", "add a section to a use case", "document how to do X with Junction" for the site, or to turn a routing scenario into an SEO page. Not for /docs or CHANGELOG changes — that's the document-change skill.
---

# Write a use case

A use-case page answers one search — "open links in a Firefox profile on Mac" —
with the Junction rule that does it. The full page contract is in
[web/README.md → Use-case pages](../../../web/README.md#use-case-pages); this is
the process. **Create one todo per numbered step** and work them in order.

## 1. New page or new section?

List what exists: `grep -h '^title:\|^order:' docs/use-cases/*.md`.

- A **new page** is a distinct search intent with at least 3 questions worth
  answering. One rule on its own (a single app's deep link) is too thin — it's a
  section on the page its siblings live on.
- Otherwise **add an H2 section** to the closest page and skip the frontmatter in
  step 3.

## 2. Check every claim before writing it

The rule is: **claim only what `/docs` documents.** Sources, in order:

| Claim | Check against |
| --- | --- |
| Behavior, actions, match semantics | `web/src/data/docs.json`, `web/src/components/docs/*.astro` |
| A Settings label, menu item, or shortcut | `Sources/JunctionApp/` (grep the exact string) |
| A `deepLink` id | the `id` field in `Sources/JunctionCore/Resources/rewriters.json` — not its display name |
| A bundle ID | `osascript -e 'id of app "Name"'`, or `BrowserDiscovery.swift` / `starter-rules.json` |
| Platform | Free, MIT, macOS 13+, **Apple silicon and Intel** (universal build) |

Known gaps — real features `/docs` doesn't cover, so they stay **out** of use
cases until someone documents them (the `document-change` skill):
per-rule `rewrite`, `extraTrackingParams`, `pickerHidden`. Also out: anything in
`docs.json` → `roadmap` or `unsupported` (Firefox containers, Arc spaces,
`mailto:`, shortener unwrapping).

Two semantics that are easy to get wrong:
- `patterns` and `regex` are **OR**; either with `sourceApps` is **AND**.
- Patterns ignore the query string — use `regex` when the query matters.

If a page promises "every link from X", the rule must sit **first** in the list
(first match wins). Say so on the page.

## 3. Write the page

Frontmatter — keep it free of `#` comments and of `: ` inside values (YAML):

```md
---
title: Open Links in a Firefox Profile on Mac
order: 11
summary: One sentence, 145–160 characters, standalone — it's the meta description, the index card, and the llms.txt line.
related: [actions, rules]
icons: [firefox]
---
```

- `title` ≤ 48 chars, the query as people type it, primary keyword first.
- `order` must be unique — next free number unless it belongs higher.
- `icons` is 1–3 names for the index card: a brand mark from
  `web/public/icons/*.svg` for the apps the page is about, or a line glyph from
  `web/src/icons/*.svg` for a topic (`shield-check`, `wrench`). A new glyph
  comes from `https://unpkg.com/lucide-static@0.460.0/icons/<name>.svg`.
- `related` takes ids from `docs.json` → `nav` (`overview`, `install`,
  `quickstart`, `config`, `rules`, `actions`, `deeplinks`, `menubar`, `cli`,
  `troubleshooting`, `privacy`).

Body:

- `# H1` in human phrasing (the title already carries the query wording), then
  an intro that names **Junction** and stands alone.
- `## Question as searched?` sections, each: **direct answer** in 1–2 sentences
  a snippet could lift → **context** (how, when, limits; facts in lists or
  tables, not buried in prose) → **proof**.
- Last section is always `## Get Junction`; copy it from an existing page.
- No "Compared with…" section unless every claim about the other app has a source.

Proof blocks — the word after the language is the code block's title bar:

````md
```json rule
{
  "name": "Acme → Acme profile",
  "match": { "patterns": ["*.acme-corp.com/*"] },
  "action": { "app": "org.mozilla.firefox", "profile": "Acme" }
}
```
````

Use ` ```json config ` for top-level keys. One top-level key per line, the rest
inline, as above.

## 4. Generate traces — never type them

A ` ```text junction test ` block must be real CLI output. Generate it:

```sh
swift build --product junction-cli
python3 .claude/skills/write-use-case/verify.py trace docs/use-cases/<slug>.md "<url>" [--source <bundleID>]
```

Paste what it prints. Only paste a deep-link trace whose `action:` reads
`deep link (…)`. If it says `fallback`, the app isn't installed on this Mac and
the trace proves nothing — show the rule and link `/docs#deeplinks` instead.

## 5. Screenshots, where the app's UI is the answer

Add one when a section tells the reader to use a Settings pane, a menu, a dialog,
or the picker. Skip it for anything a rule or a `junction test` trace already
shows. Files go in `docs/assets/screenshots/<slug>/NN-name.png` and are linked
as `![alt that describes what's on screen](../assets/screenshots/<slug>/NN-name.png)`;
the build turns them into WebP.

**Never capture the maintainer's own Junction.** Screenshots get published, and
the real app shows real rules, browser profile names, and recent links. Instead:

1. Write a demo config in a scratch dir (`<dir>/junction/config.json`) with
   made-up rules. Put every real browser profile in `pickerHidden`
   (`com.google.Chrome/<directory>`, `org.mozilla.firefox/<name>`), plus any
   non-browser apps that register for https.
2. Ask before quitting the user's Junction, since links can't route its way
   while it's down. Then: `osascript -e 'tell application id "com.jnahian.junction" to quit'`.
   Two copies running at once confuse System Events, so the real one has to stop.
3. Launch the demo copy: `XDG_CONFIG_HOME=<dir> dist/Junction.app/Contents/MacOS/Junction &`
   (build it with `Scripts/bundle-app.sh` if `dist/` is stale).
4. Drive it with System Events (`click menu bar item 1 of menu bar 2`, toolbar
   buttons by name). Compile the helper with
   `swiftc capture.swift -o capture`. Then `capture windows <pid>` gives window ids
   for `screencapture -x -o -l <id> out.png`, and `capture geturl <pid> <url>`
   opens the picker in the demo copy only.
5. **Never capture Settings → Browsers.** It lists real profile names.
6. `kill` the demo copy and `open -a /Applications/Junction.app`. Confirm it's running.

Look at every image before using it, and crop anything personal (menu-bar
extras, terminal text behind a menu). Captures are 2×; pad narrow ones to
1400px wide with transparent space (sharp's `extend`), so every shot renders at
the same scale as a Settings window.

## 6. Link it in

- Link **out** to at least 2 pages: other use cases by relative path
  (`firefox-profile-links.md`, `links-from-apps.md#heading-slug`) or `/docs#id`.
- Link **in**: edit at least one existing page so it links to the new one.
  The index doesn't count.

The index, sitemap, and `llms.txt` pick the page up by themselves — don't edit them.

## 7. Verify

```sh
python3 .claude/skills/write-use-case/verify.py   # every rule validates, every trace matches the CLI
cd web && npm test && npm run build               # frontmatter, headings, links, JSON samples
```

The build fails on any broken rule from the README contract, so a passing build
is required, not optional. Look at the page in `npm run preview` at phone width
if you added a table or a long rule.

## 8. Report

Name the page or section, its title and slug, which page now links to it, and
any claim you left out because `/docs` doesn't cover it.
