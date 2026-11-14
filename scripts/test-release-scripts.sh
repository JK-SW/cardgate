#!/usr/bin/env bash
# Tests of the release and maintenance scripts (part of scripts/test.sh):
#  - check-dependency-updates.sh with a fake `gh` and made-up upstream releases;
#  - make-appcast.sh with a throwaway signing key (never the real one) and made-up published feeds,
#    on a PATH with only the system tools, as in the release workflow's publish job.
source "$(dirname "$0")/common.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cardgate-release-tests.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
FAILED=0
fail() { printf '\033[1;31mFAIL: %s\033[0m\n' "$*" >&2; FAILED=1; }

# --- check-dependency-updates.sh ---------------------------------------------------------------

mkdir -p "$TMP/bin" "$TMP/api"
# A `gh api [--paginate] PATH --jq EXPR` that answers from $TMP/api/<PATH with / as _>.json.
cat >"$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == api ]] || exit 64
shift
path="" expr="."
while (($#)); do
  case "$1" in
    --paginate) ;;
    --jq) expr="$2"; shift ;;
    *) path="$1" ;;
  esac
  shift
done
jq -r "$expr" "$FAKE_API/${path//\//_}.json"
EOF
chmod +x "$TMP/bin/gh"

release() { printf '{"tag_name":"%s","draft":%s,"prerelease":%s}' "$1" "${2:-false}" "${3:-false}"; }
{
  printf '['
  release openssl-4.1.0; printf ,; release openssl-4.1.1; printf ,; release openssl-4.2.0; printf ,
  release openssl-3.5.9; printf ,; release openssl-4.3.0 false true; printf ,; release openssl-9.9.9 true
  printf ']'
} >"$TMP/api/repos_openssl_openssl_releases.json"
printf '[%s]' "$(release v1.7.19)" >"$TMP/api/repos_DaveGamble_cJSON_releases.json"
printf '[{"ref":"refs/tags/VER-2-14-3"},{"ref":"refs/tags/VER-2-15-0"},{"ref":"refs/tags/VER-2-BETA4"}]' \
  >"$TMP/api/repos_freetype_freetype_git_matching-refs_tags_VER-.json"
printf '[%s,%s,%s]' "$(release release-3.2.30)" "$(release release-3.4.18)" "$(release release-3.4.20)" \
  >"$TMP/api/repos_libsdl-org_SDL_releases.json"
printf '[%s,%s,%s]' "$(release 3.9.0)" "$(release 3.33.1)" "$(release 3.10.0)" \
  >"$TMP/api/repos_FreeRDP_FreeRDP_releases.json"
cat >"$TMP/deps.lock" <<'EOF'
# test
openssl   4.1.0   0  https://example.com/{v}
cjson     1.7.19  0  https://example.com/{v}
freetype  2.15.0  0  https://example.com/{v}
sdl3      3.4.18  0  https://example.com/{v}
freerdp   3.33.0  0  https://example.com/{v}
EOF

expected="openssl 4.1.0 4.1.1 https://github.com/openssl/openssl/releases/tag/openssl-4.1.1
openssl 4.1.0 4.2.0 https://github.com/openssl/openssl/releases/tag/openssl-4.2.0
sdl3 3.4.18 3.4.20 https://github.com/libsdl-org/SDL/releases/tag/release-3.4.20
freerdp 3.33.0 3.33.1 https://github.com/FreeRDP/FreeRDP/releases/tag/3.33.1"
log "check-dependency-updates.sh"
got="$(PATH="$TMP/bin:$PATH" FAKE_API="$TMP/api" DEPS_LOCK="$TMP/deps.lock" \
  "$ROOT/scripts/check-dependency-updates.sh")" || fail "check-dependency-updates.sh failed"
[[ "$got" == "$expected" ]] || fail "check-dependency-updates.sh printed:
$got
expected:
$expected"

printf 'unknown 1.0.0 0 https://example.com/{v}\n' >"$TMP/unknown.lock"
if PATH="$TMP/bin:$PATH" FAKE_API="$TMP/api" DEPS_LOCK="$TMP/unknown.lock" \
  "$ROOT/scripts/check-dependency-updates.sh" >/dev/null 2>&1; then
  fail "check-dependency-updates.sh accepted an unknown dependency"
fi

# --- make-appcast.sh ---------------------------------------------------------------------------

SIGN="$PREFIX/sparkle/bin/sign_update"
if [[ ! -x "$SIGN" || ! -x "$PREFIX/bin/openssl" ]]; then
  log "make-appcast.sh: skipped (run scripts/build-deps.sh for Sparkle and OpenSSL)"
else
  log "make-appcast.sh"
  public_key() { # base64 Ed25519 private key (Sparkle's key file) -> base64 public key
    { printf '302e020100300506032b657004220420' | xxd -r -p; base64 -d <"$1"; } \
      | "$PREFIX/bin/openssl" pkey -inform DER -pubout -outform DER | tail -c 32 | base64
  }
  head -c 32 /dev/urandom | base64 >"$TMP/test.key"
  head -c 32 /dev/urandom | base64 >"$TMP/other.key"
  app="$TMP/CardGate.app"
  mkdir -p "$app/Contents"
  plist="$app/Contents/Info.plist"
  plutil -create xml1 "$plist"
  plutil -insert CFBundleShortVersionString -string "$(tr -d '[:space:]' <"$ROOT/VERSION")" "$plist"
  plutil -insert CFBundleVersion -string 80 "$plist"
  plutil -insert LSMinimumSystemVersion -string 15.0 "$plist"
  plutil -insert SUPublicEDKey -string "$(public_key "$TMP/test.key")" "$plist"
  (cd "$TMP" && zip -qr CardGate-test.zip CardGate.app)
  feed() { printf '<rss><channel><item><sparkle:version>%s</sparkle:version></item></channel></rss>\n' "$1"; }
  feed 79 >"$TMP/older.xml"; feed 80 >"$TMP/same.xml"; printf '<rss/>\n' >"$TMP/empty.xml"

  # Only the system tools, as in the publish job (no Homebrew, so no ninja).
  appcast() { # PUBLISHED KEY -> output of make-appcast.sh
    env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin PUBLISHED_APPCAST="$1" SPARKLE_KEY_FILE="$2" \
      SPARKLE_SIGN_UPDATE="$SIGN" CARDGATE_BUILD_DIR="$BUILD" \
      "$ROOT/scripts/make-appcast.sh" "$TMP/CardGate-test.zip" "$app" 2>&1
  }
  expect() { # DESCRIPTION EXPECTED-STATUS EXPECTED-TEXT PUBLISHED KEY
    local out status=0
    out="$(appcast "$4" "$5")" || status=$?
    [[ "$status" == "$2" && "$out" == *"$3"* ]] || fail "$1: status $status, output: $out"
  }
  expect "higher build" 0 '<sparkle:version>80</sparkle:version>' "$TMP/older.xml" "$TMP/test.key"
  expect "higher build signs the archive" 0 "length=\"$(stat -f %z "$TMP/CardGate-test.zip")\"" \
    "$TMP/older.xml" "$TMP/test.key"
  expect "first release" 0 '<sparkle:version>80</sparkle:version>' none "$TMP/test.key"
  expect "same build" 1 'build 80 is not higher than build 80' "$TMP/same.xml" "$TMP/test.key"
  expect "feed without a build" 1 'the published feed has no build number' "$TMP/empty.xml" "$TMP/test.key"
  expect "other signing key" 1 'wrong signing key' none "$TMP/other.key"
fi

((FAILED == 0)) || die "release script tests failed"
log "Release script tests passed"
