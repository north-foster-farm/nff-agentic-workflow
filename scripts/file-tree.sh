#!/usr/bin/env bash
# File a tree of issues under a parent, as sub-issues, in either
# repository.
#
#   file-tree.sh [--dry-run] [--allow-deep] [--parent-level N]
#                <parent-issue> <tree.json>
#
# tree.json is an array of nodes. Every key but title is optional:
#
#   { "title": "...", "body": "...",
#     "type": "Feature|Task|Bug",   (Feature if it has children, else Task)
#     "repo": "owner/name",         (default: the parent's repository)
#     "stage": "ready", "owner": "claude", "kind": "build",
#     "labels": ["needs: qa"], "milestone": "Next release",
#     "children": [ ...nodes... ] }
#
# The parent sits at level N (default 1, a release issue). The tree may
# reach three levels; a deeper one needs the owner's approval, then
# --allow-deep. Every value is checked before anything is created.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

dry=0 deep=0 level=1 pos=()
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1; shift ;;
    --allow-deep) deep=1; shift ;;
    --parent-level) level="${2:?--parent-level needs a number}"; shift 2 ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) pos+=("$1"); shift ;;
  esac
done
[ ${#pos[@]} -eq 2 ] || die "usage: file-tree.sh [options] <parent> <tree.json>"
tree="${pos[1]}"
[ -f "$tree" ] || die "no such file: $tree"
jq -e 'type == "array" and length > 0' "$tree" >/dev/null ||
  die "$tree must be a non-empty JSON array"
jq -e 'def ok: (.title | type) == "string" and (.title | length) > 0
    and all(.children[]?; ok);
  all(.[]; ok)' "$tree" >/dev/null ||
  die "every node needs a non-empty title"

# Checks first, so a bad tree files nothing.
depth=$(jq 'def d: 1 + ([.children[]? | d] | max // 0);
  [.[] | d] | max' "$tree")
if [ $((level + depth)) -gt "$MAX_DEPTH" ] && [ "$deep" = 0 ]; then
  die "the tree would reach level $((level + depth)); three levels are" \
    "allowed without the owner's approval (then pass --allow-deep)"
fi
collect() {
  jq -r "[.. | objects | select(has(\"$1\")) | .$1] | unique | .[]" "$tree"
}
check_all() { # check_all <label> <allowed> <key>
  local v
  while IFS= read -r v; do
    [ -z "$v" ] || check_value "$1" "$2" "$v"
  done <<< "$(collect "$3")"
}
check_all Stage "$STAGE_VALUES" stage
check_all Owner "$OWNER_VALUES" owner
check_all Kind "$KIND_VALUES" kind
check_all Type "$TYPE_VALUES" type

resolve_ref "${pos[0]}"
parent_repo=$REF_REPO
parent_num=$REF_NUM

# file_node <node-json> <parent repo> <parent number> <level>
file_node() {
  local node="$1" prepo="$2" pnum="$3" lvl="$4"
  local title body repo type kids nkids ms num id label pad args=()
  local stage owner kind pairs=()

  title=$(printf '%s' "$node" | jq -r .title)
  body=$(printf '%s' "$node" | jq -r '.body // ""')
  repo=$(printf '%s' "$node" | jq -r '.repo // empty')
  [ -n "$repo" ] || repo=$prepo
  kids=$(printf '%s' "$node" | jq -c '.children // []')
  nkids=$(printf '%s' "$kids" | jq length)
  type=$(printf '%s' "$node" | jq -r '.type // empty')
  if [ -z "$type" ]; then
    if [ "$nkids" -gt 0 ]; then type=Feature; else type=Task; fi
  fi
  stage=$(printf '%s' "$node" | jq -r '.stage // empty')
  owner=$(printf '%s' "$node" | jq -r '.owner // empty')
  kind=$(printf '%s' "$node" | jq -r '.kind // empty')
  ms=$(printf '%s' "$node" | jq -r '.milestone // empty')
  pad=$(printf '%*s' $(((lvl - 1) * 2)) '')

  if [ "$nkids" -eq 0 ] && [ "$type" = Task ] &&
    ! printf '%s' "$body" | grep -qi 'done when'; then
    echo "warning: '$title' has no \"Done when\" section" >&2
  fi

  if [ "$dry" = 1 ]; then
    echo "${pad}L$lvl [$repo] $type: $title"
    num=0
  else
    args=(-f "title=$title" -f "body=$body" -f "type=$type")
    while IFS= read -r label; do
      [ -z "$label" ] || args+=(-f "labels[]=$label")
    done <<< "$(printf '%s' "$node" | jq -r '.labels[]?')"
    [ -z "$ms" ] || args+=(-F "milestone=$(milestone_number "$repo" "$ms")")
    local resp
    resp=$(gh api -X POST "repos/$repo/issues" "${args[@]}")
    num=$(printf '%s' "$resp" | jq -r .number)
    id=$(printf '%s' "$resp" | jq -r .id)
    gh api -X POST "repos/$prepo/issues/$pnum/sub_issues" \
      -F sub_issue_id="$id" --silent
    [ -z "$stage" ] || pairs+=("$STAGE_FIELD" "$stage")
    [ -z "$owner" ] || pairs+=("$OWNER_FIELD" "$owner")
    [ -z "$kind" ] || pairs+=("$KIND_FIELD" "$kind")
    set_fields "$repo" "$num" ${pairs[@]+"${pairs[@]}"}
    echo "${pad}L$lvl $repo#$num $type: $title"
  fi

  local i
  for ((i = 0; i < nkids; i++)); do
    file_node "$(printf '%s' "$kids" | jq -c ".[$i]")" "$repo" "$num" \
      $((lvl + 1))
  done
}

count=$(jq length "$tree")
for ((n = 0; n < count; n++)); do
  file_node "$(jq -c ".[$n]" "$tree")" "$parent_repo" "$parent_num" \
    $((level + 1))
done
