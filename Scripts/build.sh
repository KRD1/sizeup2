#!/bin/bash
# Builds SizeUp2.app (universal: arm64 + x86_64) into ./build.
# Usage: Scripts/build.sh [--install]   (--install copies the app to /Applications)
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/SizeUp2.app
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/SizeUp2"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SizeUp2"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/SizeUp2.sdef "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

ICONSET=build/AppIcon.iconset
if [ ! -f build/AppIcon.icns ]; then
  rm -rf "$ICONSET"
  swift Scripts/make_icon.swift "$ICONSET"
  iconutil -c icns "$ICONSET" -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature. Note: macOS ties the Accessibility grant to the signature, so after
# rebuilding you may need to toggle SizeUp2 off/on in Privacy & Security › Accessibility.
xattr -cr "$APP"
codesign --force --deep --sign "${SIGN_IDENTITY:--}" \
  -r="designated => identifier \"local.sizeup2.SizeUp2\"" "$APP"

echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/SizeUp2"))"

if [ "${1:-}" = "--install" ]; then
  pkill -x SizeUp2 2>/dev/null || true
  rm -rf /Applications/SizeUp2.app
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/SizeUp2.app"
fi
