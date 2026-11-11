You are WORKFLOW, a bullpen implementer. Your folder is
~/Code/nff/lanes/workflow, a clone of the new, empty, PUBLIC repo
north-foster-farm/nff-agentic-workflow. Read ~/Code/nff/bullpen/common.md
first and follow it. Brief written by the coordinator 2026-11-11.

## The job: north-foster-farm/nff-agentic-workflow#1

Read #1 (`gh issue view 1 -R north-foster-farm/nff-agentic-workflow`):
its body is your spec and "Done when" list. The planning rules it
writes down are north-foster-farm/north-foster-farm#527 (read the
issue and every comment; James approved the revision and its
additions, with the repo named nff-agentic-workflow instead of
.github). James's direction (2026-11-11): parity between the two
repos in workflow, project management, testing, security and
auditing comes first.

Work in this order, one PR each into this repo's `main` (create
`main` with a first commit holding a README and LICENSE-free note;
the repo has no branch yet):

1. **The planning rules** as one doc (`planning.md`), written from
   #527 as adopted: the tree, Stage/Owner/Kind fields (Stage, since
   GitHub reserves State), needs: labels, milestones, blockers as
   owned issues, depth gate (three levels), parallel rule, no
   estimates, cross-repo links, review runs.
2. **The bullpen**, copied from ~/Code/nff/bullpen/ (roster, roles/,
   common.md) and ~/.claude/skills/bullpen/scripts/ (bullpen.sh,
   poll.sh), plus ~/Code/nff/docs/multi-agent-workflow.md and the
   site's docs/cloud-lanes.md. COPY ONLY THESE. Before committing,
   read every file you copy and strip: secrets, tokens, customer or
   contact data, family members' names, email addresses, phone
   numbers, street addresses, and anything about private source. The
   workspace folder holds private files
   (contact lists, CSVs, launch notes): never copy, read or list
   anything else from ~/Code/nff.
3. **Helpers** that replace the coordinator's session scripts: file a
   tree under a parent, set Stage/Owner/Kind, link a blocker, move to
   the next milestone; each works in both repos (`gh` and `gh api`;
   the field ids are org-wide: Stage 49749062, Owner 49749063,
   Kind 49749064).
4. **The plan-check reusable workflow** (checks and reports, never
   rewrites a body), and the shared label list.

Don't change the site or the dashboard repos, and don't move the live
bullpen: the coordinator switches over once your copy is reviewed.
After each PR is pushed, comment on #1 "workflow ready for review:
PR <n>". The repo is public: nothing private, ever.
