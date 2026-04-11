# Core Matrix Task Group 11: Implement Agent Protocol Boundaries, Runtime Resource APIs, Contract Tests, Bootstrap, And Recovery

Part of `Core Matrix Kernel Milestone 4: Protocol, Publication, And Verification`.

Use this task-group index together with:

1. `AGENTS.md`
2. `docs/finished-plans/2026-03-24-core-matrix-phase-1-kernel-greenfield-implementation-plan.md`
3. `docs/finished-plans/2026-03-24-core-matrix-phase-1-kernel-milestone-4-protocol-publication-and-verification.md`
4. `docs/design/2026-03-24-core-matrix-agent-protocol-and-tool-surface-design.md`

This task group is split so protocol enrollment, runtime-resource APIs, credential lifecycle, and recovery logic can each be implemented against a stable contract without loading the whole phase at once.

---

Execute these tasks in order:

- [Task 11.1: Add Registration And Capability Handshake Boundaries](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-phase-1-task-11-1-registration-and-capability-handshake.md)
- [Task 11.2: Add Runtime Resource APIs](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-phase-1-task-11-2-runtime-resource-apis.md)
- [Task 11.3: Add Deployment Credential Lifecycle Controls](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-phase-1-task-11-3-connection-credential-lifecycle.md)
- [Task 11.4: Add Bootstrap And Recovery Flows](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-24-core-matrix-phase-1-task-11-4-bootstrap-and-recovery.md)

Task group boundaries:

- Task 11.1 owns registration, heartbeat, health, capabilities, handshake, and capability-snapshot contract shape.
- Task 11.2 owns transcript, variable, and human-interaction machine-facing APIs.
- Task 11.3 owns machine-credential rotation, revocation, and deployment retirement.
- Task 11.4 owns bootstrap, outage handling, auto-resume, manual resume, manual retry, and the manual dummy runtime.

Execution rules:

- do not implement directly from this index
- load only the active task document during implementation
- apply the shared execution-gate audits after each task
- if a child task consults `references/` or external implementations, write the retained conclusion into that task document and any local docs it updates; do not leave only a bare reference path behind

## Completion Record

- status:
  completed on `2026-03-25`
- landing commits:
  - Task 11.1: `513c1e4` `feat: add agent registration and handshake boundaries`
  - Task 11.2: `f2c1bc3` `feat: add runtime resource apis`
  - Task 11.3: `bac2a4e` `feat: add deployment credential lifecycle controls`
  - Task 11.4: `0b11a4c` `feat: add deployment recovery and manual resume flows`
- landed scope:
  - added the machine-facing enrollment, heartbeat, health, capability, and
    runtime-resource API surface for deployments
  - added capability-handshake reconciliation, credential rotation and
    revocation, retirement gating, and recovery-time compatibility checks
  - added bootstrap, outage, auto-resume, manual resume, manual retry, and the
    reproducible dummy runtime used for live validation
- verification evidence:
  - child task records retain the targeted request, query, service, and
    integration commands for Tasks 11.1 through 11.4
  - `cd core_matrix && bin/rails test test/services/agent_deployments/bootstrap_test.rb test/services/agent_deployments/mark_unavailable_test.rb test/services/agent_deployments/auto_resume_workflows_test.rb test/services/workflows/manual_resume_test.rb test/services/workflows/manual_retry_test.rb test/integration/agent_recovery_flow_test.rb`
    passed with `11 runs, 93 assertions, 0 failures, 0 errors` during the
    archival review
- carry-forward notes:
  - later operator or UI surfaces should reuse these machine-facing and
    recovery services directly instead of re-encoding compatibility and
    credential rules in controllers
  - future external runtime adapters must preserve the same protocol and
    recovery invariants instead of introducing adapter-specific state machines
