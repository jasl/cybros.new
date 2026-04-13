# Diagnostics Deferred Recompute Design

## Goal

Move `ConversationDiagnosticsSnapshot` and `TurnDiagnosticsSnapshot` out of the
synchronous diagnostics read path so app-facing diagnostics endpoints become
cache-first and stale-tolerant, while recomputation happens asynchronously and
debug export payloads still force fresh recomputation inside their existing
background job boundary.

This design follows:

- `docs/plans/2026-04-13-conversation-bootstrap-phase-two-design.md`
- `docs/plans/2026-04-14-post-refactor-audit-and-follow-ups-design.md`

It is the concrete implementation design for follow-up `B1`.

## Why This Work Is Worth Doing

The branch already made `Conversation` / `Turn` acceptance and workflow
bootstrap substantially lighter. Diagnostics still stands out as a remaining
heavy read-side path:

- `GET /app_api/conversations/:id/diagnostics` synchronously calls
  `ConversationDiagnostics::RecomputeConversationSnapshot`
- `GET /app_api/conversations/:id/diagnostics/turns` does the same before
  listing turn snapshots
- `ConversationDebugExports::BuildPayload` also forces recompute, but that path
  already runs inside a background export job and is not app-facing hot-path

The snapshots themselves are not boundary truth. They are derived summaries over
durable facts:

- `UsageEvent`
- `WorkflowRun` / `WorkflowNode`
- `ToolInvocation`
- `CommandRun`
- `ProcessRun`
- `SubagentConnection`
- turn lifecycle and message variant state

That makes them good deferred-recompute candidates.

## Current Baseline

Today the diagnostics flow is:

1. request hits diagnostics controller
2. controller synchronously recomputes conversation snapshot
3. recompute conversation snapshot synchronously recomputes every turn snapshot
4. request responds with fresh snapshots

This has two costs:

- diagnostics reads stay heavier than they need to be
- snapshot freshness is coupled to request completion instead of background
  maintenance

## Non-Goals

This pass does not:

- redesign the diagnostics snapshot schema itself
- introduce incremental counters inside business write paths
- make supervision/feed read models stale-tolerant
- redesign debug export payload shape
- remove the diagnostics snapshot tables

## Options Considered

### Option 1: Keep synchronous recompute on read

Pros:

- no contract changes
- always fresh when the request succeeds

Cons:

- does not achieve `B1`
- keeps synchronous aggregate work in the request path
- continues coupling diagnostics freshness to app request latency

### Option 2: Cache-only diagnostics reads plus async recompute

Pros:

- removes full recompute from the app-facing request path
- keeps snapshots explicitly derived and stale-tolerant
- avoids broad write-path hooks in the first pass
- keeps debug export fresh by recomputing in its existing background job

Cons:

- diagnostics endpoints must admit `pending` / `stale`
- freshness becomes eventual instead of immediate

### Option 3: Incremental snapshot maintenance on every fact write

Pros:

- potentially freshest cache
- no pending/stale contract in the steady state

Cons:

- much larger change surface
- pushes derived-summary responsibility back into many write paths
- too expensive for the current branch objective

## Recommendation

Choose **Option 2**.

Diagnostics should become a cache-first surface:

- app-facing diagnostics endpoints only read persisted snapshots
- if snapshots are missing or stale, the request returns a truthful
  `pending` / `stale` status and enqueues background recompute
- debug export continues to force recompute inside its export job, because that
  work is already asynchronous and should prefer freshness over latency

## Proposed Read Contract

### Conversation diagnostics show

`GET /app_api/conversations/:id/diagnostics` should:

- load the persisted `ConversationDiagnosticsSnapshot`
- determine diagnostics freshness status
- enqueue recompute when needed
- respond immediately with cached data

Top-level response should include:

- `diagnostics_status`
  - `ready`
  - `stale`
  - `pending`
- `snapshot`
  - full payload when a conversation snapshot exists
  - `null` when no snapshot exists yet

### Turn diagnostics list

`GET /app_api/conversations/:id/diagnostics/turns` should:

- load persisted `TurnDiagnosticsSnapshot` rows for the conversation
- use the same top-level diagnostics status as the conversation read
- enqueue recompute when needed
- respond immediately with cached rows

Top-level response should include:

- `diagnostics_status`
- `items`
  - ordered turn snapshots when present
  - `[]` when no turn snapshots exist yet

This first pass does **not** add per-turn freshness state. Freshness is
conversation-scoped.

## Freshness Rules

We need stale detection that is cheaper than recomputing every snapshot but
still aligned with the facts that snapshots summarize.

### Status rules

- `pending`
  - no conversation snapshot exists
  - or no turn snapshots exist for a conversation that already has turns
- `stale`
  - snapshot exists, but relevant source facts are newer than
    `conversation_diagnostics_snapshots.updated_at`
- `ready`
  - snapshot exists and no newer source facts are detected

### Freshness probe

Introduce a lightweight freshness probe service that computes a source
watermark from indexed `MAX(...)` queries over conversation-scoped facts, for
example:

- `turns.updated_at`
- `usage_events.occurred_at`
- `workflow_runs.updated_at`
- `agent_task_runs.updated_at`
- `tool_invocations.updated_at`
- `command_runs.updated_at`
- `process_runs.updated_at`
- `subagent_connections.updated_at`

This is still materially cheaper than recomputing every turn snapshot plus the
conversation rollup in request time.

The first pass does **not** try to make freshness detection perfect via dirty
flags or event counters. It only needs to be directionally correct and
substantially lighter than synchronous recompute.

## Background Recompute

Add a conversation-scoped recompute job:

- `ConversationDiagnostics::RecomputeConversationSnapshotJob`

Responsibilities:

- load the conversation
- recompute all turn snapshots
- recompute the conversation snapshot

The app-facing diagnostics controller should enqueue this job when status is
`pending` or `stale`.

This first pass does not need:

- a separate turn-only recompute job
- deduplicated queue rows
- persistent recompute failure state

Those can be added later if diagnostics traffic justifies it.

## Debug Export Behavior

`ConversationDebugExports::BuildPayload` should remain freshness-first:

- explicitly recompute diagnostics inside the export job
- then serialize the fresh snapshots

This preserves export quality without keeping recompute in synchronous app API
reads.

## API Semantics

This change intentionally makes diagnostics a stale-tolerant surface.

That means:

- missing snapshots are not an application error
- stale snapshots are still valid to return
- the contract becomes “best persisted diagnostics plus freshness status”
  instead of “always recompute now”

That is acceptable because diagnostics is an observability surface, not boundary
truth required to accept or execute user work.

## Testing Strategy

Tests should lock these contracts:

1. diagnostics requests no longer synchronously create snapshots
2. missing snapshots return `pending`
3. stale snapshots return cached payload plus `stale`
4. read miss/stale enqueues background recompute
5. background recompute creates both turn and conversation snapshots
6. debug export still forces fresh recompute before serialization

## Out Of Scope Follow-Ups

Possible later work if B1 lands well:

- add dirty markers to reduce freshness probes further
- add recompute deduplication or backlog recovery
- introduce per-turn freshness state
- move supervision/feed projections toward the same stale-tolerant cache model
