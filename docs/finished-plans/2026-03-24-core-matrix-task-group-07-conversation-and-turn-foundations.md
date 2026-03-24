# Core Matrix Task Group 07: Rebuild Conversation Tree, Turn Core, And Variant Selection

Part of `Core Matrix Kernel Milestone 3: Conversation And Runtime`.

Use this task-group index together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
3. `docs/finished-plans/2026-03-24-core-matrix-kernel-milestone-3-conversation-and-runtime.md`

This task group is split so conversation structure, turn entry state, and history-rewrite behavior can be implemented with smaller context windows and tighter acceptance boundaries.

---

Execute these tasks in order:

- [Task 07.1: Build Conversation Structure](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-task-07-1-conversation-structure.md)
- [Task 07.2: Build Turn Entry And Override State](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-task-07-2-turn-entry-and-override-state.md)
- [Task 07.3: Build Rewrite And Variant Operations](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-task-07-3-rewrite-and-variant-operations.md)

Task group boundaries:

- Task 07.1 owns conversation roots, lineage, purpose, archive lifecycle, and automation-root semantics.
- Task 07.2 owns `Turn`, `Message`, turn entry, selector persistence, override persistence, and queued-turn state.
- Task 07.3 owns rollback, tail edit, retry, rerun, and variant selection semantics.

Execution rules:

- do not implement directly from this index
- load only the active task document during implementation
- apply the shared execution-gate audits after each task
- if a child task consults `references/` or external implementations, write the retained conclusion into that task document and any local docs it updates; do not leave only a bare reference path behind

## Completion Record

- status:
  completed on `2026-03-24`
- landing commits:
  - Task 07.1: `ac93ecd` `feat: add conversation structure and lineage`
  - Task 07.2: `9733afb` `feat: add turn entry and selector state`
  - Task 07.3: `03c6d1c` `feat: add turn rewrite and variant operations`
- landed scope:
  - added workspace-rooted conversation lineage, lifecycle, and automation-root semantics
  - added turns, transcript-bearing message variants, selector persistence, override persistence, and queued-turn state
  - added rollback, tail edit, retry, rerun, and output-variant selection semantics on append-only transcript history
- verification evidence:
  - the child task records retain the exact targeted acceptance commands for Tasks 07.1, 07.2, and 07.3
  - `cd core_matrix && bin/rails db:test:prepare test` passed with `111 runs, 486 assertions, 0 failures, 0 errors` during the `2026-03-25` archival review rerun
- carry-forward notes:
  - Task Group 08 should layer attachments, visibility, imports, and summary segments onto the immutable transcript substrate from this group
  - later workflow and runtime work should consume selected transcript pointers and turn snapshots without inventing a second history-mutation model
