# Junction — website

The marketing site: landing page, docs, and changelog. Astro, static output, no
framework runtime shipped to the browser.

```sh
npm install
npm run dev       # http://localhost:4321
npm run build     # → dist/
npm run preview   # serve dist/ exactly as it deploys
npm test          # the three self-checks in src/lib
```

Deployed on Vercel with **Root Directory = `web`**. Astro is auto-detected; there
is no `vercel.json` and nothing to configure.

## The rule: repo facts are read, not copied

Anything the repo already knows is read from the repo at build time, via
[`src/lib/repo.js`](src/lib/repo.js). Copying these into the site is what makes a
website go stale, so don't:

| Fact | Source of truth |
| --- | --- |
| Version (`v0.5.1` in the topbar, the install button, the DMG link) | `App/Info.plist` → `CFBundleShortVersionString` |
| Every release on `/changelog` | `CHANGELOG.md` |
| The deep-link app list and the "17 rewriters" count | `Sources/JunctionCore/Resources/rewriters.json` |

So bumping the version in `Info.plist` updates the site. Adding a rewriter to
`rewriters.json` updates the site. Neither needs a change here.

`repo.js` runs at **build time only** — it uses `node:fs`. Never import it from
`src/scripts/` (those run in the browser).

### CHANGELOG.md has a shape

`repo.js` parses it, so it isn't free-form:

- Release heading: `## 0.5.1 — 2026-07-14`
- Every bullet: `- Added: …`, `- Changed: …`, or `- Fixed: …`

The marker drives the filter pills on the changelog page. A bullet without one
is a build error, not a silently untyped entry. Work in progress goes under a
`## Unreleased` heading (no date); the [release skill](../.claude/skills/release/SKILL.md)
renames it to `## X.Y.Z — DATE` when it ships.

## Everything else is data

Prose that *isn't* derivable lives in `src/data/*.json` — no copy is hardcoded in
a component:

- `site.json` — name, URLs (GitHub, releases, issues, license), install commands, footer columns
- `landing.json` — hero, feature cards, the interactive matcher's rules, install copy
- `diagram.json` — the animated routing diagram: input chips, destinations, and which routes to which
- `docs.json` — sidebar nav, config samples, pattern/action tables, troubleshooting

To fix a typo or reword a feature, edit the JSON. To restructure a page, edit the
component.

## Layout

```
src/
  data/         the copy (above)
  lib/          repo.js (repo facts) · match.js (pattern matcher) · highlight.js (JSON syntax colors)
  layouts/      Base.astro — <head>, fonts, favicon
  components/   one per section: landing/*, docs/*, changelog/*, shared TopBar
  scripts/      client JS, one module per behavior
  styles/       one stylesheet per page
  pages/        index · docs · changelog
```

No inline `<script>` or `<style>` survives the build — Astro emits hashed
external assets and the HTML only references them.

`src/lib` holds the only real logic, so each file has a self-check next to it
(`npm test`):

- `match.js` — mirrors Junction's pattern semantics (`*` within a segment, `**`
  across, `*.host` includes the apex) for the landing page's rule tester
- `highlight.js` — colors the JSON config samples, so `docs.json` can store them
  as plain text instead of span soup
- `repo.js` — parses `CHANGELOG.md` / `Info.plist` / `rewriters.json`; the test
  also asserts the newest shipped changelog entry matches the version in
  `Info.plist`, which catches a release that forgot its notes

## Adding a page

Add `src/pages/<name>.astro`, wrap it in `Base`, import a stylesheet. Links are
plain `<a href="/…">`; external ones get `target="_blank"` automatically
(`src/scripts/external-links.js`, loaded from the layout).
