#!/usr/bin/env bash
# Notarizes and staples dist/Junction.app.
# Requires: CODESIGN_IDENTITY used in bundle-app.sh, plus an App Store Connect
# API key configured as a notarytool keychain profile named "junction".
#
#   xcrun notarytool store-credentials junction \
#     --apple-id you@example.com --team-id TEAMID --password app-specific-pw
#
# Order matters: staple the .app here, then build the installer around it
# (Scripts/release.sh runs make-dmg.sh). Building the DMG first would ship an
# unstapled app, which needs an online Gatekeeper check on every first launch.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="dist/Junction.app"

[ -d "$APP" ] || { echo "run Scripts/bundle-app.sh first"; exit 1; }

# notarytool needs an archive to upload; this zip is a submission vehicle only,
# never a release artifact — the stapled .app is what ends up in the DMG.
ZIP="$(mktemp -d)/Junction.zip"

echo "▸ zipping for notarization"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "▸ submitting to notarytool"
xcrun notarytool submit "$ZIP" --keychain-profile junction --wait

echo "▸ stapling"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "✓ $APP notarized and stapled — now run Scripts/release.sh"
