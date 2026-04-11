# Plans Index

This directory contains active execution plans for the monorepo. Most plans are
primarily for `core_matrix` or `agents/fenix`, and only currently executable,
not-yet-completed work should remain here.

## Current Status (`2026-04-11`)

The current active planning documents in this directory are:

- [2026-04-03-recoverable-failure-step-resume-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-04-03-recoverable-failure-step-resume-design.md)
- [2026-04-03-recoverable-failure-step-resume-implementation.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-04-03-recoverable-failure-step-resume-implementation.md)
- [2026-04-11-agent-runtime-conversation-reset-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-04-11-agent-runtime-conversation-reset-design.md)
- [2026-04-11-agent-runtime-conversation-reset.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-04-11-agent-runtime-conversation-reset.md)

Practical state:

- The March-April reset framework, round-1 audit, round-1 reset ledger, and
  `Fenix` cowork roadmap have been archived because those tracks already
  landed and were superseded by the completed implementation records.
- The recoverable-failure step-resume work remains the only still-open
  legacy execution family in this directory.
- The agent/runtime/conversation reset is now an active destructive architecture
  reset track spanning `core_matrix`, `agents/fenix`, `executors/nexus`, docs,
  and acceptance.
- Current acceptance runs now execute through the top-level
  [acceptance harness](/Users/jasl/Workspaces/Ruby/cybros/acceptance/README.md),
  not the old `core_matrix/script/manual/acceptance` path.
- The completed April supervision and `2048` acceptance execution plans were
  archived to
  [docs/finished-plans](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/README.md).
- The completed app-facing runtime/supervision contract is archived in
  [docs/finished-plans](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/README.md).
- The completed April 8-9 `Fenix` cowork implementation, skills isolation,
  process runtime restoration, contract audit, and load-harness plans were
  archived to
  [docs/finished-plans/fenix](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/fenix/README.md).
- The remaining load-harness threshold work moved to
  [docs/future-plans](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/README.md).
- The completed April 10 throughput, provider transport, and `Fenix` role
  separation plans were archived to
  [docs/finished-plans](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/README.md)
  and
  [docs/finished-plans/fenix](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/fenix/README.md).

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
