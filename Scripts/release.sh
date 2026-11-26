#!/usr/bin/env bash
# Publish a release: build the DMG and upload it to GitHub Releases under a
# v<version> tag, with this version's CHANGELOG section as the notes, then bump the
# Homebrew cask. Installed copies find it on their own: Junction checks the latest
# GitHub release and sends the user to its page.
#
# Run Scripts/bundle-app.sh first (bump CFBundleShortVersionString in App/Info.plist),
# then Scripts/release.sh.
#
# Requires: gh (authenticated).
set -euo pipefail

cd "$(dirname "$0")/.."
REPO="jnahian/junction"

APP="dist/Junction.app"
DMG="dist/Junction.dmg"
[ -d "$APP" ] || { echo "No $APP — run Scripts/bundle-app.sh first."; exit 1; }

# Every release must be signed with the same certificate. macOS ties each user's Full Disk
# Access grant to it: an ad-hoc build, or one signed with any other certificate, silently
# revokes that grant on every Mac that installs the update.
SIGNING_CERT_SHA1="a613b6fd8adf45a493011a17449cca022d8affcb"
REQUIREMENT="$(codesign -d -r- "$APP" 2>&1)"
if ! codesign --verify --deep --strict "$APP" \
   || [[ "$REQUIREMENT" != *"certificate leaf = H\"${SIGNING_CERT_SHA1}\""* ]]; then
  echo "$APP isn't signed with the Junction Code Signing certificate (${SIGNING_CERT_SHA1})."
  echo "Restore it to your login keychain from its .p12 backup — never make a new one —"
  echo "then rerun Scripts/bundle-app.sh."
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
TAG="v${VERSION}"

# Copies from 0.12.0 and earlier still check for updates with Sparkle, which reads
# releases/latest/download/appcast.xml, so every release must carry one or those copies
# never hear of a new version again. Sparkle compares CFBundleVersion, not the display
# string: if it didn't increase past the published build, they see "no update".
# Refuse to publish in that case.
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

# release-notes.sh fails if this version has no CHANGELOG section, so a release with
# no notes stops here. CI runs the same script, so it stops at the pull request first.
NOTES_HTML="$(Scripts/release-notes.sh "$VERSION")"
NOTES_MD="$(Scripts/release-notes.sh "$VERSION" --markdown)"

# The appcast is informational: a <link> and no <enclosure>. Sparkle shows the notes and
# a "Learn More…" button that opens the release page, downloads nothing, and so needs
# no EdDSA signature.
cat > dist/appcast.xml <<APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Junction</title>
    <item>
      <title>Junction ${VERSION}</title>
      <sparkle:version>${NEW_BUILD}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <link>https://github.com/${REPO}/releases/tag/${TAG}</link>
      <description><![CDATA[
${NOTES_HTML}
      ]]></description>
    </item>
  </channel>
</rss>
APPCAST

# Create the release (or replace assets if the tag already exists). Must be the
# newest, non-prerelease release: the app asks for releases/latest, and old copies
# read releases/latest/download/appcast.xml.
gh release create "$TAG" "$DMG" dist/appcast.xml \
    --repo "$REPO" --title "$TAG" --notes "$NOTES_MD" \
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
