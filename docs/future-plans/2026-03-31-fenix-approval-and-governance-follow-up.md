# Fenix Approval And Governance Follow-Up

## Status

Deferred follow-up after the runtime appliance and operator-surface work.

## Purpose

The current runtime product shape intentionally prioritizes usable execution
over rich approval choreography:

- Core Matrix owns the durable runtime identities and governance record
- Fenix enforces the current execution topology and runtime-local constraints
- approval-stage behavior remains largely deferred and default-skip

This document records the deferred governance work so future changes do not
accidentally treat the current simplified policy model as final.

## Deferred Capability

The deferred governance and approval work includes:

- explicit approval-stage handling for runtime-owned side effects
- selective approval modes instead of global interruption
- runtime-local permission profiles for:
  - workspace mutation
  - command execution
  - long-lived process launch
  - browser automation
  - network access
- plugin-level policy and allow/deny surfaces
- richer reporting around:
  - auto-allowed actions
  - policy-denied actions
  - approval-required actions

This follow-up should stay aligned with the existing Core Matrix record of
approval-stage and handle-recovery decisions instead of inventing a separate
runtime-only governance truth.

## Why Deferred

This work is real, but it would widen the state machine substantially:

- it touches operator UX, kernel approval UX, and runtime execution behavior
- it is easier to design once the operator surface is coherent
- the current product baseline is acceptable with default-skip approval and
  explicit policy-denied outcomes

## Activation Trigger

Re-open this follow-up when one or more of the following becomes true:

- product requirements demand explicit approval before runtime side effects
- operators need runtime profiles beyond the current topology guardrails
- workspace/plugin loading needs finer-grained governance
- browser/command/process surfaces need differentiated allowlists

## Related Documents

- [2026-03-30-core-matrix-runtime-approval-and-handle-recovery-follow-up.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-30-core-matrix-runtime-approval-and-handle-recovery-follow-up.md)
- [2026-03-30-fenix-runtime-appliance-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/fenix/2026-03-30-fenix-runtime-appliance-design.md)
- [2026-03-31-fenix-operator-surface-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/fenix/2026-03-31-fenix-operator-surface-design.md)
