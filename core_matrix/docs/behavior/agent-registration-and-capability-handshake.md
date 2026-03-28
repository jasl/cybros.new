# Agent Registration And Capability Handshake

## Purpose

Task 11.1 adds the first machine-facing HTTP protocol boundary for Core Matrix:
registration by enrollment token, authenticated heartbeat and health probes,
capability refresh, and capability handshake with config reconciliation.

## Status

This document records the current landed registration and handshake substrate.

Phase 2 now layers mailbox-driven control, split presence versus health, and
optional realtime delivery on top of this registration and handshake
substrate. This document remains the source of truth for registration,
machine-credential issuance, and capability handshake behavior.

Planned replacement design:

- [2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md)

## Controller Boundary

- `AgentAPI::RegistrationsController` is the only unauthenticated machine-facing
  endpoint in this task.
- `AgentAPI::HeartbeatsController`, `AgentAPI::HealthController`, and
  `AgentAPI::CapabilitiesController` are thin wrappers around application
  services and deployment lookups.
- These controllers stay machine-facing only; they do not introduce browser UI,
  schedule-trigger ingress, or webhook-trigger ingress.

## Identifier Boundary

- registration now resolves `execution_environment_id` by
  `ExecutionEnvironment.public_id`
- registration, health, and heartbeat payloads keep the existing field names
  such as `deployment_id`, but those fields now carry public UUIDv7-backed
  `public_id` values
- internal deployment, installation, and environment relations still use
  `bigint` after the HTTP boundary lookup

## Authentication Model

- registration uses a one-time `AgentEnrollment` token and exchanges it for a
  durable machine credential
- all follow-up agent API calls authenticate with HTTP bearer token auth using
  the deployment machine credential
- machine credentials are still matched by digest lookup on `AgentDeployment`;
  plaintext credentials are only returned at registration time
- invalid machine credentials return `401 unauthorized`

## Public Contract Shape

### Protocol Methods

- capability snapshots publish `protocol_methods` as a separate array from the
  tool catalog
- each protocol method entry carries a stable `snake_case` `method_id`
- this task preserves explicit protocol method IDs such as `agent_health`,
  `capabilities_handshake`, and `capabilities_refresh`

### Tool Catalog

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
  - `environment_plane`
  - `effective_tool_catalog`
- those sections now come from one shared `RuntimeCapabilityContract`
  projection instead of controller-local hash assembly
- `effective_tool_catalog` resolves ordinary tool-name conflicts in this order:
  - `ExecutionEnvironment`
  - `AgentDeployment`
  - `Core Matrix`
- reserved `core_matrix__*` system tools remain outside ordinary collision
  resolution

### Endpoint Responses

- registration returns deployment identity, bootstrap state, machine
  credential, and the initial capability snapshot
- registration returns `deployment_id` and `agent_installation_id` as public
  ids
- heartbeat returns `method_id: "agent_health"` plus deployment health and the
  latest heartbeat timestamp
- heartbeat returns `deployment_id` as a public id
- health returns the same public `agent_health` method family plus deployment
  fingerprint, protocol version, SDK version, and active capability version
- health returns `deployment_id` as a public id
- capabilities refresh returns `method_id: "capabilities_refresh"` and the
  active capability snapshot payload
- capabilities handshake returns `method_id: "capabilities_handshake"` and the
  reconciled capability snapshot payload
- both capability endpoints also return execution-environment identity and the
  current environment capability payload and tool catalog

## Capability Snapshot Rules

- `CapabilitySnapshot` remains immutable after creation
- protocol method entries must be hashes with `snake_case` `method_id` values
- tool catalog entries must be hashes with `snake_case` `tool_name` values and
  a supported `tool_kind`
- `RuntimeCapabilityContract` is the shared formatter for:
  - machine-facing capability refresh and handshake payloads
  - `agent_plane`
  - `environment_plane`
  - `effective_tool_catalog`
  - conversation-facing runtime capability payloads
- `CapabilitySnapshot#as_contract_payload`,
  `CapabilitySnapshot#as_agent_plane_payload`, and
  `ExecutionEnvironment#as_runtime_plane_payload` are thin adapters over that
  shared contract

## Config Reconciliation

- `AgentDeployments::Handshake` requires the caller fingerprint to match the
  authenticated deployment fingerprint
- handshake reuses an identical capability snapshot when one already exists on
  the deployment; otherwise it appends a new versioned snapshot
- identical snapshot reuse compares the normalized runtime capability contract
  rather than a narrow tool-name subset
- that comparison surface includes `agent_plane`, `environment_plane`,
  `effective_tool_catalog`, `profile_catalog`, and the config, override, and
  default schema snapshots that shape runtime-visible behavior
- capability-snapshot version allocation is serialized at the deployment
  boundary so concurrent handshakes either reuse the same snapshot or append
  exactly one new version
- handshake updates the deployment protocol version, SDK version, and active
  capability snapshot pointer in one transaction
- handshake normalizes both environment-plane and agent-plane payloads through
  the shared runtime capability contract before persistence or response
  rendering
- `AgentDeployments::ReconcileConfig` keeps selector-bearing defaults from the
  previous active snapshot when the new config schema still exposes those keys
- the retained selector-bearing keys in this task are `interactive`,
  `model_slots`, and `model_roles`
- reconciliation is best-effort and returns a `reconciliation_report` with
  status plus retained keys rather than failing activation on schema drift

## Failure Modes

- invalid, consumed, or expired enrollment tokens are rejected during
  registration
- execution environments from another installation are rejected with a
  controlled validation-style error rather than bubbling a server exception
- fingerprint mismatches are rejected during capability handshake
- machine-facing endpoints reject unknown deployment credentials before mutating
  deployment health or capability state

## Retained Implementation Notes

- Rails autoloading expects the `app/controllers/agent_api` namespace to be
  `AgentAPI`, not `AgentApi`, so the controller module uses the acronym form to
  satisfy Zeitwerk
- `ActionController::API` does not include HTTP token auth helpers by default,
  so `AgentAPI::BaseController` includes
  `ActionController::HttpAuthentication::Token::ControllerMethods` explicitly
