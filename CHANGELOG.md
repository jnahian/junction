# Changelog

Notes for each release. The section matching the app's version is shown in the
Sparkle update dialog, so write it for users, not for contributors.

## 0.5.0

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
