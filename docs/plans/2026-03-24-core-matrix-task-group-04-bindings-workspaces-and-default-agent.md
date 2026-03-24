# Core Matrix Task Group 04: Build User Bindings, Private Workspaces, And Bundled Default-Agent Bootstrap

Part of `Core Matrix Kernel Milestone 1: Foundations`.

Use this task-group index together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-milestone-1-foundations.md`

This task group is split into narrower task documents so workspace ownership rules and bundled bootstrap behavior can be implemented and verified separately.

---

Execute these tasks in order:

- [Task 04.1: Build User Bindings And Private Workspaces](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-04-1-bindings-and-workspaces.md)
- [Task 04.2: Add Bundled Default-Agent Bootstrap](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-04-2-bundled-default-agent-bootstrap.md)

Task group boundaries:

- Task 04.1 owns `UserAgentBinding`, `Workspace`, and default-workspace creation.
- Task 04.2 owns bundled runtime registration, first-admin bundled binding, and the bootstrap hook.

Execution rules:

- do not implement directly from this index
- load only the active task document during implementation
- apply the shared execution-gate audits after each task
