# The plan check

A reusable workflow that holds issues to `../planning.md`. It checks and
reports. It never edits a body, title, field or label.

## What it does

On an issue event (`mode: issue`) it comments once when the issue:

- has no Stage or no Owner;
- has no "Done when" heading in its body;
- sits deeper than three levels without the label `depth: approved`.

A marker in the comment (`plan-check:issue`) keeps it from commenting
again, so fixing the issue ends it. Only the bot's own comments count
as a marker, so a pasted marker from anyone else can't silence it.
Pull requests and closed issues are skipped.

On a schedule (`mode: hard-blocks`) it finds each open blocker owned by
`james` whose blocked issue is ready or active, and comments on it when
it has had no comment for 24 hours. Only comments by the bot or an
owner, member or collaborator reset that clock. The reminder repeats
once per silent day and stops when the owner answers, defers the work
or closes the issue.

## Calling it from a project

Pin both the `uses:` line and `ref:` to one commit SHA of this
repository, never `@main`, so a change here reaches a project only
when someone reviews and bumps it. Replace `<sha>` below; the tag in the
comment is for people.

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
    uses: north-foster-farm/nff-agentic-workflow/.github/workflows/plan-check.yml@<sha>
    with:
      mode: issue
      ref: <sha>
    permissions:
      contents: read
      issues: write
  hard-blocks:
    if: github.event_name == 'schedule'
    uses: north-foster-farm/nff-agentic-workflow/.github/workflows/plan-check.yml@<sha>
    with:
      mode: hard-blocks
      ref: <sha>
    permissions:
      contents: read
      issues: write
```

`plan-check-self.yml` in this repository is the same caller, with a
manual trigger; it runs the checked-out commit. Inputs: `mode`,
`issue-number` (default: the event's issue) and `ref` (required: the
commit SHA of this repository whose scripts run, the same as in `uses:`).

**To bump the pin,** take the new commit's SHA from `git ls-remote
https://github.com/north-foster-farm/nff-agentic-workflow main`, change
both places in each caller, and merge that as a normal reviewed change.

Runs are serialized per issue (`concurrency`), and the issue number is
checked to be digits before use.

## Limits

- A hard-block reminder on a blocker in another repository is skipped
  (with a logged warning) unless the token can write there; the
  repository's own `GITHUB_TOKEN` can't.
- Issue fields are read through the REST API with the workflow's token.
  If the token can't read the organization's fields, the job fails
  loudly rather than reporting a missing Stage.
- Issues made before these rules are checked when next edited, never
  in bulk (planning.md, "Migration").
- Tests are in `../tests/run.sh`. The first live run on a repository
  needs the caller above on its default branch.
