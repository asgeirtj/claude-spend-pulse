#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

ICONSET="build/AppIcon.iconset"
SOURCE="build/icon_1024.png"
OUTPUT="Resources/AppIcon.icns"

mkdir -p "$(dirname "$SOURCE")"
swift Tools/generate_icon.swift "$SOURCE"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# macOS .iconset required sizes
sips -z 16 16     "$SOURCE" --out "$ICONSET/icon_16x16.png"     >/dev/null
sips -z 32 32     "$SOURCE" --out "$ICONSET/icon_16x16@2x.png"  >/dev/null
sips -z 32 32     "$SOURCE" --out "$ICONSET/icon_32x32.png"     >/dev/null
sips -z 64 64     "$SOURCE" --out "$ICONSET/icon_32x32@2x.png"  >/dev/null
sips -z 128 128   "$SOURCE" --out "$ICONSET/icon_128x128.png"   >/dev/null
sips -z 256 256   "$SOURCE" --out "$ICONSET/icon_128x128@2x.png">/dev/null
sips -z 256 256   "$SOURCE" --out "$ICONSET/icon_256x256.png"   >/dev/null
sips -z 512 512   "$SOURCE" --out "$ICONSET/icon_256x256@2x.png">/dev/null
sips -z 512 512   "$SOURCE" --out "$ICONSET/icon_512x512.png"   >/dev/null
cp "$SOURCE"                       "$ICONSET/icon_512x512@2x.png"

mkdir -p "$(dirname "$OUTPUT")"
iconutil -c icns "$ICONSET" -o "$OUTPUT"

echo "Wrote $OUTPUT"
