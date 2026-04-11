# Conversation Export, Import, And Debug Bundles Design

## Status

- Date: 2026-04-02
- Status: proposed and approved for implementation planning

## Goal

Add a user-facing `ConversationExport` and `ConversationImport` capability to
`core_matrix`, while keeping internal diagnostic export separate as
`ConversationDebugExport`.

The system should treat user export bundles as portable conversation assets and
should treat debug bundles as internal runtime evidence packages. These two
surfaces must not share a format, a request model, or an import path.

## Product Position

This design deliberately separates three user intentions that are easy to blur
together:

1. export a conversation as a user-owned asset
2. import a previously exported conversation into a new conversation
3. bring an exported conversation into the current turn as reference material

Only the first two are system-level import/export features. The third should be
handled by normal file upload plus agent interpretation, not by mutating
existing conversation history.

## Inputs And References

This design is informed by two external product patterns:

- `RisuAI` export/import is asset-oriented. It exports user-readable and
  machine-readable chat bundles and allows re-import of its own formats. The
  relevant implementation lives in
  `/Users/jasl/Workspaces/Ruby/cybros/references/original/references/Risuai/src/ts/characters.ts`
  and
  `/Users/jasl/Workspaces/Ruby/cybros/references/original/references/Risuai/src/lib/SideBars/SideChatList.svelte`.
- `ChatGPT` exposes formal data export as an asynchronous, time-limited package
  download and treats “bring old conversation into a new chat” as a file-upload
  workflow rather than a history merge. See
  [How do I export my ChatGPT history and data?](https://help.openai.com/en/articles/7260999-how-do-i-export-my-chatgpt-history-and-data)
  and
  [Transferring conversations from one ChatGPT account to another](https://help.openai.com/en/articles/9106926-transferring-conversations-from-1-chatgpt-account-to-another-chatgpt-account%253F.pls).

The design borrows:

- from `RisuAI`: versioned asset bundles with explicit import format ownership
- from `ChatGPT`: asynchronous export generation, time-limited download, and
  “upload as context” instead of merge-style import

## Approved Requirements

The product direction is already decided:

- `ConversationExport` is user-facing
- `ConversationDebugExport` is internal-facing
- both export surfaces should be asynchronous
- both export surfaces should produce `zip` bundles
- downloads should be temporary and expire after a `TTL`
- user export should include files only when they are explicitly attached to a
  `conversation/message`
- user export must not scan workspace files
- user import should accept only this product’s own versioned export bundle
- user import should always create a new conversation
- user import should preserve message order and timestamps
- user import should generate new internal ids and new `public_id` values
- user import should be all-or-nothing
- the “bring old conversation into this conversation” use case should be served
  by uploading the export bundle to the current conversation and letting the
  agent read it as reference material

## Non-Goals

- no workspace backup or project snapshot behavior
- no import into an existing conversation
- no merge of imported history with current history
- no support for third-party export formats in v1
- no support for importing `ConversationDebugExport` bundles
- no attempt to reconstruct hidden internal runtime data into user history
- no persistent “always downloadable” export artifact in v1

## Existing Constraints In `core_matrix`

### Naming Constraint

`ConversationImport` is already an existing model for conversation-to-
conversation context imports:

- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/conversation_import.rb`

That name must not be reused for user bundle import requests. The new user
import request surface needs distinct names.

### Attachment Boundary

Conversation-visible files already exist at the message layer:

- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/message_attachment.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/message.rb`

This is the correct inclusion boundary for user export bundles.

### Transcript Source

The current transcript projection is already user-oriented:

- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/app_api/conversation_transcripts_controller.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/projections/conversation_transcripts/page_projection.rb`

The export system should reuse these transcript semantics rather than inventing
a second definition of visible conversation history.

### Artifact Reuse Constraint

`WorkflowArtifact` already supports file attachments, but it is tied to
`workflow_run`, `workflow_node`, and workflow presentation policy:

- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/workflow_artifact.rb`

That ownership model is a poor fit for user export lifecycle, which is:

- conversation-scoped rather than workflow-node-scoped
- request-driven rather than workflow-driven
- time-limited rather than durable proof by default

The export system should therefore use dedicated request models rather than
shoehorning export bundles into `WorkflowArtifact`.

## Alternatives Considered

### Option A: One Unified Export Service With Modes

Shape:

- one request model
- one builder
- mode flag such as `user` or `debug`
- one controller family

Pros:

- fewer classes
- lower initial implementation count

Cons:

- user-facing and internal-facing semantics become entangled
- import validation gets harder because the user format and debug format drift
  inside the same surface
- authorization mistakes become more likely because the same endpoint family
  serves very different audiences
- future maintenance encourages “just add another mode” instead of keeping
  product boundaries clean

Verdict:

- rejected

### Option B: Separate User Export/Import And Separate Debug Export

Shape:

- `ConversationExportRequest`
- `ConversationDebugExportRequest`
- `ConversationBundleImportRequest`
- distinct jobs, builders, and controllers
- separate bundle formats

Pros:

- maps directly to the approved product semantics
- keeps user asset portability independent from internal diagnostics
- makes import validation straightforward because only one bundle family is
  importable
- supports different retention rules and authorization rules for user bundles
  versus debug bundles

Cons:

- more classes and routes up front
- some repeated request lifecycle code

Verdict:

- recommended

### Option C: Reuse `WorkflowArtifact` As The Export Container

Shape:

- export requests write their output bundle into `WorkflowArtifact.file`
- the workflow layer becomes the distribution layer for export assets

Pros:

- reuses an existing attached-file model

Cons:

- wrong ownership boundary
- conversation export should not require a live workflow run or workflow node
- export retention and workflow proof retention are different concerns
- importable user assets and internal workflow proof would become muddled

Verdict:

- rejected

## Recommended Architecture

Adopt Option B.

Create three independent request surfaces:

- `ConversationExportRequest`
- `ConversationDebugExportRequest`
- `ConversationBundleImportRequest`

Each request type should own:

- its own database row
- its own `ActiveJob`
- its own state machine
- its own payload schema
- its own file attachment

Export request types should expose these lifecycle states:

- `queued`
- `running`
- `succeeded`
- `failed`
- `expired`

Import request types should expose:

- `queued`
- `running`
- `succeeded`
- `failed`

The shared behavior should be implementation detail only, not product contract.
If common behavior appears, extract a concern or service object later. Do not
merge the request models into a single “generic export request” abstraction in
v1.

## User Bundle Format

`ConversationExport` should generate a single `zip` bundle with this stable
top-level layout:

- `manifest.json`
- `conversation.json`
- `transcript.md`
- `conversation.html`
- `files/...`

### `manifest.json`

This is the bundle descriptor and validation entry point.

Minimum fields:

- `bundle_kind`: `conversation_export`
- `bundle_version`
- `exported_at`
- `conversation_public_id`
- `original_title`
- `message_count`
- `attachment_count`
- `files`
- `checksums`
- `generator`

Each file entry in `files` should record:

- `kind`: `user_upload` or `generated_output`
- `message_public_id`
- `filename`
- `mime_type`
- `byte_size`
- `sha256`
- `relative_path`

### `conversation.json`

This is the only import truth source.

It should contain:

- conversation-level metadata safe to rehydrate
- ordered message records
- message attachment references pointing to `files/...`
- enough original metadata to preserve user-visible history shape

It must not contain:

- internal bigint ids
- hidden debug traces
- workflow nodes
- tool invocations
- process runs
- provider usage events

### `transcript.md`

This is a human-readable markdown transcript intended for inspection, sharing,
and agent consumption as a normal uploaded file.

### `conversation.html`

This is a static, human-readable HTML rendering of the transcript and
attachments summary. It should not embed the structured JSON.

### `files/...`

This directory contains only files that are explicitly attached to messages in
the exported conversation.

Included:

- user-uploaded files attached to messages
- assistant-generated files attached to messages

Excluded:

- workspace files
- transient runtime outputs
- workflow proof artifacts
- unreferenced attachments outside the exported conversation

## Import Semantics

`ConversationBundleImportRequest` should accept only the versioned
`ConversationExport` bundle described above.

Import rules:

- import always creates a new conversation
- import never appends to an existing conversation
- import preserves original message ordering
- import preserves original visible timestamps
- import generates fresh database ids and fresh `public_id` values
- import rehydrates attached files from `files/...`
- import should record provenance that the conversation came from a bundle
  import, but should not pretend the imported messages are the original rows

### Atomicity

Import is all-or-nothing.

Any of the following must fail the entire import:

- missing `manifest.json`
- missing `conversation.json`
- unsupported `bundle_kind`
- unsupported `bundle_version`
- checksum mismatch
- missing attachment file referenced by the manifest
- mismatch between manifest and conversation payload
- invalid message ordering or attachment references

There should be no partial import and no “best effort” recovery in v1.

## Debug Bundle Position

`ConversationDebugExport` is a separate product surface.

It should produce a different bundle family, likely JSON-first, that can
include:

- workflow runs
- workflow nodes
- tool invocations
- command runs
- process runs
- subagent connections
- usage events
- diagnostics snapshots

It must not be accepted by `ConversationBundleImportRequest`.

## Async Lifecycle

All three request types should be asynchronous and server-side.

### Export Flow

1. user requests export
2. server creates request row in `queued`
3. `ActiveJob` claims request and moves it to `running`
4. builder generates bundle into attached file
5. request moves to `succeeded`
6. UI fetches download metadata and downloads while request is still valid
7. expiration job moves request to `expired` and purges the file

### Import Flow

1. user uploads bundle
2. server creates import request row in `queued`
3. `ActiveJob` validates and parses bundle in `running`
4. import either creates a new conversation and marks `succeeded`, or records a
   terminal failure and marks `failed`

The request row should remain after file expiry so the UI can still show:

- that an export existed
- whether it succeeded or failed
- whether the downloadable file has expired
- that the user can request a fresh export

## Retention And Storage

Downloadable export bundles should be temporary.

Recommended v1 behavior:

- attached file stored server-side via Active Storage
- configurable `expires_at`
- explicit background expiry job purges attached file payload
- request metadata row is retained after purge

This balances:

- user experience
- operational simplicity
- storage control
- auditability of export actions

## Authorization Model

### User Export / Import

Only the owner-addressable user-facing surface should be able to create,
inspect, and download these requests for a conversation they can access.

### Debug Export

Debug export should be treated as an internal capability and should remain
restricted to trusted internal or operator-facing surfaces.

## API Surface Recommendation

Create distinct controller families:

- `conversation_export_requests`
- `conversation_bundle_import_requests`
- `conversation_debug_export_requests`

Recommended actions:

- `create`
- `show`
- `download` for export requests only

Do not create a single “conversation transfer requests” controller.

## Why “Upload As Context” Is Not Import

When a user wants to reuse old chat history in the current conversation, the
system should not mutate the current conversation record. Instead:

- the user uploads the previously exported bundle
- the bundle becomes a normal file attachment
- the agent reads `transcript.md`, `conversation.html`, or `conversation.json`
  as reference material

This preserves the integrity of the current conversation history and avoids
intractable merge semantics.

## Acceptance Criteria

The design is considered correctly implemented when:

- users can asynchronously export one conversation into a versioned `zip`
  bundle
- the bundle includes user-visible conversation history and only message-bound
  files
- the bundle expires and becomes unavailable after its `TTL`
- users can import that bundle only as a new conversation
- import fails atomically on any validation mismatch
- debug export remains a separate internal-only surface with a separate format
- no bigint ids cross the external boundary
