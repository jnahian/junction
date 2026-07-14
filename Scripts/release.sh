#!/usr/bin/env bash
# Publish a Sparkle auto-update release: build the DMG, sign it, generate
# appcast.xml, and upload both to GitHub Releases under a v<version> tag, then
# bump the Homebrew cask.
#
# Run Scripts/bundle-app.sh first (bump CFBundleShortVersionString in App/Info.plist),
# then Scripts/release.sh.
#
# Requires: gh (authenticated) and the Sparkle EdDSA private key in your keychain
# under the `junction` account (minted with `generate_keys --account junction`).
set -euo pipefail

cd "$(dirname "$0")/.."
REPO="jnahian/junction"
KEY_ACCOUNT="junction"
GEN="$PWD/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"

APP="dist/Junction.app"
DMG="dist/Junction.dmg"
[ -d "$APP" ] || { echo "No $APP — run Scripts/bundle-app.sh first."; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
TAG="v${VERSION}"

# Sparkle compares CFBundleVersion, not the display string. If it didn't increase
# past the published build, every client sees "no update" — the classic silent
# no-op. Refuse to publish in that case.
NEW_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
PUB_BUILD="$(curl -fsSL "https://github.com/${REPO}/releases/latest/download/appcast.xml" 2>/dev/null \
  | sed -n 's/.*<sparkle:version>\([0-9][0-9]*\)<.*/\1/p' | head -1 || true)"
if [ -n "${PUB_BUILD}" ] && [ "${NEW_BUILD}" -le "${PUB_BUILD}" ]; then
  echo "CFBundleVersion ${NEW_BUILD} must exceed the published ${PUB_BUILD}, or clients"
  echo "see no update. Rebuild with Scripts/bundle-app.sh."
  exit 1
fi

# Build the installer only once the version guard has passed.
Scripts/make-dmg.sh

# generate_appcast signs the DMG (private key pulled from the keychain) and writes
# appcast.xml. Isolate the DMG so only this build becomes an update entry; the
# download URL points at where gh will host it under this tag.
STAGE="$(mktemp -d)"
cp "$DMG" "$STAGE/"

# Release notes: generate_appcast embeds an HTML fragment named after the archive
# (Junction.html next to Junction.dmg) as the item's <description>, which is what
# Sparkle's update dialog renders. release-notes.sh builds it from this version's
# CHANGELOG section and fails if there isn't one — empty notes are a release bug,
# not a warning, since nobody finds out until a user opens the dialog. CI runs the
# same script, so the release stops at the pull request instead.
"$(dirname "$0")/release-notes.sh" "$VERSION" > "$STAGE/Junction.html"

"$GEN" --account "$KEY_ACCOUNT" \
  --download-url-prefix "https://github.com/${REPO}/releases/download/${TAG}/" "$STAGE"
cp "$STAGE/appcast.xml" dist/appcast.xml

# Create the release (or replace assets if the tag already exists). Must be the
# newest, non-prerelease release so releases/latest/download/appcast.xml resolves.
gh release create "$TAG" "$DMG" dist/appcast.xml \
    --repo "$REPO" --title "$TAG" --generate-notes \
  || gh release upload "$TAG" "$DMG" dist/appcast.xml --repo "$REPO" --clobber

echo "Released ${TAG}: appcast.xml + Junction.dmg uploaded to ${REPO}."

# Point the Homebrew cask at this release. The dmg url is version-templated, so
# only the version and sha256 change per release; rewrite those two lines and
# commit so `brew install --cask` never serves a stale build. The sha256 is of
# the exact DMG we just uploaded, so `brew` verifies the same bytes.
CASK="Casks/junction.rb"
DMG_SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
sed -i '' \
  -e "s/^  version \".*\"/  version \"${VERSION}\"/" \
  -e "s/^  sha256 \".*\"/  sha256 \"${DMG_SHA}\"/" \
  "$CASK"
if ! git diff --quiet -- "$CASK"; then
  git add "$CASK"
  git commit -m "chore: update Homebrew cask to ${TAG}"
  git push
  echo "Updated ${CASK} -> ${VERSION} (${DMG_SHA})."
fi
