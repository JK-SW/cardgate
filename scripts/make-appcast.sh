#!/usr/bin/env bash
# Signs the release archive for Sparkle and prints the update feed (appcast.xml) for it.
#
# Usage: scripts/make-appcast.sh <archive.zip> <app bundle>
# The EdDSA private key is read from the file in $SPARKLE_KEY_FILE (never from the repository).
source "$(dirname "$0")/common.sh"
ZIP="${1:?archive}"; APP="${2:?app bundle}"
[[ -f "${SPARKLE_KEY_FILE:-}" ]] || die "SPARKLE_KEY_FILE must point to the EdDSA private key"
SIGN="$PREFIX/sparkle/bin/sign_update"
[[ -x "$SIGN" ]] || die "Sparkle tools missing – run scripts/build-deps.sh sparkle"

VERSION="$(tr -d '[:space:]' <"$ROOT/VERSION")"
PLIST="$APP/Contents/Info.plist"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
MIN_SYSTEM="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST")"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")" == "$VERSION" ]] \
  || die "the app is not version $VERSION"

# The private key must belong to the public key built into the app, or the app rejects the update.
PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$PLIST" 2>/dev/null || true)"
[[ -n "$PUBLIC_KEY" ]] || die "the app has no SUPublicEDKey (app/sparkle-public-key.txt)"
DERIVED="$( { printf '302e020100300506032b657004220420' | xxd -r -p; base64 -d <"$SPARKLE_KEY_FILE"; } \
  | "$PREFIX/bin/openssl" pkey -inform DER -pubout -outform DER | tail -c 32 | base64)"
[[ "$DERIVED" == "$PUBLIC_KEY" ]] || die "the signing key does not match the app's SUPublicEDKey"

SIGNATURE="$("$SIGN" --ed-key-file "$SPARKLE_KEY_FILE" "$ZIP")"   # sparkle:edSignature="…" length="…"
URL="https://github.com/JK-SW/cardgate/releases/download/v$VERSION/$(basename "$ZIP")"

"$ROOT/scripts/release-notes.sh" | python3 -I -c '
import datetime, html, re, sys
version, build, min_system, url, signature = sys.argv[1:6]
m = re.fullmatch(r"\s*sparkle:edSignature=\"([A-Za-z0-9+/=]+)\"\s+length=\"(\d+)\"\s*", signature)
if not m:
    sys.exit("unexpected sign_update output")
ed_signature, length = m.groups()

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
' "$VERSION" "$BUILD_NUMBER" "$MIN_SYSTEM" "$URL" "$SIGNATURE"
