#!/usr/bin/env bash
# Tests for the planning helpers, against a stub gh. Run: tests/run.sh
set -u
here="$(cd "$(dirname "$0")" && pwd)"
scripts="$here/../scripts"
export PATH="$here/stub:$PATH"
export STUB_LOG="$(mktemp)"
pr=north-foster-farm/nff-agentic-workflow
export NFF_REPO=$pr
trap 'rm -f "$STUB_LOG"' EXIT

fails=0 runs=0
ok() { runs=$((runs + 1)); }
fail() { runs=$((runs + 1)); fails=$((fails + 1)); echo "FAIL: $*"; }

reset() { : > "$STUB_LOG"; }
logged() { grep -Fq -- "$1" "$STUB_LOG"; }
expect_logged() {
  if logged "$1"; then ok; else fail "$2 (no '$1' in log)"; fi
}
expect_not_logged() {
  if logged "$1"; then fail "$2 ('$1' in log)"; else ok; fi
}
expect_status() { # expect_status <want 0|nonzero> <name> cmd...
  local want="$1" name="$2"
  shift 2
  "$@" >/dev/null 2>&1
  local rc=$?
  if [ "$want" = 0 ] && [ $rc -eq 0 ]; then ok
  elif [ "$want" != 0 ] && [ $rc -ne 0 ]; then ok
  else fail "$name (exit $rc)"; fi
}

# set-field
reset
"$scripts/set-field.sh" --stage "in review" --owner james 7 >/dev/null
expect_logged 'issues/7/issue-field-values' 'set-field posts to the issue'
expect_logged '"field_id":49749062,"value":"in review"' 'stage sent'
expect_logged '"field_id":49749063,"value":"james"' 'owner sent'
expect_not_logged '49749064' 'kind not sent when not given'
reset
expect_status nonzero 'bad stage refused' "$scripts/set-field.sh" \
  --stage bogus 7
expect_not_logged 'issue-field-values' 'bad stage makes no call'
expect_status nonzero 'no field refused' "$scripts/set-field.sh" 7
expect_status nonzero 'bad kind refused' "$scripts/set-field.sh" \
  --kind chat 7
reset
"$scripts/set-field.sh" --kind credential \
  other-org/other-repo#12 >/dev/null
expect_logged 'repos/other-org/other-repo/issues/12/issue-field-values' \
  'set-field reaches another repository'

# link-blocker (the fixture's id is 6333284390)
reset
"$scripts/link-blocker.sh" 3 other-org/other-repo#9 >/dev/null
expect_logged "POST repos/$pr/issues/3/dependencies/blocked_by \
-F issue_id=6333284390" \
  'blocker linked across repositories'
expect_logged 'repos/other-org/other-repo/issues/9' \
  'blocker id read from its own repository'
reset
"$scripts/link-blocker.sh" --remove 3 99 >/dev/null
expect_logged "DELETE repos/$pr/issues/3/dependencies/blocked_by/\
6333284390" \
  'blocker removed'
expect_status nonzero 'self-block refused' "$scripts/link-blocker.sh" 3 3
expect_status nonzero 'one argument refused' "$scripts/link-blocker.sh" 3

# move-milestone (the fixture's "Next release" is number 2)
reset
"$scripts/move-milestone.sh" 5 https://github.com/o/r/issues/6 >/dev/null
expect_logged "PATCH repos/$pr/issues/5 -F milestone=2" \
  'issue moved to the milestone'
expect_logged 'PATCH repos/o/r/issues/6 -F milestone=2' \
  'a URL reference moves an issue in its own repository'
reset
expect_status nonzero 'unknown milestone refused' \
  "$scripts/move-milestone.sh" --to 'No such' 5
expect_not_logged 'PATCH' 'unknown milestone changes nothing'

# file-tree
tmp="$(mktemp -d)"
trap 'rm -f "$STUB_LOG"; rm -rf "$tmp"' EXIT
cat > "$tmp/tree.json" <<'JSON'
[{"title": "Feature A", "stage": "scoped", "owner": "claude",
  "body": "Done when: ok",
  "children": [{"title": "Work A1", "stage": "ready", "owner": "claude",
                "body": "## Done when\n- [ ] ok", "labels": ["needs: qa"]}]}]
JSON
reset
out=$("$scripts/file-tree.sh" --dry-run 4 "$tmp/tree.json")
case "$out" in
  *"L2 [north-foster-farm/nff-agentic-workflow] Feature: Feature A"*) ok ;;
  *) fail "dry run shows the feature at level 2: $out" ;;
esac
case "$out" in
  *"L3 "*"Task: Work A1"*) ok ;;
  *) fail "dry run shows the work issue at level 3: $out" ;;
esac
expect_not_logged 'POST' 'dry run creates nothing'
reset
"$scripts/file-tree.sh" 4 "$tmp/tree.json" >/dev/null 2>&1
expect_logged "repos/$pr/issues/4/sub_issues" \
  'feature filed under the parent'
expect_logged 'type=Feature' 'a parent node is a Feature'
expect_logged 'type=Task' 'a leaf node is a Task'
expect_logged 'labels[]=needs: qa' 'labels sent'
expect_logged '"value":"ready"' 'child stage set'
expect_status nonzero 'fourth level refused' "$scripts/file-tree.sh" \
  --parent-level 2 4 "$tmp/tree.json"
reset
"$scripts/file-tree.sh" --dry-run --allow-deep --parent-level 2 4 \
  "$tmp/tree.json" >/dev/null 2>&1
expect_not_logged 'POST' '--allow-deep passes the gate'
printf '%s' '[{"title":"X","owner":"nobody"}]' > "$tmp/bad.json"
reset
expect_status nonzero 'bad owner refused' "$scripts/file-tree.sh" \
  4 "$tmp/bad.json"
expect_not_logged 'POST' 'a bad tree files nothing'
printf '%s' '[{"body":"no title"}]' > "$tmp/notitle.json"
expect_status nonzero 'missing title refused' "$scripts/file-tree.sh" \
  4 "$tmp/notitle.json"

# file-tree: milestones, labels and the parent's real depth (fixtures:
# #4 is a root, #9 its child, #10 its grandchild; labels as recorded).
printf '%s' '[{"title":"X","milestone":"Next release",
  "body":"## Done when\n- [ ] ok"}]' > "$tmp/ms.json"
reset
"$scripts/file-tree.sh" 4 "$tmp/ms.json" >/dev/null 2>&1
expect_logged 'milestone=2' 'a known milestone is used'
printf '%s' '[{"title":"X","milestone":"No such milestone"}]' \
  > "$tmp/badms.json"
reset
expect_status nonzero 'unknown milestone refused' \
  "$scripts/file-tree.sh" 4 "$tmp/badms.json"
expect_not_logged 'POST' 'an unknown milestone files nothing'
printf '%s' '[{"title":"X","children":[{"title":"Y","labels":["no such"]}]}]' \
  > "$tmp/badlabel.json"
reset
expect_status nonzero 'unknown label refused' \
  "$scripts/file-tree.sh" --dry-run 4 "$tmp/badlabel.json"
expect_not_logged 'POST' 'an unknown label files nothing'
printf '%s' '[{"title":"Child"}]' > "$tmp/one.json"
printf '%s' '[{"title":"Child","children":[{"title":"Grandchild"}]}]' \
  > "$tmp/two.json"
expect_status 0 'one level under a level-2 parent is allowed' \
  "$scripts/file-tree.sh" --dry-run 9 "$tmp/one.json"
expect_status nonzero 'two levels under a level-2 parent refused' \
  "$scripts/file-tree.sh" --dry-run 9 "$tmp/two.json"
expect_status nonzero 'a child of a level-3 issue refused' \
  "$scripts/file-tree.sh" --dry-run 10 "$tmp/one.json"
expect_status 0 '--allow-deep passes a deep parent' \
  "$scripts/file-tree.sh" --dry-run --allow-deep 10 "$tmp/one.json"

echo "$((runs - fails))/$runs passed"
[ "$fails" -eq 0 ]
