# Conversation Structure And Lineage

## Purpose

Core Matrix conversations now carry these independent concerns:

- lineage shape
- addressability
- runtime binding
- user-visible lifecycle state
- deletion state and lineage-store ownership

This document reflects the landed behavior after lineage store integration
and safe deletion support.

## Conversation State Axes

- kind:
  - `root`
  - `branch`
  - `fork`
  - `checkpoint`
- purpose:
  - `interactive`
  - `automation`
- addressability:
  - `owner_addressable`
  - `agent_addressable`
- lifecycle state:
  - `active`
  - `archived`
- deletion state:
  - `retained`
  - `pending_delete`
  - `deleted`
- runtime binding:
  - one fixed `ExecutionEnvironment`
  - one active `AgentDeployment` that may change within that environment

`addressability`, `lifecycle_state`, and `deletion_state` are separate axes. A
conversation can be agent-addressable yet active, owner-addressable yet
archived, or active yet pending deletion while safe-deletion cleanup is still
running.

Runtime binding is a separate independent concern. A conversation stays bound
to one execution environment for its whole lifetime, while the active
deployment may rotate or be switched within that bound environment.

## Kind Rules

- `root` conversations have no parent conversation and no historical anchor
- `branch` conversations require both a parent conversation and a
  `historical_anchor_message_id`
- `fork` conversations require a parent conversation and may optionally
  record a historical anchor for provenance
- `checkpoint` conversations require both a parent conversation and a
  `historical_anchor_message_id`
- `owner_addressable` conversations accept owner-driven turn entry
- `agent_addressable` conversations accept delegated agent turn entry and are
  used for subagent child conversations
- child conversations stay in the same workspace as their parent
- child conversations inherit the parent's execution environment binding
- automation conversations remain root-only
- branch, checkpoint, and optional fork anchors are validated against the
  parent conversation's durable transcript history
- that durable history consists of:
  - inherited transcript rows still visible through parent lineage replay
  - parent-local historical transcript rows, including non-selected variants on
    the parent's own turns

## Closure And Transcript Lineage

- `ConversationClosure` stores ancestor/descendant pairs plus `depth`
- every conversation gets a self-closure row with `depth = 0`
- child conversations inherit the parent ancestor chain in the same
  transaction
- transcript projection still walks `parent_conversation` recursively
- branch, checkpoint, and anchored fork replay fail closed if the persisted
  anchor does not belong to the parent conversation
- output anchors rely on persisted `source_input_message` provenance so replay
  can restore the matching input/output pair inside the child transcript
- local historical output anchors replay from the stored source-input lineage
  pair even when the parent currently selects a newer variant on the same turn
- descendants therefore depend on deleted ancestors remaining as tombstone
  shells until lineage blockers disappear

## Canonical Store Lineage

- every root conversation bootstraps one lineage-local `LineageStore`
- root creation also creates:
  - one empty root snapshot
  - one `LineageStoreReference` from the root conversation to that snapshot
- branch, checkpoint, and fork creation create a fresh
  `LineageStoreReference` that points at the parent conversation's current
  snapshot
- child lineage creation copies zero keys and zero values
- later parent writes do not affect the child because parent and child move
  their own references independently after the fork point

## Deletion Behavior

- `Conversations::RequestDeletion` moves a retained conversation to
  `pending_delete` and stamps `deleted_at`
- delete also creates a durable
  `ConversationCloseOperation(intent_kind = "delete")`
- `pending_delete` conversations are hidden from default agent-facing
  conversation lookups
- once deletion has been requested, all caller-driven live mutation is
  rejected, including:
  - new turn entry
  - branch, fork, and checkpoint creation
  - conversation-local store writes
  - import and summary writes
  - message-visibility updates
  - selector and override updates
- queued turns are canceled immediately with `conversation_deleted`
- the current active turn is fenced through `turn_interrupt`
- parent delete does not interrupt retained child conversations
- `Conversations::FinalizeDeletion` removes the conversation's live
  `LineageStoreReference` and moves the row to `deleted` once the mainline
  stop barrier is clear
- detached background cleanup may still be `disposing` or `degraded` after the
  row has reached `deleted`
- `Conversations::PurgeDeleted` runs through an explicit ownership graph rather
  than ad hoc per-table deletes
- physical purge removes phase-two agent-control residue, including
  `agent_task_runs`, mailbox items, and report receipts that still belong to
  the deleted conversation's runtime graph
- physical purge also tears down attachment-backed runtime rows such as
  `MessageAttachment` and `WorkflowArtifact` through model destruction so their
  Active Storage attachment joins are cleaned up
- `Conversations::PurgeDeleted` rejects corrupted `deleted` states that still
  retain active runtime work or a live `LineageStoreReference`
- `Conversations::PurgeDeleted` also fails closed if its purge graph reports
  any owned rows still remain after cleanup; in that case the tombstone shell
  is kept and purge raises rather than deleting the conversation row anyway
- `Conversations::PurgeDeleted(force: true)` still only helps with corrupted
  runtime residue by issuing the normal delete close contract; it does not
  bypass final-deletion or lineage guards
- `PurgeDeleted(force: true)` still does not perform final deletion on behalf
  of the caller; the live `LineageStoreReference` must already be gone
- if active runtime residue still exists after that force request, the deleted
  tombstone shell remains until close reports clear the residue and purge is
  retried
- physical purge is deferred while descendants, lineage-store root
  ownership, or other durable provenance still require the row
- a deleted row may therefore remain as a non-visible tombstone shell
- deleting a parent conversation does not cascade deletion into retained child
  conversations
- child conversations may continue their own active turns and workflows while
  an ancestor remains as a deleted tombstone shell
- ancestor purge remains blocked until descendant lineage dependencies are gone

## Archive Behavior

- `Conversations::Archive` is a retained-lifecycle transition, not a deletion
  path
- archive without force requires all of the following:
  - `deletion_state = retained`
  - `lifecycle_state = active`
  - no queued turns
  - no active turns
  - no active workflow runs
  - no active execution leases
  - no open human interaction
  - no running process or subagent execution
- `Conversations::Archive(force: true)` creates a durable
  `ConversationCloseOperation(intent_kind = "archive")`
- force archive blocks new turn entry immediately, even while the conversation
  row remains `active`
- active mainline work is fenced through `turn_interrupt`
- detached background processes are closed through mailbox close requests with
  `request_kind = "archive_force_quiesce"`
- those process-close requests target the bound execution environment as the
  durable owner and resolve the live delivery endpoint separately
- `Conversations::ReconcileCloseOperation` is the single writer for archive
  close progression; local turn fencing and mailbox terminal close reports both
  re-enter it
- the conversation transitions to `archived` once the mainline stop barrier is
  clear
- the archive close operation may remain `disposing` or `degraded` after the
  conversation is already archived if detached cleanup still has pending or
  residual outcomes
- archived conversations are excluded from open human-interaction inbox queries
- archived conversations reject all caller-driven live mutation, including:
  - turn entry and queued follow-up
  - branch, fork, and checkpoint creation
  - human-interaction open and late resolution
  - import and summary writes
  - message-visibility updates
  - selector and override updates
  - turn timeline rewrites and rollback
- conversations with an unfinished close operation reject the same live
  mutation surface even while the row still reads `lifecycle_state = active`
- `Conversations::Unarchive` requires:
  - `deletion_state = retained`
  - `lifecycle_state = archived`
- archive and unarchive do not change lineage, lineage-store ownership, or
  descendant state
- archiving a parent conversation does not archive children automatically
- deleting a conversation still uses the separate deletion-state axis rather
  than archive lifecycle state

## Runtime Inspection

- `Conversation#active_turn_exists?(include_descendants: false)` is the
  supported boolean query for checking whether the conversation currently owns
  an active turn
- the default query is local to the conversation itself
- `include_descendants: true` widens the check across descendant lineage so UI
  or operator flows can warn about running child work before destructive
  actions
- `Conversations::CloseSummaryQuery` is the operator-facing query for close
  state and separates:
  - mainline blockers
  - disposal-tail blockers
  - lineage and provenance blockers
- `Conversations::BlockerSnapshotQuery` is now the canonical read-side builder
  for those blocker facts
- `ConversationBlockerSnapshot` owns the derived predicates that answer:
  - whether the mainline stop barrier is clear
  - whether disposal tail work is still pending
  - whether disposal tail cleanup degraded
  - whether lineage or provenance blockers still prevent purge
  - whether the conversation is currently mutable for live writes
- `DependencyBlockersQuery`, `WorkBarrierQuery`, and `CloseSummaryQuery` are
  thin projections over that shared blocker snapshot instead of separate
  counter families

## Invariants

- workspace ownership remains the root of conversation ownership
- lineage shape, runtime binding, visible lifecycle, and deletion state stay
  distinct
- automation conversations stay root-only
- child conversations reuse lineage-store lineage by reference, not by eager
  copying
- deletion never breaks descendant transcript or store lineage
- conversation environment binding does not change after creation

## Failure Modes

- unsupported conversation kinds, purposes, lifecycle states, or deletion
  states are rejected
- non-root conversations without a parent are rejected
- branch and checkpoint conversations without a historical anchor are rejected
- automation conversations with non-root kinds are rejected
- child conversations in a different workspace from the parent are rejected
- branch, checkpoint, and fork creation are rejected from parents that are
  non-retained, archived, or currently closing
- archive is rejected for non-retained or non-active conversations
- archive without force is rejected while unfinished runtime work remains
- unarchive is rejected for non-retained or non-archived conversations
- purge is rejected until final deletion has already removed the live lineage
  store reference, even when force is requested
- new turn entry is rejected while an archive or delete close operation is
  still in progress
- invalid or cross-conversation historical anchors are rejected at write time
- persisted child rows with broken anchor provenance fail loudly at read time
