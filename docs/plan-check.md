# The plan check

A reusable workflow that holds issues to `../planning.md`. It checks and
reports. It never edits a body, title, field or label.

## What it does

On an issue event (`mode: issue`) it comments once when the issue:

- has no Stage or no Owner;
- has no "Done when" section in its body;
- sits deeper than three levels without the label `depth: approved`.

A marker in the comment (`plan-check:issue`) keeps it from commenting
again, so fixing the issue ends it. Pull requests and closed issues are
skipped.

On a schedule (`mode: hard-blocks`) it finds each open blocker owned by
`james` whose blocked issue is ready or active, and comments on it when
it has had no comment for 24 hours. The reminder repeats once per silent
day and stops when the owner answers, defers the work or closes the
issue.

## Calling it from a project

```yaml
name: plan-check
on:
  issues:
    types: [opened, edited, reopened]
  schedule:
    - cron: "17 14 * * *"
permissions: {}
jobs:
  issue:
    if: github.event_name == 'issues'
    uses: north-foster-farm/nff-agentic-workflow/.github/workflows/plan-check.yml@main
    with:
      mode: issue
    permissions:
      contents: read
      issues: write
  hard-blocks:
    if: github.event_name == 'schedule'
    uses: north-foster-farm/nff-agentic-workflow/.github/workflows/plan-check.yml@main
    with:
      mode: hard-blocks
    permissions:
      contents: read
      issues: write
```

`plan-check-self.yml` in this repository is the same caller, with a
manual trigger. Inputs: `mode`, `issue-number` (default: the event's
issue) and `ref` (the ref of this repository whose scripts run,
default `main`).

## Limits

- A reminder on a blocker in another repository needs a token that can
  write there; the repository's own `GITHUB_TOKEN` can't, so it logs a
  warning instead.
- Issue fields are read through the REST API with the workflow's token.
  If the token can't read the organization's fields, the job fails
  loudly rather than reporting a missing Stage.
- Issues made before these rules are checked when next edited, never
  in bulk (planning.md, "Migration").
- Tests are in `../tests/run.sh`. The first live run on a repository
  needs the caller above on its default branch.
