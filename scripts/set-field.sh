#!/usr/bin/env bash
# Set Stage, Owner or Kind on one or more issues, in either repository.
#
#   set-field.sh [--stage S] [--owner O] [--kind K] <issue>...
#
# Stage: spec scoped ready active "in review" done cut deferred
# Owner: james claude external
# Kind:  build decision review credential action (blockers only)
# An issue is a number, owner/repo#number or an issue URL.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

stage="" owner="" kind="" issues=()
while [ $# -gt 0 ]; do
  case "$1" in
    --stage) stage="${2:?--stage needs a value}"; shift 2 ;;
    --owner) owner="${2:?--owner needs a value}"; shift 2 ;;
    --kind) kind="${2:?--kind needs a value}"; shift 2 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) issues+=("$1"); shift ;;
  esac
done

[ ${#issues[@]} -gt 0 ] || die "name at least one issue"
[ -n "$stage$owner$kind" ] || die "give --stage, --owner or --kind"
[ -z "$stage" ] || check_value Stage "$STAGE_VALUES" "$stage"
[ -z "$owner" ] || check_value Owner "$OWNER_VALUES" "$owner"
[ -z "$kind" ] || check_value Kind "$KIND_VALUES" "$kind"

for ref in "${issues[@]}"; do
  resolve_ref "$ref"
  pairs=()
  [ -z "$stage" ] || pairs+=("$STAGE_FIELD" "$stage")
  [ -z "$owner" ] || pairs+=("$OWNER_FIELD" "$owner")
  [ -z "$kind" ] || pairs+=("$KIND_FIELD" "$kind")
  set_fields "$REF_REPO" "$REF_NUM" "${pairs[@]}"
  echo "$REF_REPO#$REF_NUM:" \
    "${stage:+stage=$stage }${owner:+owner=$owner }${kind:+kind=$kind}"
done
