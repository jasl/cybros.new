# Supervision Feed Todo Projection-First Design

## Goal

Remove synchronous supervision refresh from the app-facing feed and todo-plan
read paths so those endpoints become projection-first and stale-tolerant.

## Scope

This follow-up is intentionally narrow.

It only changes:

- `GET /app_api/conversations/:id/feed`
- `GET /app_api/conversations/:id/todo_plan`
- the supporting feed/todo projection readers they call

It does **not** change:

- board/list supervision APIs
- the `ConversationSupervisionState` write/update pipeline
- the runtime/report paths that currently call
  `Conversations::UpdateSupervisionState`
- the eventing model for feed entry publication

## Current Problem

The branch already moved accepted-turn truth and workflow bootstrap substrate
out of the synchronous hot path, but two app-facing read endpoints still force
runtime work back into the request:

- `AppAPI::Conversations::FeedsController#show`
- `AppAPI::Conversations::TodoPlansController#show`

Both currently call `Conversations::UpdateSupervisionState` synchronously before
reading projections.

That has two problems:

1. it makes read requests do heavyweight mixed-query recomputation again
2. it weakens the new design boundary by treating read endpoints as implicit
   repair points

If projections are stale or absent, the request should reflect that current
persisted truth, not silently repair it.

## Desired Contract

After this change:

- feed and todo-plan endpoints are **projection-first**
- they do **not** synchronously call `Conversations::UpdateSupervisionState`
- they return persisted feed / persisted todo information when present
- they may return empty or slightly stale results when projections have not yet
  caught up

This is an explicit product tradeoff. For these two endpoints:

- stale is acceptable
- empty is acceptable
- synchronous repair is not

## Recommended Approach

### 1. Remove synchronous supervision refresh from the controllers

`FeedsController#show` and `TodoPlansController#show` should stop calling
`Conversations::UpdateSupervisionState`.

The request boundary becomes:

- resolve conversation
- read persisted projections
- render response

### 2. Make `BuildActivityFeed` anchor-only

`ConversationSupervision::BuildActivityFeed` currently falls back to scanning
`turns` when anchors are absent:

- `latest_active_turn_id`
- `latest_turn_id`
- then base-table `turns` scans

That last fallback undermines the projection-first contract.

After this change, `BuildActivityFeed` should only trust persisted anchors:

- prefer `latest_active_turn_id`
- otherwise `latest_turn_id`
- otherwise return `[]`

If anchors are missing, that is treated as a valid empty read, not a reason to
scan turns.

### 3. Make `BuildCurrentTurnTodo` state-first

`ConversationSupervision::BuildCurrentTurnTodo` currently queries active
`AgentTaskRun` rows directly to decide which persisted `TurnTodoPlan` to show.

For the app-facing todo-plan endpoint, that is too close to runtime truth.

After this change, todo-plan selection should prefer persisted supervision
projection:

- inspect `conversation.conversation_supervision_state`
- only consider the current owner if `current_owner_kind == "agent_task_run"`
- load that persisted task run by `current_owner_public_id`
- return its persisted `TurnTodoPlan` if it exists
- otherwise return the existing empty projection

This keeps the endpoint aligned with already-published supervision state instead
of re-deriving “current” work directly from runtime tables.

### 4. Preserve current pending-turn behavior

The branch already has `Conversations::ProjectTurnBootstrapState`.

That means a freshly accepted pending turn can still surface as:

- queued supervision state
- empty feed
- no primary todo plan

without any synchronous `UpdateSupervisionState` call in the request.

This behavior should remain intact.

## Alternatives Considered

### A. Minimal controller-only removal

Only delete the controller calls to `UpdateSupervisionState`.

Rejected because:

- feed would still silently fall back to `turns` scans
- todo-plan would still query active task runs directly
- the endpoints would be lighter, but not truly projection-first

### B. Add explicit projection freshness status

Return a new `projection_status` field and maybe enqueue async refresh.

Rejected for this pass because:

- it adds contract surface
- it introduces another stale/miss state machine
- the product can already tolerate empty/stale results here

## Risks

### Temporary emptiness becomes user-visible

If anchors or supervision state lag, feed/todo responses may be empty longer
than before.

That is acceptable only because the product decision here is explicit:

- these endpoints are read projections
- they are not repair endpoints

### Existing tests may assume implicit repair

Some request and service tests were written against the old contract where a
read implicitly refreshed supervision state.

The implementation needs to rewrite those tests so they assert the new
projection-first semantics directly.

## Testing Strategy

The implementation should lock three kinds of behavior:

1. request endpoints no longer call synchronous supervision refresh
2. feed/todo readers return persisted projections when present
3. feed/todo readers return empty results, not runtime-derived fallbacks, when
   projections or anchors are missing

Specific regression coverage should include:

- pending turn remains queued while feed is empty
- pending turn returns no todo plan
- missing anchors no longer trigger turn scans
- provider-backed work still does not invent semantic todo/feed fallbacks

## Success Criteria

This follow-up is successful when:

- `FeedsController` and `TodoPlansController` no longer call
  `Conversations::UpdateSupervisionState`
- `BuildActivityFeed` no longer scans `turns` when anchors are absent
- `BuildCurrentTurnTodo` no longer derives the current task by scanning active
  task runs for the app-facing path
- the request suites stay green with the new stale/empty semantics
- the hot read paths get measurably lighter in SQL/query count
