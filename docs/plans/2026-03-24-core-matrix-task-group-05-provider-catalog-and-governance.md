# Core Matrix Task Group 05: Build The Config-Backed Provider Catalog And Governance Models

Part of `Core Matrix Kernel Milestone 2: Governance And Accounting`.

Use this task-group index together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-milestone-2-governance-and-accounting.md`

This task group is split so config-backed catalog semantics and persisted governance surfaces can be implemented and reviewed independently.

---

Execute these tasks in order:

- [Task 05.1: Add Provider Catalog Config And Validation](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-05-1-provider-catalog-config.md)
- [Task 05.2: Add Provider Governance Models And Services](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-05-2-provider-governance-models.md)

Task group boundaries:

- Task 05.1 owns config-backed provider and role catalog loading plus schema validation.
- Task 05.2 owns persisted credentials, entitlements, policies, and their audited service boundaries.

Execution rules:

- do not implement directly from this index
- load only the active task document during implementation
- apply the shared execution-gate audits after each task
