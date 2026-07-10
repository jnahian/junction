#!/usr/bin/env bash
# Builds a styled drag-to-Applications installer: dist/Junction.dmg
#
# Run after Scripts/bundle-app.sh. Kept out of bundle-app.sh because the Finder
# layout below needs osascript automation, which is unreliable on headless CI —
# and CI only needs the .app, not the installer.
#
# Native only (hdiutil + Finder via osascript, no create-dmg dependency): build a
# read-write image, lay the icons out over a background picture, then convert to a
# compressed read-only .dmg.
set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME="Junction"
DIST="$PWD/dist"
APP="$DIST/${APP_NAME}.app"
DMG="$DIST/${APP_NAME}.dmg"
RW="$DIST/rw.dmg"
VOL="/Volumes/${APP_NAME}"

[ -d "$APP" ] || { echo "No $APP — run Scripts/bundle-app.sh first."; exit 1; }

echo "▸ drawing background"
swift Scripts/dmg-background.swift "$DIST/dmg-bg.png"

echo "▸ building $DMG"
rm -f "$DMG" "$RW"
hdiutil detach "$VOL" >/dev/null 2>&1 || true
hdiutil create -size 200m -fs HFS+ -volname "$APP_NAME" -ov "$RW" >/dev/null
hdiutil attach "$RW" -readwrite -noverify -noautoopen -mountpoint "$VOL" >/dev/null

cp -R "$APP" "$VOL/"
ln -s /Applications "$VOL/Applications"
mkdir "$VOL/.background"
cp "$DIST/dmg-bg.png" "$VOL/.background/bg.png"

osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "${APP_NAME}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {400, 100, 1040, 500}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set background picture of opts to file ".background:bg.png"
    set position of item "${APP_NAME}.app" of container window to {160, 205}
    set position of item "Applications" of container window to {480, 205}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$VOL" >/dev/null
hdiutil convert "$RW" -format UDZO -ov -o "$DMG" >/dev/null
rm -f "$RW"

echo "✓ $DMG"
