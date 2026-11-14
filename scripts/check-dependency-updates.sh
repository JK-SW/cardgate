#!/usr/bin/env bash
# Lists newer upstream releases of the dependencies pinned in scripts/deps.lock (uses gh, needs no
# repository access). For each dependency it prints the newest release, and also the newest one of the
# pinned minor version when that differs (a security fix of the current line).
#
# Output: one line per update – NAME PINNED NEW RELEASE-URL; nothing when everything is current.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPS_LOCK="${DEPS_LOCK:-$ROOT/scripts/deps.lock}"   # another file only for the tests

# NAME → GitHub repository and the tag prefix before the version.
upstream() {
  case "$1" in
    openssl)  echo "openssl/openssl openssl-" ;;
    cjson)    echo "DaveGamble/cJSON v" ;;
    freetype) echo "freetype/freetype VER-" ;;   # tags VER-2-15-0, no GitHub releases
    sdl3)     echo "libsdl-org/SDL release-" ;;
    sdl3_ttf) echo "libsdl-org/SDL_ttf release-" ;;
    freerdp)  echo "FreeRDP/FreeRDP " ;;
    sparkle)  echo "sparkle-project/Sparkle " ;;
    *) echo "unknown dependency $1 in deps.lock" >&2; return 1 ;;
  esac
}

# Released versions X.Y.Z of a repository, one per line.
versions() {
  local repo="$1" prefix="$2"
  if [[ "$prefix" == VER- ]]; then
    gh api --paginate "repos/$repo/git/matching-refs/tags/VER-" --jq '.[].ref | ltrimstr("refs/tags/VER-")' | tr - .
  else
    gh api --paginate "repos/$repo/releases" \
      --jq ".[] | select(.draft | not) | select(.prerelease | not) | .tag_name | ltrimstr(\"$prefix\")"
  fi | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' || true
}

newest() { sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1; }

release_url() {
  local repo="$1" prefix="$2" version="$3"
  if [[ "$prefix" == VER- ]]; then
    echo "https://freetype.org/index.html#news"
  else
    echo "https://github.com/$repo/releases/tag/$prefix$version"
  fi
}

while read -r name pinned _; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  read -r repo prefix < <(upstream "$name")
  all="$(versions "$repo" "$prefix")"
  [[ -n "$all" ]] || { echo "no releases found for $name ($repo)" >&2; exit 1; }
  candidates=("$(newest <<<"$all")")
  candidates+=("$(awk -F. -v line="${pinned%.*}" '$1 "." $2 == line' <<<"$all" | newest)")
  for new in $(printf '%s\n' "${candidates[@]}" | sort -u); do
    [[ -n "$new" && "$new" != "$pinned" ]] || continue
    # Only versions above the pinned one.
    [[ "$(printf '%s\n%s\n' "$pinned" "$new" | newest)" == "$new" ]] || continue
    echo "$name $pinned $new $(release_url "$repo" "$prefix" "$new")"
  done
done <"$DEPS_LOCK"
