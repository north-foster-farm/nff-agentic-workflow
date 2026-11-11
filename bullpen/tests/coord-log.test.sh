#!/usr/bin/env bash
# Tests for coord-log.sh against a stand-in gh that only records what
# it would post. Run: bullpen/tests/coord-log.test.sh
set -u
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../scripts/coord-log.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin"
printf '%s\n' '#!/usr/bin/env bash' \
  'printf "%s\n" "$*" >> "$STUB_LOG"' \
  'echo https://github.com/x/y/issues/18#issuecomment-1' \
  > "$work/bin/gh"
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH" STUB_LOG="$work/log"

fails=0 runs=0
check() { # check <name> <want-rc> <args...>
  local name=$1 want=$2 rc=0
  shift 2
  : > "$STUB_LOG"
  "$script" "$@" >"$work/out" 2>"$work/err" || rc=$?
  runs=$((runs + 1))
  if [ "$rc" != "$want" ]; then
    fails=$((fails + 1)); echo "FAIL: $name (rc $rc, want $want)"
    cat "$work/err"
  fi
}
posted() { [ -s "$STUB_LOG" ]; }
expect_posted() {
  runs=$((runs + 1))
  posted || { fails=$((fails + 1)); echo "FAIL: $1 posted nothing"; }
}
expect_silent() {
  runs=$((runs + 1))
  ! posted || { fails=$((fails + 1)); echo "FAIL: $1 posted"; }
}

check 'a plain entry' 0 \
  'Poll found 2 comments on north-foster-farm#548, dispatched design'
expect_posted 'a plain entry'
grep -q 'issue comment 18 -R north-foster-farm/nff-agentic-workflow' \
  "$STUB_LOG" && runs=$((runs + 1)) || { runs=$((runs + 1))
  fails=$((fails + 1)); echo "FAIL: posts to issue 18"; }

check 'entry plus note' 0 'Landed PR 20' \
  --issue nff-agentic-workflow#17 'landed in PR 20'
runs=$((runs + 1))
[ "$(wc -l < "$STUB_LOG" | tr -d ' ')" = 2 ] ||
  { fails=$((fails + 1)); echo "FAIL: two posts expected"; }
grep -q 'issue comment 17 -R north-foster-farm/nff-agentic-workflow' \
  "$STUB_LOG" && runs=$((runs + 1)) || { runs=$((runs + 1))
  fails=$((fails + 1)); echo "FAIL: the note goes to the issue"; }
grep -q 'log: https://github.com' "$STUB_LOG" &&
  runs=$((runs + 1)) || { runs=$((runs + 1)); fails=$((fails + 1))
  echo "FAIL: the note links the log entry"; }

check 'a hash, a date, a PR number are fine' 0 \
  'Merged 5d9ff0d1c2b3a4f5e6d7c8b9a0f1e2d3c4b5a697 on 2026-11-11, PR #20'
expect_posted 'a hash'
u=https://github.com/north-foster-farm/north-foster-farm
check 'a long URL is fine' 0 "See $u/issues/548#issuecomment-6810075253"
expect_posted 'a url'

check 'an email' 1 'Customer jane.doe@example.com asked'
expect_silent 'an email'
check 'a phone number' 1 'Call 401-555-0123 today'
expect_silent 'a phone number'
check 'a phone number, plus form' 1 'Call +1 (401) 555 0123'
expect_silent 'a phone number, plus form'
check 'a github token' 1 'token ghp_abcdefghijklmnopqrstuvwxyz0123456789'
expect_silent 'a github token'
check 'a bearer token' 1 'Authorization: Bearer abcdef0123456789abcdef'
expect_silent 'a bearer token'
check 'a long secret' 1 'key AbCdEfGh0123456789AbCdEfGh0123456789AbCd'
expect_silent 'a long secret'
check 'a private note' 1 'Fine entry' \
  --issue north-foster-farm#1 'mail bob@farm.org'
expect_silent 'a private note (nothing posts at all)'
check 'another org' 1 'Entry' --issue other-org/repo#3 'note'
expect_silent 'another org'

check 'no arguments' 2
check 'a bad --issue' 2 'Entry' --issue nonsense 'note'
expect_silent 'a bad --issue'

echo "$((runs - fails))/$runs passed"
[ "$fails" = 0 ]
