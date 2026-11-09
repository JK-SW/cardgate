#!/usr/bin/env bash
# Fails when the app has UI strings that are missing from the string catalog, not translated
# to every language, or no longer used. Needs a finished Debug build (scripts/test.sh does one).
source "$(dirname "$0")/common.sh"
CATALOG="$ROOT/app/CardGate/Resources/Localizable.xcstrings"
DERIVED="${DERIVED_DATA:-$BUILD/DerivedData}"
LANGS=(cs sk)

data=()
while IFS= read -r -d '' f; do data+=("$f"); done \
  < <(find "$DERIVED/Build/Intermediates.noindex/CardGate.build" -name '*.stringsdata' -print0)
[[ ${#data[@]} -gt 0 ]] || die "no .stringsdata found – build the app first"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cp "$CATALOG" "$tmp/Localizable.xcstrings"  # same name = same string table
xcrun xcstringstool sync "$tmp/Localizable.xcstrings" --stringsdata "${data[@]}" >/dev/null

python3 -I - "$tmp/Localizable.xcstrings" "${LANGS[@]}" <<'PY'
import json, sys
catalog = json.load(open(sys.argv[1])); langs = sys.argv[2:]; problems = []
for key, entry in catalog["strings"].items():
    if entry.get("extractionState") == "stale":
        problems.append(f"unused string: {key!r}"); continue
    if entry.get("shouldTranslate") is False:
        continue
    for lang in langs:
        unit = entry.get("localizations", {}).get(lang, {}).get("stringUnit", {})
        if unit.get("state") != "translated" or not unit.get("value"):
            problems.append(f"missing {lang} translation: {key!r}")
for p in problems: print("FAIL:", p)
sys.exit(1 if problems else 0)
PY
log "Localization complete (${LANGS[*]})"
