# The bullpen

How James runs agents on the North Foster Farm projects. GitHub is the
queue: one coordinator watches it, opens an agent for each piece of
work, sees the work through review onto `next` and `staging`, reports
back on the issue and closes the agent. First run 2026-09-24/25 (the
site launch); reshaped 2026-10-20 from "open the whole roster" to this.

## Starting it

In tmux, open `claude` in `~/Code/nff` and type **`/bullpen`**. That
session becomes the coordinator and moves into the tmux session
`northfosterfarm.com` as its `pm` window, over a free terminal for
James. The `dev` window holds the implementers and the `qa` window the
reviewers, each with a terminal of its own; both stay open with no
agents. A blocked agent rings the bell. It then starts polling GitHub. It
opens no agents
until there is work for them.

The poll (`~/.claude/skills/bullpen/scripts/poll.sh`) runs every 5
minutes while issues and comments are arriving, hourly after 2 quiet
hours, and daily after 2 more; any activity drops it back to 5
minutes. It runs as long as the coordinator does.

Each pane has one label, top left: its role on a block of its own
color (James's terminal: plain yellow text). No two live panes share a
color, and each agent's label matches its prompt lines (its
`/color`, read from the screen). `bullpen.sh recolor` repairs
any pane that drifts.

## The flow

1. A new issue or comment arrives. The coordinator curates it: scope,
   spec and a "Done when" checklist in the body, duplicates resolved,
   stale issues closed, the backlog kept in one linear order across
   milestones.
2. It dispatches the work to an implementer, opening one with
   `bullpen.sh hire <role>` (or `/hire` for a new role).
3. The implementer builds on `lane/<role>`, rebased on `next`, and
   reports to the coordinator against the checklist.
4. The coordinator sends the branch to the reviewers it needs and
   waits for each one's go.
5. It verifies the checklist itself, fast-forwards `next` and
   `staging`, comments on the issue and closes it.
6. It closes the agent (`bullpen.sh close <role>`).

The coordinator also watches every pane for an agent that has stalled,
restarts long sessions from a clear-resume, answers agents in the
Claude app who ask about the projects, and brings James whatever
needs him: questions, blockers he can't see (a permission dialog),
unclear specs, and requests it thinks are the wrong fix.

## The roles and the pool

| Role | Model | Live at once |
|---|---|---|
| coordinator | Opus, low effort | 1 |
| implementers (`impl` in the roster) | Sonnet, low | at most 3 |
| reviewers: `qa`, `security`, `communications` | Sonnet, low | at most 2 |
| liaison | Sonnet, low | only when James asks |

(Models updated 2026-11-11 to match the roster, set 2026-10-28.)

`bullpen.sh` enforces the caps (`BULLPEN_IMPL_CAP`,
`BULLPEN_REVIEW_CAP`). `communications` reviews new or changed
customer-facing text against the farm's voice and wording rules; once
i18n begins it also keeps a neutral Latin American Spanish translation
in sync. The liaison opens only when James is working in the terminal
and several agents have questions for him; otherwise questions go to
the coordinator.

The split is by files, not topics: two agents never own the same file.

## Where everything lives

- `~/Code/nff/bullpen/`: `roster` (who starts, their kind, their
  color, any extra `claude` flags), `common.md` (every agent's rules),
  `roles/<role>.md` (one brief each; the coordinator's too).
- `~/.claude/skills/bullpen/` (`/bullpen`, with the launcher in
  `scripts/bullpen.sh`) and `~/.claude/skills/hire/` (`/hire`).
- `~/Code/nff/lanes/<role>/`: each agent's folder. A `site` role's is a
  worktree of north-foster-farm on branch `lane/<role>` cut from
  `origin/staging`; a `desk` role's is a plain folder. The QA lane
  keeps its older worktree under the site repo.

Every agent's folder has two things git never tracks:

- **`.ignored/`**, its notes folder: its resume file
  (`.ignored/resume.md`), anything it makes that isn't committed, and
  anything handed to it. To give an agent a file, put it there.
- **`CLAUDE.local.md`**, its standing instructions, loaded in every
  session, including after a `/clear`: its role, where its brief and
  the rules are, where its notes go, and that questions and reports go
  to the coordinator.

The coordinator's notes folder is `~/Code/nff/.ignored/`.


## Clearing and resuming

Any agent saves with the clear-resume skill to `.ignored/resume.md` in
its folder. After `/clear`, say `resume from .ignored/resume.md`. A
role whose folder has a resume file starts from it; the rest start
from their briefs.

## Questions

No agent asks James directly. Each sends its questions to the
coordinator (or the liaison, when one runs) with its recommendation
and whether it's urgent or quick, keeps working on its assumption, and
gets the answer back.

## Landing and releasing

Implementers rebase on `next`, run lint, tests and a Hugo build, push
`lane/<role>`, and report. Only the coordinator moves `next` and
`staging`, as fast-forwards after the reviewers' go, so `main` can
fast-forward to staging. No agent pushes `main` or touches production
data or secrets; the coordinator releases only on James's explicit go,
by the runbook.

## What went wrong at launch, and the fix

- **Launch lines pasted into running sessions** gave agents the wrong
  brief or none: `/bullpen` and `/hire` open every agent in its place.
- **Two agents in one folder:** the skills check ListAgents first; one
  agent per folder.
- **A dozen agents asking at once:** the liaison.
- **Resume files colliding at a shared repo root:** every agent's is in
  its own `.ignored/`.
- **One rate limit for everyone:** the order and contact endpoints are
  limited per IP, shared by every agent on the machine; lockout tests
  are announced first.
- **Unattended runs:** before James sleeps, busy agents finish their
  item, land it, save, and stop. Never kill a session that says it's
  busy.
- **Shell traps** (heredocs, `< file`, a double-quoted `<`, backticks in
  double quotes) hang or run commands; they're in `common.md`.

## Cloud dispatch (2026-10-24)

Since 2026-10-24 implementers and most reviewers run as GitHub
Actions runs of Claude Code (#349, .github/workflows/claude.yml, rules
in docs/cloud-lanes.md), started by a coordinator comment on the issue.
They push lane/cloud-<n> and report on the issue. Local panes are kept
for work that needs James's Mac (secrets, local files, the local
browser profile, private security findings), at most 2 at once.
