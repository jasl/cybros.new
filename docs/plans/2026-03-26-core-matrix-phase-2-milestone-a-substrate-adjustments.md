# Core Matrix Phase 2 Milestone A: Substrate Adjustments

Part of `Core Matrix Phase 2: Agent Loop Execution`.

## Purpose

Finish the substrate corrections that Phase 2 depends on before provider
execution and runtime pairing widen the surface area.

Milestone A is intentionally narrow:

- freeze the active scope against the landed Phase 1 substrate
- extend workflow-owned storage and projection metadata so later mailbox,
  close, retry, and proof work can target stable kernel structures

## Included Tasks

### Task A1

- [2026-03-25-core-matrix-phase-2-task-structural-gate-and-scope-freeze.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-structural-gate-and-scope-freeze.md)

### Task A2

- [2026-03-25-core-matrix-phase-2-task-workflow-substrate-extensions.md](/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-25-core-matrix-phase-2-task-workflow-substrate-extensions.md)

## Exit Criteria

- Phase 2 scope is frozen against the current codebase and docs
- workflow-owned yield, barrier, successor, and presentation metadata exist in
  durable kernel structures
- later tasks do not need to invent local shadow state for workflow control or
  projection
- read-facing workflow projection metadata is sufficient for later proof export
  and operator inspection without complex graph reconstruction queries

## Non-Goals

- real provider execution
- agent runtime pairing
- mailbox delivery
- conversation close orchestration

