#!/bin/bash

set -e

APP_NAME="Cogi"
PROJECT="${APP_NAME}.xcodeproj"
SCHEME="${APP_NAME}"
CONFIGURATION="Release"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
OUTPUT_DIR="$ROOT_DIR/release"
APP_PATH="$BUILD_DIR/Build/Products/$CONFIGURATION/$APP_NAME.app"
DMG_PATH="$OUTPUT_DIR/$APP_NAME.dmg"

echo "==> Cleaning previous build"
rm -rf "$BUILD_DIR" "$OUTPUT_DIR"

mkdir -p "$OUTPUT_DIR"

echo "==> Building $APP_NAME.app"

xcodebuild \
  -project "$ROOT_DIR/$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  ONLY_ACTIVE_ARCH=NO \
  build

if [ ! -d "$APP_PATH" ]; then
  echo "ERROR: $APP_NAME.app was not created."
  exit 1
fi

echo "==> Creating DMG"

STAGING_DIR="$BUILD_DIR/dmg"

mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"

create-dmg \
  --volname "$APP_NAME" \
  --window-size 800 450 \
  --icon-size 120 \
  --icon "$APP_NAME.app" 220 220 \
  --app-drop-link 580 220 \
  "$DMG_PATH" \
  "$STAGING_DIR"

echo ""
echo "======================================"
echo "Release created:"
echo "$DMG_PATH"
echo "======================================"