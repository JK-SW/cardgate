#!/usr/bin/env bash
# Builds FreeRDP (with our patches) and all its runtime dependencies from pinned sources
# into $BUILD/prefix. Re-running only rebuilds steps whose inputs changed.
#
# Usage: scripts/build-deps.sh [step...]   steps: licenses openssl cjson freetype sdl3 sdl3_ttf freerdp sparkle
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
    -DWITH_KRB5=OFF \
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

# Static analysis of the C sources CardGate adds to FreeRDP (fails the build on any finding).
analyze_patched_sources() {
  local s="$1" file cmd
  for file in libfreerdp/core/gateway/rdg_sc.c; do
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
    (cd "$OBJ/freerdp" && eval "$CC --analyze -Xanalyzer -analyzer-output=text -Werror $cmd -o /dev/null") \
      || die "static analyzer reported issues in $file"
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
  for entry in "openssl:LICENSE.txt" "cjson:LICENSE" "freetype:LICENSE.TXT docs/FTL.TXT" \
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

ALL=(licenses openssl cjson freetype sdl3 sdl3_ttf freerdp sparkle)
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
