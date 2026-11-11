#!/usr/bin/env bash
# Make the shared labels (labels.json) exist, with their colors and
# descriptions, in each repository named. It creates what is missing and
# updates what differs; it never deletes a label. Per-repository labels
# such as lane: ones are left alone.
#
#   sync-labels.sh [--dry-run] <owner/repo>...
set -euo pipefail
. "$(dirname "$0")/lib.sh"

dry=0 repos=()
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1; shift ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) repos+=("$1"); shift ;;
  esac
done
[ ${#repos[@]} -gt 0 ] || die "name at least one owner/repo"
list="$(dirname "$0")/../labels.json"

for repo in "${repos[@]}"; do
  case "$repo" in */*) ;; *) die "not owner/repo: $repo" ;; esac
  have=$(gh api --paginate "repos/$repo/labels?per_page=100" |
    jq -c '[.[] | {name, color, description}]')
  count=$(jq length "$list")
  for ((i = 0; i < count; i++)); do
    name=$(jq -r ".[$i].name" "$list")
    color=$(jq -r ".[$i].color" "$list")
    desc=$(jq -r ".[$i].description" "$list")
    same=$(printf '%s' "$have" | jq --arg n "$name" --arg c "$color" \
      --arg d "$desc" 'any(.[]; .name == $n and .color == $c
        and (.description // "") == $d)')
    if [ "$same" = true ]; then
      echo "$repo: '$name' ok"
    elif [ "$dry" = 1 ]; then
      echo "$repo: '$name' would be created or updated"
    else
      gh label create "$name" -R "$repo" -c "$color" -d "$desc" --force \
        >/dev/null
      echo "$repo: '$name' synced"
    fi
  done
done
