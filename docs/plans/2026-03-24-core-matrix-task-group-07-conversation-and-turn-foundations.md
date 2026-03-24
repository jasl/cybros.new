# Core Matrix Task Group 07: Rebuild Conversation Tree, Turn Core, And Variant Selection

Part of `Core Matrix Kernel Milestone 3: Conversation And Runtime`.

Use this task-group index together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-milestone-3-conversation-and-runtime.md`

This task group is split so conversation structure, turn entry state, and history-rewrite behavior can be implemented with smaller context windows and tighter acceptance boundaries.

---

Execute these tasks in order:

- [Task 07.1: Build Conversation Structure](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-07-1-conversation-structure.md)
- [Task 07.2: Build Turn Entry And Override State](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-07-2-turn-entry-and-override-state.md)
- [Task 07.3: Build Rewrite And Variant Operations](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-07-3-rewrite-and-variant-operations.md)

Task group boundaries:

- Task 07.1 owns conversation roots, lineage, purpose, archive lifecycle, and automation-root semantics.
- Task 07.2 owns `Turn`, `Message`, turn entry, selector persistence, override persistence, and queued-turn state.
- Task 07.3 owns rollback, tail edit, retry, rerun, and variant selection semantics.

Execution rules:

- do not implement directly from this index
- load only the active task document during implementation
- apply the shared execution-gate audits after each task
