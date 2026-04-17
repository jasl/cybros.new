# Core Matrix Runtime Approval And Handle Recovery Follow-Up

## Status

Deferred follow-up after the current agent-loop and runtime-control work.

## Purpose

The current runtime architecture now has first-class kernel identities for
runtime-owned side effects:

- `ToolInvocation`
- `CommandRun`
- `ProcessRun`

That is enough for phase completion and final acceptance. Two related concerns
remain intentionally deferred:

- a real tool-approval stage that can pause runtime-owned tool execution before
  side effects happen
- stronger runtime-local handle recovery beyond the current worker-local
  projection model

This document records both the deferred work and the current architectural
decision so future changes do not accidentally treat Fenix local runtime state
as a durable source of truth.

## Deferred Capability: Tool Approval Stage

The kernel already has generic approval infrastructure, but runtime-owned tool
execution does not yet enter a dedicated approval stage. The current behavior
is still:

- create `ToolInvocation` / `CommandRun` / `ProcessRun`
- evaluate policy locally and through kernel-side governance
- either proceed or fail with a recorded authorization/policy reason

The deferred follow-up is to introduce an explicit tool-approval stage with the
following shape:

- review result expands from `allow | deny` to `allow | approval_required | deny`
- approval-required requests materialize through existing kernel approval
  infrastructure
- the default mode stays "skip approval" until a product surface enables it
- future policy can decide automatically when approval is required instead of
  interrupting every call

This applies primarily to runtime-owned side effects such as:

- `exec_command`
- `write_stdin`
- detached process launch and control
- future environment-mutating tools

## Current Runtime Handle Model

Fenix local command/process handles are intentionally not treated as reliable
facts. They are runtime-local projections of kernel-owned durable resources.

Current invariants:

- `ToolInvocation`, `CommandRun`, and `ProcessRun` remain the durable kernel
  source of truth
- Fenix local handles may live purely in memory
- if later useful, Fenix may keep a lightweight local record for convenience or
  recovery hints
- any local record remains non-authoritative because Fenix and the operating
  system can always drift
- recovery should prefer explicit lost/failed/closed reporting back to the
  kernel, not reconstructing truth from a stale local mirror

This means the current worker-local registry model is acceptable for now. A
future reattach or crash-recovery design should only be pursued if there is a
clear product need.

## Why Deferred

These concerns are real, but they are not on the critical path for closing the
current phase:

- approval-stage work widens the runtime state machine and operator UX
- confidence-based approval policy needs a clearer product contract before it is
  worth implementing
- local handle durability does not turn Fenix into a trustworthy fact source
- advanced reattach/recovery adds complexity without changing the kernel truth
  model

## Activation Trigger

Re-open this follow-up when one or more of the following becomes true:

- runtime-owned tools need user-visible approval gates
- approval policy needs a default-skip mode with selective escalation
- product requirements demand recovery or reattach after runtime worker restart
- operators need richer audit around approved versus auto-allowed tool actions

## Related Documents

- [2026-03-30-websocket-first-runtime-mailbox-control-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-30-websocket-first-runtime-mailbox-control-design.md)
- [2026-03-30-websocket-first-runtime-mailbox-control.md](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/2026-03-30-websocket-first-runtime-mailbox-control.md)
- [2026-03-30-fenix-runtime-appliance-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/fenix/2026-03-30-fenix-runtime-appliance-design.md)
- [human-interactions-and-conversation-events.md](/Users/jasl/Workspaces/Ruby/cybros/docs/archived-plans/core_matrix-docs-legacy-2026-04-17/behavior/human-interactions-and-conversation-events.md)
