# Core Matrix Phase 2 Milestone C: Runtime Pairing And Control

Part of `Core Matrix Phase 2: Agent Loop Execution`.

## Purpose

Prove that `Core Matrix` can pair with an agent program, deliver mailbox
control work through `poll` and `WebSocket`, and enforce stop or close behavior
under kernel authority.

Milestone C builds on Milestone A substrate and Milestone B provider execution.
It should not rediscover provider logic inside the runtime protocol layer.
It also owns the single reusable Protocol E2E harness for Phase 2 mailbox and
close work; later tasks should extend that harness instead of creating a second
end-to-end stack.

## Included Tasks

### Task C1

- [2026-03-26-core-matrix-phase-2-task-mailbox-control-and-resource-close-contract.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-26-core-matrix-phase-2-task-mailbox-control-and-resource-close-contract.md)

### Task C2

- [2026-03-26-core-matrix-phase-2-task-turn-interrupt-and-conversation-close-semantics.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-26-core-matrix-phase-2-task-turn-interrupt-and-conversation-close-semantics.md)

### Task C3

- [2026-03-25-core-matrix-phase-2-task-fenix-runtime-surface-and-execution-hooks.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-fenix-runtime-surface-and-execution-hooks.md)

### Task C4

- [2026-03-25-core-matrix-phase-2-task-external-fenix-pairing-and-deployment-rotation.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-external-fenix-pairing-and-deployment-rotation.md)

### Task C5 Follow-Up

- [2026-03-26-core-matrix-phase-2-task-execution-environment-runtime-boundary-follow-up.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-26-core-matrix-phase-2-task-execution-environment-runtime-boundary-follow-up.md)

### Task C2 Follow-Up

- [2026-03-27-core-matrix-phase-2-close-operation-reconciliation-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-27-core-matrix-phase-2-close-operation-reconciliation-design.md)
- [2026-03-27-core-matrix-phase-2-plan-close-operation-reconciliation.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-27-core-matrix-phase-2-plan-close-operation-reconciliation.md)

### Task C6 Follow-Up

- [2026-03-27-core-matrix-phase-2-runtime-binding-and-rewrite-safety-hardening-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-27-core-matrix-phase-2-runtime-binding-and-rewrite-safety-hardening-design.md)
- [2026-03-27-core-matrix-phase-2-plan-runtime-binding-and-rewrite-safety-hardening.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-27-core-matrix-phase-2-plan-runtime-binding-and-rewrite-safety-hardening.md)

### Task C7 Follow-Up

- [2026-03-27-core-matrix-phase-2-conversation-mutation-contract-unification-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-27-core-matrix-phase-2-conversation-mutation-contract-unification-design.md)
- [2026-03-27-core-matrix-phase-2-plan-conversation-mutation-contract-unification.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-27-core-matrix-phase-2-plan-conversation-mutation-contract-unification.md)

### Task C8 Follow-Up

- [2026-03-27-core-matrix-phase-2-lineage-provenance-and-supersession-hardening-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-27-core-matrix-phase-2-lineage-provenance-and-supersession-hardening-design.md)
- [2026-03-27-core-matrix-phase-2-plan-lineage-provenance-and-supersession-hardening.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-27-core-matrix-phase-2-plan-lineage-provenance-and-supersession-hardening.md)

### Task C9 Follow-Up

- [2026-03-27-core-matrix-phase-2-anchor-lineage-and-provenance-regression-hardening-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-27-core-matrix-phase-2-anchor-lineage-and-provenance-regression-hardening-design.md)
- [2026-03-27-core-matrix-phase-2-plan-anchor-lineage-and-provenance-regression-hardening.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-27-core-matrix-phase-2-plan-anchor-lineage-and-provenance-regression-hardening.md)

### Task C10 Follow-Up

- [2026-03-26-core-matrix-phase-2-conversation-purge-hardening-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-26-core-matrix-phase-2-conversation-purge-hardening-design.md)
- [2026-03-26-core-matrix-phase-2-plan-conversation-purge-hardening.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-26-core-matrix-phase-2-plan-conversation-purge-hardening.md)

### Task C11 Follow-Up

- [2026-03-26-core-matrix-phase-2-review-audit-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-26-core-matrix-phase-2-review-audit-design.md)
- [2026-03-26-core-matrix-phase-2-plan-review-audit.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-26-core-matrix-phase-2-plan-review-audit.md)
- [2026-03-26-core-matrix-phase-2-review-audit-findings.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-26-core-matrix-phase-2-review-audit-findings.md)

## Exit Criteria

- mailbox control is durable and transport-neutral
- `poll`, `WebSocket`, and response piggyback share one mailbox envelope
- protocol-E2E infrastructure exists for runtime pairing and mailbox control
- the initial protocol-E2E golden scenarios for mailbox delivery, transport
  fallback, turn interrupt, and close orchestration are in place
- C3 and C4 extend the same protocol-E2E harness instead of replacing it with
  runtime-specific one-off end-to-end tests
- `turn_interrupt` is a tested kernel primitive
- archive and delete reuse the close model without collapsing into one
  lifecycle state machine
- close progression uses one explicit conversation-scoped reconciler rather
  than scattered lifecycle writers
- deployment rebinding, new turn entry, and turn-history rewrite all reuse one
  explicit runtime-binding and rewrite-safety contract
- caller-driven conversation-local mutation uses one explicit contract family:
  retained-only, live-mutation, or turn timeline mutation
- legacy retained-state helpers no longer survive as an alternate path for
  lifecycle checks
- rollback supersession rejects live owned runtime instead of canceling it
  blindly
- transcript output variants carry explicit input provenance and selection stays
  within one lineage
- child-conversation historical anchors are validated against the parent
  conversation history instead of relying on permissive raw ids
- effective transcript history, output-anchor fork-point protection, and
  provenance fail-closed behavior all share one lineage contract
- `Fenix` can pair as a bundled runtime and as an external runtime
- same-installation deployment rotation works for both upgrade and downgrade
- `ExecutionEnvironment` is explicitly the stable owner of runtime resources
- agent plane and environment plane are explicit protocol concepts even when one
  runtime process implements both
- capability publication exposes environment-first effective tool catalogs

## Non-Goals

- human interaction and subagent breadth
- Streamable HTTP MCP breadth
- skills installation breadth
- final milestone acceptance
