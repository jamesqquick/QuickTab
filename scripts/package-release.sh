#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/.build/QuickTab.app"
DMG="$ROOT/.build/QuickTab.dmg"
STAGING="$ROOT/.build/QuickTab-dmg"
SIGN_IDENTITY="${QUICKTAB_SIGN_IDENTITY:-}"

if [[ -z "$SIGN_IDENTITY" ]]; then
  print -u2 "QUICKTAB_SIGN_IDENTITY is required for a release build"
  exit 1
fi

QUICKTAB_UNIVERSAL=1 "$ROOT/scripts/build-app.sh" release

rm -rf "$STAGING"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/QuickTab.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
  -volname "QuickTab" \
  -srcfolder "$STAGING" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "$DMG"

rm -rf "$STAGING"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"

if [[ -n "${QUICKTAB_NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$QUICKTAB_NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
fi

codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=2 "$APP"
codesign --verify --verbose=2 "$DMG"
hdiutil verify "$DMG"

print "$DMG"
