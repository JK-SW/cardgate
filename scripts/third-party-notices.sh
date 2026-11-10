#!/usr/bin/env bash
# Prints the third-party notices shipped with the app (versions from deps.lock, license texts
# collected by build-deps.sh into $PREFIX/share/licenses).
source "$(dirname "$0")/common.sh"
LIC="$PREFIX/share/licenses"
[[ -d "$LIC" ]] || die "license texts missing – run scripts/build-deps.sh licenses"

section() { # name title url license-file...
  local name="$1" title="$2" url="$3"; shift 3
  printf '%s\n' "================================================================================"
  printf '%s %s\n%s\n\n' "$title" "$(dep_field "$name" version)" "$url"
  local f; for f in "$@"; do cat "$LIC/$name/$f"; printf '\n'; done
}

cat <<'HEAD'
CardGate includes the following third-party software. Each component is distributed under
its own license, reproduced below. CardGate applies its own patches to FreeRDP; they are
published in the CardGate source repository.

HEAD
section freerdp  "FreeRDP" "https://www.freerdp.com" LICENSE
section openssl  "OpenSSL" "https://www.openssl.org" LICENSE.txt
section sdl3     "SDL" "https://www.libsdl.org" LICENSE.txt
section sdl3_ttf "SDL_ttf" "https://github.com/libsdl-org/SDL_ttf" LICENSE.txt
section freetype "FreeType" "https://freetype.org" LICENSE.TXT FTL.TXT
section cjson    "cJSON" "https://github.com/DaveGamble/cJSON" LICENSE
section sparkle  "Sparkle" "https://sparkle-project.org" LICENSE
printf '%s\n' "================================================================================"
printf '%s\n' "PKCS#11 header (pkcs11.h)" "This file is in the Public Domain."
