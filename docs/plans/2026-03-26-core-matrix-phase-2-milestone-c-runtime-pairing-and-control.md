# Core Matrix Phase 2 Milestone C: Runtime Pairing And Control

Part of `Core Matrix Phase 2: Agent Loop Execution`.

## Purpose

Prove that `Core Matrix` can pair with an agent program, deliver mailbox
control work through `poll` and `WebSocket`, and enforce stop or close behavior
under kernel authority.

Milestone C builds on Milestone A substrate and Milestone B provider execution.
It should not rediscover provider logic inside the runtime protocol layer.

## Included Tasks

### Task C1

- [2026-03-26-core-matrix-phase-2-task-mailbox-control-and-resource-close-contract.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-26-core-matrix-phase-2-task-mailbox-control-and-resource-close-contract.md)

### Task C2

- [2026-03-26-core-matrix-phase-2-task-turn-interrupt-and-conversation-close-semantics.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-26-core-matrix-phase-2-task-turn-interrupt-and-conversation-close-semantics.md)

### Task C3

- [2026-03-25-core-matrix-phase-2-task-fenix-runtime-surface-and-execution-hooks.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-fenix-runtime-surface-and-execution-hooks.md)

### Task C4

- [2026-03-25-core-matrix-phase-2-task-external-fenix-pairing-and-deployment-rotation.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-external-fenix-pairing-and-deployment-rotation.md)

## Exit Criteria

- mailbox control is durable and transport-neutral
- `poll`, `WebSocket`, and response piggyback share one mailbox envelope
- `turn_interrupt` is a tested kernel primitive
- archive and delete reuse the close model without collapsing into one
  lifecycle state machine
- `Fenix` can pair as a bundled runtime and as an external runtime
- same-installation deployment rotation works for both upgrade and downgrade

## Non-Goals

- human interaction and subagent breadth
- Streamable HTTP MCP breadth
- skills installation breadth
- final milestone acceptance

