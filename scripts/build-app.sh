#!/usr/bin/env bash
# Builds the Release app into build/dist/CardGate.app and a zip for distribution.
# Requires the helper (scripts/build-deps.sh && scripts/assemble-helper.sh).
source "$(dirname "$0")/common.sh"
"$ROOT/scripts/generate-project.sh"
xcodebuild -project "$ROOT/app/CardGate.xcodeproj" -scheme CardGate -configuration Release \
  -destination "platform=macOS,arch=arm64" -derivedDataPath "$BUILD/DerivedData" -quiet build
VERSION="$(tr -d '[:space:]' <"$ROOT/VERSION")"
DIST="$BUILD/dist"
rm -rf "$DIST"; mkdir -p "$DIST"
ditto "$BUILD/DerivedData/Build/Products/Release/CardGate.app" "$DIST/CardGate.app"
codesign --verify --deep --strict "$DIST/CardGate.app"
ditto -c -k --keepParent "$DIST/CardGate.app" "$DIST/CardGate-$VERSION.zip"
log "Built $DIST/CardGate.app and CardGate-$VERSION.zip ($(du -sh "$DIST/CardGate-$VERSION.zip" | cut -f1))"
