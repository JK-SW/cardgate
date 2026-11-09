#!/usr/bin/env bash
# Generates app/CardGate.xcodeproj from app/project.yml with the version from VERSION.
source "$(dirname "$0")/common.sh"
command -v xcodegen >/dev/null || die "xcodegen not found (brew install xcodegen)"
CARDGATE_VERSION="$(tr -d '[:space:]' <"$ROOT/VERSION")"
CARDGATE_BUILD="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
export CARDGATE_VERSION CARDGATE_BUILD
[[ "$CARDGATE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "VERSION must be X.Y.Z, got '$CARDGATE_VERSION'"
xcodegen generate --quiet --spec "$ROOT/app/project.yml" --project "$ROOT/app"
log "Generated app/CardGate.xcodeproj (version $CARDGATE_VERSION, build $CARDGATE_BUILD)"
