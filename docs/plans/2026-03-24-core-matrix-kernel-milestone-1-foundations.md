# Core Matrix Kernel Milestone 1: Foundations

Use this milestone index together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/design/2026-03-24-core-matrix-kernel-phase-shaping-design.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
5. `docs/future-plans/2026-03-24-core-matrix-kernel-ui-follow-up.md`
6. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

This milestone owns Tasks 01-03, Task Group 04, and its child tasks:

- [Task 01: Re-Baseline The Rails Shell And Validation Scaffolding](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-01-shell-baseline.md)
- [Task 02: Build Installation, Identity, User, Invitation, Session, And Audit Foundations](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-02-installation-identity-and-audit.md)
- [Task 03: Build Agent Registry And Connectivity Foundations](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-03-agent-registry-and-connectivity.md)
- [Task Group 04: Build User Bindings, Private Workspaces, And Bundled Default-Agent Bootstrap](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-group-04-bindings-workspaces-and-default-agent.md)
- [Task 04.1: Build User Bindings And Private Workspaces](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-04-1-bindings-and-workspaces.md)
- [Task 04.2: Add Bundled Default-Agent Bootstrap](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-04-2-bundled-default-agent-bootstrap.md)

Milestone goals:

- establish the Rails shell baseline
- build installation, identity, invitation, session, and audit roots
- build the agent registry boundary
- build user bindings, private workspaces, and bundled default-agent bootstrap

Execution rules:

- execute the task documents in order
- load only the active execution-unit document during implementation
- treat this file as the milestone ordering index, not as the detailed task body
- apply the shared guardrails and execution-gate audits from the implementation-plan index after every task
- if Tasks 01-04 reveal a likely later root-shape or schema problem, fix that shape in the substrate now rather than deferring it into later execution-layer work
- keep the early registry and bundled-bootstrap work generic enough that later external execution adapters can attach without re-rooting the database model
