# Agent Registry And Connectivity Foundations

## Purpose

Task 03 establishes the machine-facing registry substrate for Core Matrix:
agents, execution runtimes, one-time enrollment tokens,
immutable agent snapshots, and connection-backed heartbeat state.

## Status

This document records the current landed connectivity substrate.

This document is the source of truth for the registration and
connection-backed runtime aggregates underneath the control plane, including
external-runtime pairing and same-installation agent-snapshot rotation.
Mailbox-first control delivery, `poll + WebSocket + piggyback` transport
parity, and distinct realtime-link versus control-activity facts build on top
of this substrate.

Related design note:

- [2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md)

## Aggregate Responsibilities

### Agent

- `Agent` is the stable logical identity of an agent inside
  one installation.
- Visibility is `public` or `private`.
- `public` agents may be system-provisioned and ownerless, or user-created and
  owner-bound.
- `private` agents require an owner user from the same installation.
- Lifecycle state is tracked separately from runtime health.

### ExecutionRuntime

- `ExecutionRuntime` is the stable runtime-resource owner aggregate.
- It is the durable owner for environment-backed resources such as
  `ProcessRun` and future shell or file sessions.
- Visibility is `public` or `private`, with the same owner and provisioning
  invariants as `Agent`.
- Kind is `local`, `container`, or `remote`.
- Stable reconciliation identity is `execution_runtime_fingerprint`, scoped to one
  installation.
- Connection details live in `connection_metadata`.
- Lifecycle state tracks whether the executor carrier is still available for
  new work.

### AgentEnrollment

- Enrollment tokens are one-time and expiring.
- Enrollment token digests are stored, not plaintext tokens.
- Consuming an enrollment sets `consumed_at`.

### AgentSnapshot

- `AgentSnapshot` is the immutable version and capability snapshot for
  one `Agent`.
- It stores the protocol methods, tool catalog, profile catalog, and config
  snapshots advertised by one runtime release fingerprint.
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
  for one
  `ExecutionRuntime`.
- Only one `active` connection may exist for a given `ExecutionRuntime` at a
  time.
- Execution delivery and runtime-owned resource reporting lease against this
  connection rather than against `AgentSnapshot`.

## Services

### `AgentEnrollments::Issue`

- Mints a one-time enrollment token for an agent.
- Requires the issuing actor to belong to the same installation.
- Writes the `agent_enrollment.issued` audit row.

### `AgentSnapshots::Register`

- Resolves an enrollment token by digest lookup.
- Rejects invalid, consumed, or expired tokens.
- Creates or reuses the advertised `AgentSnapshot` and opens the live
  `AgentConnection` plus `ExecutionRuntimeConnection` in one transaction.
- Exchanges the one-time enrollment token for a durable connection credential.
- Works for bundled and external runtimes because the kernel only needs
  registration metadata, not a callback path into the runtime's private
  network.
- Writes the `agent_connection.registered` audit row.

### `AgentSnapshots::RecordHeartbeat`

- Updates `AgentConnection` health metadata and heartbeat timestamps.
- Marks the live connection healthy or unavailable without mutating the
  immutable
  `AgentSnapshot`.
- Preserves version identity while connectivity changes over time.

## Pairing And Rotation

- external runtimes pair outbound with Core Matrix; normal execution delivery
  does not require the kernel to dial runtime-private addresses
- the runtime pairing manifest is registration metadata, not a product
  execution callback surface
- bundled and external runtimes share the same registration and heartbeat
  substrate once the `AgentSnapshot` row exists
- release change is represented as registering a new `AgentSnapshot`,
  waiting for a healthy connection, and then cutting future work over to that
  newly active connection
- both upgrade and downgrade use the same rotation contract
- version rotation reuses the same `ExecutionRuntime` when
  `execution_runtime_fingerprint` is unchanged
- mailbox control targets logical owners plus live connections, not persisted
  agent-snapshot rows

## Invariants

- `Agent` and `AgentSnapshot` remain separate aggregates.
- `ExecutionRuntime` remains stable across version rotation for the same
  runtime carrier.
- Cross-installation references are rejected for owners, enrollments, and
  versions.
- Active connection uniqueness is scoped to the logical owner (`agent_id`
  or `execution_runtime_id`), not the top-level installation.
- `AgentSnapshot` rows are append-only historical records.
- Cross-aggregate side effects happen through service objects, not model
  callbacks.

## Failure Modes

- Private agents without an owner user are invalid.
- Enrollment reuse or unknown enrollment tokens raise `InvalidEnrollment`.
- Expired enrollment tokens raise `ExpiredEnrollment`.
- Cross-installation issuance or registration raises `ArgumentError`.
- Attempting to mutate a persisted `AgentSnapshot` raises
  `ActiveRecord::ReadOnlyRecord`.
