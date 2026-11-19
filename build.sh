#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/مصحصح.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
MODULE_CACHE_DIR="$BUILD_DIR/ModuleCache-v2"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET_DIR" "$MODULE_CACHE_DIR"

swiftc \
  -sdk "$SDK_PATH" \
  -target x86_64-apple-macosx13.0 \
  -module-cache-path "$MODULE_CACHE_DIR" \
  -O \
  -framework AppKit \
  -framework ServiceManagement \
  -framework IOKit \
  "$ROOT_DIR/Musahseh.swift" \
  -o "$BUILD_DIR/Musahseh-x86_64"

swiftc \
  -sdk "$SDK_PATH" \
  -target arm64-apple-macosx13.0 \
  -module-cache-path "$MODULE_CACHE_DIR" \
  -O \
  -framework AppKit \
  -framework ServiceManagement \
  -framework IOKit \
  "$ROOT_DIR/Musahseh.swift" \
  -o "$BUILD_DIR/Musahseh-arm64"

lipo -create "$BUILD_DIR/Musahseh-x86_64" "$BUILD_DIR/Musahseh-arm64" -output "$MACOS_DIR/Musahseh"
cp "$ROOT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"

swiftc \
  -sdk "$SDK_PATH" \
  -module-cache-path "$MODULE_CACHE_DIR" \
  -framework AppKit \
  "$ROOT_DIR/IconGenerator.swift" \
  -o "$BUILD_DIR/IconGenerator"

make_icon() {
  local size="$1"
  local output="$2"
  "$BUILD_DIR/IconGenerator" "$size" "$output"
}

make_icon 16 "$ICONSET_DIR/icon_16x16.png"
make_icon 32 "$ICONSET_DIR/icon_16x16@2x.png"
cp "$ICONSET_DIR/icon_16x16@2x.png" "$ICONSET_DIR/icon_32x32.png"
make_icon 64 "$ICONSET_DIR/icon_32x32@2x.png"
make_icon 128 "$ICONSET_DIR/icon_128x128.png"
make_icon 256 "$ICONSET_DIR/icon_128x128@2x.png"
cp "$ICONSET_DIR/icon_128x128@2x.png" "$ICONSET_DIR/icon_256x256.png"
make_icon 512 "$ICONSET_DIR/icon_256x256@2x.png"
cp "$ICONSET_DIR/icon_256x256@2x.png" "$ICONSET_DIR/icon_512x512.png"
make_icon 1024 "$ICONSET_DIR/icon_512x512@2x.png"

swiftc \
  -sdk "$SDK_PATH" \
  -module-cache-path "$MODULE_CACHE_DIR" \
  "$ROOT_DIR/IconPacker.swift" \
  -o "$BUILD_DIR/IconPacker"

"$BUILD_DIR/IconPacker" \
  "$RESOURCES_DIR/AppIcon.icns" \
  "$ICONSET_DIR/icon_16x16.png" \
  "$ICONSET_DIR/icon_32x32.png" \
  "$ICONSET_DIR/icon_32x32@2x.png" \
  "$ICONSET_DIR/icon_128x128.png" \
  "$ICONSET_DIR/icon_256x256.png" \
  "$ICONSET_DIR/icon_512x512.png" \
  "$ICONSET_DIR/icon_512x512@2x.png"

codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
