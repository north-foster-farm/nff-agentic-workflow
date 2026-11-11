#!/usr/bin/env bash
# Post one entry to the Coordinator log (nff-agentic-workflow#18) and,
# with --issue, a short note on the affected issue:
#
#   coord-log.sh "<text>" [--issue repo#N "<note>"]
#
# repo is a name in the north-foster-farm org (or org/name). The log is
# public, so the script refuses, posting nothing, when the text or note
# looks like it carries an email address, a phone number or a token.
# Private matters go in as "private item, details with James".
#
# Environment: COORD_LOG_REPO (default north-foster-farm/
# nff-agentic-workflow) and COORD_LOG_ISSUE (default 18), for tests.
set -euo pipefail
org=north-foster-farm
log_repo="${COORD_LOG_REPO:-$org/nff-agentic-workflow}"
log_issue="${COORD_LOG_ISSUE:-18}"

usage() {
  echo 'usage: coord-log.sh "<text>" [--issue repo#N "<note>"]' >&2
  exit 2
}

# looks_private <text>: print the reason and return 0 when the text
# looks like it carries an email, phone number or token.
looks_private() {
  local t=$1 word digits bare
  bare=$(printf '%s' "$t" | sed -E 's#https?://[^ )>]*##g')
  local mail='[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}'
  local tok='gh[pousr]_[A-Za-z0-9]{16,}|github_pat_|sk-[A-Za-z0-9_-]{16,}'
  tok="$tok|xox[abprs]-|AKIA[0-9A-Z]{16}|eyJ[A-Za-z0-9_-]{8,}\.|-----BEGIN"
  tok="$tok|[Bb]earer +[A-Za-z0-9._~+/=-]{12,}"
  if printf '%s' "$t" | grep -qE "$mail"; then
    echo "an email address"; return 0
  fi
  if printf '%s' "$t" | grep -qE "$tok"; then
    echo "a token"; return 0
  fi
  # Phone numbers: a run of digits and separators holding 10 or more
  # digits. Dates, issue numbers and SHAs are shorter or contain letters.
  while IFS= read -r word; do
    digits=$(printf '%s' "$word" | tr -cd '0-9')
    [ "${#digits}" -ge 10 ] || continue
    echo "a phone number"; return 0
  done < <(printf '%s' "$bare" |
    grep -oE '\+?[0-9][0-9 ().-]{8,}[0-9]' || true)
  # A long unbroken secret-like string. URLs (stripped above) and
  # pure-hex git hashes are fine.
  while IFS= read -r word; do
    case "$word" in
      *[0-9]*) ;; *) continue ;;
    esac
    case "$word" in
      *[a-zA-Z]*) ;; *) continue ;;
    esac
    printf '%s' "$word" | grep -qE '^[0-9a-f]{40}$|^[0-9a-f]{64}$' &&
      continue
    echo "a token-like string"; return 0
  done < <(printf '%s' "$bare" |
    grep -oE '[A-Za-z0-9_+/=-]{32,}' || true)
  return 1
}

[ "$#" -ge 1 ] || usage
text=$1; shift
issue="" note=""
if [ "$#" -gt 0 ]; then
  [ "$#" = 3 ] && [ "$1" = --issue ] || usage
  issue=$2 note=$3
fi
[ -n "$text" ] || usage

for t in "$text" "$note"; do
  if why=$(looks_private "$t"); then
    echo "coord-log: refused, the text looks like it carries $why." \
      "Say \"private item, details with James\" instead." >&2
    exit 1
  fi
done

target_repo="" target_num=""
if [ -n "$issue" ]; then
  [ -n "$note" ] || usage
  printf '%s' "$issue" | grep -qE '^[A-Za-z0-9._/-]+#[0-9]+$' || usage
  target_repo=${issue%#*} target_num=${issue##*#}
  case "$target_repo" in */*) ;; *) target_repo="$org/$target_repo" ;; esac
  case "$target_repo" in
    "$org"/*) ;;
    *) echo "coord-log: $target_repo is not in $org" >&2; exit 1 ;;
  esac
fi

stamp=$(TZ=America/New_York date '+%Y-%m-%d %H:%M ET')
url=$(gh issue comment "$log_issue" -R "$log_repo" \
  --body "**$stamp.** $text" | tail -1)
echo "$url"
if [ -n "$issue" ]; then
  gh issue comment "$target_num" -R "$target_repo" \
    --body "Coordinator: $note (log: $url)" | tail -1
fi
