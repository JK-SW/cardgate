#!/usr/bin/env bash
# Shared settings and helpers for the build scripts. Source, do not execute.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="${CARDGATE_BUILD_DIR:-$ROOT/build}"
SRC="$BUILD/src"          # downloaded archives and extracted sources
OBJ="$BUILD/obj"          # out-of-tree build directories
PREFIX="$BUILD/prefix"    # install prefix of all dependencies
HELPER="$BUILD/helper"    # self-contained FreeRDP helper (bin + lib)

export CC="${CC:-/usr/bin/clang}" CXX="${CXX:-/usr/bin/clang++}"
export SDKROOT="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-15.0}"
ARCH=arm64
JOBS="$(sysctl -n hw.ncpu)"

# Keep Homebrew/MacPorts libraries out of the build: only our prefix is searched.
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
unset PKG_CONFIG_PATH CPATH LIBRARY_PATH C_INCLUDE_PATH
export CFLAGS="-arch $ARCH -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET -O2"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-arch $ARCH -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"

CMAKE_COMMON=(
  -G Ninja
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_INSTALL_PREFIX="$PREFIX"
  -DCMAKE_PREFIX_PATH="$PREFIX"
  -DCMAKE_IGNORE_PREFIX_PATH="/opt/homebrew;/usr/local;/opt/local"
  -DCMAKE_MAKE_PROGRAM="$(command -v ninja)"
  -DCMAKE_OSX_ARCHITECTURES="$ARCH"
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET"
  -DCMAKE_INSTALL_NAME_DIR="@rpath"
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5
)

log() { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# dep_field NAME FIELD(version|sha|url)
dep_field() {
  local name="$1" field="$2" line v
  line="$(grep -E "^$name[[:space:]]" "$ROOT/scripts/deps.lock")" || die "unknown dependency $name"
  read -r _ v sha url <<<"$line"
  case "$field" in
    version) echo "$v" ;;
    sha) echo "$sha" ;;
    url) echo "${url//\{v\}/$v}" ;;
  esac
}

# fetch NAME -> prints path of the verified archive
fetch() {
  local name="$1" url sha file
  url="$(dep_field "$name" url)"; sha="$(dep_field "$name" sha)"
  file="$SRC/$name-$(dep_field "$name" version)-$(basename "${url%%\?*}")"
  mkdir -p "$SRC"
  if [[ ! -f "$file" ]]; then
    log "Downloading $name" >&2
    curl -fsSL --retry 3 -o "$file.part" "$url"
    mv "$file.part" "$file"
  fi
  local got; got="$(shasum -a 256 "$file" | cut -d' ' -f1)"
  [[ "$got" == "$sha" ]] || { rm -f "$file"; die "checksum mismatch for $name: $got"; }
  echo "$file"
}

# unpack NAME -> prints source directory (fresh extraction)
unpack() {
  local name="$1" archive dir
  archive="$(fetch "$name")"
  dir="$SRC/$name-$(dep_field "$name" version)"
  rm -rf "$dir"; mkdir -p "$dir"
  tar -xf "$archive" -C "$dir" --strip-components 1
  local patch
  for patch in "$ROOT/patches/$name"/*.patch; do
    [[ -e "$patch" ]] || continue
    log "Applying $name/$(basename "$patch")" >&2
    patch -d "$dir" -p1 --forward --quiet <"$patch" >&2 || die "patch $(basename "$patch") does not apply"
  done
  echo "$dir"
}

# patches_hash NAME -> short hash of patches/NAME/*.patch (empty input hashes too)
patches_hash() {
  { cat "$ROOT/patches/$1"/*.patch 2>/dev/null || true; } | shasum -a 256 | cut -c1-16
}

# Stamp files make each step re-runnable: a step is skipped when its stamp matches.
stamp_key() { # steps that are not a pinned dependency (e.g. licenses) are keyed by their recipe only
  if grep -qE "^$1[[:space:]]" "$ROOT/scripts/deps.lock"; then
    echo "$(dep_field "$1" version)-$(dep_field "$1" sha)-${2:-}"
  else
    echo "step-${2:-}"
  fi
}
done_already() { [[ -f "$OBJ/.stamp-$1" && "$(cat "$OBJ/.stamp-$1")" == "$(stamp_key "$1" "${2:-}")" ]]; }
mark_done() { mkdir -p "$OBJ"; stamp_key "$1" "${2:-}" >"$OBJ/.stamp-$1"; }
