# Core Matrix Task Group 08: Add Transcript Support Models For Attachments, Imports, Summaries, And Visibility

Part of `Core Matrix Kernel Milestone 3: Conversation And Runtime`.

Use this task-group index together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-milestone-3-conversation-and-runtime.md`

This task group is split so visibility and attachment mechanics can be implemented independently from imports and summary-compaction behavior.

---

Execute these tasks in order:

- [Task 08.1: Add Visibility And Attachments](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-08-1-visibility-and-attachments.md)
- [Task 08.2: Add Imports And Summary Segments](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-08-2-imports-and-summary-segments.md)

Task group boundaries:

- Task 08.1 owns mutable visibility overlays and attachment materialization.
- Task 08.2 owns transcript imports, summary segments, and compaction-boundary semantics.

Execution rules:

- do not implement directly from this index
- load only the active task document during implementation
- apply the shared execution-gate audits after each task
- if a child task consults `references/` or external implementations, write the retained conclusion into that task document and any local docs it updates; do not leave only a bare reference path behind
