# Conversation Structure And Lineage

## Purpose

Core Matrix conversations now carry three independent concerns:

- lineage shape
- user-visible lifecycle state
- deletion state and canonical-store ownership

This document reflects the landed behavior after canonical store integration
and safe deletion support.

## Conversation State Axes

- kind:
  - `root`
  - `branch`
  - `thread`
  - `checkpoint`
- purpose:
  - `interactive`
  - `automation`
- lifecycle state:
  - `active`
  - `archived`
- deletion state:
  - `retained`
  - `pending_delete`
  - `deleted`

`lifecycle_state` and `deletion_state` are separate axes. A conversation can be
archived yet retained, or active yet pending deletion while safe-deletion
cleanup is still running.

## Kind Rules

- `root` conversations have no parent conversation and no historical anchor
- `branch` conversations require both a parent conversation and a
  `historical_anchor_message_id`
- `thread` conversations require a parent conversation and may optionally
  record a historical anchor for provenance
- `checkpoint` conversations require both a parent conversation and a
  `historical_anchor_message_id`
- child conversations stay in the same workspace as their parent
- automation conversations remain root-only

## Closure And Transcript Lineage

- `ConversationClosure` stores ancestor/descendant pairs plus `depth`
- every conversation gets a self-closure row with `depth = 0`
- child conversations inherit the parent ancestor chain in the same
  transaction
- transcript projection still walks `parent_conversation` recursively
- descendants therefore depend on deleted ancestors remaining as tombstone
  shells until lineage blockers disappear

## Canonical Store Lineage

- every root conversation bootstraps one lineage-local `CanonicalStore`
- root creation also creates:
  - one empty root snapshot
  - one `CanonicalStoreReference` from the root conversation to that snapshot
- branch, checkpoint, and thread creation create a fresh
  `CanonicalStoreReference` that points at the parent conversation's current
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
- new turn entry, branching, checkpointing, threading, and conversation-local
  store writes are rejected once deletion has been requested
- queued turns are canceled immediately with `conversation_deleted`
- the current active turn is fenced through `turn_interrupt`
- parent delete does not interrupt retained child conversations
- `Conversations::FinalizeDeletion` removes the conversation's live
  `CanonicalStoreReference` and moves the row to `deleted` once the mainline
  stop barrier is clear
- detached background cleanup may still be `disposing` or `degraded` after the
  row has reached `deleted`
- `Conversations::PurgeDeleted` now rejects corrupted `deleted` states that
  still retain active runtime work or a live `CanonicalStoreReference`
- `Conversations::PurgeDeleted(force: true)` still only helps with corrupted
  runtime residue by issuing the normal delete close contract; it does not
  bypass final-deletion or lineage guards
- `PurgeDeleted(force: true)` still does not perform final deletion on behalf
  of the caller; the live `CanonicalStoreReference` must already be gone
- if active runtime residue still exists after that force request, the deleted
  tombstone shell remains until close reports clear the residue and purge is
  retried
- physical purge is deferred while descendants, canonical-store root
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
- the conversation transitions to `archived` once the mainline stop barrier is
  clear
- the archive close operation may remain `disposing` or `degraded` after the
  conversation is already archived if detached cleanup still has pending or
  residual outcomes
- archived conversations are excluded from open human-interaction inbox queries
- archived conversations reject opening new human interactions and reject late
  resolution of still-open requests
- `Conversations::Unarchive` requires:
  - `deletion_state = retained`
  - `lifecycle_state = archived`
- archive and unarchive do not change lineage, canonical-store ownership, or
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

## Invariants

- workspace ownership remains the root of conversation ownership
- lineage shape, visible lifecycle, and deletion state stay distinct
- automation conversations stay root-only
- child conversations reuse canonical-store lineage by reference, not by eager
  copying
- deletion never breaks descendant transcript or store lineage

## Failure Modes

- unsupported conversation kinds, purposes, lifecycle states, or deletion
  states are rejected
- non-root conversations without a parent are rejected
- branch and checkpoint conversations without a historical anchor are rejected
- automation conversations with non-root kinds are rejected
- child conversations in a different workspace from the parent are rejected
- branch, checkpoint, and thread creation are rejected from non-retained
  parents
- archive is rejected for non-retained or non-active conversations
- archive without force is rejected while unfinished runtime work remains
- unarchive is rejected for non-retained or non-archived conversations
- purge is rejected until final deletion has already removed the live canonical
  store reference, even when force is requested
- new turn entry is rejected while an archive or delete close operation is
  still in progress
