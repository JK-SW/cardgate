#!/usr/bin/env bash
# Signs the release archive for Sparkle and prints the update feed (appcast.xml) for it.
#
# Usage: scripts/make-appcast.sh <archive.zip> <app bundle>
# The EdDSA private key is read from the file in $SPARKLE_KEY_FILE (never from the repository).
# $SPARKLE_SIGN_UPDATE: Sparkle's sign_update (default: the one scripts/build-deps.sh installed).
# $PUBLISHED_APPCAST: the feed of the release users have now (URL or file; "none" before the first
# release); the new build number must be higher, or Sparkle would not offer the update.
source "$(dirname "$0")/common.sh"
ZIP="${1:?archive}"; APP="${2:?app bundle}"
[[ -f "${SPARKLE_KEY_FILE:-}" ]] || die "SPARKLE_KEY_FILE must point to the EdDSA private key"
SIGN="${SPARKLE_SIGN_UPDATE:-$PREFIX/sparkle/bin/sign_update}"
[[ -x "$SIGN" ]] || die "Sparkle tools missing – run scripts/build-deps.sh sparkle"
PUBLISHED_APPCAST="${PUBLISHED_APPCAST:-https://github.com/JK-SW/cardgate/releases/latest/download/appcast.xml}"

VERSION="$(tr -d '[:space:]' <"$ROOT/VERSION")"
PLIST="$APP/Contents/Info.plist"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
MIN_SYSTEM="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST")"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")" == "$VERSION" ]] \
  || die "the app is not version $VERSION"

[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || die "the app's build number '$BUILD_NUMBER' is not a number"

# Sparkle offers an update only when its build number (CFBundleVersion) is higher than the installed
# one; a rewritten history can lower the commit count the build number comes from.
if [[ "$PUBLISHED_APPCAST" != none ]]; then
  if [[ "$PUBLISHED_APPCAST" == *://* ]]; then
    feed="$(curl -fsSL --retry 3 "$PUBLISHED_APPCAST")" || die "cannot read the published feed $PUBLISHED_APPCAST"
  else
    feed="$(cat "$PUBLISHED_APPCAST")"
  fi
  published="$(sed -n 's:.*<sparkle\:version>\([0-9][0-9]*\)</sparkle\:version>.*:\1:p' <<<"$feed" | head -n 1)"
  [[ -n "$published" ]] || die "the published feed has no build number"
  ((BUILD_NUMBER > published)) \
    || die "build $BUILD_NUMBER is not higher than build $published of the published release"
fi

PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$PLIST" 2>/dev/null || true)"
[[ -n "$PUBLIC_KEY" ]] || die "the app has no SUPublicEDKey (app/sparkle-public-key.txt)"

SIGNATURE="$("$SIGN" --ed-key-file "$SPARKLE_KEY_FILE" "$ZIP")"
pattern='^[[:space:]]*sparkle:edSignature="([A-Za-z0-9+/=]+)"[[:space:]]+length="([0-9]+)"[[:space:]]*$'
[[ "$SIGNATURE" =~ $pattern ]] || die "unexpected sign_update output: $SIGNATURE"
ED_SIGNATURE="${BASH_REMATCH[1]}"; LENGTH="${BASH_REMATCH[2]}"

# The private key must belong to the public key built into the app, or the app rejects the update.
status=0
swift "$ROOT/scripts/verify-update-signature.swift" "$ZIP" "$ED_SIGNATURE" "$PUBLIC_KEY" || status=$?
case "$status" in
  0) ;;
  1) die "the signature does not verify with the app's SUPublicEDKey (wrong signing key?)" ;;
  *) die "verify-update-signature.swift failed ($status): bad archive, signature or SUPublicEDKey" ;;
esac
URL="https://github.com/JK-SW/cardgate/releases/download/v$VERSION/$(basename "$ZIP")"

"$ROOT/scripts/release-notes.sh" | python3 -I -c '
import datetime, html, re, sys
version, build, min_system, url, ed_signature, length = sys.argv[1:7]

def inline(text):
    text = html.escape(text, quote=False)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    return re.sub(r"\[([^\]]+)\]\((https://[^)\s]+)\)", r"<a href=\"\2\">\1</a>", text)

# Release notes (Markdown subset of CHANGELOG.md) as HTML.
out, items, para = [], [], []
def flush():
    global items, para
    if items: out.append("<ul>" + "".join(f"<li>{inline(i)}</li>" for i in items) + "</ul>")
    if para: out.append(f"<p>{inline(chr(32).join(para))}</p>")
    items, para = [], []
for line in sys.stdin.read().splitlines():
    if line.startswith("### "):
        flush(); out.append(f"<h3>{inline(line[4:])}</h3>")
    elif line.startswith("- "):
        if para: flush()
        items.append(line[2:].strip())
    elif line.startswith("  ") and items:
        items[-1] += " " + line.strip()
    elif line.strip():
        if items: flush()
        para.append(line.strip())
    else:
        flush()
flush()
notes = "\n".join(out).replace("]]>", "]]&gt;")
date = datetime.datetime.now(datetime.timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")
print(f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>CardGate</title>
    <item>
      <title>CardGate {version}</title>
      <pubDate>{date}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{min_system}</sparkle:minimumSystemVersion>
      <description><![CDATA[{notes}]]></description>
      <enclosure url="{html.escape(url)}" length="{length}" type="application/octet-stream"
                 sparkle:edSignature="{ed_signature}"/>
    </item>
  </channel>
</rss>""")
' "$VERSION" "$BUILD_NUMBER" "$MIN_SYSTEM" "$URL" "$ED_SIGNATURE" "$LENGTH"
