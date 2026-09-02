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
  layouts/      Base.astro — <head>, favicons, and the site chrome
  components/   MenuBar + TopBar (chrome) · one per section: landing/*, docs/*, changelog/*
  scripts/      client JS, one module per behavior
  styles/       chrome.css (shared) + one stylesheet per page
  pages/        index · docs · changelog
```

`Base.astro` renders the fake macOS menu bar and the topbar on **every** page, so
a page only declares what's page-specific:

```astro
<Base title="Junction — Documentation" topbar={{ kind: "Docs", menuButton: true }}>
```

Both bars are sticky and stack: the menu bar at `top: 0`, the topbar at
`top: var(--menubar-h)`. Anything else that pins to the top (the docs sidebar,
its mobile scrim) offsets by `var(--chrome-h)` — the two heights added. Change a
bar's height in `chrome.css` and the rest follows.

Each page sets `--bar-max` on `.topbar` so the topbar contents line up with that
page's own content column (1120px on the landing page, 1240px on docs, 820px on
the changelog).

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

## Fonts and caching

Space Grotesk and JetBrains Mono are self-hosted, imported in `Base.astro` from
`@fontsource-variable/*`. They used to come from `fonts.googleapis.com`, which put
a render-blocking stylesheet on a third-party origin at the front of the critical
path — DNS, TLS and a fetch against a host the browser had no connection to yet.
Self-hosted, that origin is gone: the `@font-face` rules ship inside `Base.css` and
the woff2 files come over the connection that already served the HTML, hashed and
`immutable`. The chain is still HTML → `Base.css` → woff2, since `Base.css` is not
inlined; flattening it further would need a `rel=preload` on the hashed font
filenames. One variable file per family covers every weight the site uses, and
`unicode-range` means a reader only downloads the latin subset. The stacks in
`styles/*.css` name `"Space Grotesk Variable"` first because that is the family the
fontsource packages register — rename it and the text silently falls back to
system-ui.

`vercel.json` gives every route except `/_astro/` a `Cache-Control` of
`public, max-age=0, must-revalidate, s-maxage=31536000`. The `s-maxage` makes edge
retention explicit and long-lived instead of leaving it to Vercel's internal
default; it does not pre-warm a cold POP, so the first visitor in a new region
still pays a MISS. Vercel keys its CDN cache per deployment, so a long `s-maxage`
cannot serve yesterday's build. The browser-facing `max-age` stays `0` on purpose —
pages bake in the version number and changelog at build time, so clients must
revalidate after a release. `/_astro/` is excluded because Vercel already serves
those hashed assets as `immutable`, and this header would be a downgrade.

## App icons

`public/icons/*.svg` are the real brand marks, from [thesvg.org](https://thesvg.org)
(`/icons/<slug>/default.svg`). They're used in two places: the routing diagram's
destination tiles (`diagram.json` → `icon`) and the deep-link app list in the docs.

Files are named after the **rewriter id** in `rewriters.json`, which is how
`repo.js` pairs them up — `teams.svg`, `vscode.svg`, `github-desktop.svg`. A
rewriter with no icon file renders as text, so adding one to `rewriters.json`
without an icon degrades rather than breaking.

Two gotchas, already handled, that will bite again if you add icons:

- GitHub's `default.svg` is broken at the source — a 16-unit path inside a
  `0 0 1024 1024` viewBox, so it renders as a speck. `github-desktop.svg` is
  built from their `light.svg` with the near-black `#1b1f23` fill swapped for
  `#e9eef7`, since the original is invisible on this background.
- Check any new icon against the dark background before shipping it.

These are third-party trademarks, used to identify the apps Junction routes to.
They aren't ours and aren't MIT-licensed with the rest of the repo.

## Adding a page

Add `src/pages/<name>.astro`, wrap it in `Base`, import a stylesheet. Links are
plain `<a href="/…">`; external ones get `target="_blank"` automatically
(`src/scripts/external-links.js`, loaded from the layout).
