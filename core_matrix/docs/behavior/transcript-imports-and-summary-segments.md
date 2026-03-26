# Transcript Imports And Summary Segments

## Purpose

Task 08.2 adds explicit transcript-support rows for branch prefixes, imported
summary context, and conversation-local summary segments.

This task also defines the compaction-boundary cleanup that rollback must apply
so retained compacted history survives while superseded post-rollback support
state is removed.

## Import Behavior

- `ConversationImport` is a read-only support row owned by one target
  conversation.
- Supported v1 import kinds are:
  - `branch_prefix`
  - `merge_summary`
  - `quoted_context`
- `branch_prefix` imports describe inherited branch history by reference; they
  do not copy parent transcript rows into the branch conversation.
- `branch_prefix` imports are branch-only and must match both the branch parent
  conversation and the branch anchor message.
- branch-prefix anchors may point at:
  - inherited transcript rows still visible in the parent lineage
  - parent-local historical variants that remain durable branch points
- `merge_summary` imports must reference a summary segment.
- `quoted_context` imports may reference a summary segment or a projected source
  message.
- When a summary segment or source message is supplied, the import records the
  source conversation explicitly.

## Branch Prefix Behavior

- `Conversations::CreateBranch` now materializes a `branch_prefix` import when
  the historical anchor points at a real message row.
- The import preserves prefix provenance without cloning parent `Message` rows.
- Branch conversations therefore keep their own `messages` table empty until new
  branch-local turns are submitted.

## Summary Segment Behavior

- `ConversationSummarySegment` belongs to one target conversation but may point
  at start and end messages that come from that conversation's visible
  transcript projection, including inherited branch-prefix history.
- A summary segment must reference messages in transcript order.
- Summary segments are immutable content rows; replacement is modeled through
  `superseded_by`.
- A later segment can supersede an earlier segment without deleting the earlier
  row.

## Service Behavior

- `Conversations::AddImport` creates transcript-support imports and treats
  `branch_prefix` as a one-row-per-branch support record.
- `ConversationSummaries::CreateSegment` creates a new summary segment and can
  mark an earlier segment as superseded in the same transaction.
- `Conversations::RollbackToTurn` now prunes conversation-local summary
  segments and imports that only describe state beyond the rollback boundary.
- When rollback drops a superseding summary segment, any retained earlier
  segment has its `superseded_by` pointer cleared so the older compacted history
  becomes current again.

## Fork-Point Protection

- Messages used as historical anchors for child conversations are fork points.
- input messages referenced as `source_input_message` by output-anchored child
  conversations are fork points too.
- Fork-point transcript rows cannot be hidden or excluded from context through
  visibility overlays in either the native conversation or any descendant
  projection that depends on the anchor.
- Tail rewrite operations that would mutate the current path at a fork point are
  rejected:
  - tail input edit
  - retrying a selected failed output in place
  - rerunning a selected tail output in place
  - selecting a different output variant on a fork-point output turn
- Historical reruns that already branch remain allowed because they do not
  mutate the anchored transcript row in place.

## Invariants

- branch history is modeled by imports, not transcript copying
- summary replacement is append-only plus supersession pointers
- rollback preserves compacted history that still describes retained transcript
  state
- rollback drops only support rows that describe superseded post-rollback local
  state
- fork-point transcript rows remain stable once a child conversation depends on
  them, including against descendant visibility overlays

## Failure Modes

- branch-prefix imports with a mismatched parent or anchor are rejected
- summary segments whose range runs backward through the transcript projection
  are rejected
- imports or summary segments that point outside the visible transcript
  projection are rejected
- rollback removes imports that reference dropped summary segments
- fork-point visibility rewrites and in-place tail rewrites are rejected

## Rails And Reference Findings

- Local Rails source confirmed that `enum ... validate: true` is the right
  pattern when import-kind validation should happen on `valid?` rather than by
  immediate assignment-time `ArgumentError`.
- Local Rails association guides confirmed the self-referential
  `foreign_key: { to_table: ... }` migration and `belongs_to` pattern used for
  summary supersession.
- A narrow Dify and OpenClaw sanity sweep did not yield a better authoritative
  model for branch-prefix imports or compaction-boundary rollback cleanup, so
  this task followed the local design doc as the source of truth.
