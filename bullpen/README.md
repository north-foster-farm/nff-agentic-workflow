# The bullpen

The roster, shared rules, role briefs and launcher scripts for running
several Claude agents in tmux panes. The flow is in
`../docs/multi-agent-workflow.md`; the planning rules are in
`../planning.md`.

- `roster`: every role the coordinator may open.
- `common.md`: the rules every agent follows.
- `roles/`: the standing briefs (coordinator, liaison, project manager,
  qa, security, communications) and this repository's own.
- `scripts/bullpen.sh`: opens, closes and lays out the panes.
- `scripts/poll.sh`: the coordinator's GitHub poll.

## What stays out

- Finished one-off briefs. Each implementer's brief is written fresh for
  its work and removed when the work lands.
- `sandbox.json` (the agents' permission settings), `shims/` and
  `serve.py`, which `bullpen.sh` reads from the workspace folder next to
  the roster. They hold machine settings, not process.
- The workspace's notes, resume files and contact data.

Nothing private belongs here: no secrets, customer or contact data,
family names, or source under a restrictive license.
