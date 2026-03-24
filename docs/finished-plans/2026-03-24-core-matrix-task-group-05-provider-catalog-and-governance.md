# Core Matrix Task Group 05: Build The Config-Backed Provider Catalog And Governance Models

Part of `Core Matrix Kernel Milestone 2: Governance And Accounting`.

Use this task-group index together with:

1. `AGENTS.md`
2. `docs/finished-plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
3. `docs/finished-plans/2026-03-24-core-matrix-kernel-milestone-2-governance-and-accounting.md`

This task group is split so config-backed catalog semantics and persisted governance surfaces can be implemented and reviewed independently.

---

Execute these tasks in order:

- [Task 05.1: Add Provider Catalog Config And Validation](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-task-05-1-provider-catalog-config.md)
- [Task 05.2: Add Provider Governance Models And Services](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-task-05-2-provider-governance-models.md)

Task group boundaries:

- Task 05.1 owns config-backed provider and role catalog loading plus schema validation.
- Task 05.2 owns persisted credentials, entitlements, policies, and their audited service boundaries.

Execution rules:

- do not implement directly from this index
- load only the active task document during implementation
- apply the shared execution-gate audits after each task
- if a child task consults `references/` or external implementations, write the retained conclusion into that task document and any local docs it updates; do not leave only a bare reference path behind

## Completion Record

- status:
  completed on `2026-03-24`
- landing commits:
  - Task 05.1: `6074088` `feat: add provider catalog config validation`
  - Task 05.2: `2cc4bc4` `feat: add provider governance models`
- landed scope:
  - added the config-backed provider, model, and model-role catalog with strict validation
  - added installation-scoped provider credentials, entitlements, policies, and audited service boundaries
- verification evidence:
  - the child task records retain the exact targeted acceptance commands for Tasks 05.1 and 05.2
  - `cd core_matrix && bin/rails db:test:prepare test` passed with `111 runs, 486 assertions, 0 failures, 0 errors` during the `2026-03-25` archival review rerun
- carry-forward notes:
  - later selector and execution work should keep catalog data config-backed while leaving mutable installation facts in SQL
  - later provider integrations should keep audited writes flowing through the explicit governance services rather than direct model saves
