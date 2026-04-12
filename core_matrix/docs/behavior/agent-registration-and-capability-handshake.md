# Agent Registration And Capability Handshake

## Purpose

Task 11.1 adds the first machine-facing HTTP protocol boundary for Core Matrix:
registration by enrollment token, authenticated heartbeat and health probes,
capability refresh, and capability handshake with config reconciliation.

## Status

This document records the current landed registration and handshake substrate.

This document is the source of truth for agent/runtime connection
registration, connection-credential issuance, and capability handshake
behavior. Mailbox-driven control, split presence versus health, and optional
realtime delivery build on top of this substrate.

Related design note:

- [2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md)

## Controller Boundary

- `AgentAPI::RegistrationsController` is the only unauthenticated machine-facing
  endpoint in this task.
- `AgentAPI::HeartbeatsController`, `AgentAPI::HealthController`, and
  `AgentAPI::CapabilitiesController` are thin wrappers around application
  services and agent-connection lookups.
- These controllers stay machine-facing only; they do not introduce browser UI,
  schedule-trigger ingress, or webhook-trigger ingress.

## Identifier Boundary

- registration now reconciles the bound `ExecutionRuntime` from the stable
  request-side `execution_runtime_fingerprint`
- registration responses still expose `execution_runtime_id`, and that
  field now carries `ExecutionRuntime.public_id`
- registration, health, and heartbeat payloads expose public ids such as
  `agent_id`, `agent_definition_version_id`, `agent_connection_id`, and
  `execution_runtime_connection_id`
- internal agent-definition-version, installation, and execution-runtime relations still use
  `bigint` after the HTTP boundary reconciliation

## Authentication Model

- registration uses a one-time `PairingSession` token and exchanges it for a
  durable connection credential
- all follow-up agent API calls authenticate with HTTP token auth using the
  `AgentConnection` credential
- execution-runtime-plane calls authenticate separately with the
  `ExecutionRuntimeConnection` credential when an `ExecutionRuntime` is
  present
- connection credentials are matched by digest lookup on `AgentConnection` or
  `ExecutionRuntimeConnection`; plaintext credentials are only returned at registration time
- invalid connection credentials return `401 unauthorized`

## Public Contract Shape

### Protocol Methods

- capability snapshots publish `protocol_methods` as a separate array from the
  tool catalog
- each protocol method entry carries a stable `snake_case` `method_id`
- this task preserves explicit protocol method IDs such as `agent_health`,
  `capabilities_handshake`, and `capabilities_refresh`

### Tool Catalog

- both `AgentDefinitionVersion` and `ExecutionRuntime` register their own tool catalogs
  independently
- capability snapshots publish `tool_catalog` separately from
  `protocol_methods`
- each tool entry carries a stable `snake_case` `tool_name`
- supported `tool_kind` values in this task are:
  - `kernel_primitive`
  - `agent_observation`
  - `effect_intent`
- the contract payload includes tool metadata fields for implementation source,
  implementation reference, input schema, result schema, streaming support, and
  idempotency policy
- capability refresh and handshake now also publish:
  - `agent_plane`
  - `execution_runtime_plane`
  - `effective_tool_catalog`
  - `governed_effective_tool_catalog`
- those sections now come from one shared `RuntimeCapabilityContract`
  projection instead of controller-local hash assembly
- `effective_tool_catalog` resolves ordinary tool-name conflicts in this order:
  - `ExecutionRuntime`
  - `AgentDefinitionVersion`
  - `Core Matrix`
- the agent profile policy may still mask tools from that effective set through
  `allowed_tool_names` before a turn freezes visible bindings
- reserved `core_matrix__*` system tools remain outside ordinary collision
  resolution
- `governed_effective_tool_catalog` decorates the effective entries with:
  - `tool_definition_id`
  - `tool_implementation_id`
  - `governance_mode`
- those identifiers are `public_id` values on the durable governance rows; the
  HTTP boundary does not expose internal `bigint` ids for tool governance

### Endpoint Responses

- registration returns agent identity, agent definition version identity, connection
  credentials, and the initial capability snapshot
- registration returns `agent_id`, `agent_definition_version_id`,
  `agent_connection_id`, and optional `execution_runtime_connection_id` as public ids
- heartbeat returns `method_id: "agent_health"` plus agent-connection health and
  the latest heartbeat timestamp
- health returns the same public `agent_health` method family plus agent
  definition fingerprint, protocol version, and SDK version
- health returns `agent_definition_version_id` as a public id
- capabilities refresh returns `method_id: "capabilities_refresh"` and the
  current agent-definition-version capability payload
- capabilities handshake returns `method_id: "capabilities_handshake"` and the
  current agent-definition-version capability payload
- when a default execution runtime is present, both capability endpoints also
  return execution-runtime identity and the current execution-runtime
  capability payload and tool catalog

## Agent Definition Version Rules

- `AgentDefinitionVersion` remains immutable after creation
- protocol method entries must be hashes with `snake_case` `method_id` values
- tool catalog entries must be hashes with `snake_case` `tool_name` values and
  a supported `tool_kind`
- runtime-owned tool names under the reserved `core_matrix__*` prefix are
  rejected unless the implementation source is explicitly `core_matrix`
- `RuntimeCapabilityContract` is the shared formatter for:
  - machine-facing capability refresh and handshake payloads
  - `agent_plane`
  - `execution_runtime_plane`
  - `effective_tool_catalog`
  - conversation-facing runtime capability payloads
- capability handshake now also projects the durable governance rows for the
  current agent definition version:
  - `ImplementationSource`
  - `ToolDefinition`
  - `ToolImplementation`
- projection is idempotent per agent definition version and profile policy:
  - if profiles declare `allowed_tool_names`, the governed projection is
    limited to the union of those declared logical tools
  - otherwise projection falls back to the full effective tool catalog
- paused-work recovery now also relies on that same capability-contract shape:
  `ExecutionIdentityRecovery::ResolveTarget` compares the replacement
  agent definition version against the paused turn's frozen capability surface before it
  allows paused work to continue
- controllers and recovery paths build the shared contract through
  `RuntimeCapabilityContract` instead of carrying separate controller-local
  payload formatters

## Config Reconciliation

- `AgentDefinitionVersions::Handshake` authenticates through the live
  `AgentConnection`, not by trusting a caller-provided agent-definition-version identity
- handshake reuses the existing `AgentDefinitionVersion` when the normalized
  definition package already matches the authenticated version fingerprint
- handshake appends a new `AgentDefinitionVersion` only when the normalized
  package changes
- handshake normalizes both execution-runtime-plane and agent-plane payloads
  through the shared runtime capability contract before response rendering and
  tool governance projection
- concurrent handshakes serialize only the governed tool projection, so
  repeated handshakes reuse the same durable tool-definition rows without
  duplicate-key races
- paused-work recovery re-resolves the frozen selector through
  `ExecutionIdentityRecovery::ResolveTarget`, so frozen selector-bearing
  defaults continue to shape whether a replacement agent definition version can resume or
  retry paused work safely
- handshake returns a structured `reconciliation_report` with:
  - `definition_changed`
  - `agent_config_version`
- `AgentConfigStates::Reconcile` keeps the effective config version stable when
  both the base definition and effective payload remain unchanged

## Failure Modes

- invalid, consumed, or expired enrollment tokens are rejected during
  registration
- blank `execution_runtime_fingerprint` values are rejected during registration
- execution-runtime reconciliation remains scoped to the enrollment
  installation instead of trusting caller-provided runtime ids
- machine-facing endpoints reject unknown connection credentials before mutating
  connection health or capability state

## Retained Implementation Notes

- Rails autoloading expects the `app/controllers/agent_api` namespace to be
  `AgentAPI`, not `AgentApi`, so the controller module uses the acronym form to
  satisfy Zeitwerk
- `ActionController::API` does not include HTTP token auth helpers by default,
  so `AgentAPI::BaseController` includes
  `ActionController::HttpAuthentication::Token::ControllerMethods` explicitly
