# Core Matrix Task Group 06: Build Usage Accounting, Rollups, And Execution Profiling Facts

Part of `Core Matrix Kernel Milestone 2: Governance And Accounting`.

Use this task-group index together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
3. `docs/finished-plans/2026-03-24-core-matrix-kernel-milestone-2-governance-and-accounting.md`

This task group is split so provider billing facts and generic execution profiling facts can be implemented without sharing unnecessary context.

---

Execute these tasks in order:

- [Task 06.1: Add Usage Events And Rollups](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-task-06-1-usage-events-and-rollups.md)
- [Task 06.2: Add Execution Profiling Facts](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-task-06-2-execution-profiling-facts.md)

Task group boundaries:

- Task 06.1 owns provider usage events and rollups.
- Task 06.2 owns generic execution profiling facts.

Execution rules:

- do not implement directly from this index
- load only the active task document during implementation
- apply the shared execution-gate audits after each task
- if a child task consults `references/` or external implementations, write the retained conclusion into that task document and any local docs it updates; do not leave only a bare reference path behind

## Completion Record

- status:
  completed on `2026-03-24`
- landing commits:
  - Task 06.1: `92d1dca` `feat: add provider usage events and rollups`
  - Task 06.2: `8c74487` `feat: add execution profiling facts`
- landed scope:
  - added detailed provider usage events plus derived rollup projection
  - added separate execution profiling facts for runtime telemetry that is not provider billing
- verification evidence:
  - the child task records retain the exact targeted acceptance commands for Tasks 06.1 and 06.2
  - `cd core_matrix && bin/rails db:test:prepare test` passed with `111 runs, 486 assertions, 0 failures, 0 errors` during the `2026-03-25` archival review rerun
- carry-forward notes:
  - later reporting and entitlement logic should treat usage events as durable truth and rollups as derived aggregates
  - later runtime resource work should continue to keep operational profiling separate from provider billing semantics
