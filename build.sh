#!/usr/bin/env bash
set -euo pipefail

NAME="ClaudeCreditWidget"
BUILD_DIR="build"
APP_DIR="${BUILD_DIR}/${NAME}.app"

if [ ! -f "Resources/AppIcon.icns" ]; then
    echo "AppIcon.icns missing — generating..."
    bash Tools/build_icns.sh
fi

echo "Building ${NAME} (release)..."
swift build -c release

echo "Assembling app bundle at ${APP_DIR}..."
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"
cp ".build/release/${NAME}" "${APP_DIR}/Contents/MacOS/"
cp "Resources/Info.plist" "${APP_DIR}/Contents/"
cp "Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/"

echo ""
echo "Built: ${APP_DIR}"
echo ""
echo "Run:     open ${APP_DIR}"
echo "Install: cp -R ${APP_DIR} /Applications/"
