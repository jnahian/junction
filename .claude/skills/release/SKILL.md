---
name: release
description: Cut a Junction release — bump the version, build the .app, and publish it on GitHub Releases. Use when the user wants to release, ship a new version, publish an update, or cut a build of Junction.
---

# Release Junction

A release touches the version in `App/Info.plist`, a tag that must point at the
committed bump, and the appcast that copies from 0.12.0 and earlier read. Miss any
one and the DMG, the update check, and the cask drift apart. Work the checklist top to bottom — **create one todo per
numbered step.**

Releases are cut **locally**, not by CI. The self-signed **Junction Code Signing**
certificate lives in the maintainer's login keychain: `bundle-app.sh` signs the app
with it, and `release.sh` refuses a build that isn't. On a new Mac, import its
`.p12` backup. A new certificate, even one with the same name, revokes every user's
Full Disk Access. There is deliberately no release workflow: CI doesn't have the
certificate, and a build signed with anything else would revoke that access too.

Junction doesn't install updates. It asks GitHub's `releases/latest` for the newest
tag, compares it with its own `CFBundleShortVersionString`, and when the tag is
newer, its **Update to …** item opens the release page.

## 1. Decide the version

- **Display version** (`CFBundleShortVersionString`): semver, e.g. `0.2.0`. This
  is the only version you choose.
- **Build number** (`CFBundleVersion`): derived automatically from the build time
  (`date +%Y%m%d%H%M`) in `Scripts/bundle-app.sh` — nothing to bump. Copies from
  0.12.0 and earlier still run Sparkle, which compares it against the appcast;
  being time-based it's always monotonic.

## 2. Bump the display version in `App/Info.plist`

Edit the one value:

```
<key>CFBundleShortVersionString</key>
<string>NEW_DISPLAY</string>
```

Leave `CFBundleVersion` alone — it's stamped at build time.

## 3. Close out the changelog

Users read `CHANGELOG.md` in three places: as the notes on the GitHub release
page that **Update to …** opens (the section whose heading matches the version),
in the update dialog of copies from 0.12.0 and earlier (through the appcast), and
on the website's changelog page, which is generated from this file. Rename the `## Unreleased` heading to the version and
today's date:

```md
## NEW_DISPLAY — YYYY-MM-DD
```

Bullets must already be prefixed `Added:` / `Changed:` / `Fixed:` — that's what
the website parses. If there's no `Unreleased` section, the work shipped
undocumented: write the entries now, from the commits since the last tag, before
going further. See the `document-change` skill.

Check it parses, and that the release will actually have notes to show:

```sh
cd web && npm test && cd ..
Scripts/release-notes.sh NEW_DISPLAY --markdown   # the GitHub release notes
```

`npm test` asserts the newest shipped changelog section equals
`CFBundleShortVersionString`. `release-notes.sh` is the same script `release.sh`
uses for the release notes and the appcast — run it here and you see exactly what
users will read. It exits non-zero when the section is missing, so a release with
no notes stops here rather than reaching users as an empty release page. CI runs
both.

## 4. Commit and push the bump — before releasing

`gh release create` tags the latest **pushed** commit. If the bump isn't
committed and pushed, the tag and the DMG's source won't match.

```sh
git add App/Info.plist CHANGELOG.md
git commit -m "chore(release): bump version to NEW_DISPLAY"
git push
```

Nothing else needs a version bump: the website reads `App/Info.plist` and
`CHANGELOG.md` at build time, and `release.sh` rewrites the Homebrew cask.

## 5. Build the app

```sh
Scripts/bundle-app.sh
```

Sanity-check the versions baked into the bundle:

```sh
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/Junction.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' dist/Junction.app/Contents/Info.plist
```

The display version must equal `NEW_DISPLAY`; the build number must exceed the
one in the currently published appcast.

Optional smoke test: `open dist/Junction.app`, then menu bar → **Check for
Updates…** should say you're up to date (the newest published release is older).

## 6. Publish

```sh
Scripts/release.sh
```

`release.sh` re-checks that the time-based `CFBundleVersion` exceeds the
published build (it always will, short of clock skew) and refuses otherwise. It
builds the installer (`Scripts/make-dmg.sh`), writes `appcast.xml` for copies from
0.12.0 and earlier, and uploads both to the `vNEW_DISPLAY` GitHub release, with
this version's changelog section as the notes. The appcast is informational: a
link to the release page and no download, so there's nothing to sign. It then
rewrites
`Casks/junction.rb` with the new version and the uploaded DMG's sha256 and
commits that (`chore: update Homebrew cask …`), so the `brew install --cask` tap
tracks the release automatically — nothing to bump by hand.

## 7. Confirm

```sh
gh release view "vNEW_DISPLAY" --repo jnahian/junction
```

The release must be the newest non-prerelease (the app asks GitHub for
`releases/latest`, and old copies read `releases/latest/download/appcast.xml`) and
carry both `Junction.dmg` and `appcast.xml`. This should print `vNEW_DISPLAY`:

```sh
curl -fsSL https://api.github.com/repos/jnahian/junction/releases/latest | grep '"tag_name"'
```

The build is universal, so it runs on both Apple-silicon and Intel Macs.

## What goes missing if you skip a step

| Skipped | Symptom |
| --- | --- |
| Version not bumped in `App/Info.plist` | Release is tagged `vNEW` but the app reports the old version |
| `CHANGELOG.md` section not renamed from `Unreleased` | `release.sh` stops for want of notes; the website's changelog has no entry for the release |
| Bump not committed/pushed before release | Tag points at old source; DMG ≠ tag |
| `appcast.xml` not uploaded | Copies from 0.12.0 and earlier never hear of this or any later version |
| `release.sh` cask commit not pushed | `brew install --cask` serves the previous version |
| DMG re-uploaded after `release.sh` | Its sha256 no longer matches the cask, so `brew install` fails |
| DMG built before `notarize.sh` staples the app | Installed app has no ticket; Gatekeeper checks online every launch |

## The old Sparkle key

Copies from 0.12.0 and earlier still trust the EdDSA public key that was in their
`Info.plist` (`SUPublicEDKey`). Its private key is in the login keychain, account
`junction`, service `https://sparkle-project.org`. Nothing signs with it any more,
but anyone holding it can still sign a build that those copies install and run on
their own, so it stays as secret as it ever was. This repo is **public**: never
commit it, encrypted or not. `.gitignore` covers `*-key.txt`, but the rule is the
point, not the pattern.

The appcast `release.sh` writes doesn't need the key. Keep it only if you might
one day want to push a signed update to those old copies; otherwise deleting it
from the keychain is the safest thing to do with it.

## Not yet notarized

`Scripts/bundle-app.sh` signs with the self-signed Junction Code Signing certificate
(ad-hoc without it), which Gatekeeper doesn't trust, so every download is quarantined
and users clear the flag after each update. The `CODESIGN_IDENTITY` path signs with
Hardened Runtime for a Developer ID certificate, and `Scripts/notarize.sh` staples
the result, if there's ever one.
