#!/usr/bin/env bash
# Prints the CHANGELOG.md section of the version in VERSION (fails if it is missing).
source "$(dirname "$0")/common.sh"
VERSION="$(tr -d '[:space:]' <"$ROOT/VERSION")"
notes="$(awk -v v="$VERSION" '
  /^## \[/ { if (found) exit; if (index($0, "## [" v "]") == 1) { found = 1; next } }
  found { print }
' "$ROOT/CHANGELOG.md")"
[[ -n "${notes//[[:space:]]/}" ]] || die "CHANGELOG.md has no section '## [$VERSION]'"
printf '%s\n' "$notes"
