#!/usr/bin/env bash
# Takes the screenshots of the user guides (docs/images/<language>/) in light mode, with a demo
# card and example addresses, so no real name or address appears. Drives the debug build with
# the ScreenshotTests UI test and scripts/screenshot-server.swift; needs an unlocked desktop session and Screen Recording permission
# for the terminal. Usage: scripts/screenshots.sh [language…]   (default: cs sk en)
source "$(dirname "$0")/common.sh"
cd "$ROOT"
"$ROOT/scripts/generate-project.sh" >/dev/null
DEBUG_APP="$BUILD/DerivedData/Build/Products/Debug/CardGate.app"
LANGUAGES=("$@"); [[ ${#LANGUAGES[@]} -gt 0 ]] || LANGUAGES=(cs sk en)

# capture NAME PID DIR: the frontmost window of process PID, without its shadow
capture() {
  local id
  id="$(swift -e "import CoreGraphics
let w = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
if let n = w.first(where: { (\$0[kCGWindowOwnerPID as String] as? Int) == $2 && (\$0[kCGWindowLayer as String] as? Int ?? 0) < 25 })?[kCGWindowNumber as String] { print(n) }")"
  [[ -n "$id" ]] || die "no window of process $2"
  screencapture -x -o -l "$id" "$3/$1.png"
}

for lang in "${LANGUAGES[@]}"; do
  case "$lang" in
    cs) holder="Jan Novák"; connection="Kancelář" ;;
    sk) holder="Ján Novák"; connection="Kancelária" ;;
    en) holder="Jane Doe"; connection="Office" ;;
    *) die "unknown language $lang" ;;
  esac
  out="$ROOT/docs/images/$lang"; work="$BUILD/screenshots/$lang"
  rm -rf "$work"; mkdir -p "$work" "$out"
  log "Screenshots ($lang)"

  swift "$ROOT/scripts/screenshot-server.swift" "$work" "$DEBUG_APP" >"$work/server.log" 2>&1 &
  server_pid=$!
  until grep -q ready "$work/server.log" 2>/dev/null; do sleep 0.5; done
  TEST_RUNNER_CARDGATE_SCREENSHOTS_LANGUAGE="$lang" \
  TEST_RUNNER_CARDGATE_DEMO_CARD="$holder" TEST_RUNNER_CARDGATE_SCREENSHOTS_CONNECTION="$connection" \
    xcodebuild -project app/CardGate.xcodeproj -scheme CardGate -configuration Debug \
      -destination "platform=macOS,arch=arm64" -derivedDataPath "$BUILD/DerivedData" \
      -resultBundlePath "$work/result.xcresult" -only-testing:CardGateUITests/ScreenshotTests -quiet test \
      >"$work/xcodebuild.log" 2>&1 || { kill "$server_pid"; tail -20 "$work/xcodebuild.log"; die "screenshot test failed ($lang)"; }
  kill "$server_pid" 2>/dev/null || true

  # The PIN dialog: started the way the RDP client starts it, without a module (no card access).
  CARDGATE_APPEARANCE=light "$DEBUG_APP/Contents/MacOS/CardGate" --askpass \
    "Credentials required for rdg.example.com" -AppleLanguages "($lang)" >/dev/null 2>&1 &
  pin_pid=$!
  sleep 3
  capture pin "$pin_pid" "$work"
  kill "$pin_pid" 2>/dev/null || true

  cp "$work"/*.png "$out/"
done
log "Screenshots in docs/images"
