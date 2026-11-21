#!/usr/bin/env bash
# Builds FreeRDP (with our patches) and all its runtime dependencies from pinned sources
# into $BUILD/prefix. Re-running only rebuilds steps whose inputs changed.
#
# Usage: scripts/build-deps.sh [step...]   steps: licenses openssl krb5 cjson freetype sdl3 sdl3_ttf freerdp sparkle
# Build tools needed: Xcode command line tools, cmake, ninja, pkg-config.
source "$(dirname "$0")/common.sh"

for tool in cmake ninja pkg-config; do
  command -v "$tool" >/dev/null || die "$tool not found (brew install cmake ninja pkg-config)"
done

# A step is rebuilt when its own recipe (function body), common settings, pinned version or patches change.
COMMON_HASH="$(shasum -a 256 "$ROOT/scripts/common.sh" | cut -c1-16)"
recipe_hash() { { declare -f "build_$1"; declare -f build_cmake_dep; echo "$COMMON_HASH"; } | shasum -a 256 | cut -c1-16; }

build_openssl() {
  local s; s="$(unpack openssl)"
  log "Building OpenSSL"
  # no-module: providers (incl. "legacy" with RC4/MD4, required by RDP standard security)
  # are built into libcrypto, so no ossl-modules directory has to be shipped or located.
  (cd "$s" && ./Configure darwin64-arm64-cc shared no-module no-tests no-docs \
      --prefix="$PREFIX" --libdir=lib --openssldir=/private/etc/ssl \
      -mmacosx-version-min="$MACOSX_DEPLOYMENT_TARGET" \
    && make -j"$JOBS" >/dev/null && make install_sw >/dev/null)
}

# MIT Kerberos with PKINIT: network level authentication (NLA) to the computer with the card
# (Kerberos via the gateway's KDC proxy). Only the client side is built: the libraries FreeRDP links
# (krb5, k5crypto, com_err, krb5support), the plugins it loads at runtime (pkinit: the card, k5tls:
# HTTPS to the KDC proxy), the headers and krb5-config. No KDC, admin tools or RPC library.
#
# libkrb5 compiles its prefix in: a configuration file and plugin directories it reads whatever its
# configuration says. They point to a directory only root can create (/var/empty is root's), not to
# the build directory (on the release build machine a path any user could create); the client gets
# its own configuration and plugin directory (KRB5_CONFIG, FreeRDPCommand). The files are installed
# into a staging directory and moved to $PREFIX, install names rewritten to @rpath.
build_krb5() {
  local KRB5_COMPILED_PREFIX=/var/empty/cardgate-krb5
  local parts=(util include lib/crypto lib/krb5 plugins/preauth/pkinit plugins/tls/k5tls build-tools)
  local s part stage="$OBJ/krb5-stage" f ref; s="$(unpack krb5)"
  log "Building MIT Kerberos (client)"
  rm -rf "$stage"
  (cd "$s/src" && ./configure --prefix="$KRB5_COMPILED_PREFIX" \
      --with-crypto-impl=openssl --with-tls-impl=openssl --enable-pkinit \
      --without-system-verto --without-ldap --without-libedit --without-readline \
      --disable-nls --disable-rpath \
      CPPFLAGS="-I$PREFIX/include" LDFLAGS="$LDFLAGS -L$PREFIX/lib" >"$OBJ/krb5-configure.log" 2>&1) \
    || { tail -30 "$OBJ/krb5-configure.log"; die "MIT Kerberos configure failed"; }
  (cd "$s/src" && make install-mkdirs DESTDIR="$stage") >"$OBJ/krb5-build.log" 2>&1 \
    || die "MIT Kerberos install-mkdirs failed"
  for part in "${parts[@]}"; do
    (cd "$s/src/$part" && make -j"$JOBS" WARN_CFLAGS="-Wall -Wno-deprecated-declarations" \
        && make install DESTDIR="$stage") >>"$OBJ/krb5-build.log" 2>&1 \
      || { tail -30 "$OBJ/krb5-build.log"; die "MIT Kerberos build failed in $part"; }
  done
  # Into the prefix: libraries by @rpath (as every other one), krb5-config with the real paths.
  # Without its pkg-config files: they name the compiled-in prefix (FreeRDP asks krb5-config).
  rsync -a --exclude lib/pkgconfig "$stage$KRB5_COMPILED_PREFIX/" "$PREFIX/"
  while IFS= read -r -d '' f; do
    [[ "$f" == *.dylib ]] && install_name_tool -id "@rpath/$(basename "$f")" "$f"
    while read -r ref; do
      [[ "$ref" == "$KRB5_COMPILED_PREFIX"/* ]] && install_name_tool -change "$ref" "@rpath/$(basename "$ref")" "$f"
    done < <(otool -L "$f" | tail -n +2 | awk '{print $1}')
  done < <(find "$PREFIX/lib" \( -name 'lib*.dylib' -o -name '*.so' \) -type f -newer "$OBJ/krb5-configure.log" -print0)
  sed -i '' "s#$KRB5_COMPILED_PREFIX#$PREFIX#g" "$PREFIX/bin/krb5-config"
}

build_cmake_dep() { # name source-subdir extra-cmake-args...
  local name="$1" sub="$2"; shift 2
  local s; s="$(unpack "$name")"
  log "Building $name"
  rm -rf "$OBJ/$name"
  cmake -S "$s/$sub" -B "$OBJ/$name" "${CMAKE_COMMON[@]}" "$@" >/dev/null
  cmake --build "$OBJ/$name" >/dev/null
  cmake --install "$OBJ/$name" >/dev/null
}

build_cjson() {
  build_cmake_dep cjson . -DBUILD_SHARED_LIBS=ON -DENABLE_CJSON_TEST=OFF -DENABLE_CJSON_UTILS=OFF \
    -DENABLE_CUSTOM_COMPILER_FLAGS=OFF
}

build_freetype() {
  # Static, linked into SDL3_ttf only; no optional codecs.
  build_cmake_dep freetype . -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DFT_DISABLE_ZLIB=ON -DFT_DISABLE_BZIP2=ON -DFT_DISABLE_PNG=ON \
    -DFT_DISABLE_HARFBUZZ=ON -DFT_DISABLE_BROTLI=ON -DFT_DISABLE_HVF=ON
}

build_sdl3() {
  build_cmake_dep sdl3 . -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF \
    -DSDL_INSTALL_DOCS=OFF
}

build_sdl3_ttf() {
  build_cmake_dep sdl3_ttf . -DBUILD_SHARED_LIBS=ON -DSDLTTF_VENDORED=OFF -DSDLTTF_HARFBUZZ=OFF \
    -DSDLTTF_PLUTOSVG=OFF -DSDLTTF_SAMPLES=OFF
}

build_freerdp() {
  local s; s="$(unpack freerdp)"
  log "Building FreeRDP"
  rm -rf "$OBJ/freerdp"
  cmake -S "$s" -B "$OBJ/freerdp" "${CMAKE_COMMON[@]}" \
    -DWITH_CLIENT_SDL3=ON -DWITH_CLIENT_SDL2=OFF -DWITH_CLIENT_MAC=OFF -DWITH_X11=OFF -DWITH_WAYLAND=OFF \
    -DWITH_SERVER=OFF -DWITH_SAMPLE=OFF -DWITH_PROXY=OFF -DWITH_SHADOW=OFF -DWITH_PLATFORM_SERVER=OFF \
    -DWITH_KRB5=ON -DKRB5_ROOT_FLAVOUR=MIT -DKRB5_ROOT_CONFIG="$PREFIX/bin/krb5-config" \
    -DWITH_PKCS11=ON -DWITH_SMARTCARD_PCSC=ON -DWITH_SMARTCARD_EMULATE=OFF \
    -DWITH_OPENSSL=ON -DOPENSSL_ROOT_DIR="$PREFIX" \
    -DWITH_CJSON_REQUIRED=ON -DWITH_JANSSON_REQUIRED=OFF -DWITH_JSONC_REQUIRED=OFF \
    -DWITH_URIPARSER=OFF -DCHANNEL_URBDRC=OFF \
    -DWITH_FFMPEG=OFF -DWITH_SWSCALE=OFF -DWITH_DSP_FFMPEG=OFF -DWITH_FUSE=OFF -DWITH_CUPS=OFF \
    -DWITH_OPUS=OFF -DWITH_FAAD2=OFF -DWITH_FAAC=OFF -DWITH_SOXR=OFF -DWITH_LAME=OFF \
    -DWITH_WEBVIEW=OFF -DWITH_AAD=OFF -DWITH_MANPAGES=OFF -DBUILD_TESTING=OFF \
    -DWITH_WINPR_TOOLS=OFF -DWITH_CCACHE=OFF -DWITH_ABSOLUTE_PLUGIN_LOAD_PATHS=OFF \
    -DUSE_VERSION_FROM_GIT_TAG=OFF -DWITH_VERBOSE_WINPR_ASSERT=OFF -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
    >"$OBJ/freerdp-cmake.log" 2>&1 || { tail -30 "$OBJ/freerdp-cmake.log"; die "FreeRDP cmake failed"; }
  cmake --build "$OBJ/freerdp" >"$OBJ/freerdp-build.log" 2>&1 || { tail -30 "$OBJ/freerdp-build.log"; die "FreeRDP build failed"; }
  cmake --install "$OBJ/freerdp" >/dev/null
  analyze_patched_sources "$s"
}

# Analyzer findings in FreeRDP's own code of a file CardGate patches (message as printed, without
# position), one line each: each is ignored once; any other finding, or the same one again, fails.
known_upstream_findings() {
  case "$1" in
    # user-to-user ticket encoding (KRB_TGT_REP), which CardGate does not use; patch 0015 is elsewhere
    winpr/libwinpr/sspi/Kerberos/kerberos.c)
      echo "Access to field 'cbBuffer' results in a dereference of a null pointer (loaded from variable 'buf') [core.NullDereference]" ;;
    *) ;;
  esac
}

# Static analysis of the C sources CardGate adds to FreeRDP (fails the build on any finding).
# libfreerdp/utils/smartcard_call.c (patch 0006) is left out: the analyzer reports two false memory
# leaks in FreeRDP's own code there (HashTable_Insert takes ownership).
analyze_patched_sources() {
  local s="$1" file cmd
  for file in libfreerdp/core/gateway/rdg_sc.c libfreerdp/core/gateway/rdg.c libfreerdp/core/smartcardlogon.c \
    winpr/libwinpr/sspi/Kerberos/kerberos.c libfreerdp/crypto/tls.c libfreerdp/core/nla.c libfreerdp/core/info.c \
    client/common/client.c client/SDL/SDL3/sdl_monitor.cpp client/SDL/SDL3/sdl_context.cpp \
    client/SDL/SDL3/sdl_freerdp.cpp client/SDL/SDL3/sdl_utils.cpp client/SDL/SDL3/sdl_input.cpp; do
    cmd="$(python3 -I -c '
import json, shlex, sys
for entry in json.load(open(sys.argv[1])):
    if entry["file"].endswith(sys.argv[2]):
        args = shlex.split(entry["command"]) if "command" in entry else entry["arguments"]
        args = [a for a in args[1:] if a not in ("-c",)]
        if "-o" in args:
            i = args.index("-o"); del args[i:i + 2]
        print(shlex.join(args)); break
' "$OBJ/freerdp/compile_commands.json" "$file")"
    [[ -n "$cmd" ]] || die "no compile command for $file"
    log "Static analysis: $file"
    # Compiler warnings fail the analysis (-Werror); the analyzer's own findings are warnings named by
    # checker (e.g. [core.NullDereference], [unix.Malloc]) that -Werror does not turn into errors.
    local findings
    findings="$(cd "$OBJ/freerdp" \
      && eval "$CC --analyze -Xanalyzer -analyzer-output=text -Werror $cmd -o /dev/null" 2>&1)" \
      || die "static analysis failed for $file: $findings"
    # Analyzer findings without file position, minus the known ones in FreeRDP's own code.
    local reported
    reported="$(grep -E 'warning: .*\[[a-z]+(\.[A-Za-z0-9]+)+\]$' <<<"$findings" \
      | sed -E 's/^.*:[0-9]+:[0-9]+: warning: //' \
      | awk -v known="$(known_upstream_findings "$file")" \
          'BEGIN { n = split(known, k, "\n"); for (i = 1; i <= n; i++) if (k[i] != "") left[k[i]]++ }
           left[$0]-- > 0 { next } { print }' || true)"
    if [[ -n "$reported" ]]; then
      printf '%s\n' "$findings" >&2
      die "static analyzer reported issues in $file"
    fi
  done
}

# License texts of everything shipped in the app, from the verified source archives.
build_sparkle() {
  # Prebuilt by the Sparkle project (checksum pinned): the update framework embedded in the app and
  # the tool that signs release archives for the update feed.
  local s; s="$(unpack sparkle)"
  log "Installing Sparkle"
  rm -rf "$PREFIX/sparkle"; mkdir -p "$PREFIX/sparkle/bin"
  ditto "$s/Sparkle.framework" "$PREFIX/sparkle/Sparkle.framework"
  cp "$s/bin/sign_update" "$s/bin/generate_keys" "$PREFIX/sparkle/bin/"
}

build_licenses() {
  local dir="$PREFIX/share/licenses"
  rm -rf "$dir"; mkdir -p "$dir"
  local entry name files f archive top
  for entry in "openssl:LICENSE.txt" "krb5:NOTICE" "cjson:LICENSE" "freetype:LICENSE.TXT docs/FTL.TXT" \
               "sdl3:LICENSE.txt" "sdl3_ttf:LICENSE.txt" "freerdp:LICENSE" "sparkle:LICENSE"; do
    name="${entry%%:*}"; files="${entry#*:}"
    archive="$(fetch "$name")"
    top="$(tar -tf "$archive" | head -1 | cut -d/ -f1)"
    mkdir -p "$dir/$name"
    for f in $files; do
      tar -xOf "$archive" "$top/$f" >"$dir/$name/$(basename "$f")" || die "$f missing in $name"
    done
  done
  log "License texts collected"
}

ALL=(licenses openssl krb5 cjson freetype sdl3 sdl3_ttf freerdp sparkle)
STEPS=("${@:-${ALL[@]}}")
mkdir -p "$OBJ" "$PREFIX"
rebuilt=0  # once a step is rebuilt, everything after it is rebuilt too
for step in "${STEPS[@]}"; do
  extra="$(recipe_hash "$step")-$(patches_hash "$step")"
  if [[ $# -eq 0 && $rebuilt -eq 0 ]] && done_already "$step" "$extra"; then
    log "$step is up to date"; continue
  fi
  "build_$step"
  rebuilt=1
  mark_done "$step" "$extra"
done
log "Dependencies installed in $PREFIX"
