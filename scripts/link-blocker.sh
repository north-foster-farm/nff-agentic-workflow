#!/usr/bin/env bash
# Link a blocker: the first issue is blocked by the second. The two may
# be in different repositories of the organization.
#
#   link-blocker.sh <blocked-issue> <blocker-issue>
#   link-blocker.sh --remove <blocked-issue> <blocker-issue>
#
# A blocker is an owned issue (planning.md): set its Owner and Kind
# with set-field.sh.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

remove=0
if [ "${1:-}" = --remove ]; then remove=1; shift; fi
[ $# -eq 2 ] || die "usage: link-blocker.sh [--remove] <blocked> <blocker>"

resolve_ref "$1"; blocked_repo=$REF_REPO; blocked_num=$REF_NUM
resolve_ref "$2"; blocker_repo=$REF_REPO; blocker_num=$REF_NUM
[ "$blocked_repo#$blocked_num" != "$blocker_repo#$blocker_num" ] ||
  die "an issue cannot block itself"

blocker_id=$(issue_id "$blocker_repo" "$blocker_num")
path="repos/$blocked_repo/issues/$blocked_num/dependencies/blocked_by"

if [ "$remove" = 1 ]; then
  gh api -X DELETE "$path/$blocker_id" --silent
  echo "$blocked_repo#$blocked_num no longer blocked by" \
    "$blocker_repo#$blocker_num"
else
  gh api -X POST "$path" -F issue_id="$blocker_id" --silent
  echo "$blocked_repo#$blocked_num blocked by $blocker_repo#$blocker_num"
fi
