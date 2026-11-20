#!/usr/bin/env bash
# Tests of the release and maintenance scripts (part of scripts/test.sh):
#  - check-dependency-updates.sh with a fake `gh` and made-up upstream releases;
#  - report-dependency-updates.sh with a fake `gh` and made-up issues;
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
printf '[{"ref":"refs/tags/krb5-1.22-final"},{"ref":"refs/tags/krb5-1.22.3-final"},{"ref":"refs/tags/krb5-1.22.4-final"},{"ref":"refs/tags/krb5-1.23-beta1"},{"ref":"refs/tags/krb5-1.23-final"},{"ref":"refs/tags/krb5-1.23.1-final"},{"ref":"refs/tags/krb5-1.24-final"}]' \
  >"$TMP/api/repos_krb5_krb5_git_matching-refs_tags_krb5-.json"
printf '[%s,%s,%s]' "$(release release-3.2.30)" "$(release release-3.4.18)" "$(release release-3.4.20)" \
  >"$TMP/api/repos_libsdl-org_SDL_releases.json"
printf '[%s,%s,%s]' "$(release 3.9.0)" "$(release 3.33.1)" "$(release 3.10.0)" \
  >"$TMP/api/repos_FreeRDP_FreeRDP_releases.json"
cat >"$TMP/deps.lock" <<'EOF'
# test
openssl   4.1.0   0  https://example.com/{v}
krb5      1.22.3  0  https://example.com/{v}
cjson     1.7.19  0  https://example.com/{v}
freetype  2.15.0  0  https://example.com/{v}
sdl3      3.4.18  0  https://example.com/{v}
freerdp   3.33.0  0  https://example.com/{v}
EOF

expected="openssl 4.1.0 4.1.1 https://github.com/openssl/openssl/releases/tag/openssl-4.1.1
openssl 4.1.0 4.2.0 https://github.com/openssl/openssl/releases/tag/openssl-4.2.0
krb5 1.22.3 1.22.4 https://web.mit.edu/kerberos/krb5-1.22/
krb5 1.22.3 1.24 https://web.mit.edu/kerberos/krb5-1.24/
sdl3 3.4.18 3.4.20 https://github.com/libsdl-org/SDL/releases/tag/release-3.4.20
freerdp 3.33.0 3.33.1 https://github.com/FreeRDP/FreeRDP/releases/tag/3.33.1"
log "check-dependency-updates.sh"
got="$(PATH="$TMP/bin:$PATH" FAKE_API="$TMP/api" DEPS_LOCK="$TMP/deps.lock" \
  "$ROOT/scripts/check-dependency-updates.sh")" || fail "check-dependency-updates.sh failed"
[[ "$got" == "$expected" ]] || fail "check-dependency-updates.sh printed:
$got
expected:
$expected"

# A line MIT Kerberos named X.Y: its fixes X.Y.Z are reported, not only the newest line.
printf '%s\n' "krb5      1.23  0  https://example.com/{v}" >"$TMP/krb5-line.lock"
got="$(PATH="$TMP/bin:$PATH" FAKE_API="$TMP/api" DEPS_LOCK="$TMP/krb5-line.lock" \
  "$ROOT/scripts/check-dependency-updates.sh")" || fail "check-dependency-updates.sh failed for krb5 1.23"
expected="krb5 1.23 1.23.1 https://web.mit.edu/kerberos/krb5-1.23/
krb5 1.23 1.24 https://web.mit.edu/kerberos/krb5-1.24/"
[[ "$got" == "$expected" ]] || fail "check-dependency-updates.sh printed for krb5 1.23:
$got
expected:
$expected"

printf 'unknown 1.0.0 0 https://example.com/{v}\n' >"$TMP/unknown.lock"
if PATH="$TMP/bin:$PATH" FAKE_API="$TMP/api" DEPS_LOCK="$TMP/unknown.lock" \
  "$ROOT/scripts/check-dependency-updates.sh" >/dev/null 2>&1; then
  fail "check-dependency-updates.sh accepted an unknown dependency"
fi

# --- report-dependency-updates.sh --------------------------------------------------------------

mkdir -p "$TMP/bin-issues"
# A `gh issue list|create|close` on the issues in $FAKE_ISSUES; changes are logged to $FAKE_LOG.
cat >"$TMP/bin-issues/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == issue ]] || exit 64
case "$2" in
  list) cat "$FAKE_ISSUES" ;;
  create)
    [[ "$3" == --title ]] || exit 64
    number="$(jq 'map(.number) | max + 1' "$FAKE_ISSUES")"
    jq --arg title "$4" --argjson number "$number" '. + [{number: $number, title: $title, state: "OPEN"}]' \
      "$FAKE_ISSUES" >"$FAKE_ISSUES.new" && mv "$FAKE_ISSUES.new" "$FAKE_ISSUES"
    echo "created #$number $4" >>"$FAKE_LOG"
    echo "https://github.com/example/repo/issues/$number" ;;
  close)
    [[ "$4" == --comment ]] || exit 64
    jq --argjson number "$3" 'map(if .number == $number then .state = "CLOSED" else . end)' \
      "$FAKE_ISSUES" >"$FAKE_ISSUES.new" && mv "$FAKE_ISSUES.new" "$FAKE_ISSUES"
    echo "closed #$3: $5" >>"$FAKE_LOG" ;;
  *) exit 64 ;;
esac
GH
chmod +x "$TMP/bin-issues/gh"
cat >"$TMP/issues.json" <<'JSON'
[
  {"number": 1, "title": "Dependency update: sdl3 3.4.20", "state": "OPEN"},
  {"number": 2, "title": "Dependency update: sdl3_ttf 3.2.4", "state": "OPEN"},
  {"number": 3, "title": "Dependency update: openssl 4.1.1", "state": "OPEN"},
  {"number": 4, "title": "Dependency update: freerdp 3.33.1", "state": "OPEN"},
  {"number": 5, "title": "Dependency update: openssl 4.2.0", "state": "CLOSED"},
  {"number": 6, "title": "Dependency update: cjson 1.7.19", "state": "OPEN"},
  {"number": 7, "title": "Dependency update: freetype 2.15.0", "state": "OPEN"},
  {"number": 8, "title": "Dependency update: sparkle 2.10.10", "state": "OPEN"}
]
JSON
cat >"$TMP/report.lock" <<'LOCK'
# test
openssl   4.1.0   0  https://example.com/{v}
cjson     1.7.20  0  https://example.com/{v}
freetype  2.15.0  0  https://example.com/{v}
sdl3      3.4.18  0  https://example.com/{v}
sdl3_ttf  3.2.2   0  https://example.com/{v}
freerdp   3.33.0  0  https://example.com/{v}
sparkle   2.10.9  0  https://example.com/{v}
LOCK
cat >"$TMP/updates.txt" <<'UPDATES'
sdl3 3.4.18 3.4.22 https://example.com/sdl3
openssl 4.1.0 4.1.2 https://example.com/openssl-4.1.2
openssl 4.1.0 4.2.0 https://example.com/openssl-4.2.0
freerdp 3.33.0 3.33.1 https://example.com/freerdp
UPDATES
# New versions open issues (openssl 4.2.0 was closed: not again) and close the ones they replace,
# naming the issues of both openssl lines; versions deps.lock pins (cjson older, freetype the same)
# close; sdl3_ttf and sparkle report nothing now (a failed check?) and stay open, as does the
# reported freerdp.
expected="created #9 Dependency update: sdl3 3.4.22
created #10 Dependency update: openssl 4.1.2
closed #1: Superseded by sdl3 3.4.22 (#9).
closed #3: Superseded by openssl 4.1.2 (#10), openssl 4.2.0 (#5).
closed #6: scripts/deps.lock already pins cjson 1.7.20.
closed #7: scripts/deps.lock already pins freetype 2.15.0."
report() {
  : >"$TMP/issues.log"
  PATH="$TMP/bin-issues:$PATH" FAKE_ISSUES="$TMP/issues.json" FAKE_LOG="$TMP/issues.log" \
    DEPS_LOCK="$TMP/report.lock" "$ROOT/scripts/report-dependency-updates.sh" "$TMP/updates.txt" >/dev/null \
    || fail "report-dependency-updates.sh failed"
}
log "report-dependency-updates.sh"
report
got="$(cat "$TMP/issues.log")"
[[ "$got" == "$expected" ]] || fail "report-dependency-updates.sh did:
$got
expected:
$expected"
# A second run changes nothing.
report
[[ ! -s "$TMP/issues.log" ]] || fail "report-dependency-updates.sh changed issues again: $(cat "$TMP/issues.log")"

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
