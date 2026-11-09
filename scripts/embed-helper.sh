#!/usr/bin/env bash
# Xcode build phase: copies the self-contained FreeRDP helper (scripts/assemble-helper.sh)
# into the app bundle and signs it, before Xcode signs the app itself.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="${CARDGATE_BUILD_DIR:-$ROOT/build}/helper"
CONTENTS="${TARGET_BUILD_DIR:?}/${CONTENTS_FOLDER_PATH:?}"

if [[ ! -x "$HELPER/Helpers/sdl-freerdp" ]]; then
  echo "error: FreeRDP helper not found in $HELPER – run scripts/build-deps.sh and scripts/assemble-helper.sh" >&2
  exit 1
fi

mkdir -p "$CONTENTS/Helpers" "$CONTENTS/Frameworks"
rsync -a --delete "$HELPER/Helpers/" "$CONTENTS/Helpers/"
rsync -a "$HELPER/Frameworks/" "$CONTENTS/Frameworks/"
mkdir -p "$CONTENTS/Resources"
cp "$HELPER/ThirdPartyNotices.txt" "$CONTENTS/Resources/ThirdPartyNotices.txt"

IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
[[ -n "$IDENTITY" ]] || IDENTITY="-"
find "$CONTENTS/Frameworks" -name '*.dylib' -exec codesign --force --timestamp=none -s "$IDENTITY" {} \;
codesign --force --timestamp=none -s "$IDENTITY" "$CONTENTS/Helpers/sdl-freerdp"
