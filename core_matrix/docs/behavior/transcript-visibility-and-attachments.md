# Transcript Visibility And Attachments

## Purpose

Task 08.1 adds mutable transcript-visibility overlays and kernel-owned message
attachments without mutating historical transcript rows in place.

This task also adds the minimal branch and checkpoint support projections needed
to prove that hidden or context-excluded messages do not leak their attachments
into descendant conversation support surfaces.

## Visibility Overlay Behavior

- `ConversationMessageVisibility` is scoped to one conversation projection and
  one message.
- Overlay rows are mutable state layered on top of immutable `Message` rows.
- Supported v1 overlay flags are:
  - `hidden`
  - `excluded_from_context`
- An overlay row must express at least one effective state; all-false rows are
  rejected.
- A conversation can store at most one overlay row for a given message.
- Overlay rows only apply to messages that are present in the target
  conversation's transcript projection.
- `ConversationMessageVisibility` model validation keeps only overlay-state and
  installation-consistency rules; projection membership is enforced by
  `Messages::UpdateVisibility`.

## Transcript Projection Behavior

- `Conversations::TranscriptProjection.call(conversation: conversation)`
  returns the visible transcript path for the conversation.
- Root conversations project the selected input and selected output message of
  each turn in sequence order.
- Fork conversations inherit the full parent projection and append their own
  selected messages.
- Branch and checkpoint conversations inherit the parent projection only up to
  the `historical_anchor_message_id`, then append their own selected messages.
- Hidden overlays are inherited down the conversation lineage because descendant
  projections consult the full ancestor chain from the source message's native
  conversation to the target conversation.
- Projection helpers batch the relevant overlay rows for the current lineage
  path instead of issuing per-message overlay existence checks.
- `Conversations::ContextProjection.call(conversation: conversation).messages`
  starts from the visible transcript projection and removes messages marked
  `excluded_from_context` anywhere along that lineage path.

## Attachment Behavior

- `MessageAttachment` belongs to an installation, conversation, and immutable
  submitted message row.
- File-bearing attachment rows use `has_one_attached :file`.
- File-bearing attachment rows require an attached file before validation can
  pass.
- v1 does not introduce a separate attachment-visibility overlay model.
- Attachment visibility and context inclusion inherit entirely from the parent
  message projection state.
- `Conversations::ContextProjection.call(conversation: conversation).attachments`
  derives attachment support rows from the context-message projection, so
  hidden or context-excluded messages do not leak attachments into branch or
  checkpoint support projections.
- transcript visibility decides which attachments are even eligible for a
  conversation, but later runtime exposure is still gated by the turn's frozen
  capability surface from its `AgentSnapshot` plus any optional
  `ExecutionRuntime`.

## Attachment Ancestry Behavior

- Reusing a historical attachment creates a new logical `MessageAttachment`
  row instead of mutating or re-parenting the source row.
- Attachment reuse streams the source blob into a new blob upload; it does not
  need to buffer the full file body in Ruby memory before attach.
- Materialized attachment rows keep:
  - `origin_attachment`
  - `origin_message`
- `origin_message` stays aligned with the source attachment ancestry so later
  materializations can preserve the historical source message identity.

## Service Behavior

- `Messages::UpdateVisibility` upserts one conversation-message overlay row.
- `Messages::UpdateVisibility` is the write boundary that checks message
  membership against the target conversation's base transcript path before it
  saves or deletes the overlay row.
- Visibility updates never mutate or delete the historical `Message` row.
- Fork-point messages cannot be hidden or excluded from context in any
  conversation projection that depends on them, including descendant branch and
  checkpoint projections.
- If all overlay flags are cleared, `Messages::UpdateVisibility` removes the
  now-empty overlay row.
- `Attachments::MaterializeRefs` clones file-bearing source attachment rows onto
  a target message, preserving origin pointers and copying the attached file
  contents into a new logical attachment row.

## Invariants

- transcript-bearing `Message` rows remain append-only and immutable
- visibility changes are modeled as overlay rows, not transcript mutation
- attachment reuse produces new logical rows with origin ancestry
- branch and checkpoint support projections derive from selected transcript
  paths plus conversation-specific overlays
- hidden or context-excluded messages cannot leak attachments into descendant
  support projections
- fork-point transcript rows cannot be hidden or context-excluded after branch
  or checkpoint anchoring, even from descendant overlays

## Failure Modes

- overlay rows with no effective state are rejected
- duplicate overlay rows for the same conversation and message are rejected
- overlay rows targeting messages outside the conversation transcript projection
  are rejected
- attachment rows without a file are rejected
- attachment rows whose ownership does not match the parent message or
  installation are rejected
- attachment materialization rejects refs that are not `MessageAttachment`
  records

## Rails And Reference Findings

- Local Rails Active Storage guide and source checks confirmed that
  `has_one_attached` is the correct v1 attachment primitive here and that
  `validates_presence_of` works for file-bearing attached rows.
- The retained Rails conclusion was written locally instead of relying on the
  guide paths at runtime.
- A non-authoritative reference sweep over Dify and OpenClaw did not provide a
  better canonical model for transcript visibility overlays or attachment
  ancestry, so Task 08.1 follows the local design doc as the source of truth.
