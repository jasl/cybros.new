# Core Matrix Kernel Milestone 4: Protocol, Publication, And Verification

Use this milestone index together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/future-plans/2026-03-24-core-matrix-kernel-ui-follow-up.md`
5. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

This milestone owns Task Groups 11-12 and their child tasks:

- [Task Group 11: Implement Agent Protocol Boundaries, Runtime Resource APIs, Contract Tests, Bootstrap, And Recovery](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-group-11-agent-protocol-and-recovery.md)
- [Task 11.1: Add Registration And Capability Handshake Boundaries](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-11-1-registration-and-capability-handshake.md)
- [Task 11.2: Add Runtime Resource APIs](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-11-2-runtime-resource-apis.md)
- [Task 11.3: Add Deployment Credential Lifecycle Controls](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-11-3-deployment-credential-lifecycle.md)
- [Task 11.4: Add Bootstrap And Recovery Flows](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-11-4-bootstrap-and-recovery.md)
- [Task Group 12: Add Publication, Query Objects, Seeds, Checklist Updates, And Final Verification](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-group-12-publication-and-final-verification.md)
- [Task 12.1: Add Publication Model And Live Projection](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-12-1-publication-model-and-live-projection.md)
- [Task 12.2: Add Read-Side Queries And Seed Baseline](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-12-2-read-side-queries-and-seed-baseline.md)
- [Task 12.3: Run Verification And Manual Validation](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-12-3-verification-and-manual-validation.md)

Milestone goals:

- expose the machine-facing protocol and runtime resource APIs
- implement bootstrap, heartbeat, recovery, and manual recovery controls
- implement read-only publication and supporting query objects
- finish with automated verification plus real `bin/dev` manual validation

Cross-cutting notes:

- do not widen this milestone into schedule or webhook trigger implementation
- the current backend batch stops at automation-conversation and turn-origin semantics; `AutomationTrigger`, recurring execution, and webhook ingress remain follow-up scope
- machine-facing protocol work in this milestone must not introduce schedule-trigger or webhook-ingress controllers

Execution rules:

- execute the task documents in order
- load only the active execution-unit document during implementation
- treat this file as the milestone ordering index, not as the detailed task body
- apply the shared guardrails and execution-gate audits from the implementation-plan index after every task
- if a child task consults `references/` or external implementations, write the retained conclusion into that task document and any local docs it updates; do not leave only a bare reference path behind
