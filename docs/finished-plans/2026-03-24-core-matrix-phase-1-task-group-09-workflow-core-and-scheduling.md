# Core Matrix Task Group 09: Rebuild Workflow Core, Context Assembly, And Scheduling Rules

Part of `Core Matrix Kernel Milestone 3: Conversation And Runtime`.

Use this task-group index together with:

1. `AGENTS.md`
2. `docs/finished-plans/2026-03-24-core-matrix-phase-1-kernel-greenfield-implementation-plan.md`
3. `docs/finished-plans/2026-03-24-core-matrix-phase-1-kernel-milestone-3-conversation-and-runtime.md`
4. `docs/design/2026-03-24-core-matrix-model-role-resolution-design.md`

This task group is split so graph structure, scheduler semantics, selector resolution, and context assembly can each be implemented against narrower runtime concerns.

---

Execute these tasks in order:

- [Task 09.1: Build Workflow Graph Foundations](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-phase-1-task-09-1-workflow-graph-foundations.md)
- [Task 09.2: Add Scheduler And Wait States](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-phase-1-task-09-2-scheduler-and-wait-states.md)
- [Task 09.3: Add Model Selector Resolution](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-phase-1-task-09-3-model-selector-resolution.md)
- [Task 09.4: Add Context Assembly And Execution Snapshot](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-phase-1-task-09-4-context-assembly-and-execution-snapshot.md)

Task group boundaries:

- Task 09.1 owns workflow graph tables, models, and acyclic mutation.
- Task 09.2 owns scheduler semantics and workflow wait-state behavior.
- Task 09.3 owns selector normalization, entitlement-aware fallback, and resolved model snapshots.
- Task 09.4 owns context assembly, attachment manifests, and execution snapshot projection.

Execution rules:

- do not implement directly from this index
- load only the active task document during implementation
- apply the shared execution-gate audits after each task
- if a child task consults `references/` or external implementations, write the retained conclusion into that task document and any local docs it updates; do not leave only a bare reference path behind
