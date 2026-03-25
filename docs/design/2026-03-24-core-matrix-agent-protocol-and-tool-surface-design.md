# Core Matrix Agent Protocol And Tool Surface Design

## Status

Focused design note aligned with the 2026-03-24 kernel greenfield design.

Use this document to normalize public-contract naming, capability-snapshot structure, and the boundary between kernel-owned execution authority and agent-owned tool surfaces.

## Purpose

Core Matrix needs a stable public contract between the kernel and external agent runtimes. That contract must be:

- consistent in naming
- explicit about which identifiers are protocol methods versus model-visible tool names
- explicit about which actions remain kernel authority
- flexible enough to let agent programs expose domain-specific tool surfaces without collapsing the strong-kernel side-effect rule

This note freezes those boundaries at the contract level. It does not require the current backend batch to implement every future bridge or tool adapter.

## Identifier Types

The public contract uses three different identifier families. They must not be conflated.

### 1. Protocol Method IDs

These are the logical operation identifiers used between Core Matrix and an external agent runtime.

Examples:

- `initialize`
- `agent_describe`
- `agent_health`
- `agent_schemas_get`
- `capabilities_handshake`
- `capabilities_refresh`
- `conversation_transcript_list`
- `conversation_variables_get`
- `conversation_variables_mget`
- `conversation_variables_list`
- `conversation_variables_resolve`
- `conversation_variables_write`
- `conversation_variables_promote`
- `workspace_variables_get`
- `workspace_variables_mget`
- `workspace_variables_list`
- `workspace_variables_write`
- `human_interactions_request`

Rule:

- public protocol method IDs use `snake_case`

### 2. Tool Names

These are the model-visible tool identifiers surfaced inside a capability snapshot or runtime tool surface.

Examples:

- `subagent_spawn`
- `subagent_poll`
- `memory_search`
- `skills_install`
- `compact_context`

Rules:

- public tool names use `snake_case`
- dotted names such as `human_interactions.request` are not valid public tool names
- tool names and protocol method IDs may overlap in wording, but they are different identifier families and must remain independently documented

### 3. HTTP Routes

These are transport details for the current Rails implementation.

Examples:

- `/agent_api/registrations`
- `/agent_api/conversation_variables`
- `/agent_api/human_interactions`

Rules:

- HTTP route shape is implementation-specific
- routes do not define the canonical public method ID
- the logical protocol contract must remain stable even if controller or route structure changes

## Naming Rules

The new Core Matrix contract should follow these rules consistently:

1. Use `snake_case` for all public protocol method IDs.
2. Use `snake_case` for all model-visible tool names.
3. Reserve controller paths for transport only.
4. Avoid dotted public identifiers in the new contract, even if older prototypes used them.
5. Keep naming semantic and collision-resistant.
6. Keep the same identifier stable across capability snapshots, audit records, telemetry facts, and contract tests.

## Transport Boundary

The public contract should remain transport-neutral.

Phase 2 should separate:

- logical method ids and envelopes
- durable execution semantics
- transport implementation details

Rules:

- short HTTP requests are the canonical transport for the public agent API in
  Phase 2
- long-running agent execution must not depend on one held HTTP request from
  `Core Matrix` into an agent program
- an outbound WebSocket session may exist as an optional accelerator for
  notifications or wakeups
- ActionCable, SolidCable, and AnyCable are Rails implementation options, not
  public protocol standards
- if WebSocket is used, it must carry the platform's own message envelope
  rather than ActionCable-specific channel semantics

## Capability Snapshot Shape

Capability snapshots should separate protocol metadata from tool-surface metadata.

At minimum, a capability snapshot should expose:

- `protocol_methods`
- `agent_capabilities_version`
- `tool_catalog`
- `config_schema_snapshot`
- `conversation_override_schema_snapshot`
- `default_config_snapshot`

Rules:

- do not overload one mixed `supported_methods` list with both protocol methods and tool names
- `protocol_methods` describes callable runtime operations
- `tool_catalog` describes model-visible or runtime-callable tools
- the handshake must freeze enough metadata for history, audit, and recovery-time compatibility checks

## Tool Catalog Shape

Each tool entry should carry at least:

- `tool_name`
- `tool_kind`
- `implementation_source`
- `implementation_ref`
- `input_schema`
- `result_schema`
- `streaming_support`
- `idempotency_policy`

Recommended `tool_kind` values:

- `kernel_primitive`
- `agent_observation`
- `effect_intent`

Rules:

- `tool_name` is the canonical model-visible identifier
- `implementation_source` identifies where the implementation lives, such as `kernel` or `agent`
- `implementation_ref` is a stable implementation locator for audit and diagnostics, not a user-facing label
- input and result schema snapshots must be stable enough for contract tests and replay diagnostics

## Tool Invocation Envelope

Whenever Core Matrix later exposes a generic tool-execution bridge between the kernel and an agent runtime, that bridge should use a stable invocation envelope rather than ad hoc request shapes.

At minimum, a tool invocation request should carry:

- `invocation_id`
- `tool_name`
- `tool_kind`
- `caller_context`
- `input`
- `idempotency_key`
- `timeout_ms`
- `streaming_mode`

At minimum, a tool invocation result should carry:

- `invocation_id`
- `status`
- `output`
- `artifacts`
- `approval_required`
- `retryable`
- `error`

Rules:

- `invocation_id` must be stable across logs, retries, audit rows, and replay diagnostics
- `caller_context` should include enough kernel identity to attribute execution, at minimum installation, workspace, conversation, turn, workflow, and deployment references when available
- `status` should distinguish successful completion, kernel-registered intent, approval-blocked intent, and failure
- `approval_required` should reflect kernel-governed approval state, not an agent-local guess
- `retryable` must be a contract-level field, because retry semantics affect workflow policy and operator recovery flows
- `error` should use a stable machine-readable shape with at least `code`, `message`, and optional diagnostic metadata
- streaming partials must not be treated as durable proof that a final side effect completed
- `effect_intent` invocations must not report durable side-effect success until the kernel has materialized the governed workflow node or equivalent execution resource
- the current backend batch does not need to ship this bridge yet, but follow-up bridge work should inherit this envelope rather than inventing a new one

## Durable Execution Delivery

For agent-program-owned execution that may take non-trivial time, the platform
should prefer durable delivery semantics over synchronous RPC.

Recommended logical method families for follow-up work:

- `execution_claim`
- `execution_lease_heartbeat`
- `execution_progress`
- `execution_complete`
- `execution_fail`

Rules:

- `Core Matrix` remains the source of truth for execution state
- the agent program claims executable work instead of receiving a blocking
  request from the kernel
- the same durable execution path must remain valid when the optional WebSocket
  accelerator is unavailable
- claim, heartbeat, progress, completion, and failure reporting must remain
  attributable to one authenticated deployment and one durable execution id

## Authority Rules

Core Matrix remains a strong-kernel system.

### Kernel Primitive

`kernel_primitive` tools are kernel-owned and kernel-executed.

### Agent Observation

`agent_observation` tools may be agent-owned and may execute inside the agent runtime, but they must return observation data only.

### Effect Intent

`effect_intent` tools may be proposed by an agent-owned surface, but they must not complete the final side effect inside the agent runtime.

Rules:

- `effect_intent` results must materialize into kernel workflow nodes or equivalent kernel-governed execution resources
- approval, audit, usage attribution, timeout, retry, and idempotency remain kernel authority
- colocating the runtime and execution environment in v1 does not change the contract-level authority model

## Current Batch Versus Follow-Up

The current backend kernel batch should freeze:

- naming rules
- capability-snapshot structure
- tool-catalog structure
- invocation-envelope semantics for future generic tool bridges
- the `tool_kind` taxonomy
- the distinction between agent observation and effect intent

The current backend kernel batch does not need to fully implement:

- generic agent-owned tool execution bridges
- attachment-import bridges for every runtime
- connector-specific bridge adapters
- optional WebSocket accelerator transports
- schedule or webhook trigger runners
- knowledge or long-term memory bridge implementations
- MCP transport adapters beyond the contract-level reserved integration surface

Those items belong to follow-up implementation plans, but they should inherit the contract rules defined here rather than inventing new naming or authority semantics ad hoc.
