# Changelog

Notes for each release. The section matching the app's version is shown in the
Sparkle update dialog, so write it for users, not for contributors.

## 0.5.1

- Junction now launches on Macs other than the one it was built on. 0.5.0 crashed on startup for everyone else — it looked for its icon and starter rules in a folder that only existed on the developer's machine, and gave up when it wasn't there. If 0.5.0 did nothing when you opened it, this is why.
- Intel Macs are supported again. Previous builds only contained Apple-silicon code, so they could not start on an Intel Mac at all.

## 0.5.0

- Add your own deep-link apps. Settings → Deep Links → "Add App…" takes the app's URL scheme, a pattern for the web link, and a template for the app link, with a test field to try it before saving. Your apps sit alongside the built-in ones, work as a rule's deep-link action, and can replace a built-in by using the same name.

## 0.4.3

- Double-clicking a local .html file works again. Making Junction your default browser also hands it your HTML files, and it was quietly dropping them; they now open in your fallback browser.

## 0.4.2

- New updates announce themselves quietly: the menu bar icon gets a dot and the menu offers "Update to …" instead of an update window appearing behind your other apps.

## 0.4.1

- Slack deep links now open the right channel and message. They need a team ID, which Slack permalinks don't carry, so map your workspaces in Settings → Deep Links; unmapped ones open in the browser as before.
- Recent links moved into their own submenu, so the menu bar stays short.

## 0.4.0

- Keyboard shortcuts now work: Cut/Copy/Paste/Select All in every Settings field, and ⌘W to close a window.
- Settings opens on General, and a new About tab shows the version, credits, and a link to report an issue.
- The onboarding welcome screen shows the real app icon.

## 0.3.0

- Route links to a specific Firefox profile.
- Onboarding no longer offers starter rules for apps you don't have installed, and remembers your fallback pick when you step back.
- Ships as a styled DMG installer.

## 0.2.0

- Automatic updates via Sparkle.

## 0.1.1

- Fixes to the Homebrew cask install.

## 0.1.0

- First release: rule-based link routing, browser picker, deep links, transforms.
