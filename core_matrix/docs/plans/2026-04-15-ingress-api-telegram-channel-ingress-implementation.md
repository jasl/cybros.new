# IngressAPI Telegram-First And Weixin Channel Ingress Implementation Plan

> Status note: this plan is phase 2 and assumes
> `2026-04-15-workspace-agent-decoupling-implementation.md` has already been
> executed. Implement on top of `WorkspaceAgent`, `IngressBinding`, and
> `ChannelConnector`. Do not preserve the legacy ingress-endpoint topology.

## Execution Contract

Mandatory execution rules:

- do not add compatibility layers for the old workspace-coupled ingress model
- do not backfill or preserve legacy ingress data shapes
- if schema or migration history is rewritten, use the repository-standard
  rebuild flow from `core_matrix`:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:drop
rm db/schema.rb
bin/rails db:create
bin/rails db:migrate
bin/rails db:reset
```

Before starting each task:

- re-read the relevant design and implementation sections
- confirm the task still matches the current branch state
- if the docs are unclear but the intended business rule can be resolved,
  update the docs first and only then implement
- if the right behavior cannot be decided confidently, stop and discuss with
  the user before coding

When transport or business behavior is missing:

- consult the referenced comparison projects
- write the resolved rule back into the docs before implementation
- do not let undocumented behavior land only in code

Checkpoint protocol:

- group tasks into milestones
- after each milestone, run multi-angle static review using subagents or
  equivalent reviewer passes across:
  - transport/protocol correctness
  - business-rule correctness
  - data-shape and provenance correctness
  - test-plan completeness
- fix findings, then create a checkpoint commit

Final quality bar:

- implementation quality is more important than implementation speed
- after all milestones are complete, run the full `core_matrix` verification
  suite, the full acceptance suite including the 2048 capstone, and inspect
  both exported artifacts and resulting database state

## Milestones

Recommended milestone grouping for this plan:

1. Tasks 1-4: ingress substrate, schema, and AppAPI roots
2. Tasks 5-7: channel-ingress turn path and Telegram delivery
3. Tasks 8-9: Weixin bridge and shared artifact publication
4. Task 10: final audit, full verification, acceptance, and data inspection

**Goal:** Add a first-class `IngressAPI` boundary and ship Telegram DM as the
first external conversation entry point for CoreMatrix on top of the new
`WorkspaceAgent` topology, while keeping the shared ingress substrate and data
model ready for a Weixin direct-message connector implemented through
`lib/claw_bot_sdk`. The same implementation should also establish IM progress
sync, command handling, and attachment/result delivery primitives that can be
reused across transports.

**Architecture:** Introduce a mounted-agent-scoped `IngressBinding` root plus a
user-managed channel domain (`ChannelConnector`, `ChannelSession`,
`ChannelPairingRequest`, `ChannelInboundMessage`, `ChannelDelivery`) and a
provenance-safe channel-ingress turn path. Keep transport-specific logic in
`IngressAPI` adapters and preprocessors. Reuse CoreMatrix runtime and
supervision signals to support three outward-facing modes: `preview_stream`,
`status_progress`, and `final_delivery`. Use the `telegram-bot-rb/telegram-bot`
project via the Ruby gem `telegram-bot` for Telegram Bot API access. Put
Weixin protocol, QR login, long-polling, `context_token` handling, and media
transport behind `lib/claw_bot_sdk`.

**Tech Stack:** Ruby on Rails, Minitest, Active Record migrations, Active
Storage, Active Job, `telegram-bot`, existing CoreMatrix
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
- persist `origin_payload` with binding/session/message provenance

**Step 2: Extend steer and queued-follow-up tests**

Add failing expectations that:

- pre-boundary follow-up input on a channel-ingress turn stays on the same turn
  via `Turns::SteerCurrentInput`
- post-boundary follow-up input on a channel-ingress turn creates queued work
  without falling back to `manual_user` provenance
- queued turn `origin_payload` preserves the upstream ingress linkage

**Step 3: Add title-bootstrap coverage**

Lock the intended rule explicitly:

- first transcript-bearing channel-ingress turns bootstrap titles
- command-only paths such as `/report`, `/btw`, and `/stop` do not
  bootstrap titles because they do not append a new main-transcript user turn

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

### Task 2: Add The Mounted-Agent-Scoped Ingress Schema And Models

**Files:**
- Create: `core_matrix/db/migrate/20260415090000_create_ingress_bindings.rb`
- Create: `core_matrix/db/migrate/20260415090100_create_channel_connectors.rb`
- Create: `core_matrix/db/migrate/20260415090200_create_channel_sessions.rb`
- Create: `core_matrix/db/migrate/20260415090300_create_channel_pairing_requests.rb`
- Create: `core_matrix/db/migrate/20260415090400_create_channel_inbound_messages.rb`
- Create: `core_matrix/db/migrate/20260415090500_create_channel_deliveries.rb`
- Create: `core_matrix/app/models/ingress_binding.rb`
- Create: `core_matrix/app/models/channel_connector.rb`
- Create: `core_matrix/app/models/channel_session.rb`
- Create: `core_matrix/app/models/channel_pairing_request.rb`
- Create: `core_matrix/app/models/channel_inbound_message.rb`
- Create: `core_matrix/app/models/channel_delivery.rb`
- Modify: `core_matrix/docs/behavior/identifier-policy.md`
- Create: `core_matrix/test/models/ingress_binding_test.rb`
- Create: `core_matrix/test/models/channel_connector_test.rb`
- Create: `core_matrix/test/models/channel_session_test.rb`
- Create: `core_matrix/test/models/channel_pairing_request_test.rb`
- Create: `core_matrix/test/models/channel_inbound_message_test.rb`
- Create: `core_matrix/test/models/channel_delivery_test.rb`

**Step 1: Write failing model tests**

Add tests for:

- mounted-agent ownership consistency on `IngressBinding`
- binding public ingress ids are unique
- binding secrets are stored by digest, not plaintext
- one active channel connector per ingress binding in v1
- unique session boundary per
  `channel_connector_id + peer_kind + peer_id + normalized_thread_key`
- unique inbound event per `channel_connector_id + external_event_key`
- one active pending pairing request per sender/account
- public-id-only external references in JSON payloads and API-facing helpers

**Step 2: Write the migrations**

Add tables and indexes for:

- `ingress_bindings`
- `channel_connectors`
- `channel_sessions`
- `channel_pairing_requests`
- `channel_inbound_messages`
- `channel_deliveries`

Required schema shape:

- `ingress_bindings` must carry `workspace_agent_id`,
  optional `default_execution_runtime_id`, `public_ingress_id`,
  `ingress_secret_digest`, and routing/manual-entry policy payloads
- `channel_connectors` must carry `platform`, `driver`, `transport_kind`, and a
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
- helpers for issuing binding public ingress ids and secret tokens
- JSON normalization where required

Keep models small. Business orchestration stays in services.

**Step 4: Run the schema and model tests**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
PARALLEL_WORKERS=1 bin/rails test \
  test/models/ingress_binding_test.rb \
  test/models/channel_connector_test.rb \
  test/models/channel_session_test.rb \
  test/models/channel_pairing_request_test.rb \
  test/models/channel_inbound_message_test.rb \
  test/models/channel_delivery_test.rb
```

### Task 3: Add Workspace-Agent-Scoped AppAPI CRUD For Ingress Bindings

**Files:**
- Modify: `core_matrix/config/routes.rb`
- Create: `core_matrix/app/controllers/app_api/workspace_agents/ingress_bindings_controller.rb`
- Create: `core_matrix/app/controllers/app_api/workspace_agents/ingress_bindings/pairing_requests_controller.rb`
- Create: `core_matrix/app/controllers/app_api/workspace_agents/ingress_bindings/sessions_controller.rb`
- Create: `core_matrix/test/requests/app_api/workspace_agents/ingress_bindings_controller_test.rb`
- Create: `core_matrix/test/requests/app_api/workspace_agents/ingress_bindings/pairing_requests_controller_test.rb`
- Create: `core_matrix/test/requests/app_api/workspace_agents/ingress_bindings/sessions_controller_test.rb`

**Step 1: Write failing request tests**

Cover:

- ingress bindings are created under `/app_api/workspace_agents/:workspace_agent_id/...`
- users only choose execution runtime at binding creation time
- users create a binding by selecting `platform`, plus optional `label` and
  optional `default_execution_runtime_id`
- v1 derives connector `driver` and `transport_kind` from the selected
  platform instead of exposing free-form connector create params
- the response returns the binding public ingress id and setup metadata
- binding resources are user-scoped through the workspace agent
- pairing requests and sessions are nested under the binding owner

**Step 2: Add the routes**

Use nested routes aligned with existing AppAPI style:

- `/app_api/workspace_agents/:workspace_agent_id/ingress_bindings`
- `/app_api/workspace_agents/:workspace_agent_id/ingress_bindings/:ingress_binding_id/pairing_requests`
- `/app_api/workspace_agents/:workspace_agent_id/ingress_bindings/:ingress_binding_id/sessions`

Here `:ingress_binding_id` continues the normal CoreMatrix convention and
resolves the binding resource `public_id`. The machine-facing transport route
uses the separate `public_ingress_id`.

**Step 3: Implement the controllers**

The binding CRUD should let users:

- create/update/disable a binding
- choose an optional default execution runtime
- inspect the public ingress id
- inspect any platform-specific setup instructions
- create the single active connector implicitly from the chosen platform
- approve/reject pairing
- inspect and rebind/unbind sessions

In v1, this is the primary management surface. Do not expose free-floating
channel-connector CRUD at the top level.

**Step 4: Run the targeted tests**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/requests/app_api/workspace_agents/ingress_bindings_controller_test.rb \
  test/requests/app_api/workspace_agents/ingress_bindings/pairing_requests_controller_test.rb \
  test/requests/app_api/workspace_agents/ingress_bindings/sessions_controller_test.rb
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
- Create: `core_matrix/app/services/ingress_api/preprocessors/dispatch_command.rb`
- Create: `core_matrix/app/services/ingress_commands/parse.rb`
- Create: `core_matrix/app/services/ingress_commands/authorize.rb`
- Create: `core_matrix/app/services/ingress_commands/dispatch.rb`
- Create: `core_matrix/app/services/ingress_api/preprocessors/coalesce_burst.rb`
- Create: `core_matrix/app/services/ingress_api/preprocessors/materialize_attachments.rb`
- Create: `core_matrix/app/services/ingress_api/preprocessors/resolve_dispatch_decision.rb`
- Create: `core_matrix/test/services/ingress_api/receive_event_test.rb`
- Create: `core_matrix/test/services/ingress_api/preprocessors/create_or_bind_conversation_test.rb`
- Create: `core_matrix/test/services/ingress_api/preprocessors/dispatch_command_test.rb`
- Create: `core_matrix/test/services/ingress_commands/parse_test.rb`
- Create: `core_matrix/test/services/ingress_commands/authorize_test.rb`
- Create: `core_matrix/test/services/ingress_commands/dispatch_test.rb`

**Step 1: Write failing orchestration tests**

Add tests that expect:

- one normalized inbound event becomes one `IngressAPI::Envelope`
- middleware/preprocessors run in the designed order
- duplicate external event keys are ignored idempotently
- the same `ReceiveEvent` service can be called from an HTTP controller or a
  connector runner
- when an approved session is unbound, conversation creation uses
  `IngressBinding.workspace_agent` and resolves runtime from the
  binding/workspace-agent defaults
- supported IM commands are classified and dispatched before normal chat
  batching

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

Command-capable results should also be able to indicate that the event was
handled through:

- transcript entry
- sidecar query
- control dispatch

**Step 4: Add the adapter boundary now**

Introduce `IngressAPI::TransportAdapter` so transport-specific code can plug in
without changing the pipeline contract.

The boundary should cover:

- ingress binding and channel connector verification/identification
- payload normalization into `IngressEnvelope`
- inbound media fetch
- outbound text/media send

Keep `DispatchCommand` in the shared pipeline so commands such as `/stop`,
`/report`, and `/btw` are resolved before `CoalesceBurst`, but route the
actual behavior through `IngressCommands::Parse`,
`IngressCommands::Authorize`, and `IngressCommands::Dispatch`.

**Step 5: Run the targeted tests**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/ingress_api/receive_event_test.rb \
  test/services/ingress_api/preprocessors/create_or_bind_conversation_test.rb \
  test/services/ingress_api/preprocessors/dispatch_command_test.rb \
  test/services/ingress_commands/parse_test.rb \
  test/services/ingress_commands/authorize_test.rb \
  test/services/ingress_commands/dispatch_test.rb
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
- upstream binding/session/message linkage in `origin_payload`

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

### Task 6: Integrate Telegram Transport With `telegram-bot`

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

Add `gem "telegram-bot"` and keep the responsibility split explicit:

- webhook server remains CoreMatrix code
- Bot API requests go through the gem
- v1 reads the Telegram bot token from
  `ChannelConnector.credential_ref_payload["bot_token"]`
- the gem does not own session, pairing, batching, or routing behavior
- if preview-draft experiments later use Bot API draft methods, keep them
  behind optional adapter support rather than making them a required gem-level
  contract for v1

**Step 2: Implement binding-scoped webhook entry**

Add:

- `POST /ingress_api/telegram/bindings/:public_ingress_id/updates`

Request verification should:

- resolve the ingress binding from `public_ingress_id` in the path
- resolve the attached Telegram channel connector
- verify `X-Telegram-Bot-Api-Secret-Token` against the binding secret

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

Add `SendTelegramReply` so outbound delivery uses `telegram-bot` for:

- `sendMessage`
- `editMessageText`
- `sendChatAction`
- `sendPhoto`
- `sendDocument`
- `getFile` support where needed for attachment download
- optional `sendMessageDraft` transport support for preview experiments, kept
  behind explicit transport selection
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
- Create: `core_matrix/test/services/ingress_api/telegram/progress_bridge_test.rb`
- Create: `core_matrix/test/services/ingress_api/command_surface_test.rb`

**Step 1: Write failing policy, batching, and first-contact tests**

Cover:

- unknown DM sender creates a pending pairing request and stops processing
- approved sender proceeds
- two short text messages in the quiet period coalesce into one dispatch input
- media-only message gets synthesized transcript text
- unbound approved session creates a conversation from the binding's
  `WorkspaceAgent` and runtime defaults
- active-turn pre-boundary follow-up chooses `steer`
- post-boundary follow-up chooses `queue`
- in a shared group/thread conversation, same-sender follow-up may `steer`
  but cross-sender follow-up must `queue`
- `/stop` dispatches turn interrupt without entering the main transcript
- in a shared group/thread conversation, `/stop` may interrupt only the active
  work started by the same external sender
- `/report` returns supervision-backed status without creating a new main turn
- `/btw` asks a one-off sidecar question over the target conversation context
  without mutating the main transcript
- Telegram progress mode chooses editable preview transport plus typing/presence

**Step 2: Implement DM session resolution and pairing**

Use one `ChannelSession` per direct peer for Telegram DM. Pairing is a pre-turn
gate:

- create `ChannelPairingRequest`
- do not create turn work until approved

**Step 3: Implement deterministic burst merge and dispatch**

Keep rules deterministic:

- append text in arrival order
- preserve source inbound message ids in context
- only coalesce bursts from the same external sender in shared conversations
- do not use LLM rewrite
- for the first IM-usable milestone, implement short-burst merge inside the
  same-sender pre-side-effect active-turn window instead of adding a separate
  delayed turnless quiet-period buffer

`ResolveDispatchDecision` should choose among:

- `new_turn`
- `steer_current_turn`
- `queue_follow_up`
- `reject`

Shared channel rule:

- same-sender follow-up may choose `steer_current_turn`
- cross-sender follow-up must choose `queue_follow_up`

Command dispatch should choose among:

- `control_command`
- `sidecar_query`
- `transcript_command`

Shared control rule:

- same-sender `/stop` may dispatch bounded interrupt behavior
- cross-sender `/stop` must be rejected or ignored by policy

**Step 4: Hook outbound delivery and progress after output persistence**

After turn output is persisted:

- detect whether the turn/conversation is bound to a `ChannelSession`
- enqueue or invoke Telegram reply sending
- persist outbound delivery facts
- project `runtime.assistant_output.*` to Telegram preview delivery when the
  transport supports it
- project `runtime.agent_task.*`, `runtime.workflow_node.*`, and supervision
  evidence to status/progress responses when the command or connector mode
  asks for them

Do not block transcript completion on outbound failure.

**Step 5: Deliver attachments and generated artifacts natively**

Ensure Telegram delivery can project output attachments as native platform
media/file sends instead of flattening everything into plain text links.

**Step 6: Run the targeted tests**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/ingress_api/preprocessors/authorize_and_pair_test.rb \
  test/services/ingress_api/preprocessors/coalesce_burst_test.rb \
  test/services/ingress_api/preprocessors/materialize_attachments_test.rb \
  test/services/ingress_api/preprocessors/resolve_dispatch_decision_test.rb \
  test/services/channel_deliveries/dispatch_conversation_output_test.rb \
  test/services/ingress_api/telegram/progress_bridge_test.rb \
  test/services/ingress_api/command_surface_test.rb
```

**Deferred follow-up after the first IM-usable milestone**

This is a high-priority quality upgrade, but it does not block the current
architecture/mainline milestone:

- formalize reply / quote as the primary explicit IM-history mechanism
- extend normalization to produce when available:
  - `quoted_external_message_key`
  - `quoted_text`
  - `quoted_sender_label`
  - optional `quoted_attachment_refs`
- make quoted context outrank any pending shared-channel history window during
  supplemental-context assembly
- if the platform payload does not provide the quoted body, do not fetch a
  broad platform-history window to reconstruct it; keep the reference key and
  only small local semantic hints when available
- add focused tests around adapter normalization, supplemental-context
  assembly, and reply/quote dispatch behavior

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
- Create: `core_matrix/app/services/ingress_api/weixin/progress_bridge.rb`
- Create: `core_matrix/app/services/channel_deliveries/send_weixin_reply.rb`
- Modify: `core_matrix/app/controllers/app_api/workspace_agents/ingress_bindings_controller.rb`
- Modify: `core_matrix/app/services/channel_deliveries/dispatch_conversation_output.rb`
- Modify: `core_matrix/app/services/channel_deliveries/dispatch_runtime_progress.rb`
- Create: `core_matrix/test/lib/claw_bot_sdk/weixin/client_test.rb`
- Create: `core_matrix/test/lib/claw_bot_sdk/weixin/poller_test.rb`
- Create: `core_matrix/test/lib/claw_bot_sdk/weixin/normalize_message_test.rb`
- Create: `core_matrix/test/lib/claw_bot_sdk/weixin/context_token_store_test.rb`
- Create: `core_matrix/test/jobs/channel_connectors/weixin_poll_account_job_test.rb`
- Create: `core_matrix/test/services/ingress_api/weixin/receive_polled_message_test.rb`
- Create: `core_matrix/test/services/ingress_api/weixin/progress_bridge_test.rb`
- Create: `core_matrix/test/services/channel_deliveries/send_weixin_reply_test.rb`

**Step 1: Port the protocol boundary, not the OpenClaw runtime**

Use `references/original/references/openclaw-weixin` as structural input and
build a Ruby bridge that covers:

- long-poll `getupdates`
- outbound `sendmessage`
- `getuploadurl`
- `getconfig`
- `sendtyping`
- QR-login-oriented account lifecycle primitives

Do not port:

- TypeScript runtime globals
- filesystem state stores as the durable source of truth
- OpenClaw plugin registration assumptions

**Step 2: Persist state in CoreMatrix-owned records**

The bridge may keep short-lived in-memory caches, but durable state must be
stored in CoreMatrix:

- account-scoped state in `ChannelConnector.runtime_state_payload`
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

- load the Weixin-enabled `ChannelConnector`
- poll through `ClawBotSDK::Weixin::Poller`
- feed each normalized message into `IngressAPI::ReceiveEvent`

`IngressAPI::Weixin::ReceivePolledMessage` should also persist the newest valid
`context_token` onto the bound `ChannelSession.session_metadata` before
dispatching turn work so reply state survives process restarts.

**Step 4: Implement outbound Weixin reply delivery**

`SendWeixinReply` should:

- read `context_token` from the bound `ChannelSession`
- send text or media through `ClawBotSDK::Weixin`
- treat textual `status_progress` deliveries as ordinary `sendmessage` text
  sends; the mode distinction remains in persisted `ChannelDelivery` payloads
  and policy, not in a separate Weixin transport method
- for native attachment delivery, call `getuploadurl`, encrypt and upload the
  stored conversation attachment bytes through the Weixin CDN bridge, then send
  the resulting media/file item through `sendmessage`
- when a native attachment also carries caption text, send the caption as a
  preceding text item and the media/file item as the terminal tracked outbound
  message
- prefer server-returned `upload_full_url`; if the upstream only returns
  `upload_param`, build the CDN upload URL from connector runtime state
  `cdn_base_url`
- if native delivery is selected but the bridge does not have enough upload
  information to complete the protocol round-trip, fail loudly instead of
  silently substituting a text-only fake attachment send
- use typing plus explicit status/final-delivery messages instead of editable
  preview streaming
- persist outbound delivery metadata

`DispatchRuntimeProgress` should fan out to a Weixin-specific progress bridge so
runtime progress can materialize `status_progress` deliveries for active Weixin
sessions without reusing Telegram preview behavior.

**Step 5: Extend binding management for Weixin lifecycle**

The workspace-agent ingress-binding controller should expose Weixin-specific lifecycle
actions for the v1 account lifecycle:

- start login
- inspect login status
- disconnect an account

In v1, reconnect reuses the same `start_login` entrypoint instead of a separate
public controller action.

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
  test/services/ingress_api/weixin/progress_bridge_test.rb \
  test/services/channel_deliveries/send_weixin_reply_test.rb
```

### Task 9: Add Shared Conversation Artifact Ingress For App, Runtime, And IM Delivery

**Files:**
- Create: `core_matrix/app/services/attachments/create_for_message.rb`
- Create: `core_matrix/app/controllers/app_api/conversations/attachments_controller.rb`
- Modify: `core_matrix/app/controllers/app_api/base_controller.rb`
- Modify: `core_matrix/config/routes.rb`
- Modify: `core_matrix/app/services/channel_deliveries/dispatch_conversation_output.rb`
- Modify: `core_matrix/app/services/channel_deliveries/send_telegram_reply.rb`
- Modify: `core_matrix/app/services/channel_deliveries/send_weixin_reply.rb`
- Create: `core_matrix/test/services/attachments/create_for_message_test.rb`
- Create: `core_matrix/test/requests/app_api/conversations/attachments_controller_test.rb`
- Modify or create transcript serialization tests as needed so app-facing
  message payloads expose attachment metadata by `public_id`

**Step 1: Write failing tests for the shared artifact path**

Cover:

- a user can upload a file into a conversation/message through AppAPI
- a local generated file can be attached to an output message through a shared
  service
- channel delivery projects output attachments as native media/file sends
- app-facing transcript or attachment endpoints can discover and download the
  published artifact by `public_id`
- oversize uploads or generated files are rejected before `MessageAttachment`
  creation according to a configurable `max_bytes` policy with a default of
  100 MB
- over-count uploads or generated file batches are rejected before attachment
  creation according to a configurable `max_count` policy with a default of 10
- when an attachment is valid for conversation storage but too large for a
  specific channel transport, delivery falls back explicitly instead of failing
  silently
- publication-role metadata identifies the primary deliverable attachment

**Step 2: Implement the shared attachment-ingress service**

Keep `MessageAttachment` as the storage primitive, but add one shared
application service that can be reused by:

- app-side uploads
- runtime-generated local files
- future ingress or automation attachment paths

The AppAPI attachment surface should support the full conversation-artifact
lifecycle:

- upload a file into a message/conversation
- discover attachment metadata from transcript-facing payloads
- download a published attachment by `public_id`

Artifact policy rules:

- define one shared artifact-ingress byte-size limit for App uploads,
  runtime-generated local files, and future inbound IM attachments
- default that limit to 100 MB and make it configurable
- reject oversize artifacts before blob attach / attachment row creation
- define one shared artifact-ingress count limit for App uploads,
  runtime-generated local files, and future inbound IM attachments
- default that limit to 10 and make it configurable
- reject over-count artifact batches before attachment row creation
- keep transport-specific outbound size caps separate from conversation storage
  policy
- assign publication roles so one attachment can be treated as the primary
  deliverable and others as source/evidence/preview attachments

Default outbound publication rules:

- images should be sent natively when the transport supports it
- non-image files smaller than 1 MB should be sent natively when the transport
  supports it
- other files should default to a short-lived signed Active Storage download
  URL that does not require app-session authentication

Treat the conversation attachment as the canonical publication boundary. For
deployable web apps, prefer attaching a packaged build output such as a Vite
`dist/` bundle. Source archives remain optional secondary attachments.

The artifact publish step may happen in a second round after the main work
turn. That follow-up/export step should still attach into the same
conversation transcript so app clients, IM connectors, and acceptance harnesses
all consume the same published artifact record.

**Step 3: Run the targeted tests**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/attachments/create_for_message_test.rb \
  test/requests/app_api/conversations/attachments_controller_test.rb
```

### Task 10: Run Final Audit, Full Verification, Acceptance, And Data Inspection

**Files:**
- Modify as needed from prior tasks only

**Step 1: Run the focused ingress and turn suites**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/turns/start_channel_ingress_turn_test.rb \
  test/services/turns/steer_current_input_test.rb \
  test/services/turns/queue_follow_up_test.rb \
  test/integration/channel_ingress_follow_up_flow_test.rb \
  test/jobs/conversations/metadata/bootstrap_title_job_test.rb \
  test/models/ingress_binding_test.rb \
  test/models/channel_connector_test.rb \
  test/models/channel_session_test.rb \
  test/models/channel_pairing_request_test.rb \
  test/models/channel_inbound_message_test.rb \
  test/models/channel_delivery_test.rb \
  test/requests/app_api/workspace_agents/ingress_bindings_controller_test.rb \
  test/requests/app_api/workspace_agents/ingress_bindings/pairing_requests_controller_test.rb \
  test/requests/app_api/workspace_agents/ingress_bindings/sessions_controller_test.rb \
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
  test/services/channel_deliveries/send_weixin_reply_test.rb \
  test/services/attachments/create_for_message_test.rb \
  test/requests/app_api/conversations/attachments_controller_test.rb
```

**Step 2: Run the full standard CoreMatrix verification suite**

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

Do not claim Telegram or Weixin transport acceptance from these commands.

**Step 3: Run the full repository acceptance suite, including the 2048 capstone**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
ACTIVE_ACCEPTANCE_ENABLE_2048_CAPSTONE=1 bash acceptance/bin/run_active_suite.sh
```

Do not stop at command success. Inspect the produced acceptance artifacts.

**Step 4: Inspect 2048 exported artifacts and resulting database state**

Confirm at minimum:

- the 2048 capstone publishes its final deliverable through the conversation as
  a `MessageAttachment`
- the published artifact matches the intended product boundary
  - for a Vite-based app, prefer the built `dist/` package as the primary
    deliverable
- the acceptance flow retrieves the published artifact through app-facing
  conversation attachment APIs rather than scraping a runtime-private working
  directory
- the exported artifact bundle is internally consistent with the acceptance
  review data
- inspect the generated acceptance bundle under `acceptance/artifacts/<stamp>/`
  and confirm the review/evidence files point at the published conversation
  artifact rather than a runtime-private output directory
- the database contains the expected linked rows across:
  - `conversations`
  - `messages`
  - `message_attachments`
  - Active Storage blobs/attachments
  - ingress binding / connector / session / delivery tables where applicable
- attachment byte sizes, public ids, and conversation/message ancestry are
  correct
- the transcript-facing payload and the stored attachment rows agree on:
  - attachment `public_id`
  - filename
  - content type
  - byte size
- no external-facing payload or acceptance artifact leaks bigint ids

**Step 5: Execute manual transport validation later**

Telegram manual checklist:

- create a workspace-agent ingress binding
- attach Telegram credentials to it
- configure Telegram webhook URL using the binding public ingress id
- set the Telegram secret token to the CoreMatrix-issued binding secret
- send an unpaired DM and confirm a pairing request is created
- approve pairing in `AppAPI`
- send text-only follow-up bursts and confirm steer vs queue behavior
- send an image or file and confirm attachment projection and reply delivery

Weixin manual checklist:

- create a workspace-agent ingress binding
- attach Weixin account config to it
- complete QR login through the binding lifecycle flow
- start the poll runner
- send a direct message and confirm normalization into channel-ingress turns
- confirm `context_token` persistence on the bound session
- send an image or file and confirm bridge-mediated media handling
- confirm outbound text/media reply delivery

**Step 6: Inspect resulting business data**

Confirm:

- resource references use `public_id` at external boundaries
- machine-ingress routing uses `public_ingress_id` for binding webhook URLs or
  poller setup
- channel-origin follow-up work never falls back to owner-user provenance
- paired vs unpaired DM behavior matches the design
- first-contact conversation creation resolves workspace/agent/runtime from the
  ingress binding and mounted agent
- Telegram delivery is handled through `telegram-bot`
- Weixin durable connector state lives in CoreMatrix records, not ad hoc files
- sidecar commands such as `/report` and `/btw` do not mutate the main
  transcript
- control commands such as `/stop` dispatch bounded control/interrupt behavior
- artifact uploads and generated local files can be delivered back through IM
  as native attachments

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

- CoreMatrix should issue the binding public ingress id and binding secret
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
2. mounted-agent-scoped ingress binding and channel domain models
3. workspace-agent AppAPI CRUD for ingress bindings
4. shared `IngressAPI` contracts, command routing, and adapter boundary
5. Telegram transport, progress bridge, and DM MVP
6. Weixin bridge foundation with typing/progress/final-delivery wiring
7. shared artifact ingress and native attachment projection
8. manual channel validation

This keeps Telegram as the first usable entry point without forcing a redesign
when Weixin is added next.
