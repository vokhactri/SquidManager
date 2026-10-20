#!/bin/bash
# Builds build/SquidManager.app. Pass --install to copy it into /Applications.
# The version comes from the latest v* tag, or from $VERSION when set.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh

# SwiftPM links with the deployment target as the SDK version, so AppKit would treat the app
# as built against macOS 15 and skip newer UI behavior. Record the real SDK instead.
# 15.0 must match platforms in Package.swift.
SDK_VERSION=$(xcrun --show-sdk-version)
swift build -c release --product SquidManager \
  -Xlinker -platform_version -Xlinker macos -Xlinker 15.0 -Xlinker "$SDK_VERSION"
BIN_DIR="$(swift build -c release --show-bin-path)"
BIN="$BIN_DIR/SquidManager"
APP=build/SquidManager.app
# A build past the tag gets a suffix (0.2.0-3-gabc123). The updater compares only 0.2.0.
VERSION=${VERSION:-$(git describe --tags --match 'v[0-9]*' 2>/dev/null || echo 0.0.0-dev)}
VERSION=${VERSION#v}
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 0)

mkdir -p build
ICON=build/AppIcon.icns
if [ ! -f "$ICON" ] || [ scripts/make-icon.swift -nt "$ICON" ] \
  || [ Sources/SquidManager/Resources/squid.svg -nt "$ICON" ]; then
  swift scripts/make-icon.swift "$ICON"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SquidManager"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
cp -R "$BIN_DIR/SquidManager_SquidManager.bundle" "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>SquidManager</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>com.squidmanager.app</string>
  <key>CFBundleName</key><string>SquidManager</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Tri Vo Khac. MIT License.</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP $VERSION"

if [ "${1:-}" = "--install" ]; then
  rm -rf /Applications/SquidManager.app
  cp -R "$APP" /Applications/
  echo "Installed /Applications/SquidManager.app"
fi
