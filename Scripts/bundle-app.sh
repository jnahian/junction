#!/usr/bin/env bash
# Assembles Junction.app from the SPM release build.
#
# Usage:
#   Scripts/bundle-app.sh                 # build + bundle into dist/
#   CODESIGN_IDENTITY="Developer ID Application: …" Scripts/bundle-app.sh   # + sign
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
DIST="$ROOT/dist"
APP="$DIST/Junction.app"

echo "▸ swift build -c release"
swift build -c release

BIN="$ROOT/.build/release"

echo "▸ assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"

cp "$BIN/Junction" "$APP/Contents/MacOS/Junction"
cp "$BIN/junction-cli" "$APP/Contents/Helpers/junction"   # CLI, exposed via Homebrew `binary` stanza
cp "$ROOT/App/Info.plist" "$APP/Contents/Info.plist"

# SPM resource bundles (rewriters.json, tracking-params.json, starter-rules.json).
# Resources/ only — codesign treats anything in Helpers/ as code and rejects
# SPM's flat resource bundles. The CLI finds these via CoreResources (../Resources).
for bundle in "$BIN"/*.bundle; do
  [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

# App icon, if present (generate with Scripts/make-icon.sh or add App/AppIcon.icns)
if [ -f "$ROOT/App/AppIcon.icns" ]; then
  cp "$ROOT/App/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  echo "▸ codesigning (Hardened Runtime)"
  codesign --force --options runtime --entitlements "$ROOT/App/Junction.entitlements" \
    --sign "$CODESIGN_IDENTITY" "$APP/Contents/Helpers/junction"
  codesign --force --options runtime --entitlements "$ROOT/App/Junction.entitlements" \
    --deep --sign "$CODESIGN_IDENTITY" "$APP"
  codesign --verify --strict "$APP"
else
  echo "▸ skipping codesign (set CODESIGN_IDENTITY to sign)"
  # Ad-hoc sign so the app runs locally.
  codesign --force --deep --sign - "$APP"
fi

echo "✓ $APP"
echo
echo "Run it:            open '$APP'"
echo "Install CLI:       ln -sf '$APP/Contents/Helpers/junction' /usr/local/bin/junction"
echo "Notarize + DMG:    see Scripts/notarize.sh"
