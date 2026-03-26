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
- `deployment_health_report`
- `agent_schemas_get`
- `capabilities_handshake`
- `capabilities_refresh`
- `agent_poll`
- `execution_assignment`
- `execution_started`
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
- reserved Core Matrix system tools use the `core_matrix__` prefix
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

- canonical control semantics are mailbox-shaped, not callback-shaped
- `poll` and `WebSocket` are delivery transports for the same mailbox items
- long-running agent execution must not depend on one held HTTP request from
  `Core Matrix` into an agent program
- short HTTP requests remain the resource-plane transport for transcript,
  variable, human-interaction, and registration APIs
- `WebSocket` is preferred for low-latency control delivery, but `poll` must
  remain a complete fallback path
- ActionCable, SolidCable, and AnyCable are Rails implementation options, not
  public protocol standards
- `WebSocket` disconnect is not, by itself, the same fact as deployment
  unavailability
- if WebSocket is used, it must carry the platform's own message envelope
  rather than ActionCable-specific channel semantics

## Capability Snapshot Shape

Capability snapshots should separate protocol metadata from tool-surface metadata.

At minimum, a capability snapshot should expose:

- `protocol_methods`
- `agent_capabilities_version`
- `tool_catalog`
- `effective_tool_catalog`
- `config_schema_snapshot`
- `conversation_override_schema_snapshot`
- `default_config_snapshot`

Rules:

- do not overload one mixed `supported_methods` list with both protocol methods and tool names
- `protocol_methods` describes callable runtime operations
- `tool_catalog` describes model-visible or runtime-callable tools
- `effective_tool_catalog` describes the final winning tool surface after
  environment, agent, and reserved system-tool precedence are applied
- the handshake must freeze enough metadata for history, audit, and recovery-time compatibility checks

## Binding Freeze Boundary

Capability handshake and per-execution binding are different moments.

Rules:

- deployment handshake advertises the live capability catalog and current
  availability metadata
- per-execution binding resolution freezes later, when `AgentTaskRun` is
  created from the current execution snapshot
- invocation rows must record the resolved `ToolBinding` or equivalent binding
  ref, not just the logical `tool_name`
- retries within one attempt keep the same binding unless an explicit recovery
  policy opens a new attempt and records a new binding decision

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
- `kernel_primitive` tools that are intentionally model-visible must use the
  reserved `core_matrix__` prefix so they stay outside ordinary agent and
  environment collision domains
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

- `agent_poll`
- `execution_assignment`
- `execution_started`
- `execution_progress`
- `execution_complete`
- `execution_fail`
- `execution_interrupted`
- `resource_close_request`
- `resource_close_acknowledged`
- `resource_closed`
- `resource_close_failed`

Rules:

- `Core Matrix` remains the source of truth for execution state
- the agent program receives durable mailbox items rather than blocking
  callbacks from the kernel
- claimed work should carry stable execution hints such as:
  - likely model or model-profile context
  - resolved provider and model identifiers
  - resolved provider-facing sampling defaults when known, such as
    `temperature`, `top_p`, `top_k`, `min_p`, `presence_penalty`, and
    `repetition_penalty`
  - reserved-output guidance
  - any advisory compaction threshold the kernel already knows
- transport retries must be idempotent by `message_id`
- delivery retries must not be conflated with execution-attempt retries
- `turn_interrupt` and broader close flows must fence stale work so later retry
  or completion cannot mutate superseded turn state
- conversation-scoped execution must carry stale-work protection such as a tail
  guard so restart or queue semantics cannot later commit output onto the wrong
  conversation tail
- wait transitions must stay kernel-owned; if runtime work blocks on human
  input, subagent coordination, or another durable condition, the runtime must
  request that wait through kernel-recognized payloads rather than inventing a
  transport-local pause model
- duplicate, out-of-order, expired-lease, or superseded-lease reports must fail
  safe and must not silently mutate durable execution state
- the same durable control path must remain valid when `WebSocket` is
  unavailable
- mailbox items and reports must remain attributable to one authenticated
  deployment and one durable execution or resource identity
- completion or failure reporting may carry usage facts, but authoritative
  provider or supervised-capability usage must outrank agent-side estimates

See the focused mailbox-control note for the recommended shared envelope,
method payloads, turn-interrupt semantics, and close lifecycle:

- [2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md)

## Authority Rules

Core Matrix remains a strong-kernel system.

### Kernel Primitive

`kernel_primitive` tools are kernel-owned and kernel-executed.

When they are model-visible, they must publish reserved `core_matrix__*`
`tool_name` values rather than competing for ordinary tool names such as
`shell_exec`.

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
- transport-specific delivery optimizations beyond the shared mailbox envelope
- schedule or webhook trigger runners
- knowledge or long-term memory bridge implementations
- MCP transport adapters beyond the contract-level reserved integration surface

Those items belong to follow-up implementation plans, but they should inherit the contract rules defined here rather than inventing new naming or authority semantics ad hoc.
