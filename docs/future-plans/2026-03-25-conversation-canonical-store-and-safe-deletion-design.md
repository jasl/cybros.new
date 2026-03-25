# Conversation Canonical Store And Safe Deletion Design

## Purpose

This design splits one broad concern into two explicit tasks:

1. build a scalable conversation-local canonical store for agent-facing state
2. support safe conversation deletion without dangling work, references, or
   shared-store corruption

The goal is to make both tasks executable end-to-end with minimal product or
implementation ambiguity.

## Scope

### In Scope

- conversation-local canonical store for agent-facing key/value state
- branch and checkpoint snapshot behavior for that store
- Redis-like read and write semantics for conversation-local state
- size limits and query-discipline rules driven by PostgreSQL behavior
- safe deletion for conversations, including unfinished turns and workflow runs
- garbage collection for unreachable store snapshots, entries, and values
- destructive rewrite of the current conversation-scoped canonical-variable
  schema and runtime paths
- a test matrix covering edge cases, extreme cases, and performance traps

### Out Of Scope

- redesign of workspace-scoped canonical variables
- arbitrary point-in-time replay of store state for any historical turn
- transcript compaction or transcript lineage redesign
- product decisions about when UI should prefer archive versus delete
- non-conversation store scopes such as per-user or per-agent state

## Fixed Product And Technical Decisions

The following decisions are locked for implementation:

- branch and checkpoint use frozen snapshots
- parent writes after branch creation must not affect the child snapshot
- deletion is logical first and physical later
- the store is get-heavy, but list and mget must remain efficient enough for
  production use
- values may be a mix of small and large payloads
- blank or low-value conversations may use delete rather than archive, but that
  decision stays in product logic above the deletion service boundary
- key length is capped at 128 bytes
- value payload size is capped at 2 MiB
- list-style reads must not load all values by default
- implementation must avoid N+1 queries
- destructive refactor is allowed for this rollout
- existing migrations may be rewritten directly for schema purity
- development and test databases must be reset after schema-history edits
- no compatibility aliases, dual writes, or backfills are allowed
- implementation must finish with behavior docs, plan docs, and code in sync
- implementation must remove dead code, dead tests, dead routes, and stale docs
  created by the refactor

## Current Baseline

The existing system already defines several important constraints:

- conversation-local canonical values are currently modeled through
  `CanonicalVariable` rows with append-only history and a `current` flag
- branch transcript behavior already prefers by-reference inheritance rather
  than eager row copying
- a conversation may have queued or active turns
- a conversation may have an active workflow run or a waiting workflow run

Relevant current files:

- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/canonical_variable.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/conversation.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/turn.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/workflow_run.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/create_branch.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/queries/conversation_variables/resolve_query.rb`

## Recommended Architecture

### Design Summary

Use an immutable snapshot chain for conversation-local canonical state.
Conversations do not own the store data directly. They own a reference to the
current visible snapshot inside a lineage-local store. Branching copies only the
snapshot reference. Writing creates a new snapshot on top of the current one.

Use a separate conversation deletion state machine. Deletion first hides and
quiesces a conversation, then releases store references, then runs asynchronous
garbage collection. Physical deletion happens only when dependencies permit it.

### Boundary Decisions

- workspace-scoped canonical variables remain on the existing
  `CanonicalVariable` model, but that model is rewritten to be workspace-only
- conversation-local canonical state moves to new tables and services
- `conversation_variables_resolve` continues to merge:
  conversation-local store state over workspace-scoped canonical variables
- promotion to workspace keeps writing through the workspace
  `CanonicalVariable` path
- no deprecated conversation-scope compatibility path survives the rollout

## Data Model

### `CanonicalStore`

Represents one lineage-local store namespace.

Required columns:

- `installation_id`
- `workspace_id`
- `root_conversation_id`
- timestamps

Rules:

- one root conversation gets one canonical store
- branch, checkpoint, and thread descendants reuse the same canonical store
- the store row is deleted only after all snapshots and references are gone

### `CanonicalStoreSnapshot`

Represents one immutable visible-state boundary.

Required columns:

- `canonical_store_id`
- `base_snapshot_id`
- `depth`
- `snapshot_kind`
- timestamps

`snapshot_kind` values:

- `root`
- `write`
- `compaction`

Rules:

- root conversations start with one empty `root` snapshot
- every write batch creates one new `write` snapshot
- compaction creates one new `compaction` snapshot
- snapshots are immutable after insert
- `depth = 0` for `root` and `compaction` snapshots
- `root` and `compaction` snapshots must have no base snapshot
- `write` snapshots must have a base snapshot
- `depth = base.depth + 1` for `write` snapshots

### `CanonicalStoreEntry`

Represents one key mutation inside one snapshot.

Required columns:

- `canonical_store_snapshot_id`
- `key`
- `entry_kind`
- `canonical_store_value_id`
- `value_type`
- `value_bytesize`
- timestamps

`entry_kind` values:

- `set`
- `tombstone`

Rules:

- one snapshot may contain at most one entry per key
- `tombstone` entries must not point to a value row
- `set` entries must point to a value row
- `value_bytesize` is copied from the value row for query planning and
  list-metadata responses
- enforce uniqueness on `[:canonical_store_snapshot_id, :key]`

### `CanonicalStoreValue`

Stores the durable value payload.

Required columns:

- `typed_value_payload`
- `payload_sha256`
- `payload_bytesize`
- timestamps

Rules:

- `payload_bytesize` is the UTF-8 JSON-encoded payload byte size
- `payload_bytesize <= 2_097_152`
- duplicate values may reuse the same value row when both digest and payload
  match
- hash collision checks must compare payload content before reuse

### `CanonicalStoreReference`

Represents a live root for reachability and GC.

Required columns:

- `canonical_store_snapshot_id`
- `owner_type`
- `owner_id`
- timestamps

Rules:

- use a polymorphic owner so future non-conversation roots can reuse the same
  mechanism
- a live conversation owns exactly one active store reference
- branch and checkpoint creation create a new reference to the current parent
  snapshot instead of copying data
- enforce uniqueness on `[:owner_type, :owner_id]`

### Conversation Deletion Fields

Add to `Conversation`:

- `deletion_state`
- `deleted_at`

`deletion_state` values:

- `retained`
- `pending_delete`
- `deleted`

Add to `Turn`:

- `cancellation_requested_at`
- `cancellation_reason_kind`

Add to `WorkflowRun`:

- `cancellation_requested_at`
- `cancellation_reason_kind`

`cancellation_reason_kind` must support:

- `conversation_deleted`

## Storage Guardrails

### Key Rules

- keys are stored as case-sensitive UTF-8 strings
- keys must satisfy `1 <= octet_length(key) <= 128`
- enforce the limit in both Rails validation and a database check constraint
- do not normalize or case-fold keys implicitly

### Value Rules

- values are persisted as typed JSON payloads
- the encoded payload byte size must satisfy
  `0 <= payload_bytesize <= 2_097_152`
- reject oversized writes with a validation error
- do not truncate, compress, or spill oversized payloads automatically

## Query Contract

### Public Runtime Methods

Conversation-local runtime methods are:

- `conversation_variables_get`
- `conversation_variables_mget`
- `conversation_variables_set`
- `conversation_variables_delete`
- `conversation_variables_exists`
- `conversation_variables_list_keys`
- `conversation_variables_resolve`
- `conversation_variables_promote`

Notes:

- replace the current `conversation_variables_write` name with
  `conversation_variables_set`
- replace value-heavy `conversation_variables_list` with key-oriented
  `conversation_variables_list_keys`
- callers that need values for many keys must use `mget`
- `resolve` continues to merge workspace values under conversation-local values
- do not keep compatibility aliases for legacy method names

### Query Discipline

- `get` may load at most one value row
- `mget` must batch-resolve entries and batch-load values
- `list_keys` must never load `CanonicalStoreValue` rows
- no list-style endpoint may return raw payloads by default
- any code path that needs a set of values must do:
  1. resolve entries in batch
  2. load values in one additional batch query
- do not call `.includes(:value).to_a` on list-style query paths
- do not expose a full-store value dump endpoint in this task

### PostgreSQL-Oriented Performance Targets

- branch creation must copy zero keys and zero values
- `get` must use bounded snapshot traversal and no N+1 behavior
- `mget` must resolve all requested keys without per-key queries
- `list_keys` must read only entry metadata columns and paginate
- value payload columns must stay out of `list_keys` selects

## Snapshot And COW Semantics

### Root Conversation Creation

- create `CanonicalStore`
- create one empty root snapshot
- create one `CanonicalStoreReference` from the conversation to that snapshot

### Branch, Checkpoint, Or Thread Creation

- create the child conversation as usual
- create a new `CanonicalStoreReference` for the child conversation
- point it at the current parent snapshot
- do not create a new snapshot
- do not copy any keys
- do not copy any values

### Set

For one logical set operation:

1. resolve the conversation's current snapshot reference
2. if snapshot depth is at least 32, compact first
3. find or create a deduplicated `CanonicalStoreValue`
4. create one new `write` snapshot whose base points at the current snapshot
5. create one `set` entry inside that new snapshot
6. move the conversation's reference to the new snapshot

Optimization rule:

- if the current visible value for the key is byte-for-byte identical to the
  requested payload, the set is a no-op and must not create a new snapshot

### Delete Key

For one logical delete operation:

1. resolve the conversation's current snapshot reference
2. if snapshot depth is at least 32, compact first
3. create one new `write` snapshot whose base points at the current snapshot
4. create one `tombstone` entry inside that new snapshot
5. move the conversation's reference to the new snapshot

Optimization rule:

- if the key is already missing in the current visible state, delete is a no-op
  and must not create a new snapshot

### Get Resolution

- resolve through the current snapshot chain, newest first
- stop at the first matching key
- if the first hit is `tombstone`, return missing
- otherwise load the single referenced value row
- implement traversal with one recursive CTE or equivalent bounded SQL query

### Multi-Get Resolution

- resolve all requested keys through one bounded recursive query
- collapse to the newest hit per key
- batch-load the matching value rows in one follow-up query
- preserve request-key order in the response

### List Keys Resolution

- traverse snapshots through one bounded recursive query
- select only key, entry kind, value type, value byte size, and timestamps
- collapse to the newest visible row per key
- filter out tombstoned keys
- paginate by stable key order

### Compaction

Compaction is required to bound traversal depth.

Rules:

- max snapshot depth is 32
- if a write would target depth 32 or deeper, compact first
- compaction creates one `compaction` snapshot containing the fully visible key
  set at that point
- the new compaction snapshot becomes a fresh chain root with `depth = 0`
- compaction copies entries, not value payloads
- compaction must preserve exact visible semantics for `get`, `mget`, and
  `list_keys`

## Conversation Safe Deletion

### Service Boundaries

Required services:

- `Conversations::RequestDeletion`
- `Conversations::FinalizeDeletion`
- `Conversations::PurgeDeleted`
- `Conversations::QuiesceActiveWork`
- `CanonicalStores::GarbageCollect`

### `Conversations::RequestDeletion`

This service must:

- set `deletion_state = pending_delete`
- set `deleted_at`
- hide the conversation from default UI queries immediately
- reject future turn entry
- reject future branch, checkpoint, and thread creation
- reject future conversation-local store writes
- reject future recovery or resume actions for current work
- revoke live publications and hide deleted conversations from default
  agent-facing lookups immediately
- cancel queued turns immediately
- request cancellation for active turns and active workflow runs
- cancel open human interaction requests so no deleted conversation stays
  user-visible through the inbox

The service must be idempotent.

It uses `Conversations::QuiesceActiveWork` with
`reason_kind = conversation_deleted`.

### Behavior For Unfinished Work

- queued turns move directly to `canceled`
- active turns and workflow runs are stamped with
  `cancellation_requested_at` and
  `cancellation_reason_kind = conversation_deleted`
- active turns remain present until their workflow run reaches a terminal state
- workflow runs with `wait_state = waiting` must not resume after deletion is
  requested
- waiting workflows blocked on human interaction must cancel the blocking
  request and then transition to `canceled`
- waiting workflows blocked on any other reason must not resume and must move
  toward `canceled` through the same cancellation-request path
- active execution leases, subagent runs, and process runs must be released or
  terminated before final deletion
- once active leases, processes, and subagents have been quiesced, the
  workflow run and owning turn may move directly to `canceled`

### `Conversations::FinalizeDeletion`

This service may proceed only when all of the following are true:

- no queued turns remain
- no active turns remain
- no active workflow runs remain
- no active execution leases remain
- no open human interaction remains
- no active subagent or process execution remains

If any of those conditions are still false, the landed implementation raises
`ActiveRecord::RecordInvalid` instead of silently finalizing partial state.

Then it must:

- remove the conversation's `CanonicalStoreReference`
- transition the conversation to `deletion_state = deleted`
- enqueue `CanonicalStores::GarbageCollect`

### `Conversations::PurgeDeleted`

This service performs the final physical cleanup once both of the following are
true:

- the conversation is already in `deletion_state = deleted`
- no descendant, transcript-lineage, or other durable dependency still requires
  the conversation row as a tombstone shell

Then it must:

- delete the tombstone-shell conversation row
- delete any support rows that are now unreferenced solely because the shell is
  no longer needed

Additional landed guard:

- `PurgeDeleted` rejects corrupted `deleted` states that still have active
  runtime work or a live `CanonicalStoreReference`
- `PurgeDeleted(force: true)` may first quiesce the deleted conversation's own
  runtime work with `conversation_deleted` reasons
- `PurgeDeleted(force: true)` still requires prior finalization; it must not
  remove the live `CanonicalStoreReference` on behalf of the caller
- deleting a parent conversation does not cascade deletion into retained child
  conversations
- descendant lineage keeps the deleted ancestor as a tombstone shell until the
  child lineage no longer depends on it

### Archive And Turn-Entry State Rules

These rules stay on the retained-lifecycle axis and are intentionally separate
from safe deletion.

- `Conversations::Archive` may proceed only when:
  - `deletion_state = retained`
  - `lifecycle_state = active`
  - no queued turns remain
  - no active turns remain
  - no active workflow runs remain
  - no active execution leases remain
  - no open human interaction remains
  - no active subagent or process execution remains
- `Conversations::Archive(force: true)` may first quiesce the conversation's
  own queued or active runtime work using
  `reason_kind = conversation_archived`, then apply the same archive
  transition
- archived conversations are excluded from open human-interaction inbox queries
- archived conversations reject opening new human interactions and reject late
  resolution of still-open requests
- human-interaction open and resolution paths must re-check lifecycle state
  from fresh locked conversation/workflow/request rows so stale objects cannot
  create or resolve requests after archive/delete wins the race
- `Conversations::Unarchive` may proceed only when:
  - `deletion_state = retained`
  - `lifecycle_state = archived`
- archiving a parent does not archive children automatically
- `Conversation#active_turn_exists?(include_descendants: false)` is the
  supported runtime-inspection query for local or descendant-aware active-turn
  checks
- turn-entry services (`StartUserTurn`, `StartAutomationTurn`,
  `QueueFollowUp`) must re-check lifecycle and deletion state after acquiring
  the conversation row lock so a concurrent archive or delete transition cannot
  slip in a new turn

### Tombstone Shell Rule

Deleting a conversation must not break descendants or other durable references.

Rules:

- if descendant transcript lineage or another durable reference still needs the
  conversation row, keep the row as a deleted tombstone shell
- the tombstone shell is not user-visible
- physical row purge is deferred until no such dependency remains
- safe deletion guarantees immediate user invisibility and eventual purge, not
  unconditional immediate row removal

## Garbage Collection

### Authority

Use mark-and-sweep as the correctness authority.

Do not use raw reference counts as the sole source of truth.

### Mark Phase

- start from all live `CanonicalStoreReference` rows
- traverse `base_snapshot_id` transitively
- mark all reachable snapshots

### Sweep Phase

- delete unreachable `CanonicalStoreEntry` rows
- delete unreachable `CanonicalStoreSnapshot` rows
- delete `CanonicalStoreValue` rows that are no longer referenced by any entry
- delete empty `CanonicalStore` rows that no longer have snapshots or
  references

### GC Rules

- GC must be idempotent
- GC must be safe to retry
- GC must never delete a snapshot or value still reachable from any live root
- GC runs asynchronously after deletion finalization and may also run
  periodically for repair

## Schema Rewrite And Documentation Synchronization

### Schema Rewrite Policy

- rewrite existing migrations directly when the final schema shape changes for
  tables that are not yet production-bound
- prefer one coherent schema history over additive compatibility migrations
- after migration edits, reset development and test databases and re-export
  `db/schema.rb`
- schema load from scratch must produce the final desired shape with no
  transitional artifacts

### Direct Cutover Policy

- switch conversation-local reads and writes directly to the new store
- do not introduce backfill jobs
- do not preserve conversation-scoped runtime access on `CanonicalVariable`
- remove legacy conversation-scope write and read paths in the same rollout
- keep workspace-scoped `CanonicalVariable` behavior intact

### Documentation Synchronization Policy

- update behavior docs in the same implementation sequence as code changes
- update this design document if landed implementation changes any locked detail
- update the implementation plan if task order or task content changes during
  execution
- code, behavior docs, and both plan docs must match at the end of the rollout

### Cleanup Policy

- remove obsolete services, queries, controller actions, routes, tests, and
  supporting code that no longer match the final architecture
- remove stale behavior docs and plan text that describe removed paths
- remove schema artifacts and validations that only existed for transitional
  conversation-scope runtime behavior
- the final repository state must not contain dead compatibility code or dead
  documentation kept "just in case"

## Failure Modes

- reject keys longer than 128 bytes
- reject values larger than 2 MiB
- reject writes to `pending_delete` or `deleted` conversations
- reject branch, checkpoint, and thread creation from `pending_delete` or
  `deleted` conversations
- reject resume and recovery actions once deletion has been requested
- reject tombstone entries with a value reference
- reject set entries without a value reference
- reject duplicate keys within one snapshot
- reject snapshot references that cross store boundaries
- reject compaction output that changes visible store semantics
- reject purge while unfinished work or required tombstone-shell dependencies
  remain

## Test Matrix

The implementation is not complete unless the following tests exist.

### Model And Schema Tests

- key byte-length check passes at 128 bytes and fails at 129 bytes
- multibyte UTF-8 key length is measured by bytes, not Ruby characters
- value size check passes at exactly 2 MiB and fails at 2 MiB plus 1 byte
- tombstone entries reject value references
- set entries require value references
- one snapshot cannot contain duplicate keys
- snapshot depth increments correctly
- snapshot store boundary checks reject cross-store ancestry

### Store Read And Write Tests

- root conversation starts with an empty snapshot
- branch creation copies the parent snapshot reference without creating entries
- checkpoint creation copies the current snapshot reference without creating
  entries
- parent write after branch does not change child reads
- child write after branch only overrides the touched key
- child delete after branch only hides the touched key
- deleting a key in the child does not delete the parent value
- repeated writes to the same key resolve to the newest snapshot hit
- no-op set does not create a new snapshot
- no-op delete does not create a new snapshot
- `get` returns missing when the newest hit is a tombstone
- `mget` preserves request order and missing keys
- `list_keys` excludes tombstoned keys
- compaction preserves the exact visible key set and values

### Deduplication And Large Value Tests

- identical large values reuse one `CanonicalStoreValue`
- different payloads with the same byte size do not deduplicate incorrectly
- hash collision protection compares payload content before reuse
- list-style reads never materialize value payloads

### Query Shape Tests

- `get` loads at most one value row
- `mget` resolves in bounded queries rather than one query per key
- `list_keys` executes without joining the value table
- list pagination remains stable by key order
- the implementation does not use Active Record eager loading that pulls all
  value payloads for list-style queries

### Deletion And Unfinished Work Tests

- request deletion hides the conversation from default list queries
- request deletion on an idle conversation moves directly toward finalization
- request deletion cancels queued turns immediately
- request deletion on a conversation with an active turn stamps cancellation as
  requested and then cancels the turn once the owning workflow run has been
  driven to a terminal state
- request deletion on a waiting human interaction cancels the blocking request
- request deletion blocks new turn entry
- request deletion blocks new canonical store writes
- request deletion blocks branch, checkpoint, and thread creation
- finalize deletion rejects while active work remains
- finalize deletion removes the conversation store reference once work is
  quiescent
- deleted tombstone-shell conversations are not user-visible
- physical purge is deferred while descendants still depend on the conversation
  row

### Garbage Collection Tests

- GC does not delete shared snapshots still referenced by a child conversation
- GC does not delete shared values still referenced by reachable entries
- GC deletes unreachable snapshots after final deletion
- GC deletes unreachable values after the last entry reference disappears
- GC is idempotent across retries

### Schema Rewrite Tests

- schema load from scratch creates the final canonical-store tables and
  deletion fields with no transitional compatibility columns
- workspace-scoped canonical variables still work after the schema rewrite
- conversation-local runtime writes no longer create conversation-scoped
  `CanonicalVariable` rows
- conversation-local runtime reads no longer depend on conversation-scoped
  `CanonicalVariable` rows

## Implementation Sequence

The implementation order is fixed to reduce risk and allow unattended
execution.

1. rewrite schema history for store tables, deletion fields, and cancellation
   fields; reset databases; re-export `db/schema.rb`
2. implement model validations and schema-level check constraints
3. implement store read-path queries for get, mget, and list_keys
4. implement store write-path services for set, delete, and compaction
5. integrate root conversation creation with initial store and snapshot
6. integrate branch, checkpoint, and thread creation with snapshot-reference
   sharing
7. switch conversation-local runtime APIs directly to the new store and remove
   obsolete conversation-scope runtime paths
8. implement promotion and resolve against the new direct-cutover store shape
9. implement deletion request and active-work cancellation
10. implement deletion finalization and tombstone-shell behavior
11. implement store garbage collection
12. remove dead compatibility code, dead tests, dead routes, and stale docs
13. update behavior docs and both plan docs to match the landed code
14. run the full test matrix on the rewritten schema

This order is intentionally conservative:

- schema purity before runtime cutover
- store correctness before API cutover
- direct API cutover before deletion finalization
- deletion finalization before GC
- cleanup and docs synchronization before the final verification pass

## Ambiguity Policy

If implementation encounters a question not answered by this document, the
default action is not to guess. Stop and surface the question.

However, this design intentionally closes the following choices so they do not
require further discussion:

- snapshot behavior is frozen, not live inheritance
- store writes create immutable snapshots
- maximum snapshot depth is 32
- keys are byte-limited, not character-limited
- values are capped at 2 MiB
- list-style reads are metadata-only by default
- workspace-scope canonical variables stay on the existing model
- deletion is logical first, physical later
- mark-and-sweep is the GC authority
- no compatibility layer survives the rollout

## Exit Criteria

This design is ready for implementation only when all of the following are
true:

- every required schema element and service boundary is named
- schema rewrite rules are explicit
- no public read path implicitly loads all values
- unfinished-turn deletion behavior is fully specified
- compatibility removal is fully specified
- the test matrix covers correctness, boundaries, and performance traps
- dead code and stale docs removal is fully specified
- the final rollout updates behavior docs and both plan docs together
- no remaining section depends on an unstated product decision
