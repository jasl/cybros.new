# Core Matrix Task Group 11: Implement Agent Protocol Boundaries, Runtime Resource APIs, Contract Tests, Bootstrap, And Recovery

Part of `Core Matrix Kernel Milestone 4: Protocol, Publication, And Verification`.

Use this task-group index together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-milestone-4-protocol-publication-and-verification.md`
4. `docs/design/2026-03-24-core-matrix-agent-protocol-and-tool-surface-design.md`

This task group is split so protocol enrollment, runtime-resource APIs, credential lifecycle, and recovery logic can each be implemented against a stable contract without loading the whole phase at once.

---

Execute these tasks in order:

- [Task 11.1: Add Registration And Capability Handshake Boundaries](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-11-1-registration-and-capability-handshake.md)
- [Task 11.2: Add Runtime Resource APIs](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-11-2-runtime-resource-apis.md)
- [Task 11.3: Add Deployment Credential Lifecycle Controls](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-11-3-deployment-credential-lifecycle.md)
- [Task 11.4: Add Bootstrap And Recovery Flows](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-11-4-bootstrap-and-recovery.md)

Task group boundaries:

- Task 11.1 owns registration, heartbeat, health, capabilities, handshake, and capability-snapshot contract shape.
- Task 11.2 owns transcript, variable, and human-interaction machine-facing APIs.
- Task 11.3 owns machine-credential rotation, revocation, and deployment retirement.
- Task 11.4 owns bootstrap, outage handling, auto-resume, manual resume, manual retry, and the manual dummy runtime.

Execution rules:

- do not implement directly from this index
- load only the active task document during implementation
- apply the shared execution-gate audits after each task
