#!/usr/bin/env bash
# The plan check (planning.md, "Enforcement"). It checks and reports; it
# never edits an issue body, title, field or label.
#
#   plan-check.sh issue <issue>     check one open issue; comment once
#   plan-check.sh hard-blocks       re-flag stale hard blocks
#
# issue: comments once when the issue lacks a Stage or an Owner, lacks
#   a "Done when" section, or sits deeper than $MAX_DEPTH levels (unless
#   it carries the label "depth: approved"). It does nothing when an
#   earlier plan-check comment is there, so fixing the issue ends it.
# hard-blocks: a hard block is an open blocker owned by "james" whose
#   blocked issue is ready or active. If the blocker has had no comment
#   for $HARD_BLOCK_HOURS (default 24), it gets a reminder comment, so
#   the reminder repeats once per silent day.
#
# GH_TOKEN must be set. PLAN_CHECK_DRY=1 prints instead of commenting.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

HARD_BLOCK_HOURS="${HARD_BLOCK_HOURS:-24}"
MARK_ISSUE='<!-- plan-check:issue -->'
MARK_HARD='<!-- plan-check:hard-block -->'

# post <repo> <number> <body>: comments, or prints under PLAN_CHECK_DRY.
post() {
  if [ "${PLAN_CHECK_DRY:-0}" = 1 ]; then
    printf 'WOULD COMMENT on %s#%s:\n%s\n' "$1" "$2" "$3"
  else
    gh api -X POST "repos/$1/issues/$2/comments" -f body="$3" --silent
    echo "commented on $1#$2"
  fi
}

# field <repo> <number> <name>: a field's value, empty when unset.
field() {
  gh api "repos/$1/issues/$2/issue-field-values" |
    jq -r --arg n "$3" '[.[] | select(.issue_field_name == $n)
      | .single_select_option.name] | first // empty'
}

# The comment bodies of an issue, all pages.
comment_bodies() {
  gh api --paginate "repos/$1/issues/$2/comments?per_page=100" |
    jq -r '.[].body'
}

check_issue() {
  resolve_ref "$1"
  local repo=$REF_REPO num=$REF_NUM issue state body problems="" level=1
  local parent seen=0 stage owner approved

  issue=$(gh api "repos/$repo/issues/$num")
  if [ "$(printf '%s' "$issue" | jq -r '.pull_request != null')" = true ]; then
    echo "$repo#$num is a pull request; skipped"; return 0
  fi
  state=$(printf '%s' "$issue" | jq -r .state)
  [ "$state" = open ] || { echo "$repo#$num is $state; skipped"; return 0; }

  stage=$(field "$repo" "$num" Stage)
  owner=$(field "$repo" "$num" Owner)
  [ -n "$stage" ] || problems="$problems- It has no Stage.
"
  [ -n "$owner" ] || problems="$problems- It has no Owner.
"
  body=$(printf '%s' "$issue" | jq -r '.body // ""')
  printf '%s' "$body" | grep -qi 'done when' ||
    problems="$problems- Its body has no \"Done when\" section.
"

  approved=$(printf '%s' "$issue" |
    jq -r '[.labels[]?.name] | index("depth: approved") != null')
  parent=$(printf '%s' "$issue" | jq -r '.parent_issue_url // empty')
  while [ -n "$parent" ] && [ "$seen" -lt 10 ]; do
    level=$((level + 1)); seen=$((seen + 1))
    parent=$(gh api "${parent#https://api.github.com/}" |
      jq -r '.parent_issue_url // empty')
  done
  if [ "$level" -gt "$MAX_DEPTH" ] && [ "$approved" != true ]; then
    problems="$problems- It sits at level $level; $MAX_DEPTH are allowed \
without the owner's approval. Once approved, add the label \
\"depth: approved\".
"
  fi

  if [ -z "$problems" ]; then
    echo "$repo#$num: ok"; return 0
  fi
  if comment_bodies "$repo" "$num" | grep -qF "$MARK_ISSUE"; then
    echo "$repo#$num: problems found, already reported"; return 0
  fi
  post "$repo" "$num" "$MARK_ISSUE
Plan check (planning.md in nff-agentic-workflow):

$problems
This check never edits an issue. Fix the points above and it stays \
quiet; it comments once per issue."
}

check_hard_blocks() {
  local repo n stage blockers b brepo bnum last age
  repo=$(default_repo)
  for n in $(gh api --paginate "repos/$repo/issues?state=open&per_page=100" |
    jq -r '.[] | select(.pull_request == null
      and .issue_dependencies_summary.blocked_by > 0) | .number'); do
    stage=$(field "$repo" "$n" Stage)
    case "$stage" in ready|active) ;; *) continue ;; esac
    blockers=$(gh api "repos/$repo/issues/$n/dependencies/blocked_by" |
      jq -r '.[] | select(.state == "open")
        | "\(.repository_url | sub(".*/repos/"; ""))#\(.number)"')
    for b in $blockers; do
      brepo=${b%%#*}; bnum=${b##*#}
      [ "$(field "$brepo" "$bnum" Owner)" = james ] || continue
      last=$(gh api "repos/$brepo/issues/$bnum/comments?per_page=100" |
        jq -r '[.[].created_at] | max // empty')
      [ -n "$last" ] ||
        last=$(gh api "repos/$brepo/issues/$bnum" --jq .created_at)
      age=$(jq -n --arg t "$last" '(now - ($t | fromdateiso8601)) / 3600
        | floor')
      if [ "$age" -lt "$HARD_BLOCK_HOURS" ]; then
        echo "$b: hard block, flagged $age hours ago; wait"; continue
      fi
      post "$brepo" "$bnum" "$MARK_HARD
Hard block owned by james: $repo#$n is $stage and waits on this issue. \
It has had no comment for $age hours. Please answer here, or defer it \
(set Stage to deferred) if it can wait." ||
        echo "warning: could not comment on $b" >&2
    done
  done
}

case "${1:-}" in
  issue) [ $# -eq 2 ] || die "usage: plan-check.sh issue <issue>"
    check_issue "$2" ;;
  hard-blocks) check_hard_blocks ;;
  *) die "usage: plan-check.sh issue <issue> | hard-blocks" ;;
esac
