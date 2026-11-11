#!/usr/bin/env bash
# Shared by the planning helpers. Source it; never run it.
#
# An issue reference is any of:
#   123                                   in the default repository
#   owner/repo#123
#   https://github.com/owner/repo/issues/123
# The default repository is $NFF_REPO, else the repository of the
# current directory.

# The organization's issue fields (planning.md). Ids are org-wide.
STAGE_FIELD=49749062
OWNER_FIELD=49749063
KIND_FIELD=49749064

STAGE_VALUES='spec
scoped
ready
active
in review
done
cut
deferred'
OWNER_VALUES='james
claude
external'
KIND_VALUES='build
decision
review
credential
action'
TYPE_VALUES='Feature
Task
Bug'

# How many levels the tree may have without the owner's approval.
MAX_DEPTH=3

die() { echo "$(basename "$0"): $*" >&2; exit 1; }

default_repo() {
  if [ -n "${NFF_REPO:-}" ]; then
    printf '%s\n' "$NFF_REPO"
  else
    gh repo view --json nameWithOwner --jq .nameWithOwner
  fi
}

# Sets REF_REPO and REF_NUM from an issue reference.
resolve_ref() {
  local ref="$1"
  case "$ref" in
    https://github.com/*/issues/*)
      REF_REPO=$(printf '%s' "$ref" | cut -d/ -f4,5)
      REF_NUM=${ref##*/}
      ;;
    *#*)
      REF_REPO=${ref%%#*}
      REF_NUM=${ref##*#}
      ;;
    *)
      REF_REPO=$(default_repo)
      REF_NUM=$ref
      ;;
  esac
  case "$REF_REPO" in
    */*) ;;
    *) die "bad repository in reference: $ref" ;;
  esac
  case "$REF_NUM" in
    ''|*[!0-9]*) die "bad issue number in reference: $ref" ;;
  esac
}

# True when $2 is one of the newline-separated values in $1.
in_list() {
  printf '%s\n' "$1" | grep -Fxq -- "$2"
}

# Dies unless the value is allowed: check_value Stage "$STAGE_VALUES" v
check_value() {
  in_list "$2" "$3" ||
    die "$1 must be one of: $(printf '%s' "$2" | tr '\n' ',' |
      sed 's/,/, /g; s/, $//') (got '$3')"
}

# The database id the dependency and sub-issue APIs take.
issue_id() {
  gh api "repos/$1/issues/$2" --jq .id
}

# Sets a single-select field on an issue: set_fields repo num
# field_id value [field_id value...]. One call; values are option
# names, which GitHub matches exactly.
set_fields() {
  local repo="$1" num="$2"
  shift 2
  [ $# -gt 0 ] || return 0
  jq -nc '$ARGS.positional as $p
    | {issue_field_values: [range(0; $p | length; 2) as $i
      | {field_id: ($p[$i] | tonumber), value: $p[$i + 1]}]}' \
    --args "$@" |
    gh api -X POST "repos/$repo/issues/$num/issue-field-values" \
      --input - --silent
}

# The level of an issue in the tree: 1 for a root, 2 for its child,
# and so on, read from its real chain of parents.
issue_level() {
  local url level=1 n=0
  url=$(gh api "repos/$1/issues/$2" --jq '.parent_issue_url // empty')
  while [ -n "$url" ] && [ "$n" -lt 10 ]; do
    case "$url" in
      https://api.github.com/repos/*) ;;
      *) die "unexpected parent URL: $url" ;;
    esac
    level=$((level + 1)); n=$((n + 1))
    url=$(gh api "${url#https://api.github.com/}" \
      --jq '.parent_issue_url // empty')
  done
  printf '%s\n' "$level"
}

# True when the body has a "Done when" heading.
has_done_when() {
  printf '%s\n' "$1" | grep -qiE '^#{1,6}[[:space:]]+done when'
}

# The number of an open milestone, by title, in a repository.
milestone_number() {
  local n
  n=$(gh api "repos/$1/milestones?state=open&per_page=100" |
    jq -r --arg t "$2" '.[] | select(.title == $t) | .number')
  [ -n "$n" ] || die "no open milestone '$2' in $1"
  printf '%s\n' "$n"
}
