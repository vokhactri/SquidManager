#!/bin/bash
# Packs build/SquidManager.app into build/SquidManager.dmg next to a link to /Applications,
# so installing is a drag in Finder. Run scripts/build-app.sh first.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/SquidManager.app
DMG=build/SquidManager.dmg
STAGING=build/dmg

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/SquidManager.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname SquidManager -srcfolder "$STAGING" -fs HFS+ -format UDZO "$DMG"
rm -rf "$STAGING"
echo "Built $DMG"
