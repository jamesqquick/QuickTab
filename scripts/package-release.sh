#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/.build/QuickTab.app"
DMG="$ROOT/.build/QuickTab.dmg"
STAGING="$ROOT/.build/QuickTab-dmg"
SIGN_IDENTITY="${QUICKTAB_SIGN_IDENTITY:-}"
SPARKLE_BIN="$ROOT/.build/release-arm64/artifacts/sparkle/Sparkle/bin"
SPARKLE_ACCOUNT="com.jamesqquick.quicktab"

if [[ -z "$SIGN_IDENTITY" ]]; then
  print -u2 "QUICKTAB_SIGN_IDENTITY is required for a release build"
  exit 1
fi

QUICKTAB_UNIVERSAL=1 "$ROOT/scripts/build-app.sh" release

if [[ ! -x "$SPARKLE_BIN/sign_update" || ! -x "$SPARKLE_BIN/generate_keys" ]]; then
  print -u2 "Sparkle release tools were not found after building"
  exit 1
fi
if ! PUBLIC_KEY="$("$SPARKLE_BIN/generate_keys" --account "$SPARKLE_ACCOUNT" -p)"; then
  print -u2 "Sparkle signing key '$SPARKLE_ACCOUNT' was not found in the login Keychain"
  exit 1
fi
EMBEDDED_PUBLIC_KEY="$(plutil -extract SUPublicEDKey raw -o - "$APP/Contents/Info.plist")"
if [[ "$PUBLIC_KEY" != "$EMBEDDED_PUBLIC_KEY" ]]; then
  print -u2 "Sparkle signing key '$SPARKLE_ACCOUNT' does not match SUPublicEDKey"
  exit 1
fi

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

VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")"
BUILD="$(plutil -extract CFBundleVersion raw -o - "$APP/Contents/Info.plist")"
SIGNATURE="$("$SPARKLE_BIN/sign_update" --account "$SPARKLE_ACCOUNT" -p "$DMG")"
LENGTH="$(stat -f%z "$DMG")"
swift "$ROOT/scripts/update-appcast.swift" "$ROOT/appcast.xml" "$VERSION" "$BUILD" "$SIGNATURE" "$LENGTH"
xmllint --noout "$ROOT/appcast.xml"

print "$DMG"
print "$ROOT/appcast.xml"
