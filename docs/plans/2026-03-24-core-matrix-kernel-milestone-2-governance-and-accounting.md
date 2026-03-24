# Core Matrix Kernel Milestone 2: Governance And Accounting

Use this milestone index together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/future-plans/2026-03-24-core-matrix-kernel-ui-follow-up.md`
5. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

This milestone owns Task Groups 05-06 and their child tasks:

- [Task Group 05: Build The Config-Backed Provider Catalog And Governance Models](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-group-05-provider-catalog-and-governance.md)
- [Task 05.1: Add Provider Catalog Config And Validation](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-05-1-provider-catalog-config.md)
- [Task 05.2: Add Provider Governance Models And Services](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-05-2-provider-governance-models.md)
- [Task Group 06: Build Usage Accounting, Rollups, And Execution Profiling Facts](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-group-06-usage-accounting-and-profiling.md)
- [Task 06.1: Add Usage Events And Rollups](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-06-1-usage-events-and-rollups.md)
- [Task 06.2: Add Execution Profiling Facts](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-06-2-execution-profiling-facts.md)

Milestone goals:

- build the config-backed provider catalog and governance surfaces
- land the model-role catalog and related resolution prerequisites
- build usage accounting, rollups, and profiling facts before runtime execution resources start writing into them

Execution rules:

- execute the task documents in order
- load only the active execution-unit document during implementation
- treat this file as the milestone ordering index, not as the detailed task body
- apply the shared guardrails and execution-gate audits from the implementation-plan index after every task
- if a child task consults `references/` or external implementations, write the retained conclusion into that task document and any local docs it updates; do not leave only a bare reference path behind
