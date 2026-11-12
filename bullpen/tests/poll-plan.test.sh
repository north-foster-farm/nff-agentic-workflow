#!/usr/bin/env bash
# Tests for poll-plan.sh against a stub gh. Run: bullpen/tests/poll-plan.test.sh
set -u
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../scripts/poll-plan.sh"
export PATH="$here/stub:$PATH"
export STUB_LOG="$(mktemp)"
repo=north-foster-farm/nff-agentic-workflow
export POLL_REPOS=$repo
trap 'rm -f "$STUB_LOG"' EXIT

fails=0 runs=0
has() { # has <output> <text> <name>
  runs=$((runs + 1))
  case "$1" in *"$2"*) ;; *) fails=$((fails + 1)); echo "FAIL: $3 ($1)" ;; esac
}
lacks() {
  runs=$((runs + 1))
  case "$1" in *"$2"*) fails=$((fails + 1)); echo "FAIL: $3 ($1)" ;; *) ;; esac
}
fresh() { BULLPEN_STATE=$(mktemp -d); export BULLPEN_STATE; : > "$STUB_LOG"; }

# First run: records the state silently, then one seeded line.
fresh
out=$(HARD_BLOCK_HOURS=100000 "$script")
has "$out" 'STAGE seeded: 1 lane-held issues, 1 open blocked-by links' \
  'first run seeds quietly'
lacks "$out" "STAGE $repo#14" 'first run prints no per-issue lines'
lacks "$out" 'BLOCK' 'first run prints no block lines'

# Second run: nothing changed, nothing printed, no field calls.
: > "$STUB_LOG"
out=$(HARD_BLOCK_HOURS=100000 "$script")
[ -z "$out" ] && runs=$((runs + 1)) || { runs=$((runs + 1))
  fails=$((fails + 1)); echo "FAIL: quiet second run ($out)"; }
if grep -q 'issues/14/issue-field-values' "$STUB_LOG"; then
  runs=$((runs + 1)); fails=$((fails + 1))
  echo "FAIL: an unchanged lane issue is not re-read"
else runs=$((runs + 1)); fi

# A changed Stage, and a new link, against an older snapshot.
printf '%s\t%s\t%s\n' "$repo#14" "spec" "2000-01-01T00:00:00Z" \
  > "$BULLPEN_STATE/stages"
: > "$BULLPEN_STATE/blocks"
out=$(HARD_BLOCK_HOURS=100000 "$script")
has "$out" "STAGE $repo#14 spec>ready | \"scratch: lane issue\"" \
  'a changed Stage is reported'
has "$out" "BLOCK $repo#14 <- $repo#15 | \"scratch: lane issue\"" \
  'a new blocked-by link is reported'

# A stage with a space survives the snapshot.
printf '%s\t%s\t%s\n' "$repo#14" "in review" "2000-01-01T00:00:00Z" \
  > "$BULLPEN_STATE/stages"
out=$(HARD_BLOCK_HOURS=100000 "$script")
has "$out" "STAGE $repo#14 in review>ready" 'a two-word stage is kept'

# Hard blocks: owned by james, blocked work ready, silent long enough.
out=$(HARD_BLOCK_HOURS=0 "$script")
has "$out" "HARD $repo#15 owner james," 'a hard block is listed'
has "$out" "blocks $repo#14 (ready)" 'it names the waiting work'
out=$(HARD_BLOCK_HOURS=100000 "$script")
lacks "$out" 'HARD' 'a recent hard block is not listed'

# A private copy of the stub and fixtures to edit.
priv=$(mktemp -d)
trap 'rm -rf "$priv"; rm -f "$STUB_LOG"' EXIT
mkdir -p "$priv/stub" "$priv/fixtures"
cp "$here/stub/gh" "$priv/stub/gh"
cp "$here/fixtures"/* "$priv/fixtures/"
pre=repos_north-foster-farm_nff-agentic-workflow

# Titles are cleaned like poll.sh's: control, tag, format and separator
# characters go, and the title is quoted.
jq 'map(if .number == 14
  then .title = "a\u001b[0m👋󠁁b﻿c d⁠e"
  else . end)' "$here/fixtures/${pre}_issues.json" \
  > "$priv/fixtures/${pre}_issues.json"
fresh
printf '%s\t%s\t%s\n' "$repo#14" "spec" "2000-01-01T00:00:00Z" \
  > "$BULLPEN_STATE/stages"
out=$(PATH="$priv/stub:$PATH" HARD_BLOCK_HOURS=100000 "$script")
has "$out" "STAGE $repo#14 spec>ready | \"a[0m" 'control characters go'
runs=$((runs + 1))
case "$out" in
  *$'\033'*|*$'\xef\xbb\xbf'*|*$'\xe2\x80\xa8'*|*$'\xe2\x81\xa0'*|*$'\xf3\xa0'*)
  fails=$((fails + 1)); echo "FAIL: format characters survive" ;; esac
has "$out" "\"a[0m" 'the title is quoted'
has "$out" "bcde\"" 'the rest of the title is kept'

# A failed read stops the poll and leaves the snapshot as it was.
cp "$here/fixtures/${pre}_issues.json" "$priv/fixtures/${pre}_issues.json"
rm "$priv/fixtures/${pre}_issues_14_issue-field-values.json"
fresh
printf '%s\t%s\t%s\n' "$repo#14" "spec" "2000-01-01T00:00:00Z" \
  > "$BULLPEN_STATE/stages"
before=$(cat "$BULLPEN_STATE/stages")
PATH="$priv/stub:$PATH" HARD_BLOCK_HOURS=100000 "$script" \
  >/dev/null 2>&1; rc=$?
runs=$((runs + 1))
[ "$rc" != 0 ] || { fails=$((fails + 1)); echo "FAIL: failed read exits 0"; }
runs=$((runs + 1))
[ "$(cat "$BULLPEN_STATE/stages")" = "$before" ] ||
  { fails=$((fails + 1)); echo "FAIL: a failed read rewrote the state"; }

# Read-only: no call other than a GET.
if grep -qE ' (-X|--method) ' "$STUB_LOG"; then
  runs=$((runs + 1)); fails=$((fails + 1)); echo "FAIL: poll-plan wrote"
else runs=$((runs + 1)); fi

echo "$((runs - fails))/$runs passed"
[ "$fails" -eq 0 ]
