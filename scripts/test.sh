#!/usr/bin/env bash
# All checks that must pass before a commit and in CI: lint, unit tests, app build, localization.
source "$(dirname "$0")/common.sh"
cd "$ROOT"

log "SwiftLint"
swiftlint lint --strict --quiet

log "swift-format"
swift format lint --strict -r app/CardGateKit/Sources app/CardGateKit/Tests app/CardGate

log "Unit tests (CardGateKit)"
# With the assembled helper the tests also check it accepts CardGate's arguments and still logs
# the texts the status display depends on.
if [[ -x "$HELPER/$CLIENT" ]]; then export CARDGATE_HELPER="$HELPER"; fi
swift test --package-path app/CardGateKit --quiet

log "App build"
"$ROOT/scripts/generate-project.sh"
xcodebuild -project app/CardGate.xcodeproj -scheme CardGate -configuration Debug \
  -destination "platform=macOS,arch=arm64" -derivedDataPath "$BUILD/DerivedData" -quiet build

"$ROOT/scripts/check-localization.sh"
log "All checks passed"
