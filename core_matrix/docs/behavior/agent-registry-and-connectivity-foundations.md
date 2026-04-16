# Agent Registry And Connectivity Foundations

## Purpose

Task 03 establishes the machine-facing registry substrate for Core Matrix:
agents, execution runtimes, onboarding sessions,
immutable agent definition versions, and connection-backed heartbeat state.

## Status

This document records the current landed connectivity substrate.

This document is the source of truth for the registration and
connection-backed runtime aggregates underneath the control plane, including
external-runtime pairing and same-installation agent-definition-version rotation.
Mailbox-first control delivery, `poll + WebSocket + piggyback` transport
parity, and distinct realtime-link versus control-activity facts build on top
of this substrate.

Related design note:

- [2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md)

## Aggregate Responsibilities

### Agent

- `Agent` is the stable logical identity of an agent inside
  one installation.
- It participates in prompt and loop preparation for turns.
- It may also advertise agent-owned tools that Core Matrix can bind and route
  back to the agent control plane.
- Visibility is `public` or `private`.
- `public` agents may be system-provisioned and ownerless, or user-created and
  owner-bound.
- `private` agents require an owner user from the same installation.
- Lifecycle state is tracked separately from runtime health.

### ExecutionRuntime

- `ExecutionRuntime` is the stable runtime-resource owner aggregate.
- It may advertise runtime-owned tools, but it is not a required participant
  for every conversation.
- It is the durable owner for environment-backed resources such as
  `ProcessRun` and future shell or file sessions.
- Visibility is `public` or `private`, with the same owner and provisioning
  invariants as `Agent`.
- Kind is `local`, `container`, or `remote`.
- Stable reconciliation identity is `execution_runtime_fingerprint`, scoped to one
  installation.
- Live runtime connection details are exposed through
  `ExecutionRuntime#connection_metadata`.
- Bundled-runtime registration configuration uses
  `execution_runtime_connection_metadata` when seeding the corresponding
  `ExecutionRuntimeConnection.endpoint_metadata`.
- Lifecycle state tracks whether the runtime carrier is still available for
  new work.

### OnboardingSession

- Onboarding sessions are expiring and scoped to one installation.
- An onboarding session targets exactly one logical resource kind:
  `agent` or `execution_runtime`.
- Onboarding token digests are stored, not plaintext tokens.
- Progress through runtime registration and agent registration is recorded on
  the onboarding session row.

### AgentDefinitionVersion

- `AgentDefinitionVersion` is the immutable version and capability snapshot for
  one `Agent`.
- It stores the protocol methods, tool catalog, canonical config schema,
  workspace-agent settings schema/defaults, default canonical config, and
  reflected surface advertised by one agent program release.
- It does not own live connectivity, connection credentials, or execution-runtime
  state.

### AgentConnection

- `AgentConnection` is the live control-plane identity for one `Agent`.
- Connection credentials and connection tokens are stored as digests, not
  plaintext bearer secrets.
- Only one `active` connection may exist for a given `Agent` at a time.
- Health, heartbeat, realtime-link, and control-activity facts live here.

### ExecutionRuntimeConnection

- `ExecutionRuntimeConnection` is the live execution-runtime-plane identity
  for one `ExecutionRuntime`.
- Only one `active` connection may exist for a given `ExecutionRuntime` at a
  time.
- Execution delivery and runtime-owned resource reporting lease against this
  connection rather than against `AgentDefinitionVersion`.

## Services

### `OnboardingSessions::Issue`

- Mints an expiring onboarding token for an `Agent` or
  `ExecutionRuntime`.
- Requires the issuing actor to belong to the same installation.
- Writes the `onboarding_session.issued` audit row.

### `AgentDefinitionVersions::Register`

- Resolves an agent onboarding token by digest lookup.
- Rejects invalid, expired, revoked, or closed onboarding tokens.
- Creates or reuses the advertised `AgentDefinitionVersion` and opens the live
  `AgentConnection`.
- Reuses the agent's current `default_execution_runtime` when one is already
  registered; it does not open a new `ExecutionRuntimeConnection`.
- Works for bundled and external runtimes because the kernel only needs
  registration metadata, not a callback path into the runtime's private
  network.
- Writes the `agent_connection.registered` audit row.

### `ExecutionRuntimeVersions::Register`

- Resolves an execution-runtime onboarding token by digest lookup.
- Rejects invalid, expired, revoked, or closed onboarding tokens.
- Creates or reuses the advertised `ExecutionRuntimeVersion` and opens the
  live `ExecutionRuntimeConnection`.
- Creates the logical `ExecutionRuntime` when the onboarding session does not
  target a pre-existing runtime row.
- Does not mutate `Agent.default_execution_runtime` as a side effect of
  runtime registration.
- Writes the `execution_runtime_connection.registered` audit row.

### `AgentConnections::RecordHeartbeat`

- Updates `AgentConnection` health metadata and heartbeat timestamps.
- Marks the live connection healthy or unavailable without mutating the
  immutable `AgentDefinitionVersion`.
- Preserves version identity while connectivity changes over time.

## Onboarding And Rotation

- external runtimes pair outbound with Core Matrix; normal execution delivery
  does not require the kernel to dial runtime-private addresses
- the runtime pairing manifest is registration metadata, not a product
  execution callback surface
- bundled and external runtimes share the same registration and heartbeat
  substrate once the `AgentDefinitionVersion` row exists
- release change is represented as registering a new `AgentDefinitionVersion`,
  waiting for a healthy connection, and then cutting future work over to that
  newly active connection
- both upgrade and downgrade use the same rotation contract
- version rotation reuses the same `ExecutionRuntime` when
  `execution_runtime_fingerprint` is unchanged
- mailbox control targets logical owners plus live connections, not persisted
  agent-definition-version rows
- conversations may omit an execution runtime entirely; in that case Core
  Matrix still coordinates agent-only turns and only runtime-owned tool
  bindings are absent

## Invariants

- `Agent` and `AgentDefinitionVersion` remain separate aggregates.
- `ExecutionRuntime` remains stable across version rotation for the same
  runtime carrier.
- Cross-installation references are rejected for owners, onboarding sessions, and
  versions.
- Active connection uniqueness is scoped to the logical owner (`agent_id`
  or `execution_runtime_id`), not the top-level installation.
- `AgentDefinitionVersion` rows are append-only historical records.
- Cross-aggregate side effects happen through service objects, not model
  callbacks.

## Failure Modes

- Private agents without an owner user are invalid.
- Unknown onboarding tokens raise
  `OnboardingSessions::ResolveFromToken::InvalidOnboardingToken`.
- Expired onboarding tokens raise
  `OnboardingSessions::ResolveFromToken::ExpiredOnboardingSession`.
- Closed or revoked onboarding tokens are rejected before registration
  continues.
- Cross-installation issuance or registration raises `ArgumentError`.
- Attempting to mutate a persisted `AgentDefinitionVersion` raises
  `ActiveRecord::ReadOnlyRecord`.
