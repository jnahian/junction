#!/usr/bin/env bash
# Notarizes and staples dist/Junction.app, then zips it for GitHub Releases.
# Requires: CODESIGN_IDENTITY used in bundle-app.sh, plus an App Store Connect
# API key configured as a notarytool keychain profile named "junction".
#
#   xcrun notarytool store-credentials junction \
#     --apple-id you@example.com --team-id TEAMID --password app-specific-pw
set -euo pipefail

cd "$(dirname "$0")/.."
APP="dist/Junction.app"
ZIP="dist/Junction.zip"

[ -d "$APP" ] || { echo "run Scripts/bundle-app.sh first"; exit 1; }

echo "▸ zipping for notarization"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "▸ submitting to notarytool"
xcrun notarytool submit "$ZIP" --keychain-profile junction --wait

echo "▸ stapling"
xcrun stapler staple "$APP"

echo "▸ re-zipping stapled app"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "✓ $ZIP ready for GitHub Releases"
