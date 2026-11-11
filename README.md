# nff-agentic-workflow

How North Foster Farm plans and ships work with several Claude agents in
parallel. One home for the process, shared by the website and dashboard
repositories.

- `planning.md`: the planning rules (tree, fields, labels, blockers).
- `bullpen/`: the multi-agent roster, roles and shared rules.
- `scripts/`: helpers for the planning rules.
- `.github/workflows/plan-check.yml`: the reusable plan-check workflow.

A process change is an issue in this repository. When adopting it needs
a change inside a project repository, the issue gets one sub-issue per
repository.

## License

None. This repository is public so both projects can call its workflows,
not because it is open source. All rights reserved.
