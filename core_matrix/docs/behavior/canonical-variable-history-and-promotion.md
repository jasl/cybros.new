# Canonical Variable History And Promotion

## Purpose

Core Matrix now splits durable variable behavior into two explicit layers:

- `CanonicalVariable` stores workspace-scoped durable history only
- conversation-local agent state lives in the snapshot-backed canonical store

This document defines the landed boundary after the destructive refactor that
removed conversation-scoped `CanonicalVariable` rows entirely.

## Workspace Canonical Variable Shape

- `CanonicalVariable` is an append-only durable history record, not a mutable
  cache row.
- Every row belongs to one installation and one workspace.
- Every row stores:
  - `scope`
  - `key`
  - `typed_value_payload`
  - optional writer identity
  - `source_kind`
  - optional source conversation, turn, and workflow run references
  - `projection_policy`
  - `current`
  - supersession metadata
- The landed implementation allows exactly one scope:
  - `workspace`

## History And Supersession

- `current = true` marks the active workspace value for one key.
- A later accepted write supersedes the previous current row instead of
  mutating or deleting it.
- Superseded rows retain:
  - `current = false`
  - `superseded_at`
  - `superseded_by_id`
- A partial unique index enforces one current workspace value per
  `workspace_id + key`.
- `Variables::Write` owns the supersession transaction ordering so history and
  uniqueness remain consistent in the same write.

## Conversation-Local State Boundary

- Conversation-local variables are no longer stored in `canonical_variables`.
- They now live in the canonical store tables:
  - `canonical_stores`
  - `canonical_store_snapshots`
  - `canonical_store_entries`
  - `canonical_store_values`
  - `canonical_store_references`
- Conversation-local writes and deletes create immutable snapshot deltas.
- Conversation-local reads resolve through the active
  `CanonicalStoreReference`.
- The conversation-local store is internal storage. Store rows, snapshot ids,
  and value row ids never cross agent-facing boundaries.

## Effective Lookup

- `WorkspaceVariables::*` queries read current workspace-scoped
  `CanonicalVariable` rows only.
- `ConversationVariables::ResolveQuery` returns the effective merged view:
  conversation-local canonical store values override workspace canonical
  variables by key.
- `CanonicalVariable.effective_for` is now workspace-only infrastructure and no
  longer implements `conversation > workspace` lookup itself.

## Write And Promotion Boundaries

- `Variables::Write` accepts workspace scope only.
- Passing `scope = "conversation"` now raises `ActiveRecord::RecordInvalid`.
- `Variables::PromoteToWorkspace` reads the current conversation-local value
  from the canonical store, then writes a new workspace-scoped
  `CanonicalVariable` row.
- Promotion preserves workspace history by superseding the prior current
  workspace value rather than editing it in place.
- Promotion carries forward:
  - the same key
  - the same typed value payload
  - `source_kind = "promotion"`
  - the source conversation reference
- Promotion does not delete or mutate the originating conversation-local store
  entry.

## Deletion Interaction

- Workspace canonical-variable history survives conversation deletion.
- `source_conversation_id` remains an optional durable provenance reference.
- Because of that provenance FK, a deleted conversation may need to remain as a
  tombstone shell until no workspace canonical-variable history still points at
  it.
- Promotion is rejected once a conversation is no longer retained.

## Failure Modes

- unsupported scope values are rejected
- non-hash typed payloads are rejected
- broken writer polymorphic pairings are rejected
- superseded rows reject missing `superseded_at` or `superseded_by`
- workspace writes reject conversation-target arguments
- promotion rejects missing conversation-local store values
- promotion rejects `pending_delete` or `deleted` conversations
