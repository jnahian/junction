# Changelog

Notes for each release. The section matching the app's version is shown in the
Sparkle update dialog, so write it for users, not for contributors.

The website renders this file directly (`web/src/lib/repo.js` parses it), so the
shape matters:

- A release heading is `## <version> — <YYYY-MM-DD>`.
- Every bullet starts with `Added:`, `Changed:`, or `Fixed:` — that marker drives
  the filter pills on the changelog page.

## 0.7.1 — 2026-07-20

- Fixed: Figma links now open the Figma app at the exact frame you linked to. The node in the address (the `?node-id=…` part) was being dropped, so the app opened the file but stayed on whatever was last on screen instead of the frame you meant.

## 0.7.0 — 2026-07-16

- Added: "Ask every time" as the fallback — Junction shows the picker for any link no rule handles, instead of silently opening a browser. Choose it in Settings → Browsers or the welcome tour, where it's now the suggested default. In the config file it's `"fallback": { "app": "picker" }`.
- Added: Hide browsers or profiles you never use from the picker, with the new checkboxes in Settings → Browsers.
- Added: The welcome tour offers "Launch Junction at login" alongside the default-browser step.
- Changed: The welcome tour's starter suggestions no longer assume Chrome — you pick the browser for the work and terminal suggestions. Zoom and Spotify now switch on the matching deep link (Settings → Deep Links) instead of adding a duplicate rule.
- Added: The welcome tour ends with a "You're all set" page that shows the menu-bar icon and can send a test link through your new setup, so you can watch Junction work before the window closes.
- Changed: Pressing Esc in the picker now just closes it. It used to open the link in your fallback browser, so there was no way to dismiss the picker without opening something.
- Added: The picker has a visible "Copy Link" button — ⌘C still works too.
- Added: Copying a link to the clipboard (from the picker or a clipboard rule) now shows a brief "Link copied" confirmation. Before, a clipboard rule looked like nothing happened.

## 0.6.0 — 2026-07-14

- Added: ClickUp doc links open in the ClickUp app. Turn on "ClickUp (docs)" in Settings → Deep Links. Only task links were recognized before, so docs still opened in the browser.
- Fixed: Figma FigJam boards, Slides and prototype links now open in the Figma app — previously only design files did. They open the file in the editor; a prototype does not start in presentation mode.
- Fixed: Spotify links shared from a non-English app now open in Spotify. They carry a language prefix in the address that Junction did not recognize.
- Fixed: Notion links on its new app.notion.com address open in the Notion app, alongside the old notion.so ones.

## 0.5.1 — 2026-07-14

- Fixed: Junction now launches on Macs other than the one it was built on. 0.5.0 crashed on startup for everyone else — it looked for its icon and starter rules in a folder that only existed on the developer's machine, and gave up when it wasn't there. If 0.5.0 did nothing when you opened it, this is why.
- Fixed: Intel Macs are supported again. Previous builds only contained Apple-silicon code, so they could not start on an Intel Mac at all.

## 0.5.0 — 2026-07-13

- Added: Add your own deep-link apps. Settings → Deep Links → "Add App…" takes the app's URL scheme, a pattern for the web link, and a template for the app link, with a test field to try it before saving. Your apps sit alongside the built-in ones, work as a rule's deep-link action, and can replace a built-in by using the same name.

## 0.4.3 — 2026-07-13

- Fixed: Double-clicking a local .html file works again. Making Junction your default browser also hands it your HTML files, and it was quietly dropping them; they now open in your fallback browser.

## 0.4.2 — 2026-07-13

- Changed: New updates announce themselves quietly: the menu bar icon gets a dot and the menu offers "Update to …" instead of an update window appearing behind your other apps.

## 0.4.1 — 2026-07-12

- Fixed: Slack deep links now open the right channel and message. They need a team ID, which Slack permalinks don't carry, so map your workspaces in Settings → Deep Links; unmapped ones open in the browser as before.
- Changed: Recent links moved into their own submenu, so the menu bar stays short.

## 0.4.0 — 2026-07-12

- Added: Keyboard shortcuts now work: Cut/Copy/Paste/Select All in every Settings field, and ⌘W to close a window.
- Added: Settings opens on General, and a new About tab shows the version, credits, and a link to report an issue.
- Changed: The onboarding welcome screen shows the real app icon.

## 0.3.0 — 2026-07-12

- Added: Route links to a specific Firefox profile.
- Changed: Onboarding no longer offers starter rules for apps you don't have installed, and remembers your fallback pick when you step back.
- Changed: Ships as a styled DMG installer.

## 0.2.0 — 2026-07-10

- Added: Automatic updates via Sparkle.

## 0.1.1 — 2026-07-10

- Fixed: Fixes to the Homebrew cask install.

## 0.1.0 — 2026-07-10

- Added: First release: rule-based link routing, browser picker, deep links, transforms.
