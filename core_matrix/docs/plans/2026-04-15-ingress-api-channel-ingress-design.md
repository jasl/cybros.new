# IngressAPI Channel Ingress Design

> Status note: this document describes the incremental ingress design on top of
> the current CoreMatrix topology. If
> `2026-04-15-workspace-agent-decoupling-design.md` is adopted first, rebase
> this design on `WorkspaceAgent` and `IngressBinding`.

## Goal

Add a first-class external ingress boundary to CoreMatrix so chat-style systems
such as Telegram and Weixin can act as product entry points without being
modeled as `Conversation` itself.

Telegram DM is the first delivery target. The same substrate must also support:

- a Weixin direct-message connector implemented behind `lib/claw_bot_sdk`
- multiple channel accounts per user by design
- later group/thread expansion
- future non-IM external ingress sources under the same `IngressAPI` surface

## Context And Constraints

- `Conversation` remains the CoreMatrix product object.
- External platforms bind to a `Conversation`; they do not become the
  conversation.
- External senders must not be treated as the same role as the CoreMatrix
  conversation owner.
- Existing `AppAPI` browser/session boundaries are not suitable for machine
  ingress.
- The user-facing config root should be workspace-scoped so users do not choose
  both agent and workspace manually; the workspace already pins the agent.
- CoreMatrix already has turn, workflow, attachment, runtime-broadcast, and
  during-generation input-policy primitives that should be reused.
- Not every channel will arrive through an HTTP webhook. Telegram can; Weixin
  likely cannot.
- `references/` material is comparative input only. It informs the design but
  is not the implementation source of truth.

## Comparative Findings

### OpenClaw

OpenClaw models IM integration as a channel-plugin boundary, not as assistant
core logic. The shared builder composes channel plugins from explicit surfaces
such as security, pairing, threading, and outbound delivery.

This is the right direction for CoreMatrix:

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
application services and connector runtimes, not in transport adapters.

### `telegram-bot-ruby`

`telegram-bot-ruby` is a good fit for Telegram because it provides a Bot API
wrapper and typed payload support while still letting CoreMatrix own the webhook
controller and routing model.

Important implications:

- CoreMatrix should implement its own webhook controller
- the gem should be used for Bot API calls such as `setWebhook`, `sendMessage`,
  `sendPhoto`, `sendDocument`, and `getFile`
- webhook verification, envelope normalization, batching, pairing, and turn
  entry still belong to CoreMatrix

### `openclaw-weixin`

The Weixin plugin is structurally different from Telegram:

- inbound messages come from a long-poll HTTP JSON API, not a public webhook
- account login is QR-based and produces account-local credentials
- outbound replies require a per-peer `context_token`
- media send/download depends on CDN-specific upload/download flows and
  encryption concerns

CoreMatrix should borrow the transport decomposition, but should not copy its
filesystem state-store conventions. The CoreMatrix source of truth must stay in
Rails models and services. The Weixin-specific protocol and crypto mechanics
should live behind `lib/claw_bot_sdk`.

## Architecture

The system is split into two public surfaces plus one internal transport bridge:

- `IngressAPI`
  - machine-facing external input boundary
  - owns normalization, dedupe, routing, and turn-entry orchestration
  - can be entered through webhook controllers or connector/poller runtimes
- `AppAPI`
  - user-facing management surface
  - owns workspace-scoped ingress endpoint setup, channel account config,
    pairing approval, allowlists, session binding, and conversation association
    management
- `lib/claw_bot_sdk`
  - internal protocol bridge for transports that do not have a suitable native
    Ruby SDK or webhook-friendly shape
  - v1 first use: Weixin

Layering:

- presentation
  - `IngressAPI::*Controller`
  - `AppAPI::*Controller`
  - connector jobs/runners for poll-based channels
- application
  - ingress orchestration
  - authorization
  - channel routing
  - turn entry
  - outbound delivery
- domain
  - ingress endpoints
  - channel accounts
  - sessions
  - pairing requests
  - inbound facts
  - outbound deliveries
- infrastructure
  - Telegram client
  - Weixin bridge client
  - media downloaders
  - webhook verification
  - long-poll checkpoints

## Workspace-Scoped Entry Root

The primary user-facing configuration object should be a workspace-scoped
`IngressEndpoint`.

This solves several problems:

- users manage ingress where the conversations will live
- the workspace already pins the agent, so users only choose an optional
  execution runtime override
- each endpoint gets a stable public ingress id for Telegram webhook URLs and
  for poll-based connector routing
- multiple Telegram bots or Weixin accounts are supported simply by creating
  multiple ingress endpoints under the same workspace

In v1, one `IngressEndpoint` should own one active `ChannelAccount`.

## Transport Shapes

### Telegram

Telegram is a webhook-style transport:

- inbound shape
  - `POST /ingress_api/telegram/endpoints/:public_ingress_id/updates`
- transport library
  - `gem "telegram-bot-ruby"`
- outbound shape
  - Bot API calls through the gem
- attachment shape
  - resolve file metadata and download through Bot API

Telegram-specific code should live mostly under:

- `app/controllers/ingress_api/telegram`
- `app/services/ingress_api/telegram`
- `app/services/channel_deliveries`

### Weixin

Weixin should be treated as a connector-driven transport:

- inbound shape
  - an account-scoped poller or runner fetches updates and feeds normalized
    envelopes into `IngressAPI::ReceiveEvent`
- transport bridge
  - `lib/claw_bot_sdk/weixin`
- outbound shape
  - bridge-mediated `sendmessage`, `getuploadurl`, `sendtyping`, and related
    protocol calls
- attachment shape
  - bridge-mediated media download/upload and protocol-specific crypto

After normalization, the Rails ingress pipeline should be identical.

## Identity Model

Three identities must stay separate:

1. `Conversation owner`
   - the CoreMatrix user/workspace owner
   - decides product ownership, visibility, billing, and management rights
2. `Channel account`
   - the Telegram bot credentials or Weixin logged-in account used for transport
   - decides which external identity sends messages
3. `External sender`
   - the Telegram user or Weixin peer who sent the input
   - does not become a CoreMatrix `User`

Transcript role semantics stay unchanged:

- `Message.role = user` still means "user-side input to the agent"
- it does not mean "CoreMatrix owner user authored this message"

Turn provenance must therefore stop using `manual_user` semantics for IM ingress.

## Core Domain Objects

### `IngressEndpoint`

Represents one workspace-scoped managed external entrypoint.

Suggested fields:

- `public_id`
- `installation_id`
- `owner_user_id`
- `workspace_id`
- optional `default_execution_runtime_id`
- `kind`
- `lifecycle_state`
- `public_ingress_id`
- `ingress_secret_digest`
- `routing_policy_payload`
- `manual_entry_policy`

Notes:

- the endpoint's workspace determines the agent
- `default_execution_runtime_id` is the only runtime choice a user makes here
- `public_id` is the resource identity used in AppAPI payloads and nested
  resource lookup
- `public_ingress_id` is a separate opaque routing token used in external URLs
  or poller configuration
- `ingress_secret_digest` stores a secret used to verify external requests
- `manual_entry_policy` should default to allowing both app-side and external
  input in v1
- do not overload `Conversation.addressability` for "external-only input"

### `ChannelAccount`

Represents one configured external bot/app/account attached to one ingress
endpoint.

Suggested fields:

- `public_id`
- `installation_id`
- `ingress_endpoint_id`
- `owner_user_id`
- `platform`
- `driver`
- `transport_kind`
- `label`
- `lifecycle_state`
- `credential_ref_payload`
- `config_payload`
- `runtime_state_payload`

Notes:

- `driver` distinguishes `telegram_bot_api` from `claw_bot_sdk_weixin`
- `transport_kind` distinguishes `webhook` from `poller`
- `runtime_state_payload` can hold account-scoped live state such as QR login
  progress or a poll cursor
- v1 should enforce one active `ChannelAccount` per `IngressEndpoint`

### `ChannelSession`

Represents one external conversational boundary bound to one CoreMatrix
conversation at a time.

Suggested fields:

- `public_id`
- `installation_id`
- `ingress_endpoint_id`
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

- `channel_account_id + peer_kind + peer_id + coalesce(thread_key, '')`

Notes:

- `session_metadata` carries transport-specific reply state
- for Weixin this includes the latest valid `context_token`
- for Telegram this may include reply-thread targeting metadata later

### `ChannelPairingRequest`

Represents DM first-contact approval flow.

Suggested fields:

- `public_id`
- `installation_id`
- `ingress_endpoint_id`
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
- `ingress_endpoint_id`
- `channel_account_id`
- `channel_session_id`
- optional `conversation_id`
- `external_event_key`
- `external_message_key`
- `external_sender_id`
- `sender_snapshot`
- `content`
- `normalized_payload`
- `raw_payload`
- `received_at`

Suggested uniqueness:

- `channel_account_id + external_event_key`

### `ChannelDelivery`

Tracks outbound CoreMatrix delivery back to the external platform.

Suggested fields:

- `public_id`
- `installation_id`
- `ingress_endpoint_id`
- `channel_account_id`
- `channel_session_id`
- `conversation_id`
- optional `turn_id`
- optional `message_id`
- `external_message_key`
- `reply_to_external_message_key`
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
- `driver`
- `ingress_endpoint_public_id`
- `channel_account_public_id`
- `external_event_key`
- `external_message_key`
- `peer_kind`
- `peer_id`
- `thread_key`
- `external_sender_id`
- `sender_snapshot`
- `text`
- `attachments`
- `reply_to_external_message_key`
- `occurred_at`
- `transport_metadata`
- `raw_payload`

### `IngressContext`

Mutable per-request orchestration context.

Suggested fields:

- `ingress_endpoint`
- `channel_session`
- `conversation`
- `active_turn`
- `authorization_result`
- `coalesced_message_ids`
- `attachment_records`
- `media_digest`
- `dispatch_decision`
- `origin_payload`

## Idempotency And External Keys

Inbound ingest and reply threading should not rely on one overloaded "message
id" field. The ingress contract should keep two external key types:

- `external_event_key`
  - the ingest idempotency key
- `external_message_key`
  - the stable message reference used for reply targeting or later audit

Recommended mapping:

- Telegram
  - `external_event_key = "telegram:update:<update_id>"`
  - `external_message_key = "telegram:chat:<chat_id>:message:<message_id>"`
- Weixin
  - `external_event_key = "weixin:message:<message_id>"`
  - `external_message_key = "weixin:message:<message_id>"`
  - if `message_id` is missing, fall back to a normalized
    `session_id/seq` compound key

This keeps dedupe correct while still preserving the platform's reply target.

## Middleware And Preprocessor Pipeline

The ingress stack should be explicit and ordered.

### Middleware

These are transport-agnostic cross-cutting steps:

1. `CaptureRawPayload`
   - preserve raw bytes/body for audit and signature correctness
2. `VerifyRequest`
   - verify webhook signature or connector credentials
   - identify the `IngressEndpoint` and `ChannelAccount`
3. `AdapterNormalizeEnvelope`
   - transport adapter payload -> `IngressEnvelope`
   - this is a pipeline stage, not necessarily a standalone middleware class
4. `DeduplicateInbound`
   - enforce one normalized inbound fact per external event key
5. `RateLimit`
   - optional later v1 guardrail at account/platform boundary
   - not required for the first implementation slice

### Preprocessors

These decide how the input becomes CoreMatrix work:

1. `ResolveChannelSession`
   - bind external peer/thread to `ChannelSession`
2. `AuthorizeAndPair`
   - DM pairing, allowlists, mention gates, sender checks
3. `CreateOrBindConversation`
   - resolve the bound conversation or create one from the ingress endpoint
4. `CoalesceBurst`
   - merge client-side text splits and short burst input windows
5. `MaterializeAttachments`
   - download/store platform media and create attachment records
6. `OptionalMediaUnderstanding`
   - optional inbound media digest before reply pipeline
   - failure must not block normal processing
7. `ResolveDispatchDecision`
   - decide `new_turn`, `steer_current_turn`, `queue_follow_up`, or `reject`
8. `MaterializeTurnEntry`
   - create immutable ingress facts and enter the turn system
9. `ScheduleOutboundBinding`
   - preserve reply/thread/outbound cursor context for later delivery

Ordering matters:

- auth decisions happen before turn entry
- conversation creation happens before turn entry
- attachments are materialized before the turn snapshot is built
- dispatch decision happens after batching and attachment materialization

## Transport Adapter Boundary

After normalization, Telegram and Weixin should flow through the same
`IngressAPI::ReceiveEvent` path. The transport edge should implement a small
adapter contract:

- identify or verify the ingress endpoint and channel account
- normalize inbound payload to `IngressEnvelope`
- download inbound media when asked
- send outbound text/media when asked
- expose transport-specific delivery metadata needed for future replies

### Telegram Adapter

- implemented directly in Rails app/services
- uses `telegram-bot-ruby` for Bot API requests
- owns webhook JSON normalization and Bot API file fetch/send behavior
- identifies the ingress endpoint from `public_ingress_id` in the webhook path
- verifies the request with an endpoint-scoped secret token

### Weixin Adapter

- implemented through `lib/claw_bot_sdk/weixin`
- owns long-polling, QR login flow, `context_token` handling, and CDN/media
  protocol details
- should expose a Ruby-facing client that the Rails application can call without
  importing TypeScript code or OpenClaw runtime assumptions

## First-Contact Routing And Conversation Creation

When an inbound DM reaches an approved, unbound session, CoreMatrix should
create a new root conversation from the ingress endpoint.

Routing rules:

- workspace = `IngressEndpoint.workspace`
- agent = `IngressEndpoint.workspace.agent`
- execution runtime =
  - `IngressEndpoint.default_execution_runtime`
  - otherwise `Workspace.default_execution_runtime`
  - otherwise the agent default runtime

Conversation rules:

- create a normal interactive root conversation
- default to `owner_addressable` in v1
- allow app-side and external-side input concurrently in v1
- if later product needs "external-only input", add a separate manual-entry
  policy on `IngressEndpoint` or `ChannelSession`

Implementation note:

- new channel-ingress entry must enqueue the same workflow bootstrap path as
  ordinary user entry
- if title bootstrap should apply to channel-created conversations, current
  `manual_user`-only title bootstrap logic must be generalized explicitly

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
- materialize workflow bootstrap state in the same way as ordinary accepted user
  turns

Suggested `origin_payload` fields:

- `platform`
- `driver`
- `ingress_endpoint_id`
- `channel_account_id`
- `channel_session_id`
- `external_message_key`
- `external_sender_id`
- `peer_kind`
- `peer_id`
- `thread_key`
- `merged_inbound_message_ids`

## During-Generation Behavior

CoreMatrix already has:

- `Turns::SteerCurrentInput`
- `Conversation.during_generation_input_policy`
- `Workflows::Scheduler.apply_during_generation_policy`

That model should be reused.

Required IM behavior:

1. if there is no active/queued work:
   - batch a short burst if needed
   - create a new channel-ingress turn
2. if there is an active turn and no transcript side-effect boundary has been
   crossed:
   - steer the current turn
3. if the active turn has crossed the side-effect boundary:
   - follow the turn's frozen during-generation input policy
   - default remains `queue`

Required refactor:

- queued follow-up creation must preserve channel provenance instead of falling
  back to `manual_user`
- `Turn.origin_kind` must be expanded to include `channel_ingress`

## Continuous Input And Batching

IM conversations frequently send several short messages in sequence:

- "我想做……"
- "突然想到得考虑……"
- "不对"

The design should treat those as immutable ingress facts first and transcript
inputs second.

V1 rules:

- every external update becomes one `ChannelInboundMessage`
- transcript input may represent one or more merged inbound messages
- v1 uses deterministic merge rules only
- v1 does not use LLM rewriting

Merge windows:

1. `pre-turn merge window`
   - short quiet-period buffering before opening a new turn
2. `same-turn steer window`
   - use `Turns::SteerCurrentInput` before side effects are committed
3. `post-boundary follow-up window`
   - create queued follow-up work using frozen policy

Future LLM use, if added later, should first appear as an advisory classifier
for `new_turn / steer / queue`, not as a text rewriter.

## Attachment And Media Handling

CoreMatrix already has:

- `MessageAttachment`
- execution snapshot `attachment_manifest`
- execution snapshot `model_input_attachments`
- runtime attachment request API

IM ingress should reuse that path.

V1 rules:

1. normalize platform media into a small modality vocabulary
   - `image`
   - `audio`
   - `video`
   - `file`
2. download/store the media in CoreMatrix-managed storage
3. attach resulting files to the transcript-bearing `UserMessage`
4. preserve raw ingress media facts even if the model cannot directly consume
   that modality

Textless media:

- `Message.content` is required, so media-only inbound messages must synthesize
  a minimal textual body such as `User sent 1 image attachment.`

Weixin media boundary:

- CDN upload/download
- encryption/decryption
- media-type mapping needed by the upstream API

These should stay inside `lib/claw_bot_sdk`.

## Session Granularity

### DM

- one direct peer per `ChannelSession`

### Group / Channel

- one group/channel boundary per `ChannelSession`

### Thread / Topic

- one thread/topic per `ChannelSession`
- recommended default: one thread/topic maps to one conversation

## App-Facing Management Surface

All current management is user-scoped, not system-admin scoped.

The managing actor is the regular CoreMatrix user who owns the relevant
workspace/conversation scope.

Suggested resources:

### `Workspaces::IngressEndpoints`

- create/update/disable ingress endpoints
- choose the endpoint default execution runtime
- expose the public ingress id and platform-specific setup instructions
- expose the attached channel account lifecycle

Examples:

- Telegram bot token rotation
- Weixin QR login start/reconnect/disconnect

### `IngressEndpoints::PairingRequests`

- list pending DM approvals
- approve/reject/expire requests

### `IngressEndpoints::Sessions`

- inspect session bindings
- rebind/unbind/freeze
- inspect last activity and last sender snapshot
- inspect transport-specific reply state

### `IngressEndpoints::Policies`

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
- per-event idempotency
- no unauthorized message enters the turn system
- immutable inbound fact recording
- external sender never becomes CoreMatrix owner identity
- delivery failure does not roll back completed transcript state
- raw payloads and outbound attempts remain auditable

## Verification Boundary

Telegram and Weixin both depend on live external accounts, remote APIs, and
network conditions. CoreMatrix should therefore split verification into two
layers:

- automated internal verification
  - unit tests
  - request tests
  - model tests
  - service integration tests
- manual transport validation
  - Telegram bot webhook setup and DM round-trip
  - Weixin QR login, poll loop, `context_token` persistence, and DM round-trip

The system should maximize deterministic internal coverage, but should not claim
a fully automated end-to-end acceptance path for these channels.

## Non-Goals

This design intentionally does not include:

- LLM rewrite of user input
- global system-admin governance UI
- sender-to-CoreMatrix-user identity mapping
- rich cross-platform UI abstraction for buttons/cards
- group member directory sync
- advanced OCR/captioning/media summarization in v1
- voice-mode or live-call transport in v1

## Delivery Strategy

### Phase 1: Shared Ingress Substrate

Build:

- workspace-scoped ingress endpoints
- shared ingress contracts
- transport adapter boundary
- channel-ingress turn entry
- provenance-safe follow-up/queue path
- attachment materialization

### Phase 2: Telegram DM MVP

Build:

- `telegram-bot-ruby` integration
- endpoint-scoped Telegram webhook controller
- endpoint-scoped webhook URL and secret verification
- DM pairing
- text + image/file attachment ingress
- short burst merge
- steer vs queue behavior
- outbound reply delivery
- minimal app management surface

### Phase 3: Weixin Direct Message Connector

Build:

- `lib/claw_bot_sdk/weixin`
- QR-login-aware account lifecycle
- endpoint-bound poll routing
- `context_token` persistence on channel sessions
- text + image/file attachment ingress
- outbound reply delivery through the bridge

### Phase 4: Group / Thread Expansion

Add:

- mention gating
- group/channel policies
- thread/topic session resolution
- expanded management views

### Phase 5: Future Channels

Reuse the same substrate for later transports such as Discord or other
open-platform callbacks.

## Decision Summary

CoreMatrix should implement IM as a first-class external ingress and delivery
boundary:

- not as a special case inside `Conversation`
- not as a reuse of browser `AppAPI`
- not as a thin transport wrapper around `manual_user`

The product object remains the conversation. `IngressAPI` owns how external
systems enter that product object, `AppAPI` owns how users manage those
bindings, and `lib/claw_bot_sdk` exists only where a transport-specific bridge
is necessary.
