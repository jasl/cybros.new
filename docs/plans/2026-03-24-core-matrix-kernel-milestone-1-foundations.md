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
- if a child task consults `references/` or external implementations, write the retained conclusion into that task document and any local docs it updates; do not leave only a bare reference path behind
- if Tasks 01-04 reveal a likely later root-shape or schema problem, fix that shape in the substrate now rather than deferring it into later execution-layer work
- keep the early registry and bundled-bootstrap work generic enough that later external execution adapters can attach without re-rooting the database model

## Completion Record

- status:
  completed on `2026-03-24` on branch `codex/phase1`
- landing commits:
  - Task 01: `0dd2f6a` `chore: reset core matrix backend shell baseline`
  - Task 02: `098508f` `feat: add installation identity foundations`
  - Task 03: `5c76965` `feat: add agent registry foundations`
  - Task 04.1: `fe34078` `feat: add user bindings and workspaces`
  - Task 04.2: `508ab0b` `feat: add bundled default agent bootstrap`
- landed milestone scope:
  - documented and re-anchored the backend-only shell baseline
  - added installation, identity, user, invitation, session, and audit roots
  - added logical agent installation, execution environment, enrollment,
    deployment, capability snapshot, and heartbeat foundations
  - added user-agent bindings, private workspaces, and idempotent default
    workspace creation
  - added opt-in bundled Fenix runtime reconciliation and first-admin auto-bind
    composition through the same registry and binding abstractions
- verification evidence:
  - the `2026-03-24` doc-hardening rerun required ensuring the local
    test database existed with `cd core_matrix && bin/rails db:create`
  - `cd core_matrix && bin/rails db:test:prepare`
  - `cd core_matrix && bin/rails test test/integration/installation_bootstrap_flow_test.rb test/integration/agent_registry_flow_test.rb test/integration/user_binding_workspace_flow_test.rb test/integration/bundled_default_agent_bootstrap_flow_test.rb`
    passed with `4 runs, 34 assertions, 0 failures, 0 errors`
  - `cd core_matrix && bin/rails db:version` reported development schema
    version `20260324090012`
  - `cd core_matrix && bin/rubocop app/models/application_record.rb` passed
    with no offenses
  - `cd core_matrix && bin/rails test` passed with
    `40 runs, 188 assertions, 0 failures, 0 errors`
  - `cd core_matrix && bin/brakeman --no-pager` reported `0` warnings
  - `cd core_matrix && bin/bundler-audit` reported no vulnerabilities
- retained findings:
  - Milestone 1 did not retain any product-behavior conclusion from
    non-authoritative reference applications; the design docs and local
    behavior docs remained the authority
  - the durable debugging anchors for this milestone are the behavior docs
    under `core_matrix/docs/behavior/` plus the manual checklist flows for
    bootstrap, enrollment, binding, workspace creation, and bundled bootstrap
- carry-forward notes:
  - later tasks must preserve `Identity` versus `User`,
    `AgentInstallation` versus `AgentDeployment`, and `Workspace` as a
    private user-owned aggregate
  - later bootstrap or enablement work must compose
    `Installations::BootstrapFirstAdmin`,
    `UserAgentBindings::Enable`, and `Workspaces::CreateDefault` instead of
    recreating those side effects ad hoc
  - later protocol and recovery work must reuse capability snapshots as
    append-only history instead of mutating runtime capability state in place
