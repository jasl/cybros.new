# Conversation Execution Epoch Redesign

**Goal:** Replace the current implicit "previous turn runtime" continuity model
with an explicit conversation-owned execution epoch model that is handoff-ready
without adding steady-state query cost to normal workbench operations.

**Architecture:** `Conversation` becomes the aggregate root for execution
continuity through a current execution epoch pointer plus current-runtime cache
fields. `Turn` and `ProcessRun` keep frozen runtime snapshot fields for cheap
historical reads, while a new `ConversationExecutionEpoch` table becomes the
durable boundary between execution epochs and future runtime handoffs.

**Tech Stack:** Rails 8.2, PostgreSQL, Active Record, Action Cable, app API,
existing workflow substrate

---

## Approved Direction

- allow destructive changes
- do not keep compatibility shims
- optimize for a clean model and low steady-state read or write overhead
- allow additive redundancy when it reduces hot-path queries

## Problems In The Current Model

The current model treats runtime continuity as an implication of turn history:

- the first turn may explicitly select a runtime
- follow-up turns inherit the previous turn runtime
- follow-up runtime changes are rejected because there is no safe continuity
  boundary

This creates three problems:

1. execution continuity is implicit rather than modeled
2. handoff would require special-case logic around prior turns instead of a
   first-class boundary
3. ordinary APIs cannot cheaply expose the current execution state of a
   conversation without re-deriving it from timeline state

## Target Model

### Conversation

`Conversation` should explicitly own current execution continuity.

Add:

- `current_execution_epoch_id`
- `current_execution_runtime_id`
- `execution_continuity_state`

`execution_continuity_state` should start narrow:

- `ready`
- `handoff_pending`
- `handoff_blocked`

The current runtime id is a cache for hot paths and list views. It is not the
historical source of truth for all runtime usage.

### ConversationExecutionEpoch

Create a new durable table:

- `conversation_id`
- `sequence`
- `execution_runtime_id` optional
- `state`
- `source_execution_epoch_id` optional
- `remote_session_ref`
- `continuity_payload`
- timestamps

This table is the durable source of truth for:

- which execution epoch a turn belongs to
- where future handoff boundaries live
- which runtime a conversation should continue with next

### Turn

`Turn` should belong to `execution_epoch`.

Keep these frozen snapshot fields on `Turn`:

- `execution_runtime_id`
- `execution_runtime_version_id`

Reason:

- transcript and diagnostics reads stay cheap
- historical execution identity remains explicit on the turn row
- future epoch joins are only needed for continuity or handoff inspection

### ProcessRun

`ProcessRun` should also belong to `execution_epoch`.

Keep `execution_runtime_id` on the row as a frozen snapshot field for the same
reason as `Turn`.

## Runtime Version Semantics

The epoch should own runtime identity, not necessarily runtime version
selection.

Recommended rule:

- epoch caches runtime id
- turn freezes the exact runtime version used for execution
- internal runtime-version refresh inside the same runtime identity does not
  require a new epoch

This keeps handoff identity stable without forcing bulk conversation cache
updates whenever a runtime connection refreshes to a newer version.

## API Redesign

### Create Conversation

Replace nested agent-scoped conversation creation with a conversation-first API:

- `POST /app_api/conversations`

Request:

- `agent_id`
- `workspace_id` optional
- `content`
- `selector` optional
- `execution_runtime_id` optional

Behavior:

- create conversation
- create initial execution epoch
- create first turn inside that epoch

### Append Message

Keep:

- `POST /app_api/conversations/:id/messages`

But change semantics:

- always use `conversation.current_execution_epoch`
- never derive continuity from previous-turn runtime

### Conversation Payloads

Conversation-facing responses should include a current execution summary:

- `current_execution_epoch_id`
- `current_execution_runtime_id`
- `execution_continuity_state`

This should come from the conversation row cache, not from joins over turn
history.

## Handoff Readiness

This redesign does not implement handoff itself, but it makes handoff a clean
future feature.

Future handoff can become:

1. mark conversation continuity state non-ready
2. create target epoch
3. switch `current_execution_epoch_id`
4. switch `current_execution_runtime_id`
5. return conversation to `ready`

That future flow becomes append-only and auditable instead of mutating timeline
meaning retroactively.

## Performance Rules

The redesign must preserve these hot-path properties:

- conversation list views should read current execution state directly from the
  conversation row
- follow-up message creation should not need to inspect previous turns
- transcript and diagnostics reads should continue using frozen turn fields
  without mandatory epoch joins

That is why redundancy on `Conversation`, `Turn`, and `ProcessRun` is
intentional.

## Schema Rewrite Shape

Because destructive change is allowed and the product is still early-stage, the
cleanest implementation is to rewrite the foundational migration history
instead of layering an additive transition migration on top.

Recommended shape:

- add `Conversation` current-execution cache fields directly to the original
  conversation-creation migration
- insert `conversation_execution_epochs` into the foundational turn-era schema
  migration set
- add `execution_epoch_id` directly to the original `turns` and `process_runs`
  creation migrations
- regenerate `db/schema.rb` from a clean database reset

This avoids:

- a one-off transition migration
- temporary compatibility logic
- historical migration noise that no longer matches the intended base model

## Acceptance Criteria

- all new conversations create an execution epoch immediately
- all follow-up turns attach to the conversation current epoch
- runtime selection no longer depends on prior-turn lookup
- app API conversation payloads expose current execution continuity explicitly
- transcript and runtime-event reads still work without heavy epoch joins
- focused tests cover epoch creation, follow-up continuity, and destructive API
  replacement
