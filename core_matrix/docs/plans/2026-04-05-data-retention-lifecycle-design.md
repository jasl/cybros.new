# Data Retention And Lifecycle Design

## Goal

Define durable lifecycle classes for `core_matrix` data so business records,
shared frozen contracts, derived diagnostics, observation artifacts, and usage
history each have explicit retention semantics.

This design does not implement cleanup jobs yet. It establishes safety rules,
ownership boundaries, and read-path behavior so future deletion of derived or
time-bounded data cannot corrupt product state or break the system.

## Why This Exists

The payload normalization refactor clarified data ownership, but it also made a
second concern more visible: not all persisted rows deserve the same lifetime.

Right now the codebase mixes together:

- business truth that must live with the owning conversation or workflow
- shared frozen snapshots that should exist only while referenced
- diagnostics and observation rows that are useful but disposable
- usage facts that are valuable for audit and cost analysis, but not forever

If those categories are not modeled explicitly, future cleanup work becomes
dangerous:

- accidental deletion of business truth
- foreign-key failures when owner rows are purged
- APIs that crash when derived rows disappear
- pressure to keep every detail forever because "we might need it"

The system needs a stronger rule than "some tables feel temporary."

## Design Principles

### 1. Business truth follows owner lifecycle

If a row is canonical product state, it lives and dies with its owner. It is
not deleted by TTL.

Examples:

- conversations and turns
- transcript-bearing messages
- workflow runs and workflow nodes
- tool invocations and human interactions
- conversation imports and summary segments

### 2. Shared documents and frozen contracts are reference-owned

If a row exists to deduplicate shared immutable content, it should be deleted
only when no durable owner references it.

Examples:

- `JsonDocument`
- execution capability snapshots
- execution context snapshots
- execution contracts

### 3. Derived and presentation rows must be disposable

Diagnostics, observation, export, and similar presentation-focused rows must be
designed so deleting them does not damage business data.

Deletion may reduce convenience or observability, but it must not:

- corrupt transcript state
- corrupt workflow state
- break foreign keys for canonical owners
- raise internal errors on ordinary reads

### 4. Read paths must declare missing-data behavior

Every non-canonical lifecycle class must have an explicit answer to:

- what happens if this row is gone?
- should the system recompute it?
- should the API return expired/unavailable?
- should the absence be invisible to the caller?

### 5. Kind beats type unless STI is required

For new categorical fields, use `kind` when the model does not need Rails
single-table inheritance or per-subclass behavior. Do not overload `type`
without an actual STI need.

### 6. Future cleanup jobs must rely on lifecycle classes, not folklore

Retention policies must be driven by explicit lifecycle classes and owner/ref
rules, not by one-off table-specific intuition.

## Lifecycle Classes

The system should recognize the following lifecycle classes.

### `owner_bound`

Canonical business truth. Lifetime follows the owning product aggregate.

Deletion rule:

- only deleted through owner purge or owner deletion flow

Read-path rule:

- absence is exceptional and usually indicates corruption or an invalid caller

Examples:

- `Conversation`
- `Turn`
- `Message`
- `ConversationImport`
- `ConversationSummarySegment`
- `WorkflowRun`
- `WorkflowNode`
- `WorkflowNodeEvent`
- `ConversationEvent`
- `ToolInvocation`
- `AgentTaskRun`
- `SubagentSession`
- `HumanInteractionRequest`

### `reference_owned`

Immutable shared content with explicit durable references.

Deletion rule:

- delete only when no reachable owner references remain

Read-path rule:

- absence is exceptional if a live owner still points at it

Examples:

- `JsonDocument`

### `shared_frozen_contract`

Shared immutable contracts or snapshots that freeze execution-visible state and
can be reused across multiple owners.

Deletion rule:

- delete only when no durable owner references remain

Read-path rule:

- absence is exceptional if referenced by a live owner

Examples:

- `ExecutionCapabilitySnapshot`
- `ExecutionContextSnapshot`
- `ExecutionContract`

### `recomputable`

Derived rows that can be rebuilt from canonical state.

Deletion rule:

- may be deleted at any time

Read-path rule:

- missing rows must trigger recomputation or a safe empty/default result

Examples:

- `ConversationDiagnosticsSnapshot`
- `TurnDiagnosticsSnapshot`

### `ephemeral_observability`

Observation and export artifacts that exist to help humans or supervising
systems inspect runtime behavior.

Deletion rule:

- delete by TTL or explicit cleanup policy

Read-path rule:

- absence should surface as expired/unavailable/closed, not an internal error

Examples:

- `ConversationObservationSession`
- `ConversationObservationFrame`
- `ConversationObservationMessage`
- `ConversationExportRequest`
- `ConversationDebugExportRequest`

### `bounded_audit`

Raw detailed audit or usage events with a bounded retention period.

Deletion rule:

- delete by configurable retention window

Read-path rule:

- short-horizon detailed analysis may disappear after the retention window

Examples:

- `UsageEvent`

### `retained_aggregate`

Aggregated reporting rows intended to outlive the raw detailed events they are
derived from.

Deletion rule:

- retained by product reporting needs, not by short raw-event TTL

Read-path rule:

- long-horizon reporting should depend on these rows rather than requiring raw
  event history forever

Examples:

- `UsageRollup`

## Model Classification Matrix

### Conversation and workflow domain

- `Conversation`: `owner_bound`
- `Turn`: `owner_bound`
- `Message`: `owner_bound`
- `ConversationImport`: `owner_bound`
- `ConversationSummarySegment`: `owner_bound`
- `ConversationEvent`: `owner_bound`
- `WorkflowRun`: `owner_bound`
- `WorkflowNode`: `owner_bound`
- `WorkflowNodeEvent`: `owner_bound`
- `ToolInvocation`: `owner_bound`
- `AgentTaskRun`: `owner_bound`
- `SubagentSession`: `owner_bound`
- `HumanInteractionRequest`: `owner_bound`

### Normalized payload and contract domain

- `JsonDocument`: `reference_owned`
- `ExecutionCapabilitySnapshot`: `shared_frozen_contract`
- `ExecutionContextSnapshot`: `shared_frozen_contract`
- `ExecutionContract`: `shared_frozen_contract`

### Diagnostics and observation domain

- `ConversationDiagnosticsSnapshot`: `recomputable`
- `TurnDiagnosticsSnapshot`: `recomputable`
- `ConversationObservationSession`: `ephemeral_observability`
- `ConversationObservationFrame`: `ephemeral_observability`
- `ConversationObservationMessage`: `ephemeral_observability`
- `ConversationExportRequest`: `ephemeral_observability`
- `ConversationDebugExportRequest`: `ephemeral_observability`

### Usage and reporting domain

- `UsageEvent`: `bounded_audit`
- `UsageRollup`: `retained_aggregate`

## Read-Path Requirements

### Diagnostics

Diagnostics endpoints must not require snapshots to preexist.

If diagnostics rows are missing:

- recompute conversation diagnostics on demand
- recompute turn diagnostics on demand or return a regenerated collection
- never treat absence as corruption

The current diagnostics controller already points in this direction by calling
recompute services before reading snapshot rows.

### Observation

Observation data is allowed to disappear without affecting the target
conversation.

If observation data is missing:

- a missing observation session returns not found, closed, or expired
- a missing historical observation frame or message does not block a new
  observation session
- target conversation reads remain unaffected

### Export and debug export requests

Request rows and attached bundle files are not business truth.

If an export artifact is gone:

- the API should report expired or unavailable
- it must not raise an internal error
- the user may request a new export

### Usage reporting

Usage reads must separate detail from long-horizon reporting:

- detailed raw-event inspection reads `UsageEvent`
- hourly/daily/window reporting reads `UsageRollup`

This preserves the ability to expire raw usage events after a bounded period
while keeping longer trend views intact.

## Reference Management Strategy

### Use explicit references as the source of truth

Deletion safety should be driven by real foreign keys and reachable-owner scans,
not by a mutable counter that can drift.

This is already the right direction for:

- `JsonDocument`
- execution contracts
- execution capability snapshots
- execution context snapshots

### Allow reference counts only as cache-like optimizations

If the system later adds `reference_count`-style fields, they must be treated as
performance hints only. They must not become the sole correctness source for
deletion.

### Keep categorical fields named `kind`

If a model needs a lifecycle or content category and does not rely on STI, use
`kind` rather than `type`.

## Usage Data Strategy

The repository already has a useful split:

- `UsageEvent` for detailed durable facts
- `UsageRollup` for aggregated reporting

This design keeps that split but changes the retention interpretation:

- `UsageEvent` becomes bounded detailed history
- `UsageRollup` becomes the long-lived reporting layer

Default retention expectation:

- keep `UsageEvent` for at least 30 days
- allow the retention window to be installation-configurable later

This design intentionally does not generalize `UsageRollup` into a global event
aggregation framework yet. The current provider-usage domain is sufficient and
should be modularized only within its own boundary for now.

## Safety Constraints For Future Cleanup

Any future cleanup implementation must obey these constraints:

1. deleting `recomputable` rows must not break any normal product flow
2. deleting `ephemeral_observability` rows must not affect target conversations
3. deleting `bounded_audit` rows must not break rollup-backed long-term reports
4. deleting `reference_owned` or `shared_frozen_contract` rows must depend on
   real reachability, not time
5. owner purge must recognize derived rows explicitly so foreign keys do not
   block deletion

## Required Code Changes Before Cleanup Jobs Exist

This design does not require cleanup jobs yet, but it does require code-level
semantic hardening:

- models should declare a static lifecycle class
- read paths should support missing derived rows gracefully
- tests should assert that deleting diagnostics or observation rows does not
  damage canonical behavior
- purge logic should eventually enumerate observation and diagnostics rows as
  derived dependents rather than letting them remain implicit

## Out Of Scope

This design intentionally does not include:

- retention schedulers
- TTL jobs
- hard deletion of `UsageEvent`
- archive/cold-tier storage
- compression strategies
- a global generalized rollup framework

Those can be added later once lifecycle semantics are enforced and validated.
