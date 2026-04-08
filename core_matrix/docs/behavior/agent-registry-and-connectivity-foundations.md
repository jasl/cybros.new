# Agent Registry And Connectivity Foundations

## Purpose

Task 03 establishes the machine-facing registry substrate for Core Matrix:
agent programs, executor programs, one-time enrollment tokens,
immutable program versions, and session-backed heartbeat state.

## Status

This document records the current landed connectivity substrate.

This document is the source of truth for the registration and session-backed
runtime aggregates underneath the control plane, including external-runtime
pairing and same-installation program-version rotation. Mailbox-first control delivery,
`poll + WebSocket + piggyback` transport parity, and distinct realtime-link
versus control-activity facts build on top of this substrate.

Related design note:

- [2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md)

## Aggregate Responsibilities

### AgentProgram

- `AgentProgram` is the stable logical identity of an agent program inside
  one installation.
- Visibility is `personal` or `global`.
- Personal agent programs require an owner user from the same
  installation.
- Lifecycle state is tracked separately from runtime health.

### ExecutorProgram

- `ExecutorProgram` is the stable runtime-resource owner aggregate.
- It is the durable owner for environment-backed resources such as
  `ProcessRun` and future shell or file sessions.
- Kind is `local`, `container`, or `remote`.
- Stable reconciliation identity is `executor_fingerprint`, scoped to one
  installation.
- Connection details live in `connection_metadata`.
- Lifecycle state tracks whether the executor carrier is still available for
  new work.

### AgentEnrollment

- Enrollment tokens are one-time and expiring.
- Enrollment token digests are stored, not plaintext tokens.
- Consuming an enrollment sets `consumed_at`.

### AgentProgramVersion

- `AgentProgramVersion` is the immutable version and capability snapshot for
  one `AgentProgram`.
- It stores the protocol methods, tool catalog, profile catalog, and config
  snapshots advertised by one runtime release fingerprint.
- It does not own live connectivity, machine credentials, or executor-program
  state.

### AgentSession

- `AgentSession` is the live control-plane identity for one `AgentProgram`.
- Machine credentials and session tokens are stored as digests, not plaintext
  bearer secrets.
- Only one `active` session may exist for a given `AgentProgram` at a time.
- Health, heartbeat, realtime-link, and control-activity facts live here.

### ExecutorSession

- `ExecutorSession` is the live executor-plane identity for one
  `ExecutorProgram`.
- Only one `active` session may exist for a given `ExecutorProgram` at a
  time.
- Execution delivery and runtime-owned resource reporting lease against this
  session rather than against `AgentProgramVersion`.

## Services

### `AgentEnrollments::Issue`

- Mints a one-time enrollment token for an agent program.
- Requires the issuing actor to belong to the same installation.
- Writes the `agent_enrollment.issued` audit row.

### `AgentProgramVersions::Register`

- Resolves an enrollment token by digest lookup.
- Rejects invalid, consumed, or expired tokens.
- Creates or reuses the advertised `AgentProgramVersion` and opens the live
  `AgentSession` plus `ExecutorSession` in one transaction.
- Exchanges the one-time enrollment token for a durable machine credential.
- Works for bundled and external runtimes because the kernel only needs
  registration metadata, not a callback path into the runtime's private
  network.
- Writes the `agent_session.registered` audit row.

### `AgentProgramVersions::RecordHeartbeat`

- Updates `AgentSession` health metadata and heartbeat timestamps.
- Marks the live session healthy or unavailable without mutating the immutable
  `AgentProgramVersion`.
- Preserves version identity while connectivity changes over time.

## Pairing And Rotation

- external runtimes pair outbound with Core Matrix; normal execution delivery
  does not require the kernel to dial runtime-private addresses
- the runtime pairing manifest is registration metadata, not a product
  execution callback surface
- bundled and external runtimes share the same registration and heartbeat
  substrate once the `AgentProgramVersion` row exists
- release change is represented as registering a new `AgentProgramVersion`,
  waiting for a healthy session, and then cutting future work over to that
  newly active session
- both upgrade and downgrade use the same rotation contract
- version rotation reuses the same `ExecutorProgram` when
  `executor_fingerprint` is unchanged
- mailbox control targets logical owners plus live sessions, not persisted
  program-version rows

## Invariants

- `AgentProgram` and `AgentProgramVersion` remain separate aggregates.
- `ExecutorProgram` remains stable across version rotation for the same
  runtime carrier.
- Cross-installation references are rejected for owners, enrollments, and
  versions.
- Active session uniqueness is scoped to the logical owner (`agent_program_id`
  or `executor_program_id`), not the top-level installation.
- `AgentProgramVersion` rows are append-only historical records.
- Cross-aggregate side effects happen through service objects, not model
  callbacks.

## Failure Modes

- Personal agent programs without an owner user are invalid.
- Enrollment reuse or unknown enrollment tokens raise `InvalidEnrollment`.
- Expired enrollment tokens raise `ExpiredEnrollment`.
- Cross-installation issuance or registration raises `ArgumentError`.
- Attempting to mutate a persisted `AgentProgramVersion` raises
  `ActiveRecord::ReadOnlyRecord`.
