# Data Retention And Lifecycle Classes

## Status

This document defines lifecycle classes and retention boundaries for persisted
data in `core_matrix`.

Cleanup jobs are not implemented yet. The purpose of these classes is to make
future cleanup safe by making ownership, missing-data behavior, and retention
intent explicit now.

## Principles

### Business truth follows owner lifecycle

Canonical product state lives and dies with its owner. It is not deleted by a
time-based policy.

### Shared immutable data is reference-owned

If a row exists to deduplicate immutable content or frozen execution-visible
state, it should remain only while a durable owner still references it.

### Derived and observability data must be disposable

Diagnostics, observation, export, and similar convenience rows must be safe to
remove without corrupting product state.

### Read paths must define missing-data behavior

For every non-canonical lifecycle class, the code must answer:

- should the row be recomputed?
- should the API return expired or unavailable?
- is the absence exceptional?

### Use `kind` unless STI is required

When new categorical naming is needed, prefer `kind`.

Do not introduce `type` unless the model actually needs Rails single-table
inheritance or subclass-specific behavior.

## Lifecycle Kinds

### `owner_bound`

Canonical business truth whose lifetime follows the owning aggregate.

Deletion rule:

- delete only through owner purge or owner deletion flow

Missing-data rule:

- absence is exceptional and usually indicates corruption or an invalid caller

Representative models:

- `Conversation`
- `Turn`
- `Message`
- `ConversationImport`
- `ConversationSummarySegment`
- `ConversationEvent`
- `WorkflowRun`
- `WorkflowNode`
- `WorkflowNodeEvent`
- `ToolInvocation`
- `AgentTaskRun`
- `SubagentSession`
- `HumanInteractionRequest`

### `reference_owned`

Immutable shared content owned by explicit durable references.

Deletion rule:

- delete only when no reachable durable owner still references the row

Missing-data rule:

- absence is exceptional while a live owner still points at it

Representative models:

- `JsonDocument`

### `shared_frozen_contract`

Immutable shared contracts or snapshots that freeze execution-visible state and
may be reused by multiple owners.

Deletion rule:

- delete only when no durable owner still references the row

Missing-data rule:

- absence is exceptional while referenced by a live owner

Representative models:

- `ExecutionCapabilitySnapshot`
- `ExecutionContextSnapshot`
- `ExecutionContract`

### `recomputable`

Derived rows that can be rebuilt from canonical state.

Deletion rule:

- may be deleted at any time

Missing-data rule:

- reads must recompute or return a safe empty/default result

Representative models:

- `ConversationDiagnosticsSnapshot`
- `TurnDiagnosticsSnapshot`

### `ephemeral_observability`

Observation and export artifacts that help humans or supervisor systems inspect
runtime behavior.

Deletion rule:

- delete by TTL or explicit cleanup policy

Missing-data rule:

- reads must surface expired, unavailable, or closed instead of throwing
  internal errors

Representative models:

- `ConversationObservationSession`
- `ConversationObservationFrame`
- `ConversationObservationMessage`
- `ConversationExportRequest`
- `ConversationDebugExportRequest`

### `bounded_audit`

Detailed audit or usage events with a configurable bounded retention window.

Deletion rule:

- delete by retention policy, not by owner purge alone

Missing-data rule:

- detailed historical analysis may disappear after the retention window

Representative models:

- `UsageEvent`

### `retained_aggregate`

Aggregated reporting rows that are meant to outlive bounded raw event history.

Deletion rule:

- retain based on reporting needs rather than short raw-event retention windows

Missing-data rule:

- long-horizon reporting should depend on these rows rather than requiring raw
  detailed history forever

Representative models:

- `UsageRollup`

## Current Safety Expectations

- `owner_bound` and `shared_frozen_contract` rows are not optional while their
  live owners still reference them.
- `recomputable` rows must be safe to delete before any cleanup framework
  exists.
- `ephemeral_observability` rows must be safe to delete without affecting the
  target conversation or workflow.
- `bounded_audit` rows may eventually expire, so long-horizon reporting must
  not depend on retaining them forever.
- `reference_owned` and `shared_frozen_contract` rows should be cleaned by
  reachability or explicit reference-aware purge logic, not by blind TTL.

## Current Scope

These lifecycle kinds are declared in model code and used to shape behavior
and future cleanup work.

This document does not promise that any automatic cleanup is currently running.
It defines the rules the system must continue to satisfy when cleanup is added.
