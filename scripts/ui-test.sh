#!/usr/bin/env bash
# UI tests: drive the app like a user (no smart card or PIN needed). Each test uses an empty data
# directory, so saved connections are never touched. Needs a logged-in desktop session; macOS may
# ask once to allow the test runner to control the computer (Accessibility).
# Usage: scripts/ui-test.sh [xcodebuild -only-testing filter, e.g. CardGateUITests/CardGateUITests/testSpeaksCzech]
source "$(dirname "$0")/common.sh"
cd "$ROOT"
"$ROOT/scripts/generate-project.sh" >/dev/null
filter=()
[[ $# -gt 0 ]] && filter=(-only-testing:"$1")
log "UI tests"
rm -rf "$BUILD/ui-tests.xcresult"
xcodebuild -project app/CardGate.xcodeproj -scheme CardGate -configuration Debug \
  -destination "platform=macOS,arch=arm64" -derivedDataPath "$BUILD/DerivedData" \
  -resultBundlePath "$BUILD/ui-tests.xcresult" ${filter[@]+"${filter[@]}"} -quiet test
log "UI tests passed"
