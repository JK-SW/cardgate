#!/usr/bin/env bash
# Assembles a self-contained FreeRDP helper from $BUILD/prefix into $BUILD/helper, using the
# same layout as inside the app bundle (Contents/...):
#   Helpers/sdl-freerdp          the RDP client
#   Frameworks/*.dylib           every non-system library it needs
# All install names are rewritten to @rpath, every file is ad-hoc signed.
source "$(dirname "$0")/common.sh"

[[ -x "$PREFIX/bin/sdl-freerdp" ]] || die "run scripts/build-deps.sh first"

rm -rf "$HELPER"
mkdir -p "$HELPER/Helpers" "$HELPER/Frameworks" "$HELPER/PlugIns"

is_system() { [[ "$1" == /usr/lib/* || "$1" == /System/* ]]; }

# resolve REF FROM_FILE -> absolute path of a referenced library inside $PREFIX
resolve() {
  local ref="$1" base; base="$(basename "$ref")"
  case "$ref" in
    "$PREFIX"/*) echo "$ref" ;;
    @rpath/* | @loader_path/* | @executable_path/*)
      [[ -e "$PREFIX/lib/$base" ]] && echo "$PREFIX/lib/$base" || die "cannot resolve $ref" ;;
    *) die "unexpected non-system dependency: $ref (Homebrew leak?)" ;;
  esac
}

deps_of() { otool -L "$1" | tail -n +2 | awk '{print $1}'; }

# copy_closure FILE: copy every non-system dependency of FILE (recursively) into Frameworks
copy_closure() {
  local ref target dest
  while read -r ref; do
    is_system "$ref" && continue
    dest="$HELPER/Frameworks/$(basename "$ref")"
    [[ "$(basename "$ref")" == "$(basename "$1")" ]] && continue   # own install name
    [[ -e "$dest" ]] && continue
    target="$(resolve "$ref")"
    cp -L "$target" "$dest"; chmod u+w "$dest"
    copy_closure "$dest"
  done < <(deps_of "$1")
}

# fix FILE RPATH: rewrite install names/rpaths of one Mach-O
fix() {
  local f="$1" rpath="$2" ref r
  if [[ "$f" == *.dylib ]]; then install_name_tool -id "@rpath/$(basename "$f")" "$f"; fi
  while read -r ref; do
    is_system "$ref" && continue
    [[ "$ref" == "@rpath/$(basename "$ref")" ]] && continue
    install_name_tool -change "$ref" "@rpath/$(basename "$ref")" "$f"
  done < <(deps_of "$f")
  while read -r r; do
    install_name_tool -delete_rpath "$r" "$f"
  done < <(otool -l "$f" | awk '/LC_RPATH/{getline; getline; print $2}')
  install_name_tool -add_rpath "$rpath" "$f"
}

log "Collecting files"
cp "$PREFIX/bin/sdl-freerdp" "$HELPER/Helpers/"
# FreeRDP may load channel/codec plugins at runtime
if compgen -G "$PREFIX/lib/freerdp3/*.dylib" >/dev/null; then
  mkdir -p "$HELPER/PlugIns/freerdp3"; cp -L "$PREFIX"/lib/freerdp3/*.dylib "$HELPER/PlugIns/freerdp3/"
fi
chmod -R u+w "$HELPER"

while IFS= read -r -d '' f; do copy_closure "$f"; done \
  < <(find "$HELPER/Helpers" "$HELPER/PlugIns" -type f -print0)

log "Rewriting install names"
fix "$HELPER/Helpers/sdl-freerdp" "@executable_path/../Frameworks"
for f in "$HELPER"/Frameworks/*.dylib; do fix "$f" "@loader_path"; done
while IFS= read -r -d '' f; do
  rel="$(python3 -c 'import os,sys;print(os.path.relpath(sys.argv[1],os.path.dirname(sys.argv[2])))' \
    "$HELPER/Frameworks" "$f")"
  fix "$f" "@loader_path/$rel"
done < <(find "$HELPER/PlugIns" -type f -print0)

log "Ad-hoc signing"
find "$HELPER" -type f \( -name '*.dylib' -o -name '*.so' \) -exec codesign --force -s - {} \; 2>/dev/null
codesign --force -s - "$HELPER/Helpers/sdl-freerdp"

"$ROOT/scripts/check-helper.sh"
log "Helper ready in $HELPER ($(du -sh "$HELPER" | cut -f1))"
