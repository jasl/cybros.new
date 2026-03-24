# Core Matrix Task Group 04: Build User Bindings, Private Workspaces, And Bundled Default-Agent Bootstrap

Part of `Core Matrix Kernel Milestone 1: Foundations`.

Use this task-group index together with:

1. `AGENTS.md`
2. `docs/finished-plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
3. `docs/finished-plans/2026-03-24-core-matrix-kernel-milestone-1-foundations.md`

This task group is split into narrower task documents so workspace ownership rules and bundled bootstrap behavior can be implemented and verified separately.

---

Execute these tasks in order:

- [Task 04.1: Build User Bindings And Private Workspaces](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-task-04-1-bindings-and-workspaces.md)
- [Task 04.2: Add Bundled Default-Agent Bootstrap](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-task-04-2-bundled-default-agent-bootstrap.md)

Task group boundaries:

- Task 04.1 owns `UserAgentBinding`, `Workspace`, and default-workspace creation.
- Task 04.2 owns bundled runtime registration, first-admin bundled binding, and the bootstrap hook.

Execution rules:

- do not implement directly from this index
- load only the active task document during implementation
- apply the shared execution-gate audits after each task
- if a child task consults `references/` or external implementations, write the retained conclusion into that task document and any local docs it updates; do not leave only a bare reference path behind

## Completion Record

- status:
  completed on `2026-03-24`
- landing commits:
  - Task 04.1: `fe34078` `feat: add user bindings and workspaces`
  - Task 04.2: `508ab0b` `feat: add bundled default agent bootstrap`
- landed scope:
  - established the user-owned chain
    `User -> UserAgentBinding -> Workspace`
  - made binding enablement idempotent for a given user-agent pair
  - kept workspaces private and default-workspace uniqueness scoped to a
    binding
  - added opt-in bundled runtime reconciliation and first-admin auto-binding by
    composing the existing binding and workspace services
- verification evidence:
  - `cd core_matrix && bin/rails test test/integration/user_binding_workspace_flow_test.rb test/integration/bundled_default_agent_bootstrap_flow_test.rb`
    passed during the `2026-03-24` doc-hardening rerun as part of the
    Milestone 1 spot-check
- carry-forward notes:
  - future bootstrap, onboarding, or provider-adapter work should keep using
    `UserAgentBindings::Enable` and `Workspaces::CreateDefault`
  - bundled runtime registration stays a packaged-runtime path only; generic
    connector work remains later scope and should still model itself through
    the same registry aggregates
