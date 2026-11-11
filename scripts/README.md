# Planning helpers

Bash and `gh`; they need `jq`. Each works in both repositories: an
issue is a number (in `$NFF_REPO`, else the current repository),
`owner/repo#number` or an issue URL. Values follow `../planning.md`.

| Script | Does |
| ------ | ---- |
| `set-field.sh` | Sets Stage, Owner or Kind on issues |
| `file-tree.sh` | Files a JSON tree under a parent as sub-issues |
| `link-blocker.sh` | Links, or with `--remove` unlinks, a blocker |
| `move-milestone.sh` | Moves issues to the next milestone |
| `sync-labels.sh` | Makes the shared labels (`../labels.json`) exist |
| `plan-check.sh` | The checks behind the plan-check workflow |

```
scripts/set-field.sh --stage "in review" --owner james 540 541
scripts/set-field.sh --kind credential --owner james org/repo#12
scripts/link-blocker.sh 540 539
scripts/link-blocker.sh org/dashboard#43 org/site#530
scripts/move-milestone.sh --to "After launch" 77
scripts/file-tree.sh --dry-run 526 tree.json
```

`file-tree.sh` checks every value, milestone and label, and the depth,
before it creates anything, so a bad tree files nothing. It reads the
parent's real level from its chain of parents and refuses a fourth
level unless given `--allow-deep`. Its input format is in the script's
header.

`tests/run.sh` runs the helpers against a stub `gh` that replays
responses recorded from the real API (`tests/fixtures/`, 2026-11-11).
