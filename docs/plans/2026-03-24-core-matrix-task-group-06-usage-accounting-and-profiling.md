# Core Matrix Task Group 06: Build Usage Accounting, Rollups, And Execution Profiling Facts

Part of `Core Matrix Kernel Milestone 2: Governance And Accounting`.

Use this task-group index together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-milestone-2-governance-and-accounting.md`

This task group is split so provider billing facts and generic execution profiling facts can be implemented without sharing unnecessary context.

---

Execute these tasks in order:

- [Task 06.1: Add Usage Events And Rollups](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-06-1-usage-events-and-rollups.md)
- [Task 06.2: Add Execution Profiling Facts](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-06-2-execution-profiling-facts.md)

Task group boundaries:

- Task 06.1 owns provider usage events and rollups.
- Task 06.2 owns generic execution profiling facts.

Execution rules:

- do not implement directly from this index
- load only the active task document during implementation
- apply the shared execution-gate audits after each task
