# Publication And Live Projection

## Purpose

Task 12.1 adds the first durable publication root for Core Matrix:
publication state, publication access-event recording, and a read-only live
projection query that follows the current canonical conversation state without
copying transcript data into a second source of truth.

## Publication State

- `Publication` belongs to:
  - `installation`
  - `conversation`
  - `owner_user`
- one publication row exists per conversation
- publication visibility modes in v1 are:
  - `disabled`
  - `internal_public`
  - `external_public`
- publication rows persist:
  - stable `slug`
  - access-token digest
  - `published_at`
  - `revoked_at`
- publication ownership stays separate from workspace or conversation ownership,
  but the publication owner is pinned to the conversation workspace owner

## Publish And Revoke Services

- `Publications::PublishLive` is the only service that enables live sharing.
- publish-live creates the publication row when it does not exist and reuses the
  same row on later visibility changes.
- publish-live only accepts publishable visibility modes:
  - `internal_public`
  - `external_public`
- publish-live keeps the publication slug stable across visibility changes.
- publish-live rotates the external access token whenever the publication is
  first enabled or its visibility mode changes, and returns the fresh plaintext
  token on the in-memory publication instance.
- `Publications::Revoke` does not delete the publication row; it moves the row
  back to `visibility_mode = "disabled"` and stamps `revoked_at`.

## Access Rules

- publication reads remain read-only by definition.
- read-side access is recorded only through
  `Publications::RecordAccess` plus `PublicationAccessEvent`.
- `internal_public` rules:
  - any authenticated `User` from the same installation may read
  - anonymous access is rejected
  - cross-installation viewers are rejected
- `external_public` rules:
  - anonymous access is allowed by slug
  - anonymous access is allowed by access token
  - access still records a durable `PublicationAccessEvent`
- disabled or revoked publications reject later read access

## Access Events

- `PublicationAccessEvent` belongs to:
  - `installation`
  - `publication`
  - optional `viewer_user`
- access events store:
  - `access_via`
  - `accessed_at`
  - `request_metadata`
- access events are the explicit read-audit surface for publication reads; they
  are separate from `AuditLog` lifecycle mutations

## Audit Scope

- publication lifecycle mutations still use `AuditLog`
- enabling a publication records `publication.enabled`
- switching between internal and external visibility records
  `publication.visibility_changed`
- revocation records `publication.revoked`
- visibility lifecycle audit metadata carries both the current visibility mode
  and the previous mode when one existed

## Live Projection Query

- `Publications::LiveProjectionQuery` reads directly from the current
  conversation state instead of duplicating transcript rows into publication
  storage.
- the query combines:
  - `Conversations::TranscriptProjection.call(conversation: conversation)`
  - `ConversationEvent.live_projection(conversation: ...)`
- projection entries preserve type distinction explicitly:
  - `entry_type = "message"`
  - `entry_type = "conversation_event"`
- anchored conversation events are inserted after the selected input message of
  the same turn so the projection can render transcript and non-transcript
  runtime notices together without collapsing them into one record type
- unanchored conversation events are appended in stored
  `projection_sequence` order
- replaceable event streams still collapse to the newest revision through
  `ConversationEvent.live_projection`, so publication sees only the canonical
  live view of one stream key

## Failure Modes

- publication cannot be enabled with `visibility_mode = "disabled"`
- internal-public access rejects anonymous viewers
- revoked publications reject later slug or token reads
- publication access events reject viewer users from another installation
- live projection query rejects inactive publications instead of guessing a
  public view for disabled state

## Retained Implementation Notes

- local Rails migration guidance plus the migration failure in this task
  confirmed that `t.references` already creates a standard index, so publication
  migrations only add extra indexes when the uniqueness or compound shape is
  different from the default index
- local Rails association guidance confirmed that `belongs_to` remains required
  by default, so `viewer_user` is marked `optional: true` explicitly on
  `PublicationAccessEvent` to allow anonymous external reads while keeping the
  other publication roots required
