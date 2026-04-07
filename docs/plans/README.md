# Plans Index

This directory contains active execution plans for `core_matrix`.

## Current Status (`2026-04-08`)

The current active planning documents in this directory are:

- [2026-04-03-multi-round-architecture-audit-and-reset-framework.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-04-03-multi-round-architecture-audit-and-reset-framework.md)
- [2026-04-03-round-1-architecture-audit-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-04-03-round-1-architecture-audit-design.md)
- [2026-04-03-round-1-architecture-reset.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-04-03-round-1-architecture-reset.md)
- [2026-04-03-recoverable-failure-step-resume-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-04-03-recoverable-failure-step-resume-design.md)
- [2026-04-03-recoverable-failure-step-resume-implementation.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-04-03-recoverable-failure-step-resume-implementation.md)
- [2026-04-06-fenix-cowork-roadmap-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-04-06-fenix-cowork-roadmap-design.md)

Practical state:

- Round 1 reset batches have already landed in code and verification.
- The recoverable-failure step-resume work is partially implemented and remains
  another open closure item in this directory.
- Current acceptance runs now execute through the top-level
  [acceptance harness](/Users/jasl/Workspaces/Ruby/cybros/acceptance/README.md),
  not the old `core_matrix/script/manual/acceptance` path.
- The completed April supervision and `2048` acceptance execution plans were
  archived to
  [docs/finished-plans](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/README.md).
- The current app-facing runtime/supervision contract draft lives in
  [docs/proposed-designs](/Users/jasl/Workspaces/Ruby/cybros/docs/proposed-designs/README.md).

Earlier execution plans, implementation records, and accepted reset designs
were archived to
[docs/finished-plans](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans)
after landing and verification.

Use these companion directories instead:

- [docs/finished-plans](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans)
  for completed `core_matrix` plans, milestones, and closeout records
- [docs/future-plans](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans)
  for deferred `core_matrix` follow-up work
- [docs/finished-plans/fenix](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/fenix)
  for archived `Fenix` design and implementation records

Add only currently executable, not-yet-completed round plans here.
