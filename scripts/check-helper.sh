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
out="$(env -i HOME="$HOME" DYLD_PRINT_LIBRARIES=1 "$HELPER/$CLIENT" /version 2>&1)" || err "sdl-freerdp /version failed"
grep -E 'dyld.*(/opt/homebrew|/usr/local|/opt/local)' <<<"$out" && err "library loaded from a package manager path"
grep -q 'This is FreeRDP version' <<<"$out" || err "unexpected /version output"
# RC4/MD4 come from the OpenSSL legacy provider; without them RDP standard security fails.
syms="$(nm "$HELPER"/Frameworks/libcrypto.*.dylib 2>/dev/null)"
grep -q ' _ossl_legacy_provider_init$' <<<"$syms" \
  || err "OpenSSL legacy provider (RC4/MD4) is not built into libcrypto"

# Network level authentication with the card: Kerberos in WinPR and its PKINIT plugin.
otool -L "$HELPER"/Frameworks/libwinpr3.*.dylib | grep -q '@rpath/libkrb5\.' \
  || err "WinPR is not built with Kerberos (libkrb5)"
for plugin in preauth/pkinit.so tls/k5tls.so; do
  [[ -f "$HELPER/PlugIns/krb5/$plugin" ]] || err "Kerberos plugin $plugin missing"
done
# libkrb5 reads files and loads plugins from its compiled-in prefix: never the build directory.
krb5_files=()
for f in "$HELPER"/Frameworks/{libkrb5,libk5crypto,libcom_err,libkrb5support}.*.dylib "$HELPER"/PlugIns/krb5/*/*.so; do
  [[ -f "$f" ]] && krb5_files+=("$f")
done
[[ ${#krb5_files[@]} -ge 6 ]] || err "Kerberos libraries or plugins missing (found ${#krb5_files[@]} of 6)"
for f in ${krb5_files[@]+"${krb5_files[@]}"}; do
  text="$(strings "$f")"   # not piped into grep -q: with pipefail, its early exit would hide a match
  [[ "$text" != *"$BUILD"* ]] || err "$(basename "$f") refers to the build directory"
done

codesign --verify --strict "$HELPER/$SESSION_APP" 2>/dev/null || err "$SESSION_APP: invalid signature"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$HELPER/$SESSION_APP/Contents/Info.plist")" == true ]] \
  || err "$SESSION_APP is not an agent app (LSUIElement)"

[[ $fail -eq 0 ]] || die "helper check failed"
log "Helper check passed: $(grep -m1 'This is FreeRDP version' <<<"$out")"
