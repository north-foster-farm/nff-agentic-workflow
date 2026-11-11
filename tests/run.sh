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

# plan-check. Fixtures are scratch issues in this repository: #12 sits
# at level 4 with no fields, #10 is complete at level 3, #5 already has
# a plan-check comment, #4 is closed, and #5 is a ready issue blocked by
# #6 (owner james).
export GH_TOKEN=unused
check() { PLAN_CHECK_DRY=1 "$scripts/plan-check.sh" "$@" 2>&1; }
has() { case "$1" in *"$2"*) ok ;; *) fail "$3 (output: $1)" ;; esac; }
lacks() { case "$1" in *"$2"*) fail "$3 (output: $1)" ;; *) ok ;; esac; }

reset
out=$(check issue $pr#12)
has "$out" 'It has no Stage' 'missing Stage reported'
has "$out" 'It has no Owner' 'missing Owner reported'
has "$out" '"Done when"' 'missing Done when reported'
has "$out" 'level 4' 'depth beyond three reported'
has "$out" '<!-- plan-check:issue -->' 'comment carries its marker'
out=$(check issue $pr#10)
has "$out" '#10: ok' 'a complete issue passes'
# The recorded marker comment on #5 was posted by jbboynton.
out=$(PLAN_CHECK_BOT=jbboynton check issue $pr#5)
has "$out" 'already reported' 'the check comments once'
lacks "$out" 'WOULD COMMENT' 'no second comment'
out=$(check issue $pr#5)
has "$out" 'WOULD COMMENT' 'a marker from anyone but the bot is ignored'
out=$(check issue $pr#4)
has "$out" 'closed; skipped' 'a closed issue is skipped'

reset
"$scripts/plan-check.sh" issue $pr#12 >/dev/null 2>&1
expect_logged "POST repos/$pr/issues/12/comments" 'a comment is posted'
expect_not_logged 'PATCH' 'plan-check never patches an issue'
expect_not_logged 'issue-field-values -X POST' 'plan-check never sets a field'
reset
"$scripts/plan-check.sh" issue $pr#10 >/dev/null 2>&1
expect_not_logged 'comments -f' 'a passing issue gets no comment'

out=$(HARD_BLOCK_HOURS=0 check hard-blocks)
has "$out" "WOULD COMMENT on $pr#6" 'a stale hard block is re-flagged'
has "$out" "$pr#5 is ready" 'the reminder names the waiting work'
has "$out" '<!-- plan-check:hard-block -->' 'reminder carries its marker'
out=$(HARD_BLOCK_HOURS=100000 check hard-blocks)
lacks "$out" 'WOULD COMMENT' 'a recent hard block is left alone'
has "$out" 'wait' 'a recent hard block says why'
expect_status nonzero 'unknown mode refused' "$scripts/plan-check.sh" nope

# sync-labels. The fixtures are real label lists: this repository after
# a sync, and the site repository, which lacks "depth: approved".
site=north-foster-farm/north-foster-farm
reset
out=$("$scripts/sync-labels.sh" $pr)
has "$out" "'depth: approved' ok" 'a synced repository is unchanged'
expect_not_logged 'label create' 'nothing to create when in sync'
reset
out=$("$scripts/sync-labels.sh" --dry-run $site)
has "$out" "'needs: qa' ok" 'existing labels match'
has "$out" "'depth: approved' would be created" 'a missing label is found'
expect_not_logged 'label create' 'dry run creates nothing'
reset
"$scripts/sync-labels.sh" $site >/dev/null
expect_logged "label create depth: approved -R $site -c fbca04" \
  'a missing label is created'
expect_not_logged 'label create needs' 'matching labels are left alone'
expect_not_logged 'label delete' 'labels are never deleted'
expect_status nonzero 'bad repository refused' "$scripts/sync-labels.sh" x

echo "$((runs - fails))/$runs passed"
[ "$fails" -eq 0 ]
