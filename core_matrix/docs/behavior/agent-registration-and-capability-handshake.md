# Agent Registration And Capability Handshake

## Purpose

Task 11.1 adds the first machine-facing HTTP protocol boundary for Core Matrix:
registration by enrollment token, authenticated heartbeat and health probes,
capability refresh, and capability handshake with config reconciliation.

## Controller Boundary

- `AgentAPI::RegistrationsController` is the only unauthenticated machine-facing
  endpoint in this task.
- `AgentAPI::HeartbeatsController`, `AgentAPI::HealthController`, and
  `AgentAPI::CapabilitiesController` are thin wrappers around application
  services and deployment lookups.
- These controllers stay machine-facing only; they do not introduce browser UI,
  schedule-trigger ingress, or webhook-trigger ingress.

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

### Endpoint Responses

- registration returns deployment identity, bootstrap state, machine
  credential, and the initial capability snapshot
- heartbeat returns `method_id: "agent_health"` plus deployment health and the
  latest heartbeat timestamp
- health returns the same public `agent_health` method family plus deployment
  fingerprint, protocol version, SDK version, and active capability version
- capabilities refresh returns `method_id: "capabilities_refresh"` and the
  active capability snapshot payload
- capabilities handshake returns `method_id: "capabilities_handshake"` and the
  reconciled capability snapshot payload

## Capability Snapshot Rules

- `CapabilitySnapshot` remains immutable after creation
- protocol method entries must be hashes with `snake_case` `method_id` values
- tool catalog entries must be hashes with `snake_case` `tool_name` values and
  a supported `tool_kind`
- `CapabilitySnapshot#as_contract_payload` is the shared machine-facing payload
  formatter for registration and capability endpoints

## Config Reconciliation

- `AgentDeployments::Handshake` requires the caller fingerprint to match the
  authenticated deployment fingerprint
- handshake reuses an identical capability snapshot when one already exists on
  the deployment; otherwise it appends a new versioned snapshot
- handshake updates the deployment protocol version, SDK version, and active
  capability snapshot pointer in one transaction
- `AgentDeployments::ReconcileConfig` keeps selector-bearing defaults from the
  previous active snapshot when the new config schema still exposes those keys
- the retained selector-bearing keys in this task are `interactive`,
  `model_slots`, and `model_roles`
- reconciliation is best-effort and returns a `reconciliation_report` with
  status plus retained keys rather than failing activation on schema drift

## Failure Modes

- invalid, consumed, or expired enrollment tokens are rejected during
  registration
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
