#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/RLaunchPad.xcodeproj"
SCHEME="RLaunchPad"
CONFIGURATION="${CONFIGURATION:-Release}"
APP_NAME="RLaunchPad"
VOLUME_NAME="RLaunchPad"
BUILD_ROOT="$ROOT_DIR/build"
DERIVED_DATA_PATH="$BUILD_ROOT/DerivedData-dmg"
OUTPUT_DIR="$ROOT_DIR/dist"
STAGING_DIR="$BUILD_ROOT/dmg-staging"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
AUTO_BUMP_BUILD="${AUTO_BUMP_BUILD:-1}"

if [[ "$AUTO_BUMP_BUILD" == "1" ]]; then
  CURRENT_BUILD="$(xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME" -showBuildSettings 2>/dev/null | awk -F'= ' '/CURRENT_PROJECT_VERSION =/ {print $2; exit}')"
  if [[ "$CURRENT_BUILD" =~ ^[0-9]+$ ]]; then
    NEXT_BUILD="$((CURRENT_BUILD + 1))"
    echo "==> Bumping build number: $CURRENT_BUILD -> $NEXT_BUILD"
    (
      cd "$ROOT_DIR"
      xcrun agvtool new-version -all "$NEXT_BUILD" >/dev/null
    )
  else
    echo "WARNING: Unable to detect numeric CURRENT_PROJECT_VERSION, skip auto bump."
  fi
fi

echo "==> Building $APP_NAME ($CONFIGURATION)"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -destination "platform=macOS" \
  clean build

if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: App not found at $APP_PATH"
  exit 1
fi

INFO_PLIST_PATH="$APP_PATH/Contents/Info.plist"
APP_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST_PATH" 2>/dev/null || true)"
APP_BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST_PATH" 2>/dev/null || true)"

if [[ -n "$APP_VERSION" && -n "$APP_BUILD" ]]; then
  VERSION_TAG="${APP_VERSION}.${APP_BUILD}"
elif [[ -n "$APP_VERSION" ]]; then
  VERSION_TAG="$APP_VERSION"
elif [[ -n "$APP_BUILD" ]]; then
  VERSION_TAG="$APP_BUILD"
else
  VERSION_TAG="$(date +%Y%m%d-%H%M)"
fi

DMG_PATH="$OUTPUT_DIR/${APP_NAME}-${VERSION_TAG}.dmg"

echo "==> Preparing DMG staging folder"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

mkdir -p "$OUTPUT_DIR"
rm -f "$DMG_PATH"

echo "==> Creating DMG"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "==> DMG generated: $DMG_PATH"
