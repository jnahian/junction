---
name: release
description: Cut a Junction release — bump the version, build the .app, and publish the Sparkle update. Use when the user wants to release, ship a new version, publish an update, or cut a build of Junction.
---

# Release Junction

A release touches the version in `App/Info.plist`, a tag that must point at the
committed bump, and a signed appcast. Miss any one and the DMG, the appcast, and
the cask drift apart. Work the checklist top to bottom — **create one todo per
numbered step.**

Releases are cut **locally**, not by CI. The Sparkle EdDSA private key lives in
the maintainer's login keychain under the `junction` account; nothing signs
updates without it. There is deliberately no release workflow — a CI-built artifact
would not match the bytes `release.sh` signed, and every update would fail its
signature check.

## 1. Decide the version

- **Display version** (`CFBundleShortVersionString`): semver, e.g. `0.2.0`. This
  is the only version you choose.
- **Build number** (`CFBundleVersion`): derived automatically from the build time
  (`date +%Y%m%d%H%M`) in `Scripts/bundle-app.sh` — nothing to bump. It's what
  Sparkle compares, and being time-based it's always monotonic.

## 2. Bump the display version in `App/Info.plist`

Edit the one value:

```
<key>CFBundleShortVersionString</key>
<string>NEW_DISPLAY</string>
```

Leave `CFBundleVersion` alone — it's stamped at build time.

## 3. Close out the changelog

Users read `CHANGELOG.md` twice: in the Sparkle update dialog (the section whose
heading matches the version) and on the website's changelog page, which is
generated from this file. Rename the `## Unreleased` heading to the version and
today's date:

```md
## NEW_DISPLAY — YYYY-MM-DD
```

Bullets must already be prefixed `Added:` / `Changed:` / `Fixed:` — that's what
the website parses. If there's no `Unreleased` section, the work shipped
undocumented: write the entries now, from the commits since the last tag, before
going further. See the `document-change` skill.

Check it parses, and that Sparkle will actually have notes to show:

```sh
cd web && npm test && cd ..
Scripts/release-notes.sh NEW_DISPLAY     # the fragment the update dialog renders
```

`npm test` asserts the newest shipped changelog section equals
`CFBundleShortVersionString`. `release-notes.sh` is the same script `release.sh`
pipes into the appcast — run it here and you see exactly what users will read.
It exits non-zero when the section is missing, so a release with no notes stops
here rather than reaching users as an empty update dialog. CI runs both.

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
Updates…** should say you're up to date (it compares against the *published*
build, which is older).

## 6. Publish

```sh
Scripts/release.sh
```

`release.sh` re-checks that the time-based `CFBundleVersion` exceeds the
published build (it always will, short of clock skew) and refuses otherwise. It
builds the installer (`Scripts/make-dmg.sh`), signs `dist/Junction.dmg` with the
keychain key, generates `appcast.xml`, and uploads both to the `vNEW_DISPLAY`
GitHub release. It then rewrites
`Casks/junction.rb` with the new version and the uploaded DMG's sha256 and
commits that (`chore: update Homebrew cask …`), so the `brew install --cask` tap
tracks the release automatically — nothing to bump by hand.

## 7. Confirm

```sh
gh release view "vNEW_DISPLAY" --repo jnahian/junction
```

The release must be the newest non-prerelease (so
`releases/latest/download/appcast.xml` resolves) and carry both `Junction.dmg`
and `appcast.xml`. The build is universal, so updates reach both Apple-silicon
and Intel Macs.

## What goes missing if you skip a step

| Skipped | Symptom |
| --- | --- |
| Version not bumped in `App/Info.plist` | Release is tagged `vNEW` but the app reports the old version |
| `CHANGELOG.md` section not renamed from `Unreleased` | Sparkle shows an empty update dialog; the website's changelog has no entry for the release |
| Bump not committed/pushed before release | Tag points at old source; DMG ≠ tag |
| `appcast.xml` not uploaded | Every client silently sees "no update" |
| `release.sh` cask commit not pushed | `brew install --cask` serves the previous version |
| DMG rebuilt after `release.sh` | Bytes no longer match the signature; updates fail to install |
| DMG built before `notarize.sh` staples the app | Installed app has no ticket; Gatekeeper checks online every launch |

## Keys and secrets

- Public key (`SUPublicEDKey`) is in `App/Info.plist`. Changing it orphans every
  installed copy — they reject all future updates. Don't.
- Private key: login keychain, account `junction`, service
  `https://sparkle-project.org`. It exists in exactly one place.

### Never commit the private key

This repo is **public**, and the key is not a read credential — it authorizes
code to execute on every user's Mac. Junction checks the feed at launch, so
anyone holding the key can sign a malicious build that users install and run.
The signature is the only thing protecting them.

Git makes it permanent: committing it puts it in the history, in every clone,
and in GitHub's API even after a force-push. Rotating away from a leaked key
means changing `SUPublicEDKey`, which orphans every existing install — so you
would strand exactly the users you were protecting. There is no undo. `.gitignore`
covers `*-key.txt`, but the rule is the point, not the pattern.

### Back it up anyway

Lose the key and you can never ship an update to an existing install again —
users would have to reinstall by hand. Export it and store it somewhere private:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account junction -x ~/Desktop/junction-key.txt
```

Paste the contents into a password manager as a secure note, then `rm` the file.
If you want a file backup instead, encrypt it (`gpg -c junction-key.txt`) and put
the `.gpg` in private cloud storage — still never in this repo.

Restore onto a new machine with `generate_keys --account junction -f <file>`.

## Not yet notarized

`Scripts/bundle-app.sh` ad-hoc signs. The `CODESIGN_IDENTITY` path exists but
`--deep` does not properly sign Sparkle's nested XPC services, so it will fail
notarization. Before adding a Developer ID cert, sign Sparkle's nested code
inside-out first (see the `ponytail:` note in `bundle-app.sh`).
