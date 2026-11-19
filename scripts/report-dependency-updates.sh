#!/usr/bin/env bash
# Reports the updates printed by check-dependency-updates.sh as GitHub issues (dependencies.yml):
#  - opens an issue for each new version, once (a closed issue is not opened again);
#  - closes an open issue of a version that scripts/deps.lock already pins (or a newer one);
#  - closes an open issue that newer versions of the same dependency replace, naming them.
# An issue of a dependency without updates now stays open unless deps.lock pins it: the check may
# have failed for that dependency. Needs gh with GH_REPO and GH_TOKEN, and jq.
#
# Usage: scripts/report-dependency-updates.sh UPDATES-FILE
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPS_LOCK="${DEPS_LOCK:-$ROOT/scripts/deps.lock}"   # another file only for the tests
updates="$1"
prefix="Dependency update:"

# version_le A B: version A is B or older.
version_le() { [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1)" == "$1" ]]; }

all="$(gh issue list --state all --limit 1000 --search "\"$prefix\" in:title" --json number,title,state)"

while read -r name pinned new url; do
  title="$prefix $name $new"
  if jq -e --arg title "$title" 'any(.[]; .title == $title)' <<<"$all" >/dev/null; then
    echo "Already reported: $title"
    continue
  fi
  body="$(printf '%s\n' \
    "\`scripts/deps.lock\` pins $name $pinned; upstream released $new: $url" \
    "" \
    "- [ ] Read the release notes, above all security fixes." \
    "- [ ] Update the version and SHA-256 in \`scripts/deps.lock\` (check the notes there)." \
    "- [ ] Rebuild (\`scripts/build-deps.sh\`, patches still apply) and run the tests." \
    "" \
    "Close this issue if the update is not wanted; it will not be opened again.")"
  created="$(gh issue create --title "$title" --body "$body" </dev/null)"
  echo "Opened: $created"
  # gh prints the new issue's URL, which ends with its number.
  all="$(jq --arg title "$title" --argjson number "${created##*/}" \
    '. + [{number: $number, title: $title, state: "OPEN"}]' <<<"$all")"
done <"$updates"

# reported NAME: the versions of NAME reported now, with their issues ("sdl3 3.4.22 (#5), …").
reported() {
  awk -v name="$1" '$1 == name { print $3 }' "$updates" | while read -r version; do
    number="$(jq -r --arg title "$prefix $1 $version" \
      'map(select(.title == $title)) | first | .number // empty' <<<"$all")"
    printf '%s %s%s\n' "$1" "$version" "${number:+ (#$number)}"
  done | paste -sd, - | sed 's/,/, /g'
}

jq -r --arg start "$prefix " '.[] | select(.state == "OPEN" and (.title | startswith($start)))
  | "\(.number) \(.title)"' <<<"$all" |
  while read -r number _ _ name version; do
    if awk -v name="$name" -v version="$version" '$1 == name && $3 == version { found = 1 }
      END { exit !found }' "$updates"; then
      continue
    fi
    pinned="$(awk -v name="$name" '$1 == name { print $2 }' "$DEPS_LOCK")"
    if [[ -n "$pinned" ]] && version_le "$version" "$pinned"; then
      comment="scripts/deps.lock already pins $name $pinned."
    else
      replacing="$(reported "$name")"
      [[ -n "$replacing" ]] || continue
      comment="Superseded by $replacing."
    fi
    echo "Closing #$number: $comment"
    gh issue close "$number" --comment "$comment" </dev/null
  done
