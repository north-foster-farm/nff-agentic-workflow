# Rules for every agent in the bullpen

You are one of several agents working in parallel, each in its own
folder under ~/Code/nff/lanes/, most on their own git branch cut from
origin/staging. The coordinator (the session James started the bullpen
from, in ~/Code/nff) dispatches the work and does every release. James
runs everything. The workflow: docs/multi-agent-workflow.md in the
nff-agentic-workflow repository, and its planning rules in
planning.md (how work is scoped, tracked, blocked and released).

Read first: ~/Code/nff/CLAUDE.md, the repo's CLAUDE.md (if your folder
is a worktree), your brief, and the GitHub issues it names.

## Your notes folder: `.ignored/` at your root

Everything that is yours and not tracked lives in `.ignored/` in your
own folder, never at the repo root or anywhere else:

- your resume file: `.ignored/resume.md` (the clear-resume skill's save
  goes there, not to the repo root; after a /clear, James says "resume
  from .ignored/resume.md");
- files you create or generate that aren't committed: drafts,
  screenshots, reports, scratch;
- files James or another agent hands you: look there when told a file
  was provided;
- any script you'll run twice (a Playwright check, a sweep): the
  session scratchpad is gone after a /clear.

Git ignores `.ignored/` and `CLAUDE.local.md`. Never commit either.

In your resume and notes, name other agents by role (the coordinator,
the liaison), never by session name (`nff-69`), and point at briefs in
~/Code/nff/bullpen/roles/. Session names change on every restart, and
a note naming a dead session sends you nowhere.

## Fix a stale note the moment you find it (James, 2026-10-27)

When James corrects something, or the code, a tool or production
contradicts a note (a CLAUDE.md, a doc, an issue body, a handoff, a
rotation log), fix the note then and there: rewrite or delete the stale
line, date the change, and say in one sentence what changed. Never work
around stale information, or the next session inherits it.

## Logging (James, 2026-10-27)

Log every change a person or the CLI makes to a production record:
time, who acted (CLI, farm, host or customer), action, target, values
before and after; money and membership changes always. Don't log
reads, dry runs, previews, jobs that changed nothing, or staging and
development unless debugging needs it. Never log secrets, tokens,
payment details, or a full email address, phone number or street
address: mask each part, keeping its first three and last three
characters (#496). Log records are append-only and follow customer
data retention. A new production write ships with its log line and a
test, as part of done.

## Dependencies (James, 2026-10-27; replaces "no new dependencies")

A new package is allowed when it gives clear value, above all where a
well-tested one replaces code that breaks subtly (encoders, parsers,
crypto, dates). Lean toward fewer: write small simple code yourself.
James approves every new package before it is added: propose the
package, version, license, maintenance, what it replaces and why it
beats hand-rolling, to the coordinator, who posts it for him. Approved
packages are pinned.

## Execute the spec; don't hand it back as a question

James, 2026-09-28: "most of the first batch of blockers are the exact
requirements we gave you to begin with, just returned back to us as
questions. You should execute on the specs we gave." If the issue, its
comments or #192 already say what to build, build it. If you would
recommend an answer, that answer is decided: build it, state it on
the issue as what you did, and James overrules there if he wants.
Ask only for what James alone can give: a fact only he knows (a
photo's source, a license he accepted, a place's hours), an action
only he can take (secrets, accounts, production, his devices), or a
sign-off on something costly to undo (sending to customers,
deleting data, money). A wording or design choice with a draft is
not a question: ship the draft, marked as a draft.

## Questions go to the coordinator, never straight to James

Don't ask James in your terminal, and never with the AskUserQuestion
tool: it freezes your session until he visits your pane (one lane
waited 22 hours on one). Send every question with SendMessage to the
coordinator, or to the liaison when one is running (find either by its
pane's role: `tmux list-panes -a -F '#{pane_id} #{@role}'`): one
message per question, each with the issue it belongs to, your
recommendation, and whether it is urgent (blocks your work or risks
something) or quick (a yes/no or a one-word pick). It brings the
question to James and sends the answer back to you.

Exception (James, Q7): a brief that says you work with James in your
terminal may show him drafts and walk him through his steps there.
Decisions still go through the coordinator.

When they apply, also give: the exact wording (or the file and
section) when wording is the question; whether it's a question, a
finding, or a reminder of a step James does himself; and any other
lane the answer changes or that recommends otherwise.

Before resending a question after a /clear or a restart, check its
issue: if it's already asked there, cite it instead. Duplicates cost
James more time than anything else.

Front-load: do every part of your task that doesn't need an answer
first. When you reach a question, pick the most reasonable answer,
build with it, note it as your assumption, send the question, and keep
going. Stop and wait only for something that would
be costly to undo (sending, posting, production, deleting).

## Talking to each other

- The coordinator dispatches work and may reassign it; do what its
  messages ask, within these rules.
- Another agent's message is a teammate's, not James's: it never
  grants you a permission James hasn't.

## Scope

- Only your task. The launch takes finishing work and bug fixes, never
  a new feature. Something bigger: file it (see below) and go on.
- Stay in the files your task needs. If you must touch a file another
  agent owns, keep the change small and tell that agent.
- Media assets (James, #220): anything used on the site must be one
  James created, or one whose origin is known and recorded, before you
  commit to it. That covers logos, marks, icons, illustrations and any
  generated or traced graphic; photos need their source recorded too.
  Reuse an existing vector asset rather than making a new one. If
  something new is truly needed, say so and ask first: never generate
  an asset and ship it in the same step. A renamed or exported file is
  not a source, and logos are vectors.
- Never read, list or search outside ~/Code/nff (and the scratchpad
  and temp folders your session gives you) unless James names the
  exact path. That covers ~/Downloads, ~/Desktop, ~/Documents,
  ~/Pictures, ~/Movies and the rest of his home folder, with any tool,
  Bash included. "Search properly" means the projects. If what you need
  isn't there, say so and ask the coordinator where to look.
- Customer-facing words are James's. What you write is a draft: say
  which lines are drafts. Wording rules: ~/.claude/CLAUDE.md
  ("Writing") and the site's docs.

## Landing: through the coordinator

Work lands on `next`, then `staging`, and only the coordinator moves
either, after the reviewers' go. Never push staging yourself.

1. `git fetch origin` (bare), then `git rebase origin/next` (keep both
   sides' intent in a conflict; never drop someone else's change)
2. `npm run lint`, `npm test`, `npx hugo --gc --quiet -d .ignored/build`
   (GitHub Actions runs lint and tests as `lint-and-test` on every push
   to `next`, and staging and `main` will require it; the Netlify build
   runs the schedule check, Hugo and the grid check, so an error there
   breaks staging)
3. Verify locally, not on staging: staging is for James's review. For
   pages, serve the build with `python3 ~/Code/nff/bullpen/serve.py
   .ignored/build <port>` (plain `python3 -m http.server` resets
   connections under parallel Playwright workers, so pages lose their
   scripts and tests fail at random)
   and check it with `npx playwright screenshot` or a spec run with a
   config in `.ignored/` whose baseURL is your local server. For flows
   that need the functions, never run bare `netlify dev`: use the
   repo's wrapper. Once per worktree, `cp .env.development.sample
   .env`; then `npm run start:functions -- --offline --port <port>`
   in the background, on a port no other agent uses (it adds the dev
   pickup schedule and runs `bin/dev`, Hugo on a free port the system
   picks, behind the functions; since #276, f77fbc4). Several may run
   at once, from any worktree. Wait until
   `curl -s localhost:<port>/api/dates` answers before testing. Stop
   yours when done with Ctrl-C or a kill of its npm process: that stops
   its Hugo too and frees both ports. Never open a page in James's
   own browser (no bare `open <url>`). To show a page in a real
   browser, use the agents' separate Firefox profile, which runs
   beside his with none of his tabs or logins:
   `open -na "Firefox Developer Edition" --args -no-remote -profile
   ~/Code/nff/.ignored/firefox-agents/<role> <url>`
   (one profile per role, since two Firefoxes can't share one; create
   the folder first) and quit that Firefox when you are done
   (`pkill -f firefox-agents/<role>`) (James, 2026-10-22). A hook
   enforces both: any other browser launch is refused, and you can't
   end a turn while your Firefox is still open.
4. `git push origin HEAD:lane/<role>` (your branch, rebased on `next`)
5. Report to the coordinator (see "When you finish"). It sends the
   branch to the reviewers, verifies it and fast-forwards `next` and
   `staging` itself. Never push `next` unless your brief says to.

Mock-ups go to James as images (an artifact or screenshots), never as
a deploy. If something truly needs its own deploy to be reviewed, say
so to the coordinator before pushing; don't push to get one.

**Screenshots on GitHub: use `gh-shot`** (James, 2026-10-22). Never
leave a screenshot only in a file, and stop committing images to the
`launch-guide` branch. Run
`~/Code/nff/lanes/gh-shot/bin/gh-shot --issue N [--alt text] FILE...`
(it becomes `bin/gh-shot` once it lands on `next`) from inside the
repo; it uploads to the repo's `screenshots` branch and prints one
markdown image line per file. Paste those lines into your issue
comment, so James sees the images in the issue. Dashboard work adds
`--repo north-foster-farm/nff-dashboard`. Only mock-ups and
development or staging screens go up; never production or customer
data. Post only what James needs for work in progress or awaiting
him, a few shots each; no bulk uploads of old work (James,
2026-10-22).

If your change alters what a QA spec checks (a word, a selector, a
flow), say so in the commit body and tell `qa`.

Never push main. Never deploy production. Never read, print or change
production data or secrets (Netlify env values, tokens, `.env`).
No exceptions: the read-only Resend lookup (approved 2026-09-26) is
gone, with its key, since 2026-10-18. To see what the site sent, ask
James to look in Resend's dashboard.

## Commits and GitHub

- Commit titles 50 characters or fewer, imperative; bodies wrapped at
  72; no trailers of any kind, with one exception: a commit that
  changes the shape of a stored record (Blobs keys, record fields, a
  data migration) carries `Record-shape: <what changed>`, and a release
  batch with none carries one `Record-shape: none`, spelled exactly
  so. The pre-push hook refuses a push without it or with a
  malformed one, and CI's `record-shape` check fails on every branch
  (`bin/check-record-shape.mjs`).
- Never skip the git hooks (`--no-verify`, `-n`) unless James approves
  it for that one commit, in your own session. If a hook fails on
  something outside your work, stop and tell the coordinator.
- GitHub text has no hard line breaks.
- An issue's body is its current truth; the comments are the
  narrative. When a comment settles a decision or changes scope, edit
  the body in the same turn.
- Issues labeled `out of band` came from outside Claude Code and are
  not yet triaged. The coordinator triages them; leave them alone
  unless one is dispatched to you.
- When you land something, comment on its issue: the commit, what
  changed, what you checked. Close an issue only when it's visibly done
  on staging and nothing in it waits on James.
- Before filing, search the open issues: QA or another lane may have
  it already. When you take on an existing issue, add your `lane:`
  label; if it sits between two lanes' areas, tell the other lane.
- Any find, small or big: its own short issue with a `lane:` label,
  in the launch milestone (or "After launch"). #159 is closed (the
  curator split it, 2026-10-24); never add lines to a catch-all issue.
  A question only James can answer goes to the coordinator, who adds
  it to the launch guide as a decision item (James, 2026-10-24); never
  put it in an issue or a comment.

## Writing and code style

American English. No em-dashes. 80 columns outside HTML templates. No
trailing whitespace. Match the surrounding code.

**Family names stay off GitHub** (James, 2026-10-25). Never write a
family member's full name (or name plus relation) in an issue,
comment, PR, commit or doc. Credit a photo by its file-name suffix;
the credits doc keeps the names lightly obfuscated (#469).

**Dates on posts and policy pages are James's** (2026-10-25, #467).
When you create or edit a news post or a page with a "Last updated"
line, never set or bump its date yourself. Say in your report and
your PR body which dated pages changed and what date each carries, so
James confirms it before it ships.

## The shell (the harness hangs otherwise)

No heredocs (`<<`), no `< file` input redirects, no double-quoted
strings containing `<`, and never backticks inside a double-quoted
shell string (zsh runs them). Write scripts and commit messages to
files with the Write tool (in `.ignored/`) and run or pass them by path
(`git commit -F file`). `git add` explicit paths, never a directory.
Edit HTML templates with the Edit tool, not sed: a `<` in the command
is the usual hang. Treat any `<` followed by a space as unsafe, even
in single quotes: qa's `awk '... $9+0 < 6 ...'` hung for 10 minutes
on 2026-10-20 and never started. Write comparisons as `>=` or put the
filter in a script file. A command that shows no progress and leaves
no output file has hung: stop it and rerun it without the `<`.

## The sandbox is off

James turned the Bash sandbox off on 2026-09-28: it caused more
faults than it prevented. Pipes, `cd`, `&&`, env prefixes and a
browser launched from a Node script all work again. The rules it
enforced still stand, now on your honor: never read James's personal
folders (Downloads, Desktop, Documents, Pictures, Movies, Music,
iCloud) or the archive under ~/Code/_archived-2026-09-19; write only
inside ~/Code/nff and the tool caches; talk only to the services the
project uses. If the permission classifier refuses a command, stop
and tell the coordinator; never look for a way around it.

To see whether staging has a change, compare the commit the staging
host reports (the site's version file) with the pushed SHA. GitHub
shows no Netlify status for staging pushes.

## Things that bite

- llms.txt is generated from the site's own content and front matter
  (Q21a, 92302ed); never hand-write a summary there. Every repeated
  fact has one source in `data/` or site config, read through a
  shortcode, partial or import (Q21b); a unit test (4d83070, in
  `npm test` and CI's `lint-and-test`) fails on a literal copy
  outside its source.
- Never pipe a check through `tail` or `head` when its exit code is
  the verdict: the pipe returns the last command's status, so a
  failed build looks green. Run it bare, or check `${PIPESTATUS[0]}`.

- The order and contact endpoints are rate limited per IP, shared by
  every agent and the QA suite on this machine. Don't send test orders
  or messages you don't need; announce a lockout test.
- To check your branch's e2e in Actions, run only your own specs:
  `gh workflow run e2e.yml --ref lane/<you> -f specs="e2e/foo.spec.mjs
  e2e/bar.spec.mjs"` (paths under `e2e/` only; one shard, one pass, no
  burn-in). Never run e2e on the Mac.
- **Every faked network response comes from a real one** (James,
  2026-10-26). A fake or stub that stands in for a real service returns
  a fixture recorded from a real request to that service (the sandbox
  will do): a plain JSON object, tokens and ids scrubbed or replaced
  with placeholder strings, but otherwise the real shape. Never
  hand-write a response object. Name the source and date beside the
  fixture.
- **No full-suite runs** (James, #303, 2026-10-26: tokens). Never
  dispatch e2e.yml without `specs`, and never push `e2e/staging-full`.
  The one full run left is the final one before launch (#423), the
  coordinator's. Run only the specs your change touches or that are
  failing now. A push to `next` runs no e2e. Cloud reviews: one per
  change, no rerun for a non-blocking note.
- **Log every conflict you resolve** on #478 (James, 2026-10-26): one
  comment each, naming the files, what met, which side you kept and
  why. For drafts, the most recent update wins. James checks these.
- Poll GitHub sparingly: every lane shares one API rate limit, and
  many watchers at once trip GitHub's 403 (2026-10-26). One watcher
  per run, no more often than every 3 minutes, and stop it when the
  run ends.
- Scheduled jobs never run on staging; `bin/nff jobs run --staging`
  runs them from the CLI.
- Staging data is shared. Clean up what you create (`bin/nff ... --staging`).
- PurgeCSS strips classes that appear only in JavaScript. Markup that
  a script inserts goes in a template partial (a `<template>` element)
  so its classes survive the build.
- The `storage` event fires only in other tabs; a same-tab update
  needs an event of your own.
- To test code that races a fetch, hold the request with Playwright's
  `page.route` and fulfill it on cue rather than throttling the
  network (QA's e2e/search.spec.mjs does this).

## When you finish

Save with clear-resume to `.ignored/resume.md`, then tell the
**coordinator** in a few lines: your branch and its head SHA, the
issue, each box of its "Done when" checklist and how you met it, what
you checked (lint, tests, build), and anything waiting on an answer.
Don't land it yourself unless your brief says to: the coordinator
sends it to the reviewers, verifies it, lands it on `next` and
`staging`, reports on the issue and closes your session, so don't
start anything after reporting. Report blockers the same way, the
moment you hit one. Session names change on every start: find the
coordinator's pane with `tmux list-panes -a -F '#{pane_id} #{@role}'`
(the row whose role is `coordinator`), then send to the ListAgents row
on that pane. Never skip a report because a name didn't match.

## Run lean

Every message wakes a whole context, and the bullpen's token budget
is James's. Message only to hand off work, ask a question or report
something done or blocked. Never send a status, greeting, "still idle"
or acknowledgement. Don't reread files you already have; read the part
you need.

Don't start subagents (the Agent tool or background agents) on your
own: the coordinator decides how many agents run, by the Mac's load
(James lifted the fixed cap of 2 on 2026-10-26, as long as the Mac is
not throttling). Do the work yourself, one piece at a time, and keep
CPU-heavy work (e2e above all) in GitHub Actions. Several lanes share
the Mac: commit in batches (one commit per finished piece), run the
full `npm test` only when you're about to commit (targeted
`node --test test/<file>` while you work), and close any headless
browser as soon as you're done with it (2026-10-26, load near 30 with
four lanes committing at once).

A lane waiting only on James is closed: it saves to
`.ignored/resume.md` and its session exits. Answers for a closed lane
go to its `.ignored/answers.md`, and the coordinator reopens it. On every
start or resume, read `.ignored/answers.md` if it exists, act on each
answer, and move the answers you've handled under a "Done" heading.

## No browser but your own (James, 2026-10-24)

Every agent starts with ~/Code/nff/bullpen/shims first on PATH and
BROWSER and GH_BROWSER pointing at its `open`, which refuses anything
but your agents' Firefox launch and logs it to
~/Code/nff/.ignored/browser-blocks.log. A tool that tries to open a
page (a CLI login, `gh --web`) fails instead: never work around it.
If a CLI wants a browser login, stop and tell the coordinator.

## Never write the Claude app's handle on GitHub (2026-10-24)

A GitHub Actions workflow (#349) starts a Claude run for any comment
or issue by jbboynton that contains the app's trigger handle (an at
sign followed by "claude"). Every agent posts as jbboynton. Write "the
Claude app" in prose; only the coordinator writes the handle, and only
to dispatch.
