# Core Matrix Kernel Phase 4: Protocol, Publication, And Verification

Use this phase index together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-ui-follow-up.md`
5. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

This phase owns Tasks 11-12:

- [Task 11: Implement Agent Protocol Boundaries, Runtime Resource APIs, Contract Tests, Bootstrap, And Recovery](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-11-agent-protocol-and-recovery.md)
- [Task 12: Add Publication, Query Objects, Seeds, Checklist Updates, And Final Verification](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-24-core-matrix-task-12-publication-and-final-verification.md)

Phase goals:

- expose the machine-facing protocol and runtime resource APIs
- implement bootstrap, heartbeat, recovery, and manual recovery controls
- implement read-only publication and supporting query objects
- finish with automated verification plus real `bin/dev` manual validation

Cross-cutting notes:

- do not widen this phase into schedule or webhook trigger implementation
- the current backend batch stops at automation-conversation and turn-origin semantics; `AutomationTrigger`, recurring execution, and webhook ingress remain follow-up scope
- machine-facing protocol work in this phase must not introduce schedule-trigger or webhook-ingress controllers

Execution rules:

- execute the task documents in order
- load only the active task document during implementation
- treat this file as the phase ordering index, not as the detailed task body
- apply the shared guardrails and phase-gate audits from the implementation-plan index after every task
