#!/usr/bin/env bash
# The bullpen: agents in tmux panes, in the tmux session
# "northfosterfarm.com", across three windows (James, 2026-10-22):
#
#   pm   the coordinator (top) over James's terminal (bottom), 50/50;
#        the liaison, when open, splits the top half beside the
#        coordinator, leaving the terminal full width
#   dev  every implementer, plus one terminal
#   qa   every reviewer, plus one terminal
#
# dev and qa are created at start and kept open with no agents. Their
# panes form as uniform a grid as fits, each cell as near square as
# can be (a character is about twice as tall as it is wide), wide and
# short over tall and narrow when square can't be had; the terminal is
# last. A pane whose agent is blocked or waiting on input rings the
# bell (a Notification hook in sandbox.json; tmux monitor-bell).
#
#   bullpen.sh start [role...]   from the coordinator's pane: finds or
#                                makes the session, moves the
#                                coordinator's window into it as pm,
#                                makes dev and qa, opens the roles named
#   bullpen.sh close role...     ends finished agents and kills their panes
#   bullpen.sh recolor           relabels every pane and gives each live
#                                agent a color no other pane wears
#   bullpen.sh hire role...      opens roles in their class's window
#   bullpen.sh respawn role...   restarts idle roles in their own panes
#   bullpen.sh prepare role...   only makes their folders ready
#   bullpen.sh settle pane...    sets prompt colors, turns on Remote Control
#   bullpen.sh layout            adds missing windows and terminals and
#                                lays every window out again
#
# Each pane is titled with its role (@role) and colored by it. Config:
# ~/Code/nff/bullpen (roster, common.md, roles/). The workflow:
# ~/Code/nff/docs/multi-agent-workflow.md.
set -euo pipefail

home="$HOME/Code/nff"
# Overridable for a dry run: BULLPEN_DIR (config), BULLPEN_LANES
# (folders), BULLPEN_CLAUDE (what each pane runs instead of claude).
pen="${BULLPEN_DIR:-$home/bullpen}"
lanes="${BULLPEN_LANES:-$home/lanes}"
claude_bin="${BULLPEN_CLAUDE:-claude}"
self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
site="$home/north-foster-farm"
roster="$pen/roster"
session_name="${BULLPEN_SESSION:-northfosterfarm.com}"
terminal_color=yellow  # reserved: no agent may wear it

die() { echo "bullpen: $*" >&2; exit 1; }

# James's pool (2026-10-20): the coordinator, at most 3 implementers
# and at most 2 reviewers, plus the liaison only when he asks for it.
# Close one (bullpen.sh close) before opening another of its class.
impl_cap="${BULLPEN_IMPL_CAP:-3}"
review_cap="${BULLPEN_REVIEW_CAP:-2}"

# A role's class from the roster: impl, review or liaison.
class_of() {
  awk -v r="$1" '$1 == r { print $2; exit }' "$roster"
}

# True when the pane runs a Claude session (claude, or zsh -c claude).
pane_live() {
  local pid k
  pid=$(tmux display -p -t "$1" '#{pane_pid}')
  pgrep -P "$pid" -x claude >/dev/null && return 0
  for k in $(pgrep -P "$pid"); do
    pgrep -P "$k" -x claude >/dev/null && return 0
  done
  return 1
}

# Live agents of one class.
live_agents() {
  local n=0 pane role
  while read -r pane role; do
    [ "$(class_of "$role")" = "$1" ] || continue
    pane_live "$pane" && n=$((n + 1))
  done < <(tmux list-panes -a -F '#{pane_id} #{@role}' |
    awk 'NF == 2')
  echo "$n"
}

# Dies when starting one more agent would pass its class's cap.
check_cap() {
  local class n cap
  class=$(class_of "$1")
  case "$class" in
    impl) cap=$impl_cap ;;
    review) cap=$review_cap ;;
    *) return 0 ;;
  esac
  n=$(live_agents "$class")
  [ "$n" -lt "$cap" ] ||
    die "cap: $n $class agents already live (limit $cap); close one before starting $1"
}

# The roster line for a role: "kind color flags...".
line_for() {
  awk -v r="$1" '$1 == r { $1 = ""; sub(/^ +/, ""); print; exit }' \
    "$roster"
}

folder_for() {
  local role="$1" kind="$2"

  case "$kind" in
    path=*) local p="${kind#path=}"; echo "${p/#\~/$HOME}" ;;
    *) echo "$lanes/$role" ;;
  esac
}

# The folder, its notes folder and its standing instructions.
prepare() {
  local role="$1" kind="$2" dir="$3"

  case "$kind" in
    site)
      if [ ! -d "$dir" ]; then
        git -C "$site" fetch -q origin
        if git -C "$site" show-ref -q --verify "refs/heads/lane/$role"; then
          git -C "$site" worktree add -q "$dir" "lane/$role"
        else
          git -C "$site" worktree add -q -b "lane/$role" "$dir" \
            origin/staging
        fi
      fi
      ;;
    *) mkdir -p "$dir" ;;
  esac
  mkdir -p "$dir/.ignored"

  printf '%s\n' \
      "# You are the $role agent of the bullpen" \
      "" \
      "Your brief: ~/Code/nff/bullpen/roles/$role.md. The shared rules:" \
      "~/Code/nff/bullpen/common.md. Read both before anything else, and" \
      "again after a /clear." \
      "" \
      "Your notes folder is .ignored/ in this folder. Your resume file is" \
      ".ignored/resume.md: the clear-resume skill saves there, never at" \
      "the repo root. Files you make and files you're handed live there." \
      "" \
      "Questions for James go to the coordinator (or the liaison, when" \
      "one is running), never to James. Report to the coordinator when" \
      "your work is done; it reviews, lands and closes your session." \
      > "$dir/CLAUDE.local.md"
}

# What the pane runs: the agent (dependencies first for a worktree),
# then a shell, so the pane stays open when the agent exits.
command_for() {
  local role="$1" kind="$2" dir="$3" flags="$4" prompt
  local -a fargs=()

  # sandbox.json and shims/ are private to each machine and required:
  # they hold the permission settings and the browser guard.
  [ -f "$pen/sandbox.json" ] ||
    die "missing $pen/sandbox.json (private, required; see README)"
  [ -d "$pen/shims" ] ||
    die "missing $pen/shims (private, required; see README)"

  if [ -f "$dir/.ignored/resume.md" ]; then
    # The resume says where the lane stopped; answers.md often holds
    # newer work written after it parked. Lanes that read only the
    # resume sat idle on new work.
    prompt="resume from .ignored/resume.md, then read .ignored/answers.md and .ignored/next.md"
    prompt="$prompt: anything in it newer than your resume is your work"
    prompt="$prompt now. Start on it without waiting to be asked."
  else
    prompt="$(cat "$pen/roles/$role.md")"
    # Answers written to a lane with no resume were skipped (map,
    # 2026-10-24): they come after the brief and take precedence.
    if [ -f "$dir/.ignored/answers.md" ]; then
      prompt="$prompt

Then read .ignored/answers.md: anything in it is newer than this brief
and is your work now, ahead of the brief's own."
    fi
  fi

  local deps=""

  [ "$kind" = site ] && deps='[ -d node_modules ] || npm ci --silent; '

  # The coordinator's notes and memory are its own. A role with its own
  # deny list names them there instead, since a second
  # --disallowedTools could replace the first.
  # Each flag is quoted with %q below, so none is re-read by the shell.
  read -ra fargs <<< "$flags" || true
  if [[ " ${fargs[*]-} " != *" --disallowedTools "* ]]; then
    fargs+=(--disallowedTools "Read(~/Code/nff/.ignored/**)"
      "Read(~/.claude/projects/-Users-james-Code-nff/memory/**)")
  fi

  # The prompt goes before the flags: --disallowedTools takes every
  # argument after it, and would swallow a prompt placed last.
  # sandbox.json keeps the read denies on James's personal folders; its
  # Bash sandbox is off (James, 2026-09-28: it caused more faults than
  # it prevented).
  # shims/ first on PATH, and BROWSER and GH_BROWSER at its `open`: no
  # agent's tool can open a page in James's browser (James, 2026-10-24).
  local shim="$pen/shims"
  printf 'export PATH=%q:"$PATH" BROWSER=%q GH_BROWSER=%q; ' \
    "$shim" "$shim/open" "$shim/open"
  printf '%s%s -n %q %q --settings %q' \
    "$deps" "$claude_bin" "$role" "$prompt" "$pen/sandbox.json"
  printf ' %q' "${fargs[@]}"
  printf '; exec "$SHELL"'
}

# The bullpen's session, by id: a "." in a tmux target means a pane, so
# "northfosterfarm.com" can't be used as a target itself.
session_id() {
  tmux list-sessions -F '#{session_id}|#{session_name}' |
    awk -F'|' -v s="$session_name" '$2 == s { print $1; exit }'
}

# The session, made with a dev window when it doesn't exist.
ensure_session() {
  local sid
  sid=$(session_id)
  if [ -z "$sid" ]; then
    tmux new-session -d -s "$session_name" -n dev -c "$home"
    sid=$(session_id)
    style_terminal "$(tmux list-panes -t "$sid:dev" -F '#{pane_id}' |
      head -1)"
  fi
  echo "$sid"
}

# A window of the session by name (pm, dev, qa).
window_named() {
  local sid
  sid=$(session_id)
  [ -n "$sid" ] || return 0
  tmux list-windows -t "$sid" -F '#{window_id} #{window_name}' |
    awk -v n="$1" '$2 == n { print $1; exit }'
}

# dev or qa, made when missing; its first pane is its terminal.
ensure_window() {
  local sid="$1" name="$2" w pane
  w=$(window_named "$name")
  if [ -z "$w" ]; then
    pane=$(tmux new-window -d -P -F '#{pane_id}' -t "$sid:" -n "$name" \
      -c "$home")
    style_terminal "$pane"
    w=$(window_named "$name")
  fi
  style_window "$w"
  open_terminal "$w"
  echo "$w"
}

# The window a role opens in, by its class.
window_for() {
  case "$(class_of "$1")" in
    impl) window_named dev ;;
    review) window_named qa ;;
    *) window_named pm ;;
  esac
}

# Every bullpen pane, "pane role", across the session's windows.
session_panes() {
  local sid
  sid=$(session_id)
  [ -n "$sid" ] || return 0
  tmux list-panes -s -t "$sid" -F '#{pane_id} #{@role}'
}

# "left top height width pane" for every pane in the window.
panes() {
  tmux list-panes -t "$1" \
    -F '#{pane_left} #{pane_top} #{pane_height} #{pane_width} #{pane_id}'
}

# Pane ids in the order the window's layout fills them. pm: the
# coordinator, the liaison, then the terminal. dev and qa: agents in
# roster order, anything unknown, then the terminal last. A pane's role
# is its @role, else its title less the marks Claude Code puts first.
ordered_panes() {
  local w="$1" first last
  if [ "$(tmux display -p -t "$w" '#{window_name}')" = pm ]; then
    first="coordinator liaison terminal"
  else
    first=""
  fi
  tmux list-panes -t "$w" -F '#{pane_id}|#{@role}|#{pane_title}' |
    awk -F'|' -v first="$first" -v roles="$(roster_roles | tr '\n' ' ')" '
      BEGIN {
        n = split(first, l, " ")
        for (i = 1; i <= n; i++) rank[l[i]] = i
        m = split(roles, r, " ")
        for (i = 1; i <= m; i++) if (!(r[i] in rank)) rank[r[i]] = 100 + i
        if (!("terminal" in rank)) rank["terminal"] = 9000
      }
      {
        role = $2
        if (role == "") { role = tolower($3); sub(/^[^a-z]+/, "", role) }
        k = (role in rank) ? rank[role] : 1000 + NR
        printf "%05d %s %s\n", k, $1, role
      }' | sort -n
}

# Lays one window out. tmux fills a layout's cells with the window's
# panes in their list order, so the panes are first swapped into order.
relayout() {
  local w="$1" ordered want cur i=1 width height ids roles layout name

  [ -n "$w" ] || return 0
  ordered=$(ordered_panes "$w")
  for want in $(echo "$ordered" | awk '{ print $2 }'); do
    cur=$(tmux list-panes -t "$w" -F '#{pane_id}' | sed -n "${i}p")
    [ "$cur" = "$want" ] || tmux swap-pane -d -s "$want" -t "$cur"
    i=$(( i + 1 ))
  done

  name=$(tmux display -p -t "$w" '#{window_name}')
  width=$(tmux display -p -t "$w" '#{window_width}')
  height=$(tmux display -p -t "$w" '#{window_height}')
  ids=$(tmux list-panes -t "$w" -F '#{pane_id}' | tr -d '%' | tr '\n' ' ')
  roles=$(echo "$ordered" | awk '{ print $3 }' | tr '\n' ' ')

  layout=$(awk -v W="$width" -v H="$height" -v ids="$ids" \
    -v roles="$roles" -v name="$name" '
    function cell(w, h, x, y, k) { return w "x" h "," x "," y "," id[k] }
    # One row of c panes from id[start], full width, at y.
    function row(y, h, c, start,    s, i, x, ww) {
      if (c == 1) return cell(W, h, 0, y, start)
      x = 0; s = ""
      for (i = 1; i <= c; i++) {
        ww = (i == c) ? W - x : int((W - (c - 1)) / c)
        s = s (i > 1 ? "," : "") cell(ww, h, x, y, start + i - 1)
        x += ww + 1
      }
      return W "x" h ",0," y "{" s "}"
    }
    # Rows of the given counts, stacked, heights equal.
    function rows(r, cnt,    s, i, y, hh, start) {
      if (r == 1) return row(0, H, cnt[1], 1)
      y = 0; s = ""; start = 1
      for (i = 1; i <= r; i++) {
        hh = (i == r) ? H - y : int((H - (r - 1)) / r)
        s = s (i > 1 ? "," : "") row(y, hh, cnt[i], start)
        start += cnt[i]; y += hh + 1
      }
      return W "x" H ",0,0[" s "]"
    }
    # How far a w x h cell is from square, a character being about
    # twice as tall as wide; tall and narrow costs double.
    function cost(w, h,    a) {
      a = (w / 2) / h
      return (a >= 1) ? log(a) : -2 * log(a)
    }
    BEGIN {
      for (i = 32; i < 127; i++) ord[sprintf("%c", i)] = i
      k = split(ids, id, " ")
      split(roles, role, " ")
      if (name == "pm") {
        # The coordinator (and liaison) over the terminal, 50/50.
        t = 0
        for (i = 1; i <= k; i++) if (role[i] == "terminal") t = i
        top = (t > 0) ? k - 1 : k
        if (t == 0 || top == 0) {
          # No terminal, or nothing but one: side by side, full height.
          out = row(0, H, k, 1)
        } else {
          th = int((H - 1) / 2); bh = H - th - 1
          out = W "x" H ",0,0[" row(0, th, top, 1) "," \
            cell(W, bh, 0, th + 1, k) "]"
        }
      } else {
        # The grid: try every row count, spread panes evenly with the
        # extra ones in the top rows, keep the most nearly square.
        best = -1
        for (r = 1; r <= k; r++) {
          base = int(k / r); extra = k % r
          if (base == 0) break
          worst = 0
          for (i = 1; i <= r; i++) {
            c = base + (i <= extra ? 1 : 0)
            cw = (W - (c - 1)) / c; ch = (H - (r - 1)) / r
            if (cw < 1 || ch < 1) { worst = 1e9; break }
            x = cost(cw, ch); if (x > worst) worst = x
          }
          if (best < 0 || worst < best) { best = worst; br = r }
        }
        base = int(k / br); extra = k % br
        for (i = 1; i <= br; i++) cnt[i] = base + (i <= extra ? 1 : 0)
        out = rows(br, cnt)
      }
      # tmux checksum of the layout string.
      sum = 0
      for (i = 1; i <= length(out); i++) {
        sum = int(sum / 2) + (sum % 2) * 32768
        sum = (sum + ord[substr(out, i, 1)]) % 65536
      }
      printf "%04x,%s\n", sum, out
    }')
  tmux select-layout -t "$w" "$layout"
}

# The tmux colour nearest each of /color's names; anything else is
# taken as a tmux colour already.
tmux_color() {
  case "$1" in
    red) echo colour196 ;; orange) echo colour208 ;;
    yellow) echo colour220 ;; green) echo colour34 ;;
    cyan) echo colour44 ;; blue) echo colour33 ;;
    purple) echo colour135 ;; pink) echo colour205 ;;
    *) echo "$1" ;;
  esac
}

style_pane() {
  local pane="$1" role="$2" color="$3"

  tmux select-pane -t "$pane" -T "$role"
  tmux set -p -t "$pane" @role "$role"
  tmux set -p -t "$pane" @agent_color "$(tmux_color "$color")"
  tmux set -p -t "$pane" @prompt_color "$color"
}

# Once each pane's agent is idle, sets its prompt bar to its color and
# turns Remote Control on. Run it in the background (it waits up to 30
# minutes a pane): tmux run-shell -b "bash bullpen.sh settle %1 %2".
settle() {
  local pane color
  for pane in "$@"; do
    # A pane closed while we waited (an agent opened and closed within
    # minutes) is skipped quietly: tmux shows James any failing
    # run-shell.
    for _ in $(seq 1 360); do
      pane_exists "$pane" || continue 2
      tmux capture-pane -p -t "$pane" | grep -q 'esc to interrupt' || break
      sleep 5
    done
    pane_exists "$pane" || continue
    color=$(tmux display -p -t "$pane" '#{@prompt_color}')
    case " red orange yellow green cyan blue purple pink " in
      *" $color "*)
        apply_color "$pane" "$color" ;;
    esac
    # Opt out with BULLPEN_REMOTE_CONTROL=0 (documented in the README).
    [ "${BULLPEN_REMOTE_CONTROL:-1}" = 0 ] && continue
    tmux send-keys -t "$pane" -l '/remote-control'
    tmux send-keys -t "$pane" Enter
    # /remote-control leaves a panel open (its info, or a menu whose
    # Enter disconnects when it was already on). Close it, but only
    # while it is showing and the agent is idle: Esc would interrupt
    # a busy one.
    # In a small pane the panel's text never renders, so a match on it
    # missed and left agents stuck behind it (2026-09-28). Escape on an
    # idle prompt does nothing, so send it whenever the agent is idle.
    # The agent may be busy again by now; wait for idle, never skip.
    sleep 3
    for _ in $(seq 1 360); do
      pane_exists "$pane" || continue 2
      tmux capture-pane -p -t "$pane" |
        grep -q -e 'esc to interrupt' -e '… ([0-9]' || break
      sleep 5
    done
    pane_exists "$pane" && tmux send-keys -t "$pane" Escape
  done
  return 0
}

pane_exists() {
  tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qx "$1"
}

# Settles a new or restarted pane in the background.
settle_later() {
  tmux run-shell -b "bash $(printf %q "$self") settle $*"
}

# James's free terminal, a plain shell in the workspace, unless the
# window already has one.
open_terminal() {
  local w="$1" pane

  tmux list-panes -t "$w" -F '#{@role}' | grep -qx terminal && return 0
  pane=$(tmux split-window -P -F '#{pane_id}' -v -t "$w" -c "$home")
  style_terminal "$pane"
}

style_terminal() {
  style_pane "$1" terminal "$terminal_color"
}

# Colored, labeled borders for the whole window, and the coordinator's
# own pane styled. Run on every open: a reused window (one /bullpen
# didn't create) otherwise shows no labels at all (2026-10-20). The
# active pane's border takes its agent's color too.
style_window() {
  local w="$1" coord
  tmux set -w -t "$w" pane-border-status top
  tmux set -w -t "$w" pane-border-lines heavy 2>/dev/null || true
  tmux set -w -t "$w" pane-border-format \
    '#{?#{==:#{@role},terminal},#[fg=yellow bold] terminal #[default],#[fg=#{@agent_color} reverse bold] #{@role} #[default]}'
  tmux set -w -t "$w" pane-border-style 'fg=colour240'
  tmux set -w -t "$w" pane-active-border-style 'fg=colour255,bold'
  # A blocked agent's bell (sandbox.json's Notification hook) flags the
  # window and reaches James's terminal from any window.
  tmux set -w -t "$w" monitor-bell on
  tmux set -t "$(tmux display -p -t "$w" '#{session_id}')" bell-action any
  tmux set -t "$(tmux display -p -t "$w" '#{session_id}')" visual-bell off
  if [ "$(tmux display -p -t "$w" '#{window_name}')" = pm ]; then
    coord=$(tmux list-panes -t "$w" -F '#{pane_id} #{@role}' |
      awk '$2 == "coordinator" { print $1; exit }')
    [ -n "$coord" ] || coord="${TMUX_PANE:-}"
    [ -z "$coord" ] || style_pane "$coord" coordinator colour255
  fi
  # James's terminal: plain yellow text, no background (2026-10-20).
  tmux list-panes -t "$w" -F '#{pane_id} #{@role}' |
    awk '$2 == "terminal" { print $1 }' |
    while read -r t; do
      tmux set -p -t "$t" @agent_color yellow
      tmux set -p -t "$t" @prompt_color yellow
    done
}

# Sets a pane's label to the exact color Claude Code draws its prompt
# lines in, read from the screen. Claude's /color palette is muted
# ("orange" is colour174), so a guessed tmux colour never matched.
# Leaves the label alone until the prompt shows a non-default color.
sync_color() {
  local pane="$1" n
  n=$(tmux capture-pane -p -e -t "$pane" | grep '───' | tail -3 |
    grep -o $'\e\[38;5;[0-9]*m' | grep -o '[0-9]*m$' | tr -d m |
    grep -vx -e 244 -e 16 | sort | uniq -c | sort -rn |
    awk 'NR == 1 { print $2 }')
  [ -z "$n" ] || tmux set -p -t "$pane" @agent_color "colour$n"
}

# The color names /color takes; anything else never reaches a pane.
valid_color() {
  case "$1" in
    red|orange|yellow|green|cyan|blue|purple|pink) return 0 ;;
    *) return 1 ;;
  esac
}

# Sends /color to an idle agent, then matches its label to the result.
apply_color() {
  valid_color "$2" || die "bad color: $2"
  tmux send-keys -t "$1" -l "/color $2"
  tmux send-keys -t "$1" Enter
  sleep 3
  sync_color "$1"
}

# A color for a role: its roster color unless a live pane in the window
# already wears it, else the first of /color's eight that none does.
# James (2026-10-20): agents must be told apart at a glance.
pick_color() {
  local w="$1" role="$2" want="$3" used c
  used=" $(tmux list-panes -s -t "$w" -F '#{@role} #{@prompt_color}' |
    awk -v r="$role" '$1 != r && NF == 2 { print $2 }' | tr '\n' ' ') "
  case "$used" in *" $want "*) ;; *) echo "$want"; return ;; esac
  for c in red orange yellow green cyan blue purple pink; do
    case "$used" in *" $c "*) ;; *) echo "$c"; return ;; esac
  done
  echo "$want"
}

open_role() {
  local role="$1" w="$2" line kind color flags dir cmd tail pane

  line="$(line_for "$role")"
  [ -n "$line" ] || die "no $role in $roster"
  [ -f "$pen/roles/$role.md" ] || die "no brief: $pen/roles/$role.md"
  read -r class kind color flags <<< "$line" || true
  dir="$(folder_for "$role" "$kind")"

  # One pane per role (James, 2026-09-28: duplicates piled up). A live
  # agent is never started twice; a parked role's shell pane is reused.
  local p old=
  for p in $(session_panes | awk -v r="$role" '$2 == r { print $1 }'); do
    if pane_live "$p"; then
      echo "$role is already running ($p)"
      return 0
    fi
    if [ -z "$old" ]; then old=$p; else tmux kill-pane -t "$p"; fi
  done

  check_cap "$role"
  style_window "$w"
  color=$(pick_color "$w" "$role" "$color")
  prepare "$role" "$kind" "$dir"
  cmd="$(command_for "$role" "$kind" "$dir" "$flags")"

  if [ -n "$old" ]; then
    tmux respawn-pane -k -t "$old" -c "$dir" "$cmd"
    style_pane "$old" "$role" "$color"
    settle_later "$old"
    echo "reopened $role in its pane ($old)"
    return 0
  fi

  # The largest pane takes the split; relayout then puts it in place.
  tail=$(panes "$w" | awk '{ print $3 * $4, $5 }' | sort -n | tail -1 |
    awk '{ print $2 }')
  pane=$(tmux split-window -P -F '#{pane_id}' -v -t "$tail" -c "$dir" \
    "$cmd")
  style_pane "$pane" "$role" "$color"
  relayout "$w"
  settle_later "$pane"
  echo "opened $role ($dir)"
}

roster_roles() {
  awk '!/^#/ && NF { print $1 }' "$roster"
}

[ $# -gt 0 ] || die "usage: bullpen.sh start|hire|prepare [role...]"
action="$1"
shift

case "$action" in
  prepare)
    for role in "$@"; do
      read -r class kind color flags <<< "$(line_for "$role")" || true
      prepare "$role" "$kind" "$(folder_for "$role" "$kind")"
      echo "prepared $role"
    done
    ;;
  start)
    # Safe to run again: it finds what exists and makes what doesn't.
    [ -n "${TMUX_PANE:-}" ] || die "run from the coordinator's tmux pane"
    sid=$(ensure_session)
    w=$(tmux display -p -t "$TMUX_PANE" '#{window_id}')
    old=$(tmux display -p -t "$TMUX_PANE" '#{session_id}')
    if [ "$old" != "$sid" ]; then
      # Bring the coordinator's window over, and James's clients with
      # it, so he doesn't lose sight of it. Order matters (2026-11-10):
      # moving the old session's only window out destroys that session,
      # which detaches every client on it (tmux looked crashed) and
      # made the client lookup fail, ending the script under set -e.
      # So: note the clients, leave the old session a window so it
      # keeps its id and place in the list, move, then switch.
      clients=$(tmux list-clients -t "$old" -F '#{client_name}' \
        2>/dev/null || true)
      if [ "$(tmux list-windows -t "$old" | wc -l)" -le 1 ]; then
        tmux new-window -d -t "$old:" -c "$HOME"
      fi
      tmux move-window -s "$w" -t "$sid:"
      for c in $clients; do
        tmux switch-client -c "$c" -t "$sid" || true
      done
    fi
    tmux rename-window -t "$w" pm
    style_pane "$TMUX_PANE" coordinator colour255
    # A pane here with no role is James's: it becomes the terminal.
    if ! tmux list-panes -t "$w" -F '#{@role}' | grep -qx terminal; then
      p=$(tmux list-panes -t "$w" -F '#{pane_id} #{@role}' |
        awk 'NF == 1 { print $1; exit }')
      [ -z "$p" ] || style_terminal "$p"
    fi
    style_window "$w"
    open_terminal "$w"
    relayout "$w"
    # pm first, then dev, then qa.
    first=$(tmux list-windows -t "$sid" -F '#{window_id}' | head -1)
    [ "$first" = "$w" ] || tmux swap-window -d -s "$w" -t "$first"
    for name in dev qa; do relayout "$(ensure_window "$sid" "$name")"; done
    # Only the roles named: the coordinator opens agents as GitHub
    # hands it work (James, 2026-10-20), never the whole roster.
    for role in "$@"; do open_role "$role" "$(window_for "$role")"; done
    tmux select-window -t "$w"
    tmux select-pane -t "$TMUX_PANE"
    ;;
  layout)
    sid=$(session_id)
    [ -n "$sid" ] || die "no $session_name session; start it first"
    w=$(window_named pm)
    [ -z "$w" ] || { style_window "$w"; open_terminal "$w"; relayout "$w"; }
    for name in dev qa; do relayout "$(ensure_window "$sid" "$name")"; done
    echo "laid out"
    ;;
  hire)
    sid=$(session_id)
    [ -n "$sid" ] || die "no $session_name session; start it first"
    for role in "$@"; do
      [ -n "$(class_of "$role")" ] || die "no $role in $roster"
      w=$(window_for "$role")
      [ -n "$w" ] || case "$(class_of "$role")" in
        impl) w=$(ensure_window "$sid" dev) ;;
        review) w=$(ensure_window "$sid" qa) ;;
        *) die "no pm window; start it first" ;;
      esac
      open_role "$role" "$w"
    done
    ;;
  respawn)
    # Restarts a role's agent in its own pane, found by its folder. Only
    # for an agent that is idle or never started; never a busy one.
    sid=$(session_id)
    [ -n "$sid" ] || die "no $session_name session; start it first"
    for role in "$@"; do
      read -r class kind color flags <<< "$(line_for "$role")" || true
      dir="$(folder_for "$role" "$kind")"
      pane=$(session_panes | awk -v r="$role" '$2 == r { print $1; exit }')
      [ -n "$pane" ] ||
        pane=$(tmux list-panes -s -t "$sid" \
          -F '#{pane_id} #{pane_current_path}' |
          awk -v d="$dir" '$2 == d { print $1; exit }')
      w=$(tmux display -p -t "$pane" '#{window_id}' 2>/dev/null || true)
      [ -n "$pane" ] || die "no pane in $dir for $role"
      # Restarting a live agent keeps the count; waking a parked one
      # adds to it.
      pane_live "$pane" || check_cap "$role"
      tmux respawn-pane -k -t "$pane" -c "$dir" \
        "$(command_for "$role" "$kind" "$dir" "$flags")"
      style_window "$w"
      color=$(pick_color "$w" "$role" "$color")
      style_pane "$pane" "$role" "$color"
      settle_later "$pane"
      echo "respawned $role ($pane)"
    done
    ;;
  close)
    # Ends a finished agent: /exit when it is idle, then kills its
    # pane and lays the window out again. A busy agent is left alone.
    sid=$(session_id)
    [ -n "$sid" ] || die "no $session_name session"
    touched=""
    for role in "$@"; do
      for pane in $(session_panes | awk -v r="$role" '$2 == r { print $1 }'); do
        touched="$touched $(tmux display -p -t "$pane" '#{window_id}')"
        if pane_live "$pane"; then
          if tmux capture-pane -p -t "$pane" | tail -15 |
            grep -qE 'esc to interrupt|… \([0-9]'; then
            echo "$role: busy, left running"; continue 2
          fi
          tmux send-keys -t "$pane" -l '/exit'
          sleep 1
          tmux send-keys -t "$pane" Enter
          for _ in $(seq 1 20); do pane_live "$pane" || break; sleep 1; done
        fi
        tmux kill-pane -t "$pane"
      done
      echo "closed $role"
    done
    # dev and qa stay open: their terminals outlive every agent.
    for w in $(echo "$touched" | tr ' ' '\n' | sort -u); do
      tmux display -p -t "$w" '#{window_id}' >/dev/null 2>&1 &&
        relayout "$w"
    done
    ;;
  recolor)
    # Restyles the windows and gives every live agent a color no other
    # pane wears, then sets each idle agent's prompt bar to it. A busy
    # agent keeps its bar until the next recolor; its label changes now.
    sid=$(session_id)
    [ -n "$sid" ] || die "no $session_name session"
    for w in $(tmux list-windows -t "$sid" -F '#{window_id}'); do
      style_window "$w"
    done
    w=$sid
    for pane in $(tmux list-panes -s -t "$sid" -F '#{pane_id}'); do
      role=$(tmux display -p -t "$pane" '#{@role}')
      case "$role" in ""|coordinator|terminal) continue ;; esac
      # Already distinct and matched: leave it alone (no repeat /color).
      cur=$(tmux display -p -t "$pane" '#{@prompt_color}')
      if [ -n "$cur" ] && [ "$(pick_color "$w" "$role" "$cur")" = "$cur" ] &&
        [ "$(tmux display -p -t "$pane" '#{@agent_color}')" != "$(tmux_color "$cur")" ]; then
        echo "$role: $cur (already set)"; continue
      fi
      # Clear its own color first, so pick_color judges it fresh.
      tmux set -p -t "$pane" @prompt_color ""
      read -r class kind color flags <<< "$(line_for "$role")" || true
      color=$(pick_color "$w" "$role" "${color:-red}")
      style_pane "$pane" "$role" "$color"
      if tmux capture-pane -p -t "$pane" | tail -15 |
        grep -qE 'esc to interrupt|… \([0-9]'; then
        tmux run-shell -b "bash $(printf %q "$self") colorwait $pane $color"
        echo "$role: $color (bar set once idle)"
      else
        apply_color "$pane" "$color"
        echo "$role: $color ($(tmux display -p -t "$pane" '#{@agent_color}'))"
      fi
    done
    ;;
  colorwait)
    case "$1" in %[0-9]*) ;; *) die "bad pane: $1" ;; esac
    valid_color "$2" || die "bad color: $2"
    # Waits (up to 30 minutes) for an agent to go idle, then sets its
    # prompt bar's color.
    for _ in $(seq 1 360); do
      tmux capture-pane -p -t "$1" | tail -15 |
        grep -qE 'esc to interrupt|… \([0-9]' || break
      sleep 5
    done
    apply_color "$1" "$2"
    ;;
  settle) sleep 15; settle "$@" || true; exit 0 ;;
  *) die "unknown action: $action" ;;
esac
