#!/usr/bin/env bash
# Verifies that the assembled helper is self-contained:
#  - every dependency is a system library or an @rpath library present in Frameworks
#  - no absolute rpaths, no references to build or package-manager paths
#  - all code is validly signed, the client starts
source "$(dirname "$0")/common.sh"

fail=0
err() { printf 'FAIL: %s\n' "$*" >&2; fail=1; }

while IFS= read -r -d '' f; do
  file "$f" | grep -q 'Mach-O' || continue
  name="${f#"$HELPER"/}"
  while read -r ref; do
    case "$ref" in
      /usr/lib/* | /System/*) ;;
      @rpath/*) [[ -e "$HELPER/Frameworks/${ref#@rpath/}" ]] || err "$name: missing $ref" ;;
      *) err "$name: non-relocatable dependency $ref" ;;
    esac
  done < <(otool -L "$f" | tail -n +2 | awk '{print $1}' | grep -v "^@rpath/$(basename "$f")$" || true)
  while read -r r; do
    [[ "$r" == @loader_path* || "$r" == @executable_path* ]] || err "$name: absolute rpath $r"
  done < <(otool -l "$f" | awk '/LC_RPATH/{getline; getline; print $2}')
  codesign --verify "$f" 2>/dev/null || err "$name: invalid signature"
  lipo -archs "$f" | grep -qw arm64 || err "$name: not arm64"
done < <(find "$HELPER" -type f -print0)

# The client must start and load all libraries from the helper only.
out="$(env -i HOME="$HOME" DYLD_PRINT_LIBRARIES=1 "$HELPER/Helpers/sdl-freerdp" /version 2>&1)" || err "sdl-freerdp /version failed"
grep -E 'dyld.*(/opt/homebrew|/usr/local|/opt/local)' <<<"$out" && err "library loaded from a package manager path"
grep -q 'This is FreeRDP version' <<<"$out" || err "unexpected /version output"

[[ $fail -eq 0 ]] || die "helper check failed"
log "Helper check passed: $(grep -m1 'This is FreeRDP version' <<<"$out")"
