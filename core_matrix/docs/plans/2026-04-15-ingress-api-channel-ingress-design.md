# IngressAPI Channel Ingress Design

## Goal

Add a first-class external ingress boundary to CoreMatrix so chat-style systems
such as Telegram and Discord can act as product entry points without being
modeled as `Conversation` itself.

The first delivery target is Telegram DM. The design must also support later
group/channel/thread expansion and future non-IM ingress sources under the same
`IngressAPI` surface.

## Context And Constraints

- `Conversation` remains the CoreMatrix product object.
- External platforms bind to a `Conversation`; they do not become the
  conversation.
- The external sender must not be treated as the same role as the CoreMatrix
  conversation owner.
- Existing `AppAPI` browser/session boundaries are not suitable for machine
  ingress.
- CoreMatrix already has turn, workflow, attachment, runtime-broadcast, and
  during-generation input-policy primitives that should be reused instead of
  duplicated.
- `references/` material is comparative input only. It informs the shape of the
  solution but is not the implementation source of truth.

## Comparative Findings

### OpenClaw

OpenClaw models IM integration as a channel-plugin boundary, not as assistant
core logic. The shared builder composes channel plugins from explicit surfaces
such as security, pairing, threading, and outbound delivery.

This is the right design direction for CoreMatrix:

- transport-specific logic stays at the ingress edge
- auth, pairing, routing, and thread binding are explicit pipeline stages
- shared reply flow can optionally run inbound media preprocessing before the
  main reply pipeline

### Hermes Agent

Hermes Agent adds a practical gateway shape around this idea:

- platform adapters normalize inbound messages into a standard event object
- rapid text splits and media bursts are buffered before agent dispatch
- active-session follow-up behavior is handled as explicit queue/interrupt logic
- delivery is routed through a dedicated layer instead of being hardcoded per
  command path

CoreMatrix should borrow the normalized event and batching ideas, but should not
copy Hermes' large base-adapter object. In CoreMatrix those concerns belong in
`IngressAPI` application services, not in transport adapters.

## Architecture

The system is split into two public surfaces:

- `IngressAPI`
  - machine-facing
  - webhook/gateway ingress for Telegram, Discord, and later external systems
  - owns signature verification, normalization, dedupe, routing, and turn-entry
    orchestration
- `AppAPI`
  - user-facing management surface
  - owns account setup, pairing approval, allowlists, session binding, and
    conversation association management

This preserves a clean layered boundary:

- presentation: `IngressAPI::*Controller`, `AppAPI::*Controller`
- application: ingress orchestration, authorization, turn entry, outbound
  delivery
- domain: channel/session/account/pairing/delivery facts
- infrastructure: Telegram/Discord clients, media downloaders, webhook
  verification

## Identity Model

Three identities must stay separate:

1. `Conversation owner`
   - the CoreMatrix user/workspace owner
   - decides product ownership, visibility, billing, and management rights
2. `Channel account`
   - the Telegram bot or Discord app credentials used for transport
   - decides which external bot identity sends messages
3. `External sender`
   - the Telegram user, Discord member, or group participant who sent the input
   - does not become a CoreMatrix `User`

Transcript role semantics stay unchanged:

- `Message.role = user` still means "user-side input to the agent"
- it does not mean "CoreMatrix owner user authored this message"

Turn provenance must therefore stop using `manual_user` semantics for IM ingress.

## Core Domain Objects

### `ChannelAccount`

Represents one configured external bot/app account.

Suggested fields:

- `public_id`
- `installation_id`
- `owner_user_id`
- optional `workspace_id`
- `platform`
- `label`
- `lifecycle_state`
- `credential_ref_payload`
- `config_payload`

### `ChannelSession`

Represents one external conversational boundary bound to one CoreMatrix
conversation at a time.

Suggested fields:

- `public_id`
- `installation_id`
- `channel_account_id`
- `owner_user_id`
- `conversation_id`
- `platform`
- `peer_kind`
- `peer_id`
- `thread_key`
- `binding_state`
- `last_inbound_at`
- `last_outbound_at`
- `session_metadata`

Suggested uniqueness:

- `channel_account_id + peer_kind + peer_id + thread_key`

### `ChannelPairingRequest`

Represents DM first-contact approval flow.

Suggested fields:

- `public_id`
- `installation_id`
- `channel_account_id`
- `owner_user_id`
- optional `channel_session_id`
- `platform_sender_id`
- `sender_snapshot`
- `pairing_code_digest`
- `lifecycle_state`
- `expires_at`
- `approved_at`
- `rejected_at`

### `ChannelInboundMessage`

Immutable record of one normalized inbound external message.

Suggested fields:

- `public_id`
- `installation_id`
- `channel_account_id`
- `channel_session_id`
- optional `conversation_id`
- `external_message_id`
- `external_sender_id`
- `sender_snapshot`
- `content`
- `normalized_payload`
- `raw_payload`
- `received_at`

Suggested uniqueness:

- `channel_account_id + external_message_id`

### `ChannelDelivery`

Tracks outbound CoreMatrix delivery back to the external platform.

Suggested fields:

- `public_id`
- `installation_id`
- `channel_account_id`
- `channel_session_id`
- `conversation_id`
- optional `turn_id`
- optional `message_id`
- `external_message_id`
- `reply_to_external_message_id`
- `delivery_state`
- `payload`
- `delivered_at`
- `failed_at`
- `failure_payload`

## Ingress Event Contract

The ingress pipeline should not pass raw platform payloads between application
services. It should standardize on two objects.

### `IngressEnvelope`

Normalized verified inbound event.

Suggested fields:

- `platform`
- `channel_account_public_id`
- `external_event_id`
- `external_message_id`
- `peer_kind`
- `peer_id`
- `thread_key`
- `external_sender_id`
- `sender_snapshot`
- `text`
- `attachments`
- `reply_to_external_message_id`
- `occurred_at`
- `raw_payload`

### `IngressContext`

Mutable per-request orchestration context.

Suggested fields:

- `channel_session`
- `conversation`
- `active_turn`
- `authorization_result`
- `coalesced_message_ids`
- `attachment_records`
- `media_digest`
- `dispatch_decision`
- `origin_payload`

## Middleware And Preprocessor Pipeline

The ingress stack should be explicit and ordered.

### Middleware

These are transport-agnostic cross-cutting steps:

1. `VerifyRequest`
   - verify webhook signature or gateway trust
   - identify the `ChannelAccount`
2. `CaptureRawPayload`
   - preserve raw bytes/body for audit and signature correctness
3. `RateLimit`
   - optional v1 guardrail at account/platform boundary
4. `NormalizeEnvelope`
   - adapter-specific payload -> `IngressEnvelope`
5. `DeduplicateInbound`
   - enforce one normalized inbound fact per external message id

### Preprocessors

These decide how the input becomes CoreMatrix work:

1. `ResolveChannelSession`
   - bind external peer/thread to `ChannelSession`
2. `AuthorizeAndPair`
   - DM pairing, allowlists, mention gates, sender checks
3. `CoalesceBurst`
   - merge client-side text splits and short burst input windows
4. `MaterializeAttachments`
   - download/store platform media, create attachment records
5. `OptionalMediaUnderstanding`
   - optional inbound media digest before reply pipeline
   - failure must not block normal processing
6. `ResolveDispatchDecision`
   - decide `new_turn`, `steer_current_turn`, `queue_follow_up`, or `reject`
7. `MaterializeTurnEntry`
   - create immutable ingress facts and enter the turn system
8. `ScheduleOutboundBinding`
   - preserve reply/thread/outbound cursor context for later delivery

The ordering matters:

- auth decisions happen before turn entry
- attachments are materialized before the turn snapshot is built
- dispatch decision happens after batching and attachment materialization

## Turn Entry Integration

CoreMatrix needs a new turn-entry service for IM ingress:

- `Turns::StartChannelIngressTurn`

This should sit parallel to existing user and automation entry services.

Required behavior:

- interactive conversation only
- `origin_kind = "channel_ingress"`
- `source_ref_type = "ChannelInboundMessage"`
- `source_ref_id = channel_inbound_message.public_id`
- create a transcript-bearing `UserMessage`
- preserve `origin_payload` fields needed for audit and routing

Suggested `origin_payload` fields:

- `platform`
- `channel_account_id`
- `channel_session_id`
- `external_message_id`
- `external_sender_id`
- `peer_kind`
- `peer_id`
- `thread_key`
- `merged_inbound_message_ids`

## During-Generation Behavior

This is the most important behavioral requirement for IM.

CoreMatrix already has:

- `Turns::SteerCurrentInput`
- `Conversation.during_generation_input_policy`
- `Workflows::Scheduler.apply_during_generation_policy`

That existing model should be reused.

### Required IM Behavior

1. If there is no active/queued work:
   - batch a short burst if needed
   - create a new channel-ingress turn
2. If there is an active turn and no transcript side-effect boundary has been
   crossed:
   - steer the current turn
3. If the active turn has crossed the side-effect boundary:
   - follow the turn's frozen during-generation input policy
   - default remains `queue`

### Required Refactor

The current queued follow-up path still assumes `manual_user` provenance. That
must be generalized so IM-origin follow-up work preserves channel provenance
instead of writing owner-user provenance.

This affects:

- steer-to-queue transition
- queued follow-up turn creation
- any scheduler path that materializes a queued input after an active run

## Continuous Input And Batching

IM conversations frequently send several short messages in sequence:

- "我想做……"
- "突然想到得考虑……"
- "不对"

The design should treat those as immutable ingress facts first and transcript
inputs second.

### V1 Rules

- every external update becomes one `ChannelInboundMessage`
- transcript input may represent one or more merged inbound messages
- v1 uses deterministic merge rules only
- v1 does not use LLM rewriting

### Merge Windows

1. `pre-turn merge window`
   - short quiet-period buffering before opening a new turn
2. `same-turn steer window`
   - use `Turns::SteerCurrentInput` before side effects are committed
3. `post-boundary follow-up window`
   - create queued follow-up work using frozen policy

### Future LLM Use

If LLM is added later, it should first appear as an advisory classifier for:

- `new_turn`
- `steer`
- `queue`

It should not rewrite user text in early versions.

## Attachment And Media Handling

CoreMatrix already has:

- `MessageAttachment`
- execution snapshot `attachment_manifest`
- execution snapshot `model_input_attachments`
- runtime attachment request API

IM ingress should reuse that path.

### V1 Attachment Rules

1. Normalize platform media into a small modality vocabulary:
   - `image`
   - `audio`
   - `video`
   - `file`
2. Download/store the media in CoreMatrix-managed storage
3. Attach resulting files to the transcript-bearing `UserMessage`
4. Preserve raw ingress media facts even if the model cannot directly consume
   that modality

### Textless Media

`Message.content` is required, so media-only inbound messages must synthesize a
minimal textual body such as:

- `User sent 1 image attachment.`

### Optional Media Understanding

Aligning with OpenClaw, the system may optionally produce a short digest before
the main reply pipeline, but:

- the original attachments must still be preserved
- digest failure must not block the turn
- v1 can omit this stage entirely and leave the preprocessor slot empty

## Session Granularity

### DM

- one direct peer per `ChannelSession`

### Group / Channel

- one group/channel boundary per `ChannelSession`

### Thread / Topic

- one thread/topic per `ChannelSession`
- recommended default: one thread/topic maps to one conversation

This avoids one busy channel sharing a single transcript for unrelated topics.

## App-Facing Management Surface

All current management is user-scoped, not system-admin scoped.

The managing actor is the regular CoreMatrix user who owns the relevant
workspace/conversation scope.

Suggested resources:

### `ChannelAccounts`

- create/update/disable bot account configurations
- bind account ownership to the managing user scope

### `ChannelPairingRequests`

- list pending DM approvals
- approve/reject/expire requests

### `ChannelSessions`

- inspect session bindings
- rebind/unbind/freeze
- inspect last activity and last sender snapshot

### `ChannelPolicies`

- DM policy
- sender allowlist
- group/channel allowlist
- mention gating
- per-thread routing policy

### `ConversationChannelBindings`

- conversation-centric view of attached channel sessions

## Security And Reliability

Minimum v1 guarantees:

- verified machine ingress boundary
- per-message idempotency
- no unauthorized message enters the turn system
- immutable inbound fact recording
- external sender never becomes CoreMatrix owner identity
- delivery failure does not roll back completed transcript state
- raw payloads and outbound attempts remain auditable

## Non-Goals

This design intentionally does not include:

- LLM rewrite of user input
- global system-admin governance UI
- sender-to-CoreMatrix-user identity mapping
- rich cross-platform UI abstraction for buttons/cards
- group member directory sync
- advanced OCR/captioning/media summarization in v1
- voice-mode or live-call transport in v1

## Telegram-First Delivery Strategy

Telegram is the first target because it validates the entire ingress shape with
less platform lifecycle complexity than Discord.

### Phase 1: Shared Ingress Substrate

Build:

- shared ingress contracts
- channel-ingress turn entry
- provenance-safe follow-up/queue path
- attachment materialization

### Phase 2: Telegram DM MVP

Build:

- Telegram account adapter
- DM pairing
- text + image/file attachment ingress
- short burst merge
- steer vs queue behavior
- outbound reply delivery
- minimal app management surface

### Phase 3: Discord DM

Reuse the shared substrate and add only Discord-specific normalization and
outbound behavior.

### Phase 4: Group / Thread Expansion

Add:

- mention gating
- group/channel policies
- thread/topic session resolution
- expanded management views

## Decision Summary

CoreMatrix should implement IM as a first-class external ingress and delivery
boundary:

- not as a special case inside `Conversation`
- not as a reuse of browser `AppAPI`
- not as a thin transport wrapper around `manual_user`

The product object remains the conversation. `IngressAPI` owns how external
systems enter that product object, and `AppAPI` owns how users manage those
bindings.
