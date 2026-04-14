# IngressAPI Telegram-First And Weixin Channel Ingress Implementation Plan

> Status note: this plan is the incremental path on the current topology. If
> `2026-04-15-workspace-agent-decoupling-implementation.md` is executed first,
> rebase this plan on `WorkspaceAgent`, `ChannelConnector`, and `IngressBinding`.

**Goal:** Add a first-class `IngressAPI` boundary and ship Telegram DM as the
first external conversation entry point for CoreMatrix, while keeping the
shared ingress substrate and data model ready for a Weixin direct-message
connector implemented through `lib/claw_bot_sdk`.

**Architecture:** Introduce a workspace-scoped `IngressEndpoint` root plus a
user-managed channel domain (`ChannelAccount`, `ChannelSession`,
`ChannelPairingRequest`, `ChannelInboundMessage`, `ChannelDelivery`) and a
provenance-safe channel-ingress turn path. Keep transport-specific logic in
`IngressAPI` adapters and preprocessors. Use `telegram-bot-ruby` for Telegram
Bot API access. Put Weixin protocol, QR login, long-polling, `context_token`
handling, and media transport behind `lib/claw_bot_sdk`.

**Tech Stack:** Ruby on Rails, Minitest, Active Record migrations, Active
Storage, Active Job, `telegram-bot-ruby`, existing CoreMatrix
turn/workflow/attachment infrastructure, and a Ruby bridge in
`lib/claw_bot_sdk` for Weixin.

**Verification Boundary:** Internal behavior should be covered by automated
tests. Live Telegram and Weixin transport round-trips cannot be fully automated
inside this repository and should be treated as manual integration work after
best-effort implementation.

---

### Task 1: Lock The Channel-Ingress Provenance, Bootstrap, And Follow-Up Rules With Failing Tests

**Files:**
- Create: `core_matrix/test/services/turns/start_channel_ingress_turn_test.rb`
- Modify: `core_matrix/test/services/turns/steer_current_input_test.rb`
- Modify: `core_matrix/test/services/turns/queue_follow_up_test.rb`
- Create: `core_matrix/test/integration/channel_ingress_follow_up_flow_test.rb`
- Modify: `core_matrix/test/jobs/conversations/metadata/bootstrap_title_job_test.rb`
- Reference: `core_matrix/app/models/turn.rb`
- Reference: `core_matrix/app/services/turns/accept_pending_user_turn.rb`
- Reference: `core_matrix/app/services/turns/steer_current_input.rb`
- Reference: `core_matrix/app/services/turns/queue_follow_up.rb`
- Reference: `core_matrix/app/services/workflows/scheduler.rb`
- Reference: `core_matrix/app/jobs/conversations/metadata/bootstrap_title_job.rb`

**Step 1: Write failing turn-entry tests**

Add a service test that expects `Turns::StartChannelIngressTurn` to:

- require an interactive conversation
- create an active turn with `origin_kind = "channel_ingress"`
- set `source_ref_type = "ChannelInboundMessage"`
- set `source_ref_id` to the inbound message `public_id`
- create a transcript-bearing `UserMessage`
- carry workflow bootstrap state equivalent to accepted user entry
- persist `origin_payload` with endpoint/session/message provenance

**Step 2: Extend steer and queued-follow-up tests**

Add failing expectations that:

- pre-boundary follow-up input on a channel-ingress turn stays on the same turn
  via `Turns::SteerCurrentInput`
- post-boundary follow-up input on a channel-ingress turn creates queued work
  without falling back to `manual_user` provenance
- queued turn `origin_payload` preserves the upstream ingress linkage

**Step 3: Add title-bootstrap coverage**

Cover the intended rule explicitly:

- either channel-ingress first turns should bootstrap titles
- or they should not, but the behavior must be intentional and documented

This prevents silent drift because current title bootstrap logic is
`manual_user`-only.

**Step 4: Run the targeted tests and verify they fail**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/turns/start_channel_ingress_turn_test.rb \
  test/services/turns/steer_current_input_test.rb \
  test/services/turns/queue_follow_up_test.rb \
  test/integration/channel_ingress_follow_up_flow_test.rb \
  test/jobs/conversations/metadata/bootstrap_title_job_test.rb
```

### Task 2: Add The Workspace-Scoped Ingress Schema And Models

**Files:**
- Create: `core_matrix/db/migrate/20260415090000_create_ingress_endpoints.rb`
- Create: `core_matrix/db/migrate/20260415090100_create_channel_accounts.rb`
- Create: `core_matrix/db/migrate/20260415090200_create_channel_sessions.rb`
- Create: `core_matrix/db/migrate/20260415090300_create_channel_pairing_requests.rb`
- Create: `core_matrix/db/migrate/20260415090400_create_channel_inbound_messages.rb`
- Create: `core_matrix/db/migrate/20260415090500_create_channel_deliveries.rb`
- Create: `core_matrix/app/models/ingress_endpoint.rb`
- Create: `core_matrix/app/models/channel_account.rb`
- Create: `core_matrix/app/models/channel_session.rb`
- Create: `core_matrix/app/models/channel_pairing_request.rb`
- Create: `core_matrix/app/models/channel_inbound_message.rb`
- Create: `core_matrix/app/models/channel_delivery.rb`
- Modify: `core_matrix/docs/behavior/identifier-policy.md`
- Create: `core_matrix/test/models/ingress_endpoint_test.rb`
- Create: `core_matrix/test/models/channel_account_test.rb`
- Create: `core_matrix/test/models/channel_session_test.rb`
- Create: `core_matrix/test/models/channel_pairing_request_test.rb`
- Create: `core_matrix/test/models/channel_inbound_message_test.rb`
- Create: `core_matrix/test/models/channel_delivery_test.rb`

**Step 1: Write failing model tests**

Add tests for:

- workspace ownership consistency on `IngressEndpoint`
- endpoint public ingress ids are unique
- endpoint secrets are stored by digest, not plaintext
- one active channel account per ingress endpoint in v1
- unique session boundary per
  `channel_account_id + peer_kind + peer_id + normalized_thread_key`
- unique inbound event per `channel_account_id + external_event_key`
- one active pending pairing request per sender/account
- public-id-only external references in JSON payloads and API-facing helpers

**Step 2: Write the migrations**

Add tables and indexes for:

- `ingress_endpoints`
- `channel_accounts`
- `channel_sessions`
- `channel_pairing_requests`
- `channel_inbound_messages`
- `channel_deliveries`

Required schema shape:

- `ingress_endpoints` must carry `workspace_id`,
  optional `default_execution_runtime_id`, `public_ingress_id`,
  `ingress_secret_digest`, and routing/manual-entry policy payloads
- `channel_accounts` must carry `platform`, `driver`, `transport_kind`, and a
  JSON `runtime_state_payload`
- `channel_sessions` must carry JSON `session_metadata`
- external references surfaced outside the database must use `public_id`, not
  bigint ids
- machine-ingress transport routes must use `public_ingress_id`, not the record
  `public_id`
- DM-safe uniqueness must not rely on nullable `thread_key` uniqueness

**Step 3: Implement the models**

Add:

- associations
- validations
- minimal enums for lifecycle/binding/delivery states
- helpers for issuing endpoint public ingress ids and secret tokens
- JSON normalization where required

Keep models small. Business orchestration stays in services.

**Step 4: Run the schema and model tests**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
PARALLEL_WORKERS=1 bin/rails test \
  test/models/ingress_endpoint_test.rb \
  test/models/channel_account_test.rb \
  test/models/channel_session_test.rb \
  test/models/channel_pairing_request_test.rb \
  test/models/channel_inbound_message_test.rb \
  test/models/channel_delivery_test.rb
```

### Task 3: Add Workspace-Scoped AppAPI CRUD For Ingress Endpoints

**Files:**
- Modify: `core_matrix/config/routes.rb`
- Create: `core_matrix/app/controllers/app_api/workspaces/ingress_endpoints_controller.rb`
- Create: `core_matrix/app/controllers/app_api/workspaces/ingress_endpoints/pairing_requests_controller.rb`
- Create: `core_matrix/app/controllers/app_api/workspaces/ingress_endpoints/sessions_controller.rb`
- Create: `core_matrix/test/requests/app_api/workspaces/ingress_endpoints_controller_test.rb`
- Create: `core_matrix/test/requests/app_api/workspaces/ingress_endpoints/pairing_requests_controller_test.rb`
- Create: `core_matrix/test/requests/app_api/workspaces/ingress_endpoints/sessions_controller_test.rb`

**Step 1: Write failing request tests**

Cover:

- ingress endpoints are created under `/app_api/workspaces/:workspace_id/...`
- users only choose execution runtime at endpoint creation time
- the response returns the endpoint public ingress id and setup metadata
- endpoint resources are user-scoped through the workspace
- pairing requests and sessions are nested under the endpoint owner

**Step 2: Add the routes**

Use nested routes aligned with existing AppAPI style:

- `/app_api/workspaces/:workspace_id/ingress_endpoints`
- `/app_api/workspaces/:workspace_id/ingress_endpoints/:ingress_endpoint_id/pairing_requests`
- `/app_api/workspaces/:workspace_id/ingress_endpoints/:ingress_endpoint_id/sessions`

Here `:ingress_endpoint_id` continues the normal CoreMatrix convention and
resolves the endpoint resource `public_id`. The machine-facing transport route
uses the separate `public_ingress_id`.

**Step 3: Implement the controllers**

The endpoint CRUD should let users:

- create/update/disable an endpoint
- choose an optional default execution runtime
- inspect the public ingress id
- inspect any platform-specific setup instructions
- approve/reject pairing
- inspect and rebind/unbind sessions

In v1, this is the primary management surface. Do not expose free-floating
channel-account CRUD at the top level.

**Step 4: Run the targeted tests**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/requests/app_api/workspaces/ingress_endpoints_controller_test.rb \
  test/requests/app_api/workspaces/ingress_endpoints/pairing_requests_controller_test.rb \
  test/requests/app_api/workspaces/ingress_endpoints/sessions_controller_test.rb
```

### Task 4: Build The Shared `IngressAPI` Contracts, Endpoint Resolution, And Pipeline Skeleton

**Files:**
- Modify: `core_matrix/config/routes.rb`
- Create: `core_matrix/app/controllers/ingress_api/base_controller.rb`
- Create: `core_matrix/app/services/ingress_api/envelope.rb`
- Create: `core_matrix/app/services/ingress_api/context.rb`
- Create: `core_matrix/app/services/ingress_api/result.rb`
- Create: `core_matrix/app/services/ingress_api/receive_event.rb`
- Create: `core_matrix/app/services/ingress_api/transport_adapter.rb`
- Create: `core_matrix/app/services/ingress_api/middleware/capture_raw_payload.rb`
- Create: `core_matrix/app/services/ingress_api/middleware/verify_request.rb`
- Create: `core_matrix/app/services/ingress_api/middleware/deduplicate_inbound.rb`
- Create: `core_matrix/app/services/ingress_api/preprocessors/resolve_channel_session.rb`
- Create: `core_matrix/app/services/ingress_api/preprocessors/authorize_and_pair.rb`
- Create: `core_matrix/app/services/ingress_api/preprocessors/create_or_bind_conversation.rb`
- Create: `core_matrix/app/services/ingress_api/preprocessors/coalesce_burst.rb`
- Create: `core_matrix/app/services/ingress_api/preprocessors/materialize_attachments.rb`
- Create: `core_matrix/app/services/ingress_api/preprocessors/resolve_dispatch_decision.rb`
- Create: `core_matrix/test/services/ingress_api/receive_event_test.rb`
- Create: `core_matrix/test/services/ingress_api/preprocessors/create_or_bind_conversation_test.rb`

**Step 1: Write failing orchestration tests**

Add tests that expect:

- one normalized inbound event becomes one `IngressAPI::Envelope`
- middleware/preprocessors run in the designed order
- duplicate external event keys are ignored idempotently
- the same `ReceiveEvent` service can be called from an HTTP controller or a
  connector runner
- when an approved session is unbound, conversation creation uses
  `IngressEndpoint.workspace` and resolves runtime from the endpoint/workspace
  defaults

**Step 2: Add the `IngressAPI` base surface**

Create:

- a separate namespace under `config/routes.rb` for machine ingress
- an `IngressAPI::BaseController` that does not inherit browser-session
  assumptions from `AppAPI`

**Step 3: Add envelope/context/result value objects and orchestration service**

Implement:

- `IngressAPI::Envelope`
- `IngressAPI::Context`
- `IngressAPI::Result`
- `IngressAPI::ReceiveEvent`

`ReceiveEvent` should execute middleware/preprocessors in order and return a
small result object indicating whether the event was rejected, batched, or
materialized into turn work.

**Step 4: Add the adapter boundary now**

Introduce `IngressAPI::TransportAdapter` so transport-specific code can plug in
without changing the pipeline contract.

The boundary should cover:

- ingress endpoint and account verification/identification
- payload normalization into `IngressEnvelope`
- inbound media fetch
- outbound text/media send

**Step 5: Run the targeted tests**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/ingress_api/receive_event_test.rb \
  test/services/ingress_api/preprocessors/create_or_bind_conversation_test.rb
```

### Task 5: Add `Turns::StartChannelIngressTurn`, Provenance-Safe Follow-Up, And Bootstrap Wiring

**Files:**
- Modify: `core_matrix/app/models/turn.rb`
- Create: `core_matrix/app/services/turns/start_channel_ingress_turn.rb`
- Create: `core_matrix/app/services/turns/queue_channel_follow_up.rb`
- Create: `core_matrix/app/services/ingress_api/materialize_turn_entry.rb`
- Modify: `core_matrix/app/services/turns/steer_current_input.rb`
- Modify: `core_matrix/app/services/workflows/scheduler.rb`
- Modify: `core_matrix/app/services/turns/queue_follow_up.rb`
- Modify: `core_matrix/app/jobs/conversations/metadata/bootstrap_title_job.rb`
- Modify: `core_matrix/docs/behavior/turn-entry-and-selector-state.md`
- Modify: `core_matrix/docs/behavior/conversation-structure-and-lineage.md`

**Step 1: Implement the new turn-entry service**

Mirror the accepted user-turn bootstrap contract where needed:

- active turn creation
- input message creation
- workflow bootstrap fields
- selection-state projection
- latest-anchor refresh

Do not copy `manual_user` provenance.

**Step 2: Add a dedicated channel follow-up service**

Create `Turns::QueueChannelFollowUp` so the post-boundary path can preserve:

- `origin_kind = "channel_ingress"`
- `source_ref_type = "ChannelInboundMessage"`
- upstream endpoint/session/message linkage in `origin_payload`

Keep `Turns::QueueFollowUp` for ordinary owner-user entry.

**Step 3: Route scheduler policy decisions by turn origin**

Update `Workflows::Scheduler.apply_during_generation_policy` so:

- user-origin turns still queue owner-user follow-up work
- channel-origin turns queue channel-origin follow-up work

**Step 4: Make bootstrap behavior explicit**

Implement `IngressAPI::MaterializeTurnEntry` so channel-created turns:

- trigger workflow materialization
- refresh conversation anchors
- intentionally opt in or out of title bootstrap

Do not leave this as implicit controller behavior.

**Step 5: Run the targeted tests**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/turns/start_channel_ingress_turn_test.rb \
  test/services/turns/steer_current_input_test.rb \
  test/services/turns/queue_follow_up_test.rb \
  test/integration/channel_ingress_follow_up_flow_test.rb \
  test/jobs/conversations/metadata/bootstrap_title_job_test.rb
```

### Task 6: Integrate Telegram Transport With `telegram-bot-ruby`

**Files:**
- Modify: `core_matrix/Gemfile`
- Modify: `core_matrix/Gemfile.lock`
- Modify: `core_matrix/config/routes.rb`
- Create: `core_matrix/app/controllers/ingress_api/telegram/updates_controller.rb`
- Create: `core_matrix/app/services/ingress_api/telegram/client.rb`
- Create: `core_matrix/app/services/ingress_api/telegram/normalize_update.rb`
- Create: `core_matrix/app/services/ingress_api/telegram/download_attachment.rb`
- Create: `core_matrix/app/services/ingress_api/telegram/verify_request.rb`
- Create: `core_matrix/app/services/channel_deliveries/send_telegram_reply.rb`
- Create: `core_matrix/test/requests/ingress_api/telegram/updates_controller_test.rb`
- Create: `core_matrix/test/services/ingress_api/telegram/client_test.rb`
- Create: `core_matrix/test/services/ingress_api/telegram/normalize_update_test.rb`
- Create: `core_matrix/test/services/ingress_api/telegram/download_attachment_test.rb`
- Create: `core_matrix/test/services/ingress_api/telegram/verify_request_test.rb`
- Create: `core_matrix/test/services/channel_deliveries/send_telegram_reply_test.rb`

**Step 1: Add the gem and lock the boundary**

Add `gem "telegram-bot-ruby"` and keep the responsibility split explicit:

- webhook server remains CoreMatrix code
- Bot API requests go through the gem
- the gem does not own session, pairing, batching, or routing behavior

**Step 2: Implement endpoint-scoped webhook entry**

Add:

- `POST /ingress_api/telegram/endpoints/:public_ingress_id/updates`

Request verification should:

- resolve the ingress endpoint from `public_ingress_id` in the path
- resolve the attached Telegram channel account
- verify `X-Telegram-Bot-Api-Secret-Token` against the endpoint secret

**Step 3: Normalize Telegram updates with explicit key mapping**

Normalize into the shared envelope shape with:

- `external_event_key = "telegram:update:<update_id>"`
- `external_message_key = "telegram:chat:<chat_id>:message:<message_id>"`
- sender/chat/thread info
- attachment descriptors
- reply target metadata

**Step 4: Implement attachment download/storage**

Add a Telegram adapter service that:

- fetches Bot API file metadata and content
- stores files through Active Storage-backed `MessageAttachment`
- classifies modality as `image`, `audio`, `video`, or `file`

Keep v1 synchronous and deterministic.

**Step 5: Implement outbound delivery through the gem**

Add `SendTelegramReply` so outbound delivery uses `telegram-bot-ruby` for:

- `sendMessage`
- `sendPhoto`
- `sendDocument`
- `getFile` support where needed for attachment download
- `setWebhook` helper logic if later surfaced in setup tooling

**Step 6: Run the targeted tests**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/requests/ingress_api/telegram/updates_controller_test.rb \
  test/services/ingress_api/telegram/client_test.rb \
  test/services/ingress_api/telegram/normalize_update_test.rb \
  test/services/ingress_api/telegram/download_attachment_test.rb \
  test/services/ingress_api/telegram/verify_request_test.rb \
  test/services/channel_deliveries/send_telegram_reply_test.rb
```

### Task 7: Implement Telegram DM Pairing, Conversation Creation, Dispatch, And Delivery

**Files:**
- Modify: `core_matrix/app/services/ingress_api/preprocessors/resolve_channel_session.rb`
- Modify: `core_matrix/app/services/ingress_api/preprocessors/authorize_and_pair.rb`
- Modify: `core_matrix/app/services/ingress_api/preprocessors/coalesce_burst.rb`
- Modify: `core_matrix/app/services/ingress_api/preprocessors/materialize_attachments.rb`
- Modify: `core_matrix/app/services/ingress_api/preprocessors/resolve_dispatch_decision.rb`
- Modify: `core_matrix/app/services/ingress_api/receive_event.rb`
- Create: `core_matrix/app/services/channel_deliveries/dispatch_conversation_output.rb`
- Modify: `core_matrix/app/services/provider_execution/persist_turn_step_success.rb`
- Create: `core_matrix/test/services/ingress_api/preprocessors/authorize_and_pair_test.rb`
- Create: `core_matrix/test/services/ingress_api/preprocessors/coalesce_burst_test.rb`
- Create: `core_matrix/test/services/ingress_api/preprocessors/materialize_attachments_test.rb`
- Create: `core_matrix/test/services/ingress_api/preprocessors/resolve_dispatch_decision_test.rb`
- Create: `core_matrix/test/services/channel_deliveries/dispatch_conversation_output_test.rb`

**Step 1: Write failing policy, batching, and first-contact tests**

Cover:

- unknown DM sender creates a pending pairing request and stops processing
- approved sender proceeds
- two short text messages in the quiet period coalesce into one dispatch input
- media-only message gets synthesized transcript text
- unbound approved session creates a conversation from the endpoint workspace and
  runtime defaults
- active-turn pre-boundary follow-up chooses `steer`
- post-boundary follow-up chooses `queue`

**Step 2: Implement DM session resolution and pairing**

Use one `ChannelSession` per direct peer for Telegram DM. Pairing is a pre-turn
gate:

- create `ChannelPairingRequest`
- do not create turn work until approved

**Step 3: Implement deterministic burst merge and dispatch**

Keep rules deterministic:

- append text in arrival order
- preserve source inbound message ids in context
- do not use LLM rewrite

`ResolveDispatchDecision` should choose among:

- `new_turn`
- `steer_current_turn`
- `queue_follow_up`
- `reject`

**Step 4: Hook outbound delivery after output persistence**

After turn output is persisted:

- detect whether the turn/conversation is bound to a `ChannelSession`
- enqueue or invoke Telegram reply sending
- persist outbound delivery facts

Do not block transcript completion on outbound failure.

**Step 5: Run the targeted tests**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/ingress_api/preprocessors/authorize_and_pair_test.rb \
  test/services/ingress_api/preprocessors/coalesce_burst_test.rb \
  test/services/ingress_api/preprocessors/materialize_attachments_test.rb \
  test/services/ingress_api/preprocessors/resolve_dispatch_decision_test.rb \
  test/services/channel_deliveries/dispatch_conversation_output_test.rb
```

### Task 8: Add The Weixin Bridge Foundation In `lib/claw_bot_sdk` And Wire It Through `IngressAPI`

**Files:**
- Create: `core_matrix/lib/claw_bot_sdk.rb`
- Create: `core_matrix/lib/claw_bot_sdk/weixin.rb`
- Create: `core_matrix/lib/claw_bot_sdk/weixin/client.rb`
- Create: `core_matrix/lib/claw_bot_sdk/weixin/poller.rb`
- Create: `core_matrix/lib/claw_bot_sdk/weixin/normalize_message.rb`
- Create: `core_matrix/lib/claw_bot_sdk/weixin/context_token_store.rb`
- Create: `core_matrix/lib/claw_bot_sdk/weixin/qr_login.rb`
- Create: `core_matrix/lib/claw_bot_sdk/weixin/media_client.rb`
- Create: `core_matrix/app/jobs/channel_connectors/weixin_poll_account_job.rb`
- Create: `core_matrix/app/services/ingress_api/weixin/receive_polled_message.rb`
- Create: `core_matrix/app/services/channel_deliveries/send_weixin_reply.rb`
- Modify: `core_matrix/app/controllers/app_api/workspaces/ingress_endpoints_controller.rb`
- Modify: `core_matrix/app/services/channel_deliveries/dispatch_conversation_output.rb`
- Create: `core_matrix/test/lib/claw_bot_sdk/weixin/client_test.rb`
- Create: `core_matrix/test/lib/claw_bot_sdk/weixin/poller_test.rb`
- Create: `core_matrix/test/lib/claw_bot_sdk/weixin/normalize_message_test.rb`
- Create: `core_matrix/test/lib/claw_bot_sdk/weixin/context_token_store_test.rb`
- Create: `core_matrix/test/jobs/channel_connectors/weixin_poll_account_job_test.rb`
- Create: `core_matrix/test/services/ingress_api/weixin/receive_polled_message_test.rb`
- Create: `core_matrix/test/services/channel_deliveries/send_weixin_reply_test.rb`

**Step 1: Port the protocol boundary, not the OpenClaw runtime**

Use `references/original/references/openclaw-weixin` as structural input and
build a Ruby bridge that covers:

- long-poll `getupdates`
- outbound `sendmessage`
- `getuploadurl`
- `getconfig`
- `sendtyping` if needed later
- QR-login-oriented account lifecycle primitives

Do not port:

- TypeScript runtime globals
- filesystem state stores as the durable source of truth
- OpenClaw plugin registration assumptions

**Step 2: Persist state in CoreMatrix-owned records**

The bridge may keep short-lived in-memory caches, but durable state must be
stored in CoreMatrix:

- account-scoped state in `ChannelAccount.runtime_state_payload`
- peer-scoped reply state such as `context_token` in
  `ChannelSession.session_metadata`

**Step 3: Normalize Weixin messages and reuse the shared ingress pipeline**

The bridge must return Ruby-native objects that expose:

- sender/peer ids
- message ids
- timestamps
- text items
- file/image/video/audio descriptors
- reply state such as `context_token`

The poll runner should:

- load the Weixin-enabled `ChannelAccount`
- poll through `ClawBotSdk::Weixin::Poller`
- feed each normalized message into `IngressAPI::ReceiveEvent`

`IngressAPI::Weixin::ReceivePolledMessage` should also persist the newest valid
`context_token` onto the bound `ChannelSession.session_metadata` before
dispatching turn work so reply state survives process restarts.

**Step 4: Implement outbound Weixin reply delivery**

`SendWeixinReply` should:

- read `context_token` from the bound `ChannelSession`
- send text or media through `ClawBotSdk::Weixin`
- persist outbound delivery metadata

**Step 5: Extend endpoint management for Weixin lifecycle**

The workspace endpoint controller should expose Weixin-specific lifecycle
actions where needed, such as:

- start login
- inspect login status
- reconnect or disconnect an account

**Step 6: Run the targeted tests**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/lib/claw_bot_sdk/weixin/client_test.rb \
  test/lib/claw_bot_sdk/weixin/poller_test.rb \
  test/lib/claw_bot_sdk/weixin/normalize_message_test.rb \
  test/lib/claw_bot_sdk/weixin/context_token_store_test.rb \
  test/jobs/channel_connectors/weixin_poll_account_job_test.rb \
  test/services/ingress_api/weixin/receive_polled_message_test.rb \
  test/services/channel_deliveries/send_weixin_reply_test.rb
```

### Task 9: Run Internal Verification And Prepare Manual Integration

**Files:**
- Modify as needed from prior tasks only

**Step 1: Run the ingress and turn suites**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/turns/start_channel_ingress_turn_test.rb \
  test/services/turns/steer_current_input_test.rb \
  test/services/turns/queue_follow_up_test.rb \
  test/integration/channel_ingress_follow_up_flow_test.rb \
  test/jobs/conversations/metadata/bootstrap_title_job_test.rb \
  test/models/ingress_endpoint_test.rb \
  test/models/channel_account_test.rb \
  test/models/channel_session_test.rb \
  test/models/channel_pairing_request_test.rb \
  test/models/channel_inbound_message_test.rb \
  test/models/channel_delivery_test.rb \
  test/requests/app_api/workspaces/ingress_endpoints_controller_test.rb \
  test/requests/app_api/workspaces/ingress_endpoints/pairing_requests_controller_test.rb \
  test/requests/app_api/workspaces/ingress_endpoints/sessions_controller_test.rb \
  test/services/ingress_api/receive_event_test.rb \
  test/services/ingress_api/preprocessors/create_or_bind_conversation_test.rb \
  test/requests/ingress_api/telegram/updates_controller_test.rb \
  test/services/ingress_api/telegram/client_test.rb \
  test/services/ingress_api/telegram/normalize_update_test.rb \
  test/services/ingress_api/telegram/download_attachment_test.rb \
  test/services/ingress_api/telegram/verify_request_test.rb \
  test/services/ingress_api/preprocessors/authorize_and_pair_test.rb \
  test/services/ingress_api/preprocessors/coalesce_burst_test.rb \
  test/services/ingress_api/preprocessors/materialize_attachments_test.rb \
  test/services/ingress_api/preprocessors/resolve_dispatch_decision_test.rb \
  test/services/channel_deliveries/dispatch_conversation_output_test.rb \
  test/services/channel_deliveries/send_telegram_reply_test.rb \
  test/lib/claw_bot_sdk/weixin/client_test.rb \
  test/lib/claw_bot_sdk/weixin/poller_test.rb \
  test/lib/claw_bot_sdk/weixin/normalize_message_test.rb \
  test/lib/claw_bot_sdk/weixin/context_token_store_test.rb \
  test/jobs/channel_connectors/weixin_poll_account_job_test.rb \
  test/services/ingress_api/weixin/receive_polled_message_test.rb \
  test/services/channel_deliveries/send_weixin_reply_test.rb
```

**Step 2: Run the standard repository verification that does not require live accounts**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails db:test:prepare
bin/rails test
```

Do not claim Telegram or Weixin transport acceptance from these commands.

**Step 3: Execute manual transport validation later**

Telegram manual checklist:

- create a workspace ingress endpoint
- attach Telegram credentials to it
- configure Telegram webhook URL using the endpoint public ingress id
- set the Telegram secret token to the CoreMatrix-issued endpoint secret
- send an unpaired DM and confirm a pairing request is created
- approve pairing in `AppAPI`
- send text-only follow-up bursts and confirm steer vs queue behavior
- send an image or file and confirm attachment projection and reply delivery

Weixin manual checklist:

- create a workspace ingress endpoint
- attach Weixin account config to it
- complete QR login through the endpoint lifecycle flow
- start the poll runner
- send a direct message and confirm normalization into channel-ingress turns
- confirm `context_token` persistence on the bound session
- send an image or file and confirm bridge-mediated media handling
- confirm outbound text/media reply delivery

**Step 4: Inspect resulting business data**

Confirm:

- resource references use `public_id` at external boundaries
- machine-ingress routing uses `public_ingress_id` for endpoint webhook URLs or
  poller setup
- channel-origin follow-up work never falls back to owner-user provenance
- paired vs unpaired DM behavior matches the design
- first-contact conversation creation resolves workspace/agent/runtime from the
  ingress endpoint
- Telegram delivery is handled through `telegram-bot-ruby`
- Weixin durable connector state lives in CoreMatrix records, not ad hoc files

## External Preparation Checklist

These items are intentionally deferred until the implementation, internal
tests, and code/logic review are complete.

### Telegram

- a Telegram bot token
- the bot username
- a public HTTPS base URL that can reach CoreMatrix
- network access from the CoreMatrix environment to `api.telegram.org`
- one test Telegram account for DM validation
- later, if group support is exercised, one test group
- test media fixtures
  - one image
  - one generic file
  - optional voice/video samples if those modalities are implemented

Note:

- CoreMatrix should issue the endpoint public ingress id and endpoint secret
  itself; the user should not have to invent either one manually.

### Weixin

- confirmation of the upstream environment to target
- the Weixin-compatible backend `base_url`
- any required CDN or media endpoint configuration
- one test Weixin account that can complete QR login
- one second account or peer for direct-message validation
- any upstream tokens or account-side configuration required by that backend
- test media fixtures
  - one image
  - one generic file
  - optional voice sample if that modality is implemented
- confirmation that the test account can stay logged in long enough for polling
  and reply validation

### CoreMatrix Environment

- a runnable environment for webhook handling and poller jobs
- background workers enabled
- durable file storage enabled
- a place to store secrets and connector credentials
- accessible logs for webhook, poller, and delivery troubleshooting
- outbound network access to Telegram and the Weixin upstream services

### Product And Ops Decisions To Confirm Before Live Validation

- whether Telegram webhook delivery will use a staging hostname or a temporary
  tunnel
- whether Telegram DM pairing is enabled by default
- whether v1 live validation is DM-only or includes any group/thread cases
- whether multiple Weixin accounts are expected to run concurrently
- expected behavior when a Weixin `context_token` becomes invalid or stale
- whether channel-ingress-created conversations should remain owner-enterable in
  the app surface or later adopt an explicit external-only manual-entry policy

## Execution Order Summary

Recommended order:

1. shared provenance-safe turn entry and bootstrap
2. workspace-scoped ingress endpoint and channel domain models
3. workspace AppAPI CRUD for ingress endpoints
4. shared `IngressAPI` contracts and adapter boundary
5. Telegram transport and DM MVP
6. Weixin bridge foundation and DM wiring
7. manual channel validation

This keeps Telegram as the first usable entry point without forcing a redesign
when Weixin is added next.
