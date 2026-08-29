#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/fappswap.app"
STAGING="$ROOT/.dmg-staging"

# See scripts/bundle.sh for why the DMG's signature must be pinned to this
# specific team rather than the first "Developer ID Application" identity
# find-identity happens to list: certificate renewal can leave two valid
# identities in the keychain at once, and a DMG signed under the wrong team
# breaks the same things a wrongly-signed app bundle would.
TEAM_ID="KRCKSFNTNV"

"$ROOT/scripts/bundle.sh"

if [ ! -d "$APP" ]; then
    echo "error: $APP was not produced by bundle.sh" >&2
    exit 1
fi

# Notarize when credentials are present (CI sets these; local runs skip).
# Two passes — app first, then DMG — so the app itself carries a stapled
# ticket and passes Gatekeeper even when dragged out of the DMG offline.
NOTARIZE=false
if [ -n "${NOTARY_KEY_PATH:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_ISSUER_ID:-}" ]; then
    NOTARIZE=true
    if ! codesign -dvv "$APP" 2>&1 | grep -q "Authority=Developer ID Application"; then
        echo "error: notarization requested but the app is not Developer ID signed" >&2
        exit 1
    fi
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
if [ -z "$VERSION" ]; then
    echo "error: could not read CFBundleShortVersionString from $APP/Contents/Info.plist" >&2
    exit 1
fi

if [ "$NOTARIZE" = true ]; then
    NOTARIZE_ZIP="$ROOT/.notarize-upload.zip"
    ditto -c -k --keepParent "$APP" "$NOTARIZE_ZIP"
    xcrun notarytool submit "$NOTARIZE_ZIP" \
        --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" \
        --wait
    rm -f "$NOTARIZE_ZIP"
    xcrun stapler staple "$APP"
fi

# The zip the in-app updater downloads. Built from the (stapled, when
# notarizing) app so what the updater installs is exactly what the DMG carries.
UPDATE_ZIP="$ROOT/fappswap-${VERSION}.zip"
rm -f "$UPDATE_ZIP"
ditto -c -k --keepParent "$APP" "$UPDATE_ZIP"

DMG_NAME="fappswap-${VERSION}.dmg"
DMG_PATH="$ROOT/$DMG_NAME"

rm -rf "$STAGING"
rm -f "$DMG_PATH"

mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/fappswap.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "fappswap" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DMG_PATH"

rm -rf "$STAGING"

hdiutil verify "$DMG_PATH"

if [ "$NOTARIZE" = true ]; then
    DMG_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | awk -F'"' -v team="($TEAM_ID)" \
            '$2 ~ /Developer ID Application/ && index($2, team) { print $2; exit }' \
        || true)"
    if [ -z "$DMG_IDENTITY" ]; then
        echo "error: no Developer ID Application identity for team $TEAM_ID to sign the DMG" >&2
        exit 1
    fi
    codesign --force --sign "$DMG_IDENTITY" "$DMG_PATH"
    xcrun notarytool submit "$DMG_PATH" \
        --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" \
        --wait
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$APP"
    xcrun stapler validate "$DMG_PATH"
    spctl -a -t open --context context:primary-signature -v "$DMG_PATH"
fi

echo "built $DMG_PATH and $UPDATE_ZIP"
