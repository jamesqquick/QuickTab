#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
CONFIGURATION="${1:-release}"
APP="$ROOT/.build/QuickTab.app"

if [[ "${QUICKTAB_UNIVERSAL:-0}" == "1" ]]; then
  SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
  ARM_SCRATCH="$ROOT/.build/release-arm64"
  INTEL_SCRATCH="$ROOT/.build/release-x86_64"

  swift build --package-path "$ROOT" -c "$CONFIGURATION" --triple arm64-apple-macosx14.0 --sdk "$SDK_PATH" --scratch-path "$ARM_SCRATCH"
  swift build --package-path "$ROOT" -c "$CONFIGURATION" --triple x86_64-apple-macosx14.0 --sdk "$SDK_PATH" --scratch-path "$INTEL_SCRATCH"

  ARM_BIN_PATH="$(swift build --package-path "$ROOT" -c "$CONFIGURATION" --triple arm64-apple-macosx14.0 --sdk "$SDK_PATH" --scratch-path "$ARM_SCRATCH" --show-bin-path)"
  INTEL_BIN_PATH="$(swift build --package-path "$ROOT" -c "$CONFIGURATION" --triple x86_64-apple-macosx14.0 --sdk "$SDK_PATH" --scratch-path "$INTEL_SCRATCH" --show-bin-path)"
else
  swift build --package-path "$ROOT" -c "$CONFIGURATION"
  BIN_PATH="$(swift build --package-path "$ROOT" -c "$CONFIGURATION" --show-bin-path)"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
if [[ "${QUICKTAB_UNIVERSAL:-0}" == "1" ]]; then
  lipo -create "$ARM_BIN_PATH/QuickTab" "$INTEL_BIN_PATH/QuickTab" -output "$APP/Contents/MacOS/QuickTab"
  SPARKLE_FRAMEWORK="$ARM_BIN_PATH/Sparkle.framework"
else
  cp "$BIN_PATH/QuickTab" "$APP/Contents/MacOS/QuickTab"
  SPARKLE_FRAMEWORK="$BIN_PATH/Sparkle.framework"
fi
ditto "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@loader_path/../Frameworks" "$APP/Contents/MacOS/QuickTab"

ICONSET="$ROOT/.build/QuickTab.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
swift "$ROOT/scripts/generate-icon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/QuickTabIcon.icns"
rm -rf "$ICONSET"

SIGN_IDENTITY="${QUICKTAB_SIGN_IDENTITY:--}"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  SIGN_ARGS=(--force --sign -)
else
  SIGN_ARGS=(--force --options runtime --timestamp --sign "$SIGN_IDENTITY")
fi
codesign "${SIGN_ARGS[@]}" "$SPARKLE/XPCServices/Installer.xpc"
codesign "${SIGN_ARGS[@]}" --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
codesign "${SIGN_ARGS[@]}" "$SPARKLE/Autoupdate"
codesign "${SIGN_ARGS[@]}" "$SPARKLE/Updater.app"
codesign "${SIGN_ARGS[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
codesign "${SIGN_ARGS[@]}" "$APP"

if [[ -n "${QUICKTAB_NOTARY_PROFILE:-}" ]]; then
  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    print -u2 "QUICKTAB_SIGN_IDENTITY is required for notarization"
    exit 1
  fi
  NOTARY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/QuickTab-notary.XXXXXX")"
  NOTARY_ARCHIVE="$NOTARY_DIR/QuickTab.app.zip"
  trap 'rm -rf "$NOTARY_DIR"' EXIT
  ditto -c -k --keepParent "$APP" "$NOTARY_ARCHIVE"
  xcrun notarytool submit "$NOTARY_ARCHIVE" --keychain-profile "$QUICKTAB_NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
fi

print "$APP"
