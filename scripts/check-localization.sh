#!/usr/bin/env bash
# Fails when the app has UI strings that are missing from the string catalog, not translated
# to every language, translated with other placeholders (%@, %lld…) than the original, or no
# longer used, and when the user guides of the languages differ in their sections.
# Needs a finished Debug build (scripts/test.sh does one).
source "$(dirname "$0")/common.sh"
CATALOG="$ROOT/app/CardGate/Resources/Localizable.xcstrings"
DERIVED="${DERIVED_DATA:-$BUILD/DerivedData}"
LANGS=(cs sk)

data=()
while IFS= read -r -d '' f; do data+=("$f"); done \
  < <(find "$DERIVED/Build/Intermediates.noindex/CardGate.build/Debug" -name '*.stringsdata' -print0)
[[ ${#data[@]} -gt 0 ]] || die "no .stringsdata found – build the app first"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cp "$CATALOG" "$tmp/Localizable.xcstrings"  # same name = same string table
xcrun xcstringstool sync "$tmp/Localizable.xcstrings" --stringsdata "${data[@]}" >/dev/null

python3 -I - "$tmp/Localizable.xcstrings" "${LANGS[@]}" <<'PY'
import collections, json, re, sys
catalog = json.load(open(sys.argv[1])); langs = sys.argv[2:]; problems = []
# Placeholders by position: "%@ – %2$@" and "%2$@ – %1$@" use the same arguments.
FORMAT = re.compile(r"%(?:(\d+)\$)?(?:ll|l|h)?([@dDuUxXoOfeEgGcCsSaAp])")
def placeholders(text):
    found = collections.Counter(); position = 0
    for index, kind in FORMAT.findall(text.replace("%%", "")):
        position += 1
        found[(int(index) if index else position, kind.lower())] += 1
    return found
for key, entry in catalog["strings"].items():
    if entry.get("extractionState") == "stale":
        problems.append(f"unused string: {key!r}"); continue
    if entry.get("shouldTranslate") is False:
        continue
    for lang in langs:
        loc = entry.get("localizations", {}).get(lang, {})
        units = [loc["stringUnit"]] if "stringUnit" in loc else [
            v["stringUnit"] for v in loc.get("variations", {}).get("plural", {}).values() if "stringUnit" in v]
        if not units or any(u.get("state") != "translated" or not u.get("value") for u in units):
            problems.append(f"missing {lang} translation: {key!r}")
        elif "stringUnit" in loc and placeholders(loc["stringUnit"]["value"]) != placeholders(key):
            problems.append(f"{lang} translation has other placeholders: {key!r}")
for p in problems: print("FAIL:", p)
sys.exit(1 if problems else 0)
PY

# The guides are translations of each other: the same sections in the same order.
python3 -I - "$ROOT/docs/user-guide.en.md" "$ROOT/docs/navod.cs.md" "$ROOT/docs/navod.sk.md" <<'PY'
import re, sys
def outline(path):
    lines = open(path, encoding="utf-8").read().splitlines()
    return [len(m.group(1)) for line in lines if (m := re.match(r"(#{1,6}) ", line))]
reference = outline(sys.argv[1]); failed = False
for path in sys.argv[2:]:
    if outline(path) != reference:
        print(f"FAIL: {path.rsplit('/', 1)[-1]} has other sections ({len(outline(path))}) than "
              f"user-guide.en.md ({len(reference)})"); failed = True
sys.exit(1 if failed else 0)
PY
log "Localization complete (${LANGS[*]})"
