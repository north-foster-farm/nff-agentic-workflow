#!/usr/bin/env bash
# The plan lines of the coordinator's poll (planning.md). Read-only: it
# reads issues and their fields through gh api and writes nothing to
# GitHub. One line per item, in poll.sh's style:
#
#   STAGE repo#N old>new | title    a lane-held issue (one carrying a
#                                   lane: label) is new or changed Stage
#   BLOCK repo#N <- repo#M | title  a new open blocked-by link
#   HARD repo#M owner james, Nh silent | blocks repo#N (stage)
#                                   an open blocker owned by james, whose
#                                   blocked issue is ready or active, with
#                                   no comment for HARD_BLOCK_HOURS
#
# STAGE and BLOCK print only what changed since the last run, kept in
# $BULLPEN_STATE (stages, blocks); the very first run records the
# current state silently and prints one "seeded" line. HARD prints on
# every run while it holds, so the coordinator keeps chasing it. Stage
# is read again only for an issue whose updated_at changed, so a quiet
# poll costs one list call per repository plus the blocked issues.
#
# Only comments by an owner, member or collaborator count toward the
# silence clock. Titles are untrusted text: control characters are
# stripped.
#
# Environment: BULLPEN_STATE (as poll.sh), POLL_REPOS (space-separated
# owner/repo list, default both projects), HARD_BLOCK_HOURS (default 24).
set -euo pipefail
dir="${BULLPEN_STATE:-$HOME/Code/nff/.ignored/poll}"
mkdir -p "$dir"
hours="${HARD_BLOCK_HOURS:-24}"
repos="${POLL_REPOS:-north-foster-farm/north-foster-farm \
north-foster-farm/nff-dashboard}"
first=0
[ -f "$dir/stages" ] || first=1
touch "$dir/stages" "$dir/blocks"
new_stages=$(mktemp)
new_blocks=$(mktemp)
trap 'rm -f "$new_stages" "$new_blocks"' EXIT

api() { timeout 60 gh api "$@"; }

# fieldval <fields-json> <name>: one field's option name, else empty.
fieldval() {
  printf '%s' "$1" | jq -r --arg n "$2" '[.[]
    | select(.issue_field_name == $n) | .single_select_option.name]
    | first // empty'
}

# The snapshot (tab-separated: key, stage, updated_at) for a key, as
# "stage<TAB>updated_at", else empty. A stage can contain a space.
old_value() { # old_value <key> <file>
  awk -F'\t' -v k="$1" '$1 == k { print $2 "\t" $3; exit }' "$2"
}

for repo in $repos; do
  rows=$(api --paginate "repos/$repo/issues?state=open&per_page=100" |
    jq -c '.[] | select(.pull_request == null) | {n: .number,
      t: (.title[0:60] | gsub("[[:cntrl:]]"; "")), u: .updated_at,
      lane: ([.labels[]?.name | select(startswith("lane:"))] | length > 0),
      b: (.issue_dependencies_summary.blocked_by // 0)}')
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    n=$(printf '%s' "$row" | jq -r .n)
    t=$(printf '%s' "$row" | jq -r .t)
    upd=$(printf '%s' "$row" | jq -r .u)
    lane=$(printf '%s' "$row" | jq -r .lane)
    nb=$(printf '%s' "$row" | jq -r .b)
    key="$repo#$n"
    stage=""
    if [ "$lane" = true ]; then
      was=$(old_value "$key" "$dir/stages")
      was_stage=${was%%$'\t'*}
      was_upd=${was#*$'\t'}
      if [ -n "$was" ] && [ "$was_upd" = "$upd" ]; then
        stage=$was_stage
      else
        stage=$(fieldval "$(api "repos/$repo/issues/$n/issue-field-values")" \
          Stage)
        stage="${stage:-none}"
      fi
      printf '%s\t%s\t%s\n' "$key" "$stage" "$upd" >> "$new_stages"
      if [ "$first" = 1 ]; then
        :
      elif [ -z "$was" ]; then
        echo "STAGE $key $stage | $t"
      elif [ "$was_stage" != "$stage" ]; then
        echo "STAGE $key $was_stage>$stage | $t"
      fi
    fi
    [ "$nb" -gt 0 ] || continue
    if [ "$lane" != true ]; then
      stage=$(fieldval "$(api "repos/$repo/issues/$n/issue-field-values")" \
        Stage)
    fi
    for b in $(api "repos/$repo/issues/$n/dependencies/blocked_by" |
      jq -r '.[] | select(.state == "open")
        | "\(.repository_url | sub(".*/repos/"; ""))#\(.number)"'); do
      echo "$key<-$b" >> "$new_blocks"
      if [ "$first" = 0 ] && ! grep -qxF "$key<-$b" "$dir/blocks"; then
        echo "BLOCK $key <- $b | $t"
      fi
      case "$stage" in ready|active) ;; *) continue ;; esac
      brepo=${b%%#*}; bnum=${b##*#}
      owner=$(fieldval "$(api "repos/$brepo/issues/$bnum/issue-field-values")" \
        Owner)
      [ "$owner" = james ] || continue
      last=$(api "repos/$brepo/issues/$bnum/comments?per_page=100" |
        jq -r '[.[] | select(.user.login == "github-actions[bot]"
          or (.author_association
            | IN("OWNER", "MEMBER", "COLLABORATOR")))
          | .created_at] | max // empty')
      [ -n "$last" ] ||
        last=$(api "repos/$brepo/issues/$bnum" --jq .created_at)
      age=$(jq -n --arg t "$last" \
        '(now - ($t | fromdateiso8601)) / 3600 | floor')
      [ "$age" -ge "$hours" ] || continue
      echo "HARD $b owner james, ${age}h silent | blocks $key ($stage)"
    done
  done <<< "$rows"
done

if [ "$first" = 1 ]; then
  echo "STAGE seeded: $(awk 'END { print NR }' "$new_stages") lane-held" \
    "issues, $(awk 'END { print NR }' "$new_blocks") open blocked-by links"
fi
mv "$new_stages" "$dir/stages"
mv "$new_blocks" "$dir/blocks"
