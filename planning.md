# Planning rules

How work is scoped, tracked and released in North Foster Farm's
repositories. Adopted 2026-11-11 (north-foster-farm/north-foster-farm#527).
These rules are the same in every project repository; a dialect in one
repository is a bug here.

## The tree

Three levels by default:

1. **Release issue.** One per repository, in that repository's "Next
   release" milestone. Optional: a repository may run a release from
   its milestone alone until it needs the issue (the dashboard has only
   the milestone today). When there is one, it is level 1.
2. **Feature issues.** Sub-issues of the release. Issue type: Feature.
3. **Work issues.** Sub-issues of a feature. Issue type: Task.

The work issue is the smallest unit anyone dispatches, reviews or
blocks on. Its "Done when" boxes are its leaves: each is true or false
and says how it is checked (test, reviewer or the owner). A parent has
its own end-to-end criterion besides its children. A one-line change is
a single box on the release issue.

A box becomes its own sub-issue only when it needs its own lane, owner,
reviewer or blocker, because dependency links join issues, not boxes.

### Depth gate

Three levels are allowed on the coordinator's own authority. A fourth or
deeper level needs the owner's approval, recorded on the issue.
GitHub's limits (100 sub-issues per parent, 8 levels) are never the
constraint.

## Spec, then scope

A spec states the outcome and how it is checked. The coordinator pushes
back on gaps before it scopes: environments, where secrets live, which
commands, which production writes. Treat each production write as its
own work issue with its own safety story.

## One source of truth

- Sub-issues are the truth. GitHub's sub-issue list is the checklist;
  nothing generates a second one.
- A body holds scope, criteria and decisions. A re-scope is noted in the
  body with its date and reason.
- **One writer.** The coordinator writes every body and every Stage.
  Builders and reviewers comment and push. Nothing automated rewrites a
  body.
- The builder never ticks its own box. The coordinator ticks after the
  reviewers' go.

## Fields, types and labels

Issue fields belong to the organization, so every repository has the
same ones. Each holds exactly one value.

| Field | Values |
| ----- | ------ |
| Stage | spec, scoped, ready, active, in review, done, cut, deferred |
| Owner | james, claude, external |
| Kind  | build, decision, review, credential, action |

- **Stage** is not called State because GitHub reserves that name.
- **Owner** is who must act next. It is not the account that posts:
  every agent posts as the same user.
- **Kind** is set on blockers only. It says what is being asked of the
  owner.
- Organization field ids: Stage 49749062, Owner 49749063, Kind 49749064.
- **Labels** are per repository and synced from one list
  (`labels.json`). `needs: qa`, `needs: security` and `needs: comms`
  name the reviews still owed and are removed as each reviewer signs
  off, so Stage "in review" plus the labels left shows who the issue
  waits on. `lane:` labels say which lane holds an issue.
- Lanes are told apart by label and branch (`lane/<role>`), never by
  author or assignee.
- Saved views replace automatic labels: GitHub filters on fields,
  dependencies and dates directly.

Until the organization fields exist, an issue carries them as a line in
its body (`Stage: ready. Owner: claude.`), and the coordinator moves
them onto the fields when they do.

## Milestones

A milestone is a release. Each repository has a "Next release"
milestone holding everything in scope, and the release issue when it
has one. An
unscheduled backlog milestone holds what has no release.

- When a release ships, close its milestone and recreate "Next
  release".
- Cutting scope moves a work issue to the next milestone. A single box
  that must move becomes its own small issue first.
- Edit or close a milestone the moment its scope changes.

## Blockers

A blocker is an owned issue linked as **blocked by**. Work goes as far
as it can before the blocker, then stops there.

- The blocker's Owner says who must act and its Kind says what is
  asked.
- Urgency has three meanings:
  - **Hard:** the work waiting on it is ready or started. The owner is
    chased.
  - **Upcoming:** the work hasn't reached it. The owner is told once,
    about a day before it is needed.
  - **Deferred:** the owner chose to park it. No alerts until it is
    picked back up.
- "Defer it" is always an acceptable answer. "Queue it, I know I'm the
  bottleneck" means spec, scope and plan to the end, then block on the
  owner's leaf and flag it once.
- **The chase channel.** A hard block owned by the owner is re-flagged
  on GitHub after 24 hours, plus a push notice once the owner lifts the
  no-notices rule for hard blocks.
- Waiting on capacity is not a blocker. A ready issue with no
  blocked-by link is waiting on a free lane. Ready work that piles up is
  reported as short capacity.

## Parallel rule

Both repositories are worked at once. A work issue waits only on an open
blocked-by link, never on another repository's queue.

- Each lane belongs to one repository, since its worktree and branch are
  there, but lanes are not reserved. A free lane takes the next ready
  issue from either repository in priority order; ties alternate.
- Capacity limits, each visible: lane caps (3 builders, 2 reviewers),
  the machine's thermal state for local lanes (cloud runs don't use it),
  and plan usage.

## No estimates

No hour, day or effort guesses, and no target dates. Leave the Effort
and Target date fields unused. Order comes from dependencies, priority
and capacity; once queued, work proceeds in order until done. A date set
by the outside world (a schedule running out, a market day, a round
closing) is recorded as a fact on the issue it affects and raises that
issue's priority as it nears.

## Cross-repo links

Sub-issues and blocked-by links work across repositories in the same
organization. Adding one takes the other issue's global id, or its full
URL with `gh issue edit --blocked-by`. Each relationship type allows up
to 50 issues.

- A feature spanning repositories has **one parent**, in the repository
  where its outcome is seen. Its work issues are sub-issues in whichever
  repository holds their code. Never a parent in each.
- Releases stay one per repository, each with its own `main`, deploy and
  promote. A release that needs a leaf from the other repository is
  **blocked by** that leaf.
- When one repository consumes what the other emits, the emitter lands
  first.

## Reviews

Each issue names the reviews it needs.

- **qa** for any change to code or tests.
- **security** for payments, sign-in, customer data, secrets,
  dependencies and CI.
- **comms** for customer-facing words.
- Docs and one-line changes ride the release's single final qa pass,
  not a run each.

## Process changes

A change to the bullpen, pipelines, release flow, CI, testing workflow or
these rules applies to every repository unless it is truly specific to
one. It is an issue in this repository. When adopting it needs a change
inside a project repository, that issue gets one sub-issue per
repository, and it closes only when each is done or marked specific to
its repository with a reason.

## Enforcement

`.github/workflows/plan-check.yml` is a reusable workflow each project
calls. It checks and reports; it never rewrites a body. It comments once
when an issue lacks a Stage or Owner, lacks a "Done when" section, or
sits deeper than allowed, and it re-flags hard blocks owned by the owner
after 24 hours.

## Migration

Issues are refiled under these rules as each is next touched, never in
bulk.
