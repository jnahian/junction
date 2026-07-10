---
name: release
description: Cut a Junction release — bump the version, build the .app, and publish the Sparkle update. Use when the user wants to release, ship a new version, publish an update, or cut a build of Junction.
---

# Release Junction

A release touches the version in `App/Info.plist`, a tag that must point at the
committed bump, and a signed appcast. Miss any one and the zip, the appcast, and
the cask drift apart. Work the checklist top to bottom — **create one todo per
numbered step.**

Releases are cut **locally**, not by CI. The Sparkle EdDSA private key lives in
the maintainer's login keychain under the `junction` account; nothing signs
updates without it. There is deliberately no release workflow — a CI-built zip
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

## 3. Commit and push the bump — before releasing

`gh release create` tags the latest **pushed** commit. If the bump isn't
committed and pushed, the tag and the zip's source won't match.

```sh
git add App/Info.plist
git commit -m "chore(release): bump version to NEW_DISPLAY"
git push
```

## 4. Build the app

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

## 5. Publish

```sh
Scripts/release.sh
```

`release.sh` re-checks that the time-based `CFBundleVersion` exceeds the
published build (it always will, short of clock skew) and refuses otherwise. It
signs `dist/Junction.zip` with the keychain key, generates `appcast.xml`, and
uploads both to the `vNEW_DISPLAY` GitHub release. It then rewrites
`Casks/junction.rb` with the new version and the uploaded zip's sha256 and
commits that (`chore: update Homebrew cask …`), so the `brew install --cask` tap
tracks the release automatically — nothing to bump by hand.

## 6. Confirm

```sh
gh release view "vNEW_DISPLAY" --repo jnahian/junction
```

The release must be the newest non-prerelease (so
`releases/latest/download/appcast.xml` resolves) and carry both `Junction.zip`
and `appcast.xml`. Updates reach Apple-silicon Macs only (arm64 binary).

## What goes missing if you skip a step

| Skipped | Symptom |
| --- | --- |
| Version not bumped in `App/Info.plist` | Release is tagged `vNEW` but the app reports the old version |
| Bump not committed/pushed before release | Tag points at old source; zip ≠ tag |
| `appcast.xml` not uploaded | Every client silently sees "no update" |
| `release.sh` cask commit not pushed | `brew install --cask` serves the previous version |
| Zip rebuilt after `release.sh` | Bytes no longer match the signature; updates fail to install |

## Keys and secrets

- Public key (`SUPublicEDKey`) is in `App/Info.plist`. Changing it orphans every
  installed copy — they will reject all future updates. Don't.
- Private key: login keychain, account `junction`. Back it up with
  `generate_keys --account junction -x junction-key.txt` and store it somewhere
  safe. **Lose it and you can never ship an update to existing installs again.**

## Not yet notarized

`Scripts/bundle-app.sh` ad-hoc signs. The `CODESIGN_IDENTITY` path exists but
`--deep` does not properly sign Sparkle's nested XPC services, so it will fail
notarization. Before adding a Developer ID cert, sign Sparkle's nested code
inside-out first (see the `ponytail:` note in `bundle-app.sh`).
