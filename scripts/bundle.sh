#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/fappswap.app"

swift build -c release --package-path "$ROOT"
BIN="$(swift build -c release --package-path "$ROOT" --show-bin-path)/FappSwapApp"

pkill -x fappswap 2>/dev/null || true

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>fappswap</string>
  <key>CFBundleIdentifier</key><string>com.firatcansucu.fappswap</string>
  <key>CFBundleExecutable</key><string>fappswap</string>
  <key>CFBundleIconFile</key><string>fappswap</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>fappswap sends an activation request so an app on another desktop can bring itself to the front.</string>
</dict>
</plist>
PLIST

cp "$BIN" "$APP/Contents/MacOS/fappswap"
cp "$ROOT/Resources/fappswap.icns" "$APP/Contents/Resources/fappswap.icns"
# Developer ID when available, ad-hoc otherwise. CI's smoke test and
# contributor machines have no certificate; release builds and the maintainer's Mac
# do. The Developer ID branch is what makes the Accessibility grant survive
# rebuilds and updates: TCC pins ad-hoc grants to the per-build cdhash, but
# pins Developer ID grants to bundle ID + Team ID, which never change.
#
# Matched on Team ID, not just the "Developer ID Application" string: Apple
# issues a renewed certificate before the old one expires, so two valid
# identities can sit in the keychain at once, and find-identity lists them in
# keychain order — not anything stable or chronological. Signing under any
# other team (a contributor's own cert, say) would silently drop every
# existing user's Accessibility grant on next launch and get every future
# release permanently rejected by the in-app updater, which also checks Team
# ID. The `|| true` keeps an empty match (no identity, or awk's own exit)
# from tripping `set -e` and aborting the build.
TEAM_ID="KRCKSFNTNV"
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' -v team="($TEAM_ID)" \
        '$2 ~ /Developer ID Application/ && index($2, team) { print $2; exit }' \
    || true)"
if [ -n "${IDENTITY:-}" ]; then
    codesign --force --sign "$IDENTITY" \
        --options runtime --timestamp \
        --entitlements "$ROOT/Resources/fappswap.entitlements" \
        "$APP"
    echo "signed with: $IDENTITY"
else
    codesign --force --sign - "$APP"
    echo "signed ad-hoc (no Developer ID Application identity in the keychain)"
    echo "Note: this build has a new ad-hoc signature — you may need to re-grant Accessibility permission in System Settings > Privacy & Security > Accessibility."
fi
codesign --verify --verbose "$APP"

echo "built $APP"
