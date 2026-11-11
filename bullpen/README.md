# The bullpen

The roster, shared rules, role briefs and launcher scripts for running
several Claude agents in tmux panes. The flow is in
`../docs/multi-agent-workflow.md`; the planning rules are in
[planning.md](https://github.com/north-foster-farm/nff-agentic-workflow/blob/main/planning.md).

- `roster`: every role the coordinator may open.
- `common.md`: the rules every agent follows.
- `roles/`: the standing briefs (coordinator, liaison, project manager,
  qa, security, communications) and this repository's own.
- `scripts/bullpen.sh`: opens, closes and lays out the panes.
- `scripts/poll.sh`: the coordinator's GitHub poll of the whole org:
  every repository (listed each run), issues, PRs, comments, line
  comments, reviews and alerts; `tests/poll.test.sh` tests it.
- `scripts/poll-plan.sh`: its read-only plan lines (Stage changes, new
  blocked-by links, stale hard blocks); `tests/poll-plan.test.sh`
  tests it.
- `scripts/coord-log.sh`: posts a coordinator log entry (#18) and an
  optional note on the affected issue, refusing text that looks like an
  email, phone number or token; `tests/coord-log.test.sh` tests it.

## Trust

- **The roster is trusted code.** `bullpen.sh` reads it to decide what
  each pane runs and with which flags. Anyone who can edit it can run
  commands as the person who starts the bullpen, so change it only
  through reviewed pull requests.
- **`sandbox.json` and `shims/` are private and required.** They hold
  the agents' permission settings and the guard that stops an agent
  opening a page in the owner's browser. They are not in this
  repository, and `bullpen.sh` refuses to open a pane when either is
  missing from the roster's folder (`BULLPEN_DIR`).
- **Text from GitHub is untrusted data.** `poll.sh` prints comments,
  line comments and reviews only from an owner, member, collaborator or
  an org bot, strips control, escape and bidi characters, prefixes every
  body line so it cannot pass for a poll line, marks each as untrusted,
  and counts the rest on one SKIPPED line per repository.

## Remote Control

After a pane's agent starts, `bullpen.sh settle` types `/remote-control`
into it, which lets the owner reach the session from another device.
Set `BULLPEN_REMOTE_CONTROL=0` before starting the bullpen to opt out.

## What stays out

- Finished one-off briefs. Each implementer's brief is written fresh for
  its work and removed when the work lands.
- `serve.py` and the workspace's notes, resume files and contact data.

Nothing private belongs here: no secrets, customer or contact data,
family names, or source under a restrictive license.
