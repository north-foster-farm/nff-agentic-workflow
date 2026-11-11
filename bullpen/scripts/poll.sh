#!/usr/bin/env bash
# The coordinator's GitHub poll. Prints every issue opened or edited
# and every comment posted in both repos since the last run, then one
# last line naming the cadence the poll should now run at:
#
#   CADENCE 5m   activity in the last 2 hours
#   CADENCE 1h   none for 2 hours
#   CADENCE 1d   none for 4 hours
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
[ -f "$last" ] || date +%s > "$last"
found=0

# --mark: run by the coordinator right after its own GitHub edits, so
# they are skipped and don't count as activity. Run a normal poll
# first, so nothing posted before the edits is lost.
if [ "${1:-}" = --mark ]; then
  echo "$now" > "$state"
  exit 0
fi

for repo in north-foster-farm/north-foster-farm \
  north-foster-farm/nff-dashboard; do
  out=$(timeout 60 gh api "repos/$repo/issues?state=all&since=$since&per_page=100" \
    --jq ".[] | select(.updated_at > \"$since\")
      | (if .pull_request then \"PR\" else \"ISSUE\" end) + \" \"
        + (if .created_at > \"$since\" then \"new\" else \"updated\" end)
        + \" $repo#\(.number) [\(.state)] \(.title)\"")
  [ -z "$out" ] || { printf '%s\n' "$out"; found=1; }
  out=$(timeout 60 gh api "repos/$repo/issues/comments?since=$since&per_page=100" \
    --jq ".[] | select(.updated_at > \"$since\")
      | (if .created_at > \"$since\" then \"COMMENT\" else \"EDITED\" end)
        + \" $repo#\(.issue_url | split(\"/\") | last) \(.html_url)\n\"
        + (.body | .[0:1500]) + \"\n\"")
  [ -z "$out" ] || { printf '%s\n' "$out"; found=1; }
done

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

# claude-link: every message waiting in to-coordinator/ is printed on
# each poll until the coordinator archives it, and counts as activity.
link="${CLAUDE_LINK:-$HOME/Code/nff/claude-link}/to-coordinator"
for f in "$link"/*.md; do
  [ -e "$f" ] || continue
  title=$(grep -m1 '^# ' "$f" | sed 's/^# //')
  echo "LINK $f${title:+ ($title)}"
  found=1
done

echo "$now" > "$state"
[ "$found" = 0 ] || date +%s > "$last"
idle=$(( $(date +%s) - $(cat "$last") ))
if [ "$idle" -ge 14400 ]; then echo "CADENCE 1d"
elif [ "$idle" -ge 7200 ]; then echo "CADENCE 1h"
else echo "CADENCE 5m"
fi
