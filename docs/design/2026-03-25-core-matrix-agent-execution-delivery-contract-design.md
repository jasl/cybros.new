# Core Matrix Agent Execution Delivery Contract Design

## Status

Approved focused design note for Phase 2 execution delivery between
`Core Matrix` and external agent programs.

This document narrows one question only: how claimable agent execution should
be delivered, leased, and reported without long synchronous callbacks from the
kernel into an agent runtime.

## Purpose

Use this document to define:

- the canonical public method family for asynchronous agent execution
- the shared envelope used by HTTP and any optional WebSocket accelerator
- the recommended claimable runtime resource shape inside `Core Matrix`
- how liveness, progress, completion, failure, and cancellation should work

## Decision Summary

- Canonical execution delivery uses short HTTP methods, not held RPC calls.
- The public method family is:
  - `execution_claim`
  - `execution_lease_heartbeat`
  - `execution_progress`
  - `execution_complete`
  - `execution_fail`
- Phase 2 should support a bounded fast terminal path for short tasks without
  introducing a second claimless protocol.
- Optional WebSocket transport should reuse the same envelope family, but only
  for notification-style accelerator messages in Phase 2.
- `heartbeat` remains the canonical deployment-health signal.
- Execution leases remain the runtime-ownership mechanism for claimed work.
- `Core Matrix` should not expose `WorkflowRun` directly as the claimable
  object.
- The recommended internal runtime resource is a new workflow-owned
  `AgentTaskRun`, claimed via `ExecutionLease`.
- deployment registration and bootstrap stay on the deployment handshake path in
  Phase 2 rather than being forced into the same conversation-scoped execution
  contract.

## Why A New Claimable Runtime Resource Is Worth It

Three alternatives exist:

1. claim `WorkflowRun` directly
2. claim `WorkflowNode` directly
3. claim a dedicated execution runtime resource

The recommended option is `3`.

Reasoning:

- `WorkflowRun` is too coarse. One run may include multiple runtime steps,
  waits, retries, and side effects.
- `WorkflowNode` is the durable graph topology, not the full leaseable
  execution record.
- `ProcessRun` is already a narrow runtime resource for OS-process work and is
  not a good umbrella for prompt building, model invocation, or agent-owned
  tool use.

`AgentTaskRun` fits the existing substrate better:

- workflow-owned like `ProcessRun`, `SubagentRun`, and `HumanInteractionRequest`
- explicit execution lifecycle and attempt history
- explicit lease ownership through `ExecutionLease`
- capable of carrying progress, result, and failure data without overloading
  `WorkflowNode`

## Recommended Internal Runtime Resource

Recommended conceptual object:

- `AgentTaskRun`

Recommended ownership:

- belongs to one installation
- belongs to one workflow run
- belongs to one workflow node
- redundantly persists conversation and turn ownership when operationally
  useful

Recommended lifecycle:

- `queued`
- `running`
- `waiting`
- `completed`
- `failed`
- `canceled`

Recommended task kinds for Phase 2:

- `turn_step`
- `agent_tool_call`
- `subagent_step`

Important boundary:

- prompt building, memory assembly, risk triage, model invocation, and local
  agent-owned tool use may all occur inside one claimed `turn_step`
- the kernel does not need to model each micro-stage as its own public runtime
  resource in Phase 2
- micro-stage visibility should instead arrive through structured progress
  reports

## Shared Envelope

The public execution-delivery envelope should be stable across transports.

Recommended fields:

- `protocol_version`
- `method_id`
- `message_id`
- `causation_id`
- `sent_at`
- `payload`

Rules:

- HTTP requests and responses may carry this envelope as normal JSON bodies
- optional WebSocket messages should reuse the same envelope shape
- `message_id` must be stable enough for deduplication, logging, and replay
  diagnostics
- `causation_id` should point back to the triggering request or notification
  when applicable
- transport metadata such as ActionCable channel names or WebSocket connection
  ids must not become part of the public contract

## Canonical HTTP Method Family

### `execution_claim`

Purpose:

- let an authenticated deployment ask `Core Matrix` for executable work

Recommended request payload:

- `holder_key`
- `limit`
- `supported_task_kinds`
- optional `wait_ms`
- optional `known_accelerator_session_id`

Recommended response payload:

- `executions`
- `next_poll_after_ms`

Fast-path rule:

- `execution_claim` may use a bounded `wait_ms` long-poll so a runtime can pick
  up short work with one less round of idle polling
- this does not change the durable semantics: the runtime still receives a
  claimed execution with a real `lease_id`

Lease-acquisition rule:

- `execution_claim` must inherit `ExecutionLease` single-owner semantics
- a fresh competing lease claim for the same execution must be rejected
- a stale active lease may be replaced only through the normal stale-lease
  acquisition path; the old holder must not be silently revived

Each execution entry should include:

- `execution_id`
- `lease_id`
- `task_kind`
- `heartbeat_timeout_seconds`
- `caller_context`
- `capability_snapshot`
- optional `feature_policy_snapshot`
- optional `tail_guard`
- `budget_hints`
- `input`

### `execution_lease_heartbeat`

Purpose:

- keep runtime ownership alive for one claimed execution

Recommended request payload:

- `execution_id`
- `lease_id`
- `holder_key`
- optional `status_summary`

Recommended response payload:

- `lease_state`
- `continue`
- `cancel_requested`

Fast-path rule:

- heartbeat is not required before the first terminal report if the runtime
  completes or fails the execution before the initial heartbeat deadline
- once the task crosses that budget, normal heartbeat rules apply

### `execution_progress`

Purpose:

- append durable mid-flight execution facts without finishing the task

Recommended request payload:

- `execution_id`
- `lease_id`
- `holder_key`
- `stage_name`
- `progress_kind`
- `progress_payload`
- optional `ordinal`

Recommended response payload:

- `accepted`
- optional `cancel_requested`

Recommended stage names for Phase 2:

- `preflight`
- `memory_assembly`
- `prompt_build`
- `model_invoke`
- `tool_invoke`
- `finalize_output`

These stage names are agent-program-facing guidance, not kernel-owned prompt
logic.

### `execution_complete`

Purpose:

- finalize one execution successfully

Recommended request payload:

- `execution_id`
- `lease_id`
- `holder_key`
- `completion_kind`
- `result_payload`
- optional `artifacts`
- optional `usage`

Recommended response payload:

- `accepted`
- `workflow_state`

Fast-path rule:

- `execution_complete` may be the first and only report after `execution_claim`
  for short tasks
- this is the recommended latency optimization for simple agent-program work in
  Phase 2

### `execution_fail`

Purpose:

- finalize one execution as failed or retryable-failed

Recommended request payload:

- `execution_id`
- `lease_id`
- `holder_key`
- `failure_kind`
- `retryable`
- `error`
- optional `diagnostics`

Recommended response payload:

- `accepted`
- optional `recovery_state`

Fast-path rule:

- `execution_fail` may also be the first and only report after
  `execution_claim` for short failed tasks
- retry and recovery semantics still stay kernel-owned

## Caller Context And Budget Hints

Every claimed execution should carry enough context for agent-side runtime
decisions without moving prompt building into the kernel.

Recommended `caller_context` minimum for all task kinds:

- installation id
- workflow run id
- workflow node id
- agent deployment id

Additional minimum for conversation-scoped task kinds:

- workspace id
- conversation id
- turn id

Recommended `budget_hints` minimum:

- context-window hint when known
- reserved-output budget when known
- timeout budget when known
- correlation or request ids for provider attribution when known

## Conversation Tail Guards And Stale Work

Conversation-scoped executions need explicit stale-work protection.

Recommended `tail_guard` minimum:

- `conversation_id`
- `expected_tail_message_id` or equivalent selected-tail ref
- `during_generation_policy`
- optional `selected_input_message_id`

Rules:

- `reject` means no new transcript-affecting execution should start while the
  active guard remains valid
- `restart` invalidates older guards and creates an explicit stop boundary so
  older execution cannot later commit transcript-affecting output
- `queue` creates a new execution with its own expected-tail guard; if the tail
  changes again before that execution becomes authoritative, the queued work
  must be skipped or rejected as stale
- transcript-affecting `execution_progress`, `execution_complete`, and
  `execution_fail` reports must be rejected or recorded as stale when their
  guard has been superseded
- stale reports may still be retained for diagnostics and audit, but they must
  not mutate the selected transcript path or current workflow state as if they
  were authoritative

## Wait-State Handoff

Waiting remains kernel-owned even when the runtime detects the need to pause.

Recommended rule for blocking conditions:

- when human interaction or another blocking resource is needed, the runtime
  should first create or reference the kernel-owned blocking resource through
  the appropriate protocol or tool surface
- then the runtime should report `execution_progress` with a
  `progress_kind` such as `wait_transition_requested`

Recommended `wait_transition_requested` payload:

- `wait_reason_kind`
- `wait_reason_payload`
- `blocking_resource_type`
- `blocking_resource_id`

Rules:

- `wait_reason_kind` should align with workflow wait-state semantics such as
  `human_interaction`, `agent_unavailable`, `manual_recovery_required`, or
  `policy_gate`
- the kernel must atomically decide whether the execution transitions into the
  requested wait state
- if the referenced blocking resource does not exist or is not compatible, the
  kernel must reject the wait transition rather than silently pausing execution

## Idempotency, Ordering, And Stale-Lease Rules

The contract must fail safe under retries, duplicates, and network delays.

Rules:

- `message_id` is the protocol-level dedup key for one authenticated sender and
  one logical report
- repeated delivery of the same report with the same `message_id` must be
  idempotent
- a different terminal report for an execution that is already terminal must be
  rejected as non-authoritative and retained only for diagnostics
- `execution_progress.ordinal` should be monotonic per execution when supplied;
  duplicate or older ordinals must not roll state backward
- reports for an expired, superseded, or non-current `lease_id` must be
  rejected with a structured stale-lease outcome and must not mutate durable
  execution state
- if a stale holder retries `execution_claim` after another holder has already
  replaced its lease, the retry must observe the new ownership rather than
  silently stealing the execution back
- if recovery policy opens a new attempt after lease loss, that new attempt must
  use a new lease and retain audit linkage to the superseded attempt

## WebSocket Accelerator

Phase 2 may later add an outbound WebSocket session as an accelerator, but it
should stay intentionally narrow.

Recommended notification methods:

- `execution_available`
- `execution_cancel_requested`
- `capabilities_refresh_requested`

Rules:

- notifications reuse the shared envelope
- notifications are hints, not durable execution state
- the runtime must still behave correctly if the accelerator is disconnected
- loss of accelerator presence may speed up suspicion, but it does not replace
  deployment heartbeat policy

## Cancellation And Waiting

Cancellation and waiting should remain kernel-owned semantics.

Rules:

- `cancel_requested` is advisory until the runtime acknowledges it through the
  normal report path or lease expiry occurs
- if the runtime needs human input or another blocking condition, it should not
  invent its own durable pause store; it should report progress or failure in a
  shape that lets the kernel move the workflow into the right wait state
- long-lived waiting conditions belong to `WorkflowRun.wait_*` or other
  workflow-owned runtime resources, not to transport-local sockets

## Phase 2 Non-Goals

This design does not require Phase 2 to ship:

- a full bidirectional RPC protocol over WebSocket
- server-initiated execution callbacks into private agent networks
- a separate claimless execution API that bypasses durable claim semantics
- token streaming or transcript streaming as the canonical execution protocol
- one runtime resource per prompt-building micro-step
- replacement of deployment heartbeat with connection-presence rules

## Related Documents

- [2026-03-24-core-matrix-agent-protocol-and-tool-surface-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-24-core-matrix-agent-protocol-and-tool-surface-design.md)
- [2026-03-25-core-matrix-platform-phases-and-validation-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-core-matrix-platform-phases-and-validation-design.md)
- [2026-03-25-agent-program-public-api-and-transport-research-note.md](/Users/jasl/Workspaces/Ruby/cybros/docs/research-notes/2026-03-25-agent-program-public-api-and-transport-research-note.md)
- [2026-03-25-core-matrix-phase-2-runtime-loop-and-mcp-research-note.md](/Users/jasl/Workspaces/Ruby/cybros/docs/research-notes/2026-03-25-core-matrix-phase-2-runtime-loop-and-mcp-research-note.md)
