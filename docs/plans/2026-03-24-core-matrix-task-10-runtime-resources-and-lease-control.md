# Core Matrix Task 10 Index: Add Execution Resources, Conversation Events, Human Interactions, Canonical Variables, And Lease Control

Part of `Core Matrix Kernel Phase 3: Conversation And Runtime`.

Use this index together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-phase-3-conversation-and-runtime.md`

This task group is split so process resources, human interactions, canonical variables, and coordination control can each be implemented with a smaller runtime surface in view.

---

Execute these subtasks in order:

- [Task 10.1: Add Workflow Artifacts, Node Events, And Process Runs](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-10-1-artifacts-events-and-process-runs.md)
- [Task 10.2: Add Human Interactions And Conversation Events](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-10-2-human-interactions-and-conversation-events.md)
- [Task 10.3: Add Canonical Variables](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-10-3-canonical-variables.md)
- [Task 10.4: Add Subagents And Leases](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-10-4-subagents-and-leases.md)

Task-group boundaries:

- Task 10.1 owns workflow artifacts, workflow node events, and process runs.
- Task 10.2 owns human-interaction resources and conversation-event projection.
- Task 10.3 owns canonical variable history and promotion.
- Task 10.4 owns `SubagentRun` coordination metadata and execution leases.

Execution rules:

- do not implement directly from this index
- load only the active subtask document during implementation
- apply the shared phase-gate audits after each subtask
