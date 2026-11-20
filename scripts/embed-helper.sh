#!/usr/bin/env bash
# Xcode build phase: copies the self-contained FreeRDP helper (scripts/assemble-helper.sh)
# into the app bundle and signs it, before Xcode signs the app itself.
source "$(dirname "$0")/common.sh"   # HELPER, SESSION_APP, CLIENT
# The helper the build phase declares as input (project.yml), so Xcode tracks the one embedded.
HELPER="${CARDGATE_HELPER_DIR:-$HELPER}"
CONTENTS="${TARGET_BUILD_DIR:?}/${CONTENTS_FOLDER_PATH:?}"
# What the last run put into Contents/Frameworks, one name per line: only that is removed again
# (Xcode embeds Sparkle.framework there, a sanitizer its runtime).
EMBEDDED="${TARGET_TEMP_DIR:?}/embedded-helper-frameworks.txt"

if [[ ! -x "$HELPER/$CLIENT" ]]; then
  echo "error: FreeRDP helper not found in $HELPER – run scripts/build-deps.sh and scripts/assemble-helper.sh" >&2
  exit 1
fi

mkdir -p "$CONTENTS/Helpers" "$CONTENTS/Frameworks" "$(dirname "$EMBEDDED")"
rsync -a --delete "$HELPER/Helpers/" "$CONTENTS/Helpers/"

if [[ -f "$EMBEDDED" ]]; then
  while IFS= read -r name; do
    if [[ -n "$name" && ! -e "$HELPER/Frameworks/$name" ]]; then rm -rf "${CONTENTS:?}/Frameworks/$name"; fi
  done <"$EMBEDDED"
fi
rsync -a "$HELPER/Frameworks/" "$CONTENTS/Frameworks/"
(cd "$HELPER/Frameworks" && ls -A) >"$EMBEDDED"

# Plugins loaded at runtime: FreeRDP's channels and codecs (if it was built with any) and Kerberos
# PKINIT (krb5).
for plugins in freerdp3 krb5; do
  if [[ -d "$HELPER/PlugIns/$plugins" ]]; then
    mkdir -p "$CONTENTS/PlugIns"
    rsync -a --delete "$HELPER/PlugIns/$plugins/" "$CONTENTS/PlugIns/$plugins/"
  else
    rm -rf "${CONTENTS:?}/PlugIns/$plugins"
  fi
done
rmdir "$CONTENTS/PlugIns" 2>/dev/null || true

mkdir -p "$CONTENTS/Resources"
cp "$HELPER/ThirdPartyNotices.txt" "$CONTENTS/Resources/ThirdPartyNotices.txt"

IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
[[ -n "$IDENTITY" ]] || IDENTITY="-"
signed=("$CONTENTS/Frameworks")
[[ -d "$CONTENTS/PlugIns" ]] && signed+=("$CONTENTS/PlugIns")
find "${signed[@]}" \( -name '*.dylib' -o -name '*.so' \) -exec codesign --force --timestamp=none -s "$IDENTITY" {} \;
codesign --force --timestamp=none -s "$IDENTITY" "$CONTENTS/$SESSION_APP"
