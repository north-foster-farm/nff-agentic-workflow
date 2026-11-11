#!/usr/bin/env bash
# Move issues to the next milestone (cutting scope, planning.md).
#
#   move-milestone.sh [--to TITLE] <issue>...
#
# TITLE defaults to "Next release". Each issue moves to the open
# milestone of that title in its own repository, so one call can move
# issues of both repositories.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

to="Next release" issues=()
while [ $# -gt 0 ]; do
  case "$1" in
    --to) to="${2:?--to needs a title}"; shift 2 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) issues+=("$1"); shift ;;
  esac
done
[ ${#issues[@]} -gt 0 ] || die "name at least one issue"

for ref in "${issues[@]}"; do
  resolve_ref "$ref"
  number=$(milestone_number "$REF_REPO" "$to")
  gh api -X PATCH "repos/$REF_REPO/issues/$REF_NUM" \
    -F milestone="$number" --silent
  echo "$REF_REPO#$REF_NUM -> $to"
done
