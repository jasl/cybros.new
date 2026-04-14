# IngressAPI Telegram Channel Ingress Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a first-class `IngressAPI` boundary and ship Telegram DM as the first external conversation entry point for CoreMatrix.

**Architecture:** Introduce a user-managed channel domain (`ChannelAccount`, `ChannelSession`, `ChannelPairingRequest`, `ChannelInboundMessage`, `ChannelDelivery`) plus a provenance-safe channel-ingress turn path. Keep transport-specific logic in `IngressAPI` adapters and preprocessors, keep turn/workflow/bootstrap logic in existing CoreMatrix services, and generalize the follow-up path so IM-origin messages preserve channel provenance during steer/queue flows.

**Tech Stack:** Ruby on Rails, Minitest, Active Record migrations, Active Storage, Action Cable, Active Job, Telegram Bot API, existing CoreMatrix turn/workflow/attachment infrastructure.

---

### Task 1: Lock The Channel-Ingress Provenance Rules With Failing Tests

**Files:**
- Create: `core_matrix/test/services/turns/start_channel_ingress_turn_test.rb`
- Modify: `core_matrix/test/services/turns/steer_current_input_test.rb`
- Modify: `core_matrix/test/services/turns/queue_follow_up_test.rb`
- Create: `core_matrix/test/integration/channel_ingress_follow_up_flow_test.rb`
- Reference: `core_matrix/app/services/turns/start_user_turn.rb`
- Reference: `core_matrix/app/services/turns/steer_current_input.rb`
- Reference: `core_matrix/app/services/turns/queue_follow_up.rb`
- Reference: `core_matrix/app/services/workflows/scheduler.rb`

**Step 1: Write the failing turn-entry test**

Add a new service test that expects `Turns::StartChannelIngressTurn` to:

- require an interactive conversation
- create an active turn with `origin_kind = "channel_ingress"`
- set `source_ref_type = "ChannelInboundMessage"`
- set `source_ref_id` to the inbound message `public_id`
- create a transcript-bearing `UserMessage`
- persist `origin_payload` with channel/session/message provenance

**Step 2: Extend steer and queued-follow-up tests**

Add failing expectations that:

- pre-boundary follow-up input on a channel-ingress turn stays on the same turn
  via `Turns::SteerCurrentInput`
- post-boundary follow-up input on a channel-ingress turn creates queued work
  without falling back to `manual_user` provenance
- queued turn `origin_payload` preserves the upstream channel/session linkage

**Step 3: Add an integration test for the whole follow-up flow**

Cover this sequence:

1. create a channel-ingress turn
2. attach output to cross the side-effect boundary
3. submit a new follow-up input
4. assert the queued turn is channel-origin, not owner-user-origin

**Step 4: Run the targeted tests and verify they fail**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/turns/start_channel_ingress_turn_test.rb \
  test/services/turns/steer_current_input_test.rb \
  test/services/turns/queue_follow_up_test.rb \
  test/integration/channel_ingress_follow_up_flow_test.rb
```

Expected: failures indicate the channel-ingress turn entry and provenance-safe
follow-up path do not exist yet.

**Step 5: Commit**

```bash
git add \
  test/services/turns/start_channel_ingress_turn_test.rb \
  test/services/turns/steer_current_input_test.rb \
  test/services/turns/queue_follow_up_test.rb \
  test/integration/channel_ingress_follow_up_flow_test.rb
git commit -m "test: lock channel ingress provenance rules"
```

### Task 2: Add The Channel Domain Schema And Models

**Files:**
- Create: `core_matrix/db/migrate/20260415090000_create_channel_accounts.rb`
- Create: `core_matrix/db/migrate/20260415090100_create_channel_sessions.rb`
- Create: `core_matrix/db/migrate/20260415090200_create_channel_pairing_requests.rb`
- Create: `core_matrix/db/migrate/20260415090300_create_channel_inbound_messages.rb`
- Create: `core_matrix/db/migrate/20260415090400_create_channel_deliveries.rb`
- Create: `core_matrix/app/models/channel_account.rb`
- Create: `core_matrix/app/models/channel_session.rb`
- Create: `core_matrix/app/models/channel_pairing_request.rb`
- Create: `core_matrix/app/models/channel_inbound_message.rb`
- Create: `core_matrix/app/models/channel_delivery.rb`
- Create: `core_matrix/test/models/channel_account_test.rb`
- Create: `core_matrix/test/models/channel_session_test.rb`
- Create: `core_matrix/test/models/channel_pairing_request_test.rb`
- Create: `core_matrix/test/models/channel_inbound_message_test.rb`
- Create: `core_matrix/test/models/channel_delivery_test.rb`

**Step 1: Write failing model tests**

Add tests for:

- installation/workspace/conversation ownership consistency
- unique session boundary per `channel_account_id + peer_kind + peer_id + thread_key`
- unique inbound message per `channel_account_id + external_message_id`
- one active pending pairing request per sender/account
- public-id-only external references in JSON payloads and API-facing helpers

**Step 2: Write the migrations**

Add tables and indexes for:

- `channel_accounts`
- `channel_sessions`
- `channel_pairing_requests`
- `channel_inbound_messages`
- `channel_deliveries`

Do not expose bigint IDs outside the schema internals. Any external references
stored in payloads or surfaced later should use `public_id`.

**Step 3: Implement the models**

Add:

- associations
- validations
- minimal enums for lifecycle/binding/delivery states
- JSON normalization where required

Keep models small. Business orchestration stays in services.

**Step 4: Run the schema and model tests**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
PARALLEL_WORKERS=1 bin/rails test \
  test/models/channel_account_test.rb \
  test/models/channel_session_test.rb \
  test/models/channel_pairing_request_test.rb \
  test/models/channel_inbound_message_test.rb \
  test/models/channel_delivery_test.rb
```

Expected: new tables exist, models validate correctly, and ownership/provenance
constraints are enforced.

**Step 5: Commit**

```bash
git add \
  db/migrate/20260415090000_create_channel_accounts.rb \
  db/migrate/20260415090100_create_channel_sessions.rb \
  db/migrate/20260415090200_create_channel_pairing_requests.rb \
  db/migrate/20260415090300_create_channel_inbound_messages.rb \
  db/migrate/20260415090400_create_channel_deliveries.rb \
  app/models/channel_account.rb \
  app/models/channel_session.rb \
  app/models/channel_pairing_request.rb \
  app/models/channel_inbound_message.rb \
  app/models/channel_delivery.rb \
  test/models/channel_account_test.rb \
  test/models/channel_session_test.rb \
  test/models/channel_pairing_request_test.rb \
  test/models/channel_inbound_message_test.rb \
  test/models/channel_delivery_test.rb
git commit -m "feat: add channel ingress domain models"
```

### Task 3: Build The Shared `IngressAPI` Contracts And Pipeline Skeleton

**Files:**
- Modify: `core_matrix/config/routes.rb`
- Create: `core_matrix/app/controllers/ingress_api/base_controller.rb`
- Create: `core_matrix/app/controllers/ingress_api/telegram/updates_controller.rb`
- Create: `core_matrix/app/services/ingress_api/envelope.rb`
- Create: `core_matrix/app/services/ingress_api/context.rb`
- Create: `core_matrix/app/services/ingress_api/receive_event.rb`
- Create: `core_matrix/app/services/ingress_api/middleware/verify_request.rb`
- Create: `core_matrix/app/services/ingress_api/middleware/deduplicate_inbound.rb`
- Create: `core_matrix/app/services/ingress_api/preprocessors/resolve_channel_session.rb`
- Create: `core_matrix/app/services/ingress_api/preprocessors/authorize_and_pair.rb`
- Create: `core_matrix/app/services/ingress_api/preprocessors/coalesce_burst.rb`
- Create: `core_matrix/app/services/ingress_api/preprocessors/materialize_attachments.rb`
- Create: `core_matrix/app/services/ingress_api/preprocessors/resolve_dispatch_decision.rb`
- Create: `core_matrix/test/services/ingress_api/receive_event_test.rb`
- Create: `core_matrix/test/requests/ingress_api/telegram/updates_controller_test.rb`

**Step 1: Write failing request and orchestration tests**

Add tests that expect:

- `POST /ingress_api/telegram/updates` reaches a machine-facing controller
- request verification runs before normalization
- one normalized inbound event becomes one `IngressAPI::Envelope`
- preprocessors run in the designed order
- duplicate external message ids are ignored idempotently

**Step 2: Add the `IngressAPI` route and base controller**

Create a separate namespace under `config/routes.rb`:

- `namespace :ingress_api`
- `namespace :telegram`
- `post "updates", to: "updates#create"`

The base controller should avoid browser-session assumptions from `AppAPI`.

**Step 3: Add envelope/context value objects and orchestration service**

Implement:

- `IngressAPI::Envelope`
- `IngressAPI::Context`
- `IngressAPI::ReceiveEvent`

`ReceiveEvent` should execute middleware/preprocessors in order and return a
small result object indicating whether the event was rejected, batched, or
materialized into turn work.

**Step 4: Add empty-but-real middleware/preprocessor skeletons**

Implement service classes with the target call boundaries now, even if some
logic is still simple in this task. The objective is to lock the pipeline shape
before Telegram-specific details arrive.

**Step 5: Run the targeted tests**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/ingress_api/receive_event_test.rb \
  test/requests/ingress_api/telegram/updates_controller_test.rb
```

Expected: `IngressAPI` exists, the controller is reachable, and the ordered
pipeline contract is enforced.

**Step 6: Commit**

```bash
git add \
  config/routes.rb \
  app/controllers/ingress_api/base_controller.rb \
  app/controllers/ingress_api/telegram/updates_controller.rb \
  app/services/ingress_api/envelope.rb \
  app/services/ingress_api/context.rb \
  app/services/ingress_api/receive_event.rb \
  app/services/ingress_api/middleware/verify_request.rb \
  app/services/ingress_api/middleware/deduplicate_inbound.rb \
  app/services/ingress_api/preprocessors/resolve_channel_session.rb \
  app/services/ingress_api/preprocessors/authorize_and_pair.rb \
  app/services/ingress_api/preprocessors/coalesce_burst.rb \
  app/services/ingress_api/preprocessors/materialize_attachments.rb \
  app/services/ingress_api/preprocessors/resolve_dispatch_decision.rb \
  test/services/ingress_api/receive_event_test.rb \
  test/requests/ingress_api/telegram/updates_controller_test.rb
git commit -m "feat: add ingress api pipeline skeleton"
```

### Task 4: Add `Turns::StartChannelIngressTurn` And A Provenance-Safe Follow-Up Path

**Files:**
- Create: `core_matrix/app/services/turns/start_channel_ingress_turn.rb`
- Create: `core_matrix/app/services/turns/queue_channel_follow_up.rb`
- Modify: `core_matrix/app/services/turns/steer_current_input.rb`
- Modify: `core_matrix/app/services/workflows/scheduler.rb`
- Modify: `core_matrix/app/services/turns/queue_follow_up.rb`
- Modify: `core_matrix/app/services/turns/accept_pending_user_turn.rb`
- Modify: `core_matrix/docs/behavior/turn-entry-and-selector-state.md`
- Modify: `core_matrix/docs/behavior/conversation-structure-and-lineage.md`

**Step 1: Implement the new turn-entry service**

Copy only the minimum shared patterns from `AcceptPendingUserTurn`:

- active turn creation
- input message creation
- selector/bootstrap state projection

Do not copy `manual_user` provenance.

**Step 2: Add a dedicated channel follow-up service**

Create `Turns::QueueChannelFollowUp` so the post-boundary path can preserve:

- `origin_kind = "channel_ingress"`
- `source_ref_type = "ChannelInboundMessage"`
- upstream channel/session/message linkage in `origin_payload`

Keep `Turns::QueueFollowUp` for ordinary owner-user entry.

**Step 3: Route scheduler policy decisions by turn origin**

Update `Workflows::Scheduler.apply_during_generation_policy` so:

- user-origin turns still queue owner-user follow-up work
- channel-origin turns queue channel-origin follow-up work

**Step 4: Run the targeted tests**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/turns/start_channel_ingress_turn_test.rb \
  test/services/turns/steer_current_input_test.rb \
  test/services/turns/queue_follow_up_test.rb \
  test/integration/channel_ingress_follow_up_flow_test.rb
```

Expected: channel-ingress turn creation works and queued follow-up work keeps
correct provenance after side effects.

**Step 5: Commit**

```bash
git add \
  app/services/turns/start_channel_ingress_turn.rb \
  app/services/turns/queue_channel_follow_up.rb \
  app/services/turns/steer_current_input.rb \
  app/services/workflows/scheduler.rb \
  app/services/turns/queue_follow_up.rb \
  app/services/turns/accept_pending_user_turn.rb \
  docs/behavior/turn-entry-and-selector-state.md \
  docs/behavior/conversation-structure-and-lineage.md
git commit -m "feat: add channel ingress turn entry"
```

### Task 5: Materialize Inbound Attachments And Reuse CoreMatrix Attachment Projection

**Files:**
- Create: `core_matrix/app/services/ingress_api/telegram/normalize_update.rb`
- Create: `core_matrix/app/services/ingress_api/telegram/download_attachment.rb`
- Modify: `core_matrix/app/services/ingress_api/preprocessors/materialize_attachments.rb`
- Create: `core_matrix/test/services/ingress_api/telegram/normalize_update_test.rb`
- Create: `core_matrix/test/services/ingress_api/telegram/download_attachment_test.rb`
- Create: `core_matrix/test/services/ingress_api/preprocessors/materialize_attachments_test.rb`
- Reference: `core_matrix/app/models/message_attachment.rb`
- Reference: `core_matrix/app/services/workflows/build_execution_snapshot.rb`

**Step 1: Write failing attachment-ingest tests**

Cover:

- Telegram text-only message normalization
- Telegram image/file message normalization
- media-only message gets synthesized transcript text
- downloaded files become `MessageAttachment` rows on the selected input message
- attachments flow into `attachment_manifest` and `model_input_attachments`

**Step 2: Implement Telegram normalization**

Normalize Telegram updates into the shared envelope shape:

- `text`
- `external_message_id`
- sender/chat/thread info
- attachment descriptors
- reply target metadata

**Step 3: Implement attachment download/storage**

Add a small adapter service that:

- fetches Telegram files
- stores them through Active Storage-backed `MessageAttachment`
- classifies modality as `image`, `audio`, `video`, or `file`

Keep v1 synchronous and deterministic. Do not add OCR, captions, or media
understanding here.

**Step 4: Run the targeted tests**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/ingress_api/telegram/normalize_update_test.rb \
  test/services/ingress_api/telegram/download_attachment_test.rb \
  test/services/ingress_api/preprocessors/materialize_attachments_test.rb \
  test/services/workflows/build_execution_snapshot_test.rb
```

Expected: Telegram attachments are normalized, stored, and projected through the
existing execution snapshot attachment path.

**Step 5: Commit**

```bash
git add \
  app/services/ingress_api/telegram/normalize_update.rb \
  app/services/ingress_api/telegram/download_attachment.rb \
  app/services/ingress_api/preprocessors/materialize_attachments.rb \
  test/services/ingress_api/telegram/normalize_update_test.rb \
  test/services/ingress_api/telegram/download_attachment_test.rb \
  test/services/ingress_api/preprocessors/materialize_attachments_test.rb
git commit -m "feat: ingest telegram attachments"
```

### Task 6: Implement Telegram DM Pairing, Short-Burst Coalescing, And Dispatch Decisions

**Files:**
- Modify: `core_matrix/app/services/ingress_api/preprocessors/resolve_channel_session.rb`
- Modify: `core_matrix/app/services/ingress_api/preprocessors/authorize_and_pair.rb`
- Modify: `core_matrix/app/services/ingress_api/preprocessors/coalesce_burst.rb`
- Modify: `core_matrix/app/services/ingress_api/preprocessors/resolve_dispatch_decision.rb`
- Modify: `core_matrix/app/services/ingress_api/receive_event.rb`
- Create: `core_matrix/test/services/ingress_api/preprocessors/authorize_and_pair_test.rb`
- Create: `core_matrix/test/services/ingress_api/preprocessors/coalesce_burst_test.rb`
- Create: `core_matrix/test/services/ingress_api/preprocessors/resolve_dispatch_decision_test.rb`
- Modify: `core_matrix/test/requests/ingress_api/telegram/updates_controller_test.rb`

**Step 1: Write failing policy and batching tests**

Cover:

- unknown DM sender creates a pending pairing request and stops processing
- approved/allowlisted DM sender proceeds
- two short text messages in the quiet period coalesce into one dispatch input
- active-turn pre-boundary follow-up chooses `steer`
- post-boundary follow-up chooses `queue`

**Step 2: Implement DM session resolution and pairing**

Use one `ChannelSession` per direct peer for Telegram DM. Make pairing a
pre-turn gate:

- create `ChannelPairingRequest`
- do not create turn work until approved

**Step 3: Implement deterministic burst merge**

Implement a short quiet-period merge for Telegram DM text splits and short
follow-up bursts. Keep rules deterministic:

- append text in arrival order
- preserve source inbound message ids in context
- do not use LLM rewrite

**Step 4: Implement dispatch decision logic**

`ResolveDispatchDecision` should choose among:

- `new_turn`
- `steer_current_turn`
- `queue_follow_up`
- `reject`

Use only deterministic rules in v1.

**Step 5: Run the targeted tests**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/ingress_api/preprocessors/authorize_and_pair_test.rb \
  test/services/ingress_api/preprocessors/coalesce_burst_test.rb \
  test/services/ingress_api/preprocessors/resolve_dispatch_decision_test.rb \
  test/requests/ingress_api/telegram/updates_controller_test.rb
```

Expected: Telegram DM ingress correctly pairs, batches, and chooses new-turn vs
steer vs queue behavior.

**Step 6: Commit**

```bash
git add \
  app/services/ingress_api/preprocessors/resolve_channel_session.rb \
  app/services/ingress_api/preprocessors/authorize_and_pair.rb \
  app/services/ingress_api/preprocessors/coalesce_burst.rb \
  app/services/ingress_api/preprocessors/resolve_dispatch_decision.rb \
  app/services/ingress_api/receive_event.rb \
  test/services/ingress_api/preprocessors/authorize_and_pair_test.rb \
  test/services/ingress_api/preprocessors/coalesce_burst_test.rb \
  test/services/ingress_api/preprocessors/resolve_dispatch_decision_test.rb \
  test/requests/ingress_api/telegram/updates_controller_test.rb
git commit -m "feat: add telegram dm ingress flow"
```

### Task 7: Add Telegram Outbound Delivery And Minimal App-Facing Management

**Files:**
- Create: `core_matrix/app/services/channel_deliveries/dispatch_conversation_output.rb`
- Create: `core_matrix/app/services/channel_deliveries/send_telegram_reply.rb`
- Modify: `core_matrix/app/services/provider_execution/persist_turn_step_success.rb`
- Create: `core_matrix/app/controllers/app_api/channel_accounts_controller.rb`
- Create: `core_matrix/app/controllers/app_api/channel_pairing_requests_controller.rb`
- Create: `core_matrix/app/controllers/app_api/channel_sessions_controller.rb`
- Modify: `core_matrix/config/routes.rb`
- Create: `core_matrix/test/services/channel_deliveries/dispatch_conversation_output_test.rb`
- Create: `core_matrix/test/services/channel_deliveries/send_telegram_reply_test.rb`
- Create: `core_matrix/test/requests/app_api/channel_accounts_controller_test.rb`
- Create: `core_matrix/test/requests/app_api/channel_pairing_requests_controller_test.rb`
- Create: `core_matrix/test/requests/app_api/channel_sessions_controller_test.rb`

**Step 1: Write failing outbound and management tests**

Cover:

- completed agent output for a bound Telegram session creates a `ChannelDelivery`
- Telegram reply uses correct chat/thread/reply target metadata
- pairing requests are listable/approvable through `AppAPI`
- channel accounts and sessions are user-scoped resources, not system-admin
  resources

**Step 2: Implement outbound delivery**

Hook delivery after output persistence:

- detect whether the turn/conversation is bound to a `ChannelSession`
- enqueue or invoke Telegram reply sending
- persist outbound delivery facts

Do not block transcript completion on outbound failure.

**Step 3: Implement the minimal user-facing management surface**

Add user-scoped `AppAPI` resources for:

- `ChannelAccounts`
- `ChannelPairingRequests`
- `ChannelSessions`

Keep the surface minimal:

- list/show/create/update where necessary
- approve/reject pairing
- inspect and rebind/unbind sessions

**Step 4: Run the targeted tests**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/channel_deliveries/dispatch_conversation_output_test.rb \
  test/services/channel_deliveries/send_telegram_reply_test.rb \
  test/requests/app_api/channel_accounts_controller_test.rb \
  test/requests/app_api/channel_pairing_requests_controller_test.rb \
  test/requests/app_api/channel_sessions_controller_test.rb
```

Expected: outbound Telegram replies are tracked and the minimal app-facing
management surface exists for the owning user scope.

**Step 5: Commit**

```bash
git add \
  app/services/channel_deliveries/dispatch_conversation_output.rb \
  app/services/channel_deliveries/send_telegram_reply.rb \
  app/services/provider_execution/persist_turn_step_success.rb \
  app/controllers/app_api/channel_accounts_controller.rb \
  app/controllers/app_api/channel_pairing_requests_controller.rb \
  app/controllers/app_api/channel_sessions_controller.rb \
  config/routes.rb \
  test/services/channel_deliveries/dispatch_conversation_output_test.rb \
  test/services/channel_deliveries/send_telegram_reply_test.rb \
  test/requests/app_api/channel_accounts_controller_test.rb \
  test/requests/app_api/channel_pairing_requests_controller_test.rb \
  test/requests/app_api/channel_sessions_controller_test.rb
git commit -m "feat: add telegram delivery and channel management"
```

### Task 8: Run Full CoreMatrix Verification And Acceptance-Critical Checks

**Files:**
- Modify as needed from prior tasks only
- Reference: `core_matrix/AGENTS.md`

**Step 1: Run targeted ingress and turn suites one final time**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/turns/start_channel_ingress_turn_test.rb \
  test/services/turns/steer_current_input_test.rb \
  test/services/turns/queue_follow_up_test.rb \
  test/integration/channel_ingress_follow_up_flow_test.rb \
  test/services/ingress_api/receive_event_test.rb \
  test/requests/ingress_api/telegram/updates_controller_test.rb \
  test/services/ingress_api/telegram/normalize_update_test.rb \
  test/services/ingress_api/telegram/download_attachment_test.rb \
  test/services/ingress_api/preprocessors/materialize_attachments_test.rb \
  test/services/ingress_api/preprocessors/authorize_and_pair_test.rb \
  test/services/ingress_api/preprocessors/coalesce_burst_test.rb \
  test/services/ingress_api/preprocessors/resolve_dispatch_decision_test.rb \
  test/services/channel_deliveries/dispatch_conversation_output_test.rb \
  test/services/channel_deliveries/send_telegram_reply_test.rb
```

**Step 2: Run the standard CoreMatrix verification suite**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails db:test:prepare
bin/rails test
bin/rails test:system
```

**Step 3: Run the acceptance-critical root suite**

Because this work touches conversation/turn/bootstrap/runtime roundtrip
behavior, finish with:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
ACTIVE_ACCEPTANCE_ENABLE_2048_CAPSTONE=1 bash acceptance/bin/run_active_suite.sh
```

**Step 4: Inspect acceptance artifacts and resulting business data**

Check:

- acceptance artifacts tied to conversation/turn/runtime progression
- resulting database state for:
  - `channel_accounts`
  - `channel_sessions`
  - `channel_pairing_requests`
  - `channel_inbound_messages`
  - `channel_deliveries`
  - `turns`
  - `messages`
  - `message_attachments`

Confirm:

- provenance uses `public_id` at external boundaries
- channel-origin follow-up work never falls back to owner-user provenance
- paired vs unpaired DM behavior matches the design
- attachments land on transcript-bearing input messages and execution snapshots

**Step 5: Commit**

```bash
git add \
  app \
  config/routes.rb \
  db/migrate \
  docs/behavior \
  test
git commit -m "feat: ship telegram channel ingress"
```
