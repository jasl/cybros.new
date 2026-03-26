# Agent Registry And Connectivity Foundations

## Purpose

Task 03 establishes the machine-facing registry substrate for Core Matrix:
logical agent installations, execution environments, one-time enrollment
tokens, concrete deployments, capability snapshots, and heartbeat state.

## Status

This document records the current landed connectivity substrate.

Phase 2 now extends that substrate with mailbox-first control delivery,
`poll + WebSocket + piggyback` transport parity, and distinct realtime-link
versus control-activity facts. This document remains the source of truth for
the registration and deployment aggregates underneath that control plane.

Planned replacement design:

- [2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md)

## Aggregate Responsibilities

### AgentInstallation

- `AgentInstallation` is the stable logical identity of an agent program inside
  one installation.
- Visibility is `personal` or `global`.
- Personal agent installations require an owner user from the same
  installation.
- Lifecycle state is tracked separately from runtime health.

### ExecutionEnvironment

- `ExecutionEnvironment` models the runtime target for deployments.
- Kind is `local`, `container`, or `remote`.
- Connection details live in `connection_metadata`.
- Lifecycle state tracks whether the environment is still available for new
  deployments.

### AgentEnrollment

- Enrollment tokens are one-time and expiring.
- Enrollment token digests are stored, not plaintext tokens.
- Consuming an enrollment sets `consumed_at`.

### AgentDeployment

- `AgentDeployment` is the concrete runtime row for one `AgentInstallation`.
- Machine credentials are stored as digests, not plaintext bearer secrets.
- Bootstrap state starts at `pending` and moves to `active` on the first
  healthy heartbeat.
- Health state and heartbeat timestamps are tracked independently of bootstrap
  state.
- realtime session presence is tracked separately through
  `realtime_link_state`
- durable control-plane freshness is tracked separately through
  `control_activity_state` and `last_control_activity_at`
- Only one `active` deployment may exist for a given `AgentInstallation`.

### CapabilitySnapshot

- Capability snapshots belong to one deployment.
- Snapshots version protocol methods, tool catalog, and configuration schemas.
- Snapshots are immutable after creation.
- The deployment points to its active capability snapshot explicitly.

## Services

### `AgentEnrollments::Issue`

- Mints a one-time enrollment token for an agent installation.
- Requires the issuing actor to belong to the same installation.
- Writes the `agent_enrollment.issued` audit row.

### `AgentDeployments::Register`

- Resolves an enrollment token by digest lookup.
- Rejects invalid, consumed, or expired tokens.
- Creates a pending deployment plus its first capability snapshot in one
  transaction.
- Exchanges the one-time enrollment token for a durable machine credential.
- Writes the `agent_deployment.registered` audit row.

### `AgentDeployments::RecordHeartbeat`

- Updates deployment health metadata and heartbeat timestamps.
- Rotates a pending deployment to `active` on the first healthy heartbeat.
- Preserves deployment identity and capability snapshot history while health
  changes over time.

## Invariants

- `AgentInstallation` and `AgentDeployment` remain separate aggregates.
- Cross-installation references are rejected for owners, enrollments, and
  deployments.
- Active deployment uniqueness is scoped to `agent_installation_id`, not the
  top-level installation.
- Capability snapshots are append-only historical records.
- Cross-aggregate side effects happen through service objects, not model
  callbacks.

## Failure Modes

- Personal agent installations without an owner user are invalid.
- Enrollment reuse or unknown enrollment tokens raise `InvalidEnrollment`.
- Expired enrollment tokens raise `ExpiredEnrollment`.
- Cross-installation issuance or registration raises `ArgumentError`.
- Attempting to mutate a persisted capability snapshot raises
  `ActiveRecord::ReadOnlyRecord`.
