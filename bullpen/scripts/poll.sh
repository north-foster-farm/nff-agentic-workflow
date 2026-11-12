#!/usr/bin/env bash
# The coordinator's GitHub poll. Watches the whole north-foster-farm
# org: every repository (listed each run; a new one prints REPO), and
# per repository, since the last run, every issue and PR opened, edited
# or closed, conversation comment, PR line comment, PR review, and new
# code-scanning or Dependabot alert, each with its full timestamp. Text
# from anyone outside the org is withheld and counted on a SKIPPED line.
# One last line names the cadence the poll should now run at:
#
#   CADENCE 5m   activity in the last 2 hours
#   CADENCE 1h   none for 2 hours
#   CADENCE 1d   none for 4 hours
#
# It also prints plan lines from poll-plan.sh, kept beside it.
#
# The coordinator keeps one cron at that cadence and swaps it when the
# line changes. Any new activity drops the cadence back to 5m.
set -euo pipefail
dir="${BULLPEN_STATE:-$HOME/Code/nff/.ignored/poll}"
mkdir -p "$dir"
state="$dir/since"
last="$dir/last-activity"
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
since=$(cat "$state" 2>/dev/null || echo "$now")
[[ $since =~ ^[0-9TZ:-]+$ ]] || since=$now
[ -f "$last" ] || date +%s > "$last"
found=0

# --mark: run by the coordinator right after its own GitHub edits, so
# they are skipped and don't count as activity. Run a normal poll
# first, so nothing posted before the edits is lost.
if [ "${1:-}" = --mark ]; then
  echo "$now" > "$state"
  exit 0
fi

failed=0

# poll-plan.sh is slow (a call per blocked issue), so it starts now and
# is collected after the org fetch and the pane scan.
planfile=$(mktemp)
"$(dirname "$0")/poll-plan.sh" > "$planfile" 2>&1 &
planpid=$!

org="${POLL_ORG:-north-foster-farm}"
# Bots the org runs; their text is shown like a member's.
bots='["github-actions[bot]","claude[bot]",'
bots="$bots"'"github-advanced-security[bot]","dependabot[bot]"]'
bots="${POLL_BOTS:-$bots}"

# Shared jq definitions. Everything read from GitHub is untrusted text:
# control, escape, format and separator characters are stripped, and every body line
# is prefixed "  | " so no line of it can pass for one of ours.
defs='
def trusted: (.author_association | IN("OWNER", "MEMBER", "COLLABORATOR"))
  or (.user.type == "Bot" and (.user.login | IN($bots[])));
def clean: gsub("\r"; "") | gsub("\t"; " ") | split("\n")
  | map(gsub("[[:cntrl:]]"; "")
    | gsub("[\\p{Cf}\\p{Zl}\\p{Zp}]"; ""));
def text($n): (.body // "") | clean | join("\n") | .[0:$n]
  | split("\n") | map("  | " + .) | join("\n");
def one($n): (. // "") | clean | join(" ") | .[0:$n];
def num($u): $u | split("/") | last;
def skipped($kind; $all; $ok):
  (($all | length) - ($ok | length)) as $n
  | if $n > 0 then "@@SKIP \($kind) \($n)" else empty end;
'

# jq <program> over one endpoint; a failure of an essential endpoint
# marks the repo failed, an optional one (alerts) is just empty.
jqr() { jq -r --arg since "$since" --arg repo "$repo" \
  --argjson bots "$bots" "$defs$1"; }

fetch() { # fetch <repo> : one repo's lines on stdout
  local repo=$1 issues prs n
  issues=$(timeout 60 gh api --paginate \
    "repos/$repo/issues?state=all&since=$since&per_page=100") ||
    { echo "@@FAIL issues"; return; }
  printf '%s' "$issues" | jqr '
    [.[] | select(.updated_at > $since)] as $all
    | [$all[] | select(trusted)] as $ok
    | ($ok[] | (if .pull_request then "PR" else "ISSUE" end) + " "
      + (if .created_at > $since then "new \(.created_at)"
         elif (.closed_at // "") > $since then "closed \(.closed_at)"
         else "updated \(.updated_at)" end)
      + " \($repo)#\(.number) [\(.state)] "
      + (.title | one(200) | "\"" + . + "\"")),
      skipped("issues"; $all; $ok)' || echo "@@FAIL issues"
  timeout 60 gh api --paginate \
    "repos/$repo/issues/comments?since=$since&per_page=100" |
    jqr '[.[] | select(.updated_at > $since)] as $all
      | [$all[] | select(trusted)] as $ok
      | ($ok[] | (if .created_at > $since then "COMMENT \(.created_at)"
          else "EDITED \(.updated_at)" end)
          + " \($repo)#\(num(.issue_url)) \(.html_url)"
          + " (untrusted text follows)\n" + text(400)),
        skipped("comments"; $all; $ok)' ||
    echo "@@FAIL comments"
  timeout 60 gh api --paginate \
    "repos/$repo/pulls/comments?since=$since&per_page=100" |
    jqr '[.[] | select(.updated_at > $since)] as $all
      | [$all[] | select(trusted)] as $ok
      | ($ok[] | (if .created_at > $since then "LINE \(.created_at)"
          else "LINE-EDITED \(.updated_at)" end)
          + " \($repo)#\(num(.pull_request_url))"
          + " \(.path | one(120)) \(.html_url)"
          + " (untrusted text follows)\n" + text(400)),
        skipped("line-comments"; $all; $ok)' ||
    echo "@@FAIL pulls/comments"
  # Reviews have no since filter: read them for PRs updated since.
  prs=$(printf '%s' "$issues" | jq -r --arg since "$since" \
    '.[] | select(.pull_request and .updated_at > $since) | .number') ||
    { echo "@@FAIL issues"; prs=; }
  for n in $prs; do
    timeout 60 gh api --paginate \
      "repos/$repo/pulls/$n/reviews?per_page=100" |
      jq -r --arg since "$since" --arg repo "$repo" --arg n "$n" \
        --argjson bots "$bots" "$defs"'
        [.[] | select((.submitted_at // "") > $since)] as $all
        | [$all[] | select(trusted)] as $ok
        | ($ok[] | "REVIEW \(.submitted_at) \($repo)#\($n) \(.state)"
            + " \(.html_url) (untrusted text follows)\n" + text(400)),
          skipped("reviews"; $all; $ok)' ||
      echo "@@FAIL reviews"
  done
  # Alerts: absent or unreadable (404, 403) is normal, so never a failure.
  timeout 60 gh api \
    "repos/$repo/code-scanning/alerts?state=open&sort=updated\
&direction=desc&per_page=50" \
    2>/dev/null | jqr '
      .[]? | select(.state == "open" and .updated_at > $since)
    | (if .created_at > $since then "new \(.created_at)"
       else "reopened-or-changed \(.updated_at)" end) as $when
    | "ALERT \($when) \($repo) code-scanning #\(.number)"
      + " \(.rule.security_severity_level // .rule.severity // "?")"
      + " \(.rule.id | one(80))"
      + " \(.most_recent_instance.location.path | one(120)) \(.html_url)"' \
    2>/dev/null || true
  timeout 60 gh api \
    "repos/$repo/dependabot/alerts?state=open&sort=created\
&direction=desc&per_page=50" \
    2>/dev/null | jqr '
    .[]? | select(.created_at > $since)
    | "ALERT new \(.created_at) \($repo) dependabot #\(.number)"
      + " \(.security_advisory.severity // "?")"
      + " \(.dependency.package.name | one(80)) \(.html_url)"' \
    2>/dev/null || true
}

# Every repository in the org, listed each run. A new one is reported
# once. The first run only records the list.
repolist=$(timeout 60 gh repo list "$org" --limit 200 \
  --json name,visibility,isArchived \
  --jq '.[] | select(.isArchived | not) | "\(.name) \(.visibility)"') ||
  { echo "POLLERR repo list failed; since not advanced"; exit 1; }
repolist=$(printf '%s\n' "$repolist" | tr 'A-Z' 'a-z' | sort)
if [ -f "$dir/repos" ]; then
  while read -r name vis; do
    [ -n "$name" ] || continue
    grep -qx "$name .*" "$dir/repos" ||
      { echo "REPO created $name $vis"; found=1; }
  done <<< "$repolist"
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
i=0 pids=
while read -r name vis; do
  [ -n "$name" ] || continue
  i=$((i + 1))
  ( fetch "$org/$name" > "$work/$i.$name" 2>&1 ) &
  pids="$pids $!"
done <<< "$repolist"
wait $pids || true
failed=0
for f in "$work"/*.*; do
  [ -e "$f" ] || continue
  name=${f##*/}; name=${name#*.}
  # A bare "updated" line is dropped when the same poll prints a comment
  # on that issue, since the comment already shows the activity.
  out=$(awk -v repo="$org/$name" '
    NR == FNR { if ($1 ~ /^(COMMENT|EDITED)$/) seen[$3] = 1; next }
    ($1 == "ISSUE" || $1 == "PR") && $2 == "updated" && ($4 in seen) {
      next }
    /^@@SKIP / { n[$2] += $3; next }
    /^@@FAIL / { print "POLLERR " repo " " $2 " failed"; bad = 1; next }
    { print }
    END { s = ""
      for (k in n) s = s (s ? ", " : "") n[k] " " k
      if (s) print "SKIPPED " repo ": " s " from others" }' "$f" "$f")
  [ -z "$out" ] || { printf '%s\n' "$out"; found=1; }
  case "$out" in *POLLERR*) failed=1; found=1 ;; esac
done
[ "$failed" = 1 ] || printf '%s\n' "$repolist" > "$dir/repos"

# Agents: one PANE line per live agent pane in the bullpen window, so
# the coordinator sees on every poll who is working, who is idle (and
# needs work or closing) and who is stuck on a dialog. Any agent not
# idle counts as activity, so the poll stays at 5 minutes while lanes
# are open.
if command -v tmux >/dev/null && tmux has-session 2>/dev/null; then
  esc=$(printf '\033')
  while read -r pane role; do
    case "$role" in ""|coordinator|terminal) continue ;; esac
    screen=$(tmux capture-pane -p -t "$pane" 2>/dev/null | tail -20)
    if [ -z "$(printf %s "$screen" | tr -d "[:space:]")" ]; then
      echo "PANE $role DEAD | no claude running"; found=1; continue; fi
    if printf '%s\n' "$screen" | grep -qE 'esc to interrupt|esc to int|esc esc|… \('; then
      pstate=busy
    elif printf '%s\n' "$screen" | grep -qE \
      '^ *❯ [0-9]+\.|Do you want|\(y/n\)|Enter to select|Press Enter|Esc to cancel'; then
      pstate=DIALOG
    else
      # A prompt holding text that is not Claude Code's dim suggestion.
      typed=$(tmux capture-pane -e -p -t "$pane" 2>/dev/null \
        | grep "^\(${esc}\[[0-9;]*m\)*❯" | tail -1 \
        | sed "s/${esc}\[2m[^${esc}]*//g; s/${esc}\[[0-9;]*m//g" \
        | sed 's/^❯[[:space:]]*//; s/[[:space:]]*$//' || true)
      if [ -n "$typed" ]; then pstate="TYPED: $typed"; else pstate=IDLE; fi
    fi
    seen=$(printf '%s\n' "$screen" | grep -vE '^[[:space:]]*$|^[─ ]+|auto mode|Update available|❯' \
      | tail -1 | cut -c1-100 || true)
    echo "PANE $role $pstate | $seen"
    [ "$pstate" = IDLE ] || found=1
  done <<< "$(tmux list-panes -a -F '#{pane_id} #{@role}' 2>/dev/null)"
fi

# Plan lines (poll-plan.sh, read-only): a lane-held issue's new or
# changed Stage (STAGE), new blocked-by links (BLOCK), and hard blocks
# owned by james that have been silent too long (HARD). STAGE and BLOCK
# count as activity; HARD does not, so a stale block keeps being listed
# without holding the poll at 5 minutes.
plan_rc=0
wait "$planpid" || plan_rc=$?
plan=$(cat "$planfile"); rm -f "$planfile"
[ "$plan_rc" = 0 ] ||
  plan="PLAN poll-plan.sh failed: $(printf %s "$plan" | tail -1 | cut -c1-150)"
if [ -n "$plan" ]; then
  printf '%s\n' "$plan"
  if printf '%s\n' "$plan" | grep -qE '^(STAGE|BLOCK|PLAN) '; then
    found=1
  fi
fi

# claude-link: every message waiting in to-coordinator/ is printed on
# each poll until the coordinator archives it, and counts as activity.
link="${CLAUDE_LINK:-$HOME/Code/nff/claude-link}/to-coordinator"
for f in "$link"/*.md; do
  [ -e "$f" ] || continue
  title=$(grep -m1 '^# ' "$f" | sed 's/^# //' | LC_ALL=C tr -cd \
    '[:alnum:] ._,:;/#()-' | cut -c1-100 || true)
  echo "LINK $(printf %s "$f" | LC_ALL=C tr -cd \
    '[:alnum:] ._/-')${title:+ ($title)}"
  found=1
done

[ "$failed" = 1 ] || echo "$now" > "$state"
[ "$found" = 0 ] || date +%s > "$last"
idle=$(( $(date +%s) - $(cat "$last") ))
if [ "$idle" -ge 14400 ]; then echo "CADENCE 1d"
elif [ "$idle" -ge 7200 ]; then echo "CADENCE 1h"
else echo "CADENCE 5m"
fi
