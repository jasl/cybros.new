# Telegram Managed Ingress Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refactor Telegram ingress into independent polling and webhook platforms, add reusable managed-conversation safeguards, make operator session rebinding create managed fork-like conversations, and rotate archived or deleted channel conversations to a fresh conversation on the next inbound message.

**Architecture:** Treat `telegram` and `telegram_webhook` as separate connector/session platforms but keep normalized Telegram wire semantics shared. Reuse the existing ingress receive pipeline for both transports, add a recurring polling runtime for `telegram`, and implement managed-conversation policy primarily through entry-policy helpers plus a shared service-layer managed-policy guard instead of adding a new `Conversation` schema field.

**Tech Stack:** Ruby on Rails, Active Job, Solid Queue recurring tasks, Minitest, `telegram-bot`, existing CoreMatrix ingress and conversation lifecycle services.

---

### Task 1: Lock The Telegram Platform Contract And Family Sweep In Tests

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/app_api/workspace_agents/ingress_bindings_controller_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/channel_connector_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/channel_session_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/ingress_bindings/update_connector_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/channel_deliveries/dispatch_conversation_output_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/ingress_api/telegram/progress_bridge_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/ingress_api/telegram/verify_request_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/jobs/channel_connectors/dispatch_active_pollers_job_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/jobs/channel_connectors/telegram_poll_updates_job_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/ingress_api/telegram/receive_polled_update_test.rb`

**Step 1: Write the failing tests**

Add expectations that:

- `platform = "telegram"` creates a `poller` connector
- `platform = "telegram_webhook"` creates a `webhook` connector
- `ChannelConnector` and `ChannelSession` accept `telegram_webhook`
- delivery and progress bridges treat `telegram` and `telegram_webhook` as the
  same Telegram wire family
- active Telegram-family connectors in the same installation reject duplicated
  bot tokens
- a recurring poll dispatcher enqueues eligible poller connectors by platform
- the per-connector polling job routes updates into `IngressAPI::ReceiveEvent`
  with `request_metadata["source"] == "telegram_poller"`

**Step 2: Run the focused tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && PARALLEL_WORKERS=1 bin/rails test test/requests/app_api/workspace_agents/ingress_bindings_controller_test.rb test/models/channel_connector_test.rb test/models/channel_session_test.rb test/services/ingress_bindings/update_connector_test.rb test/services/channel_deliveries/dispatch_conversation_output_test.rb test/services/ingress_api/telegram/progress_bridge_test.rb test/services/ingress_api/telegram/verify_request_test.rb test/jobs/channel_connectors/dispatch_active_pollers_job_test.rb test/jobs/channel_connectors/telegram_poll_updates_job_test.rb test/services/ingress_api/telegram/receive_polled_update_test.rb`

Expected: failures showing the repository still assumes Telegram is webhook-only
and does not yet have a poll scheduler.

### Task 2: Split Telegram Into Polling And Webhook Platforms

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/app_api/workspace_agents/ingress_bindings_controller.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/channel_connector.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/channel_session.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/ingress_bindings/update_connector.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/ingress_api/telegram/verify_request.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/channel_deliveries/dispatch_conversation_output.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/ingress_api/telegram/progress_bridge.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/ingress_api/preprocessors/materialize_attachments.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/config/routes.rb`

**Step 1: Implement the platform split**

- add `telegram_webhook` to connector/session platform enums
- change binding defaults so `telegram` uses `transport_kind = "poller"`
- make `telegram_webhook` the explicit webhook platform
- keep normalized Telegram envelope `platform = "telegram"`
- add a Telegram-family predicate/helper wherever code currently assumes
  `platform == "telegram"`

**Step 2: Tighten connector validation**

- require bot token for both Telegram platforms
- require `webhook_base_url` only for `telegram_webhook`
- reject active Telegram-family connectors that reuse a bot token
- validate the merged connector state, not only newly provided keys

**Step 3: Run the focused tests**

Run: same command from Task 1.

Expected: PASS

### Task 3: Add The Telegram Polling Runtime

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/jobs/channel_connectors/dispatch_active_pollers_job.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/jobs/channel_connectors/telegram_poll_updates_job.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/ingress_api/telegram/receive_polled_update.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/ingress_api/telegram/client.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/config/recurring.yml`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/config/data_retention_configuration_test.rb`

**Step 1: Add the recurring dispatcher**

- schedule a recurring job that scans active configured poller connectors
- dispatch the correct per-platform poll job, reusing the existing Weixin poll
  job and adding the new Telegram poll job

**Step 2: Implement the per-connector Telegram poll job**

- load the connector by `public_id`
- serialize access on the connector so concurrent poll jobs do not race
- ensure webhook mode is cleared before polling
- read and advance durable update offset from `runtime_state_payload`
- call `getUpdates`
- route each update through `IngressAPI::ReceiveEvent`

**Step 3: Run the polling-focused tests**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && PARALLEL_WORKERS=1 bin/rails test test/jobs/channel_connectors/dispatch_active_pollers_job_test.rb test/jobs/channel_connectors/telegram_poll_updates_job_test.rb test/services/ingress_api/telegram/receive_polled_update_test.rb test/requests/ingress_api/telegram/updates_controller_test.rb test/config/data_retention_configuration_test.rb`

Expected: PASS

### Task 4: Add Managed Entry Policy Helpers And Shared Managed Policy

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/conversation.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/managed_policy.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/app_surface/presenters/conversation_presenter.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversation_exports/build_conversation_payload.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversation_debug_exports/build_payload.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/turns/start_user_turn.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/turns/accept_pending_user_turn.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/metadata/user_edit.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/metadata/regenerate.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/metadata/agent_update.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/update_override.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversations/managed_policy_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/app_surface/presenters/conversation_presenter_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversation_exports/build_conversation_payload_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversation_debug_exports/build_payload_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/turns/start_user_turn_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/turns/accept_pending_user_turn_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversations/metadata/user_edit_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversations/metadata/regenerate_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversations/metadata/agent_update_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversations/update_override_test.rb`

**Step 1: Lock the managed rules in tests**

Add expectations that:

- subagent-managed and channel-managed conversations are both detected as
  managed
- managed conversations reject ordinary user mainline turns even while idle
- managed conversations reject metadata updates and regeneration
- managed conversations reject agent-side metadata drift
- managed conversations reject override/config mutations that change future
  runtime behavior
- no new `Conversation` DB field is required for managed detection
- App/API and export/debug surfaces expose a computed management projection with
  public ids only

**Step 2: Implement the shared policy**

- derive managed state from ownership sources such as `subagent_connection` and
  bound `channel_sessions`
- add a conversation-level association or query helper so channel ownership can
  be projected without custom ad hoc queries at every call site
- expose one computed management projection through the shared managed-policy
  service and wire it into presenter/export/debug surfaces
- add helpers for channel-managed entry policy derived from the workspace-agent
  baseline
- keep `interaction_lock_state` unchanged unless a later implementation proves
  a schema change is unavoidable

**Step 3: Run the focused tests**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && PARALLEL_WORKERS=1 bin/rails test test/services/conversations/managed_policy_test.rb test/services/app_surface/presenters/conversation_presenter_test.rb test/services/conversation_exports/build_conversation_payload_test.rb test/services/conversation_debug_exports/build_payload_test.rb test/services/turns/start_user_turn_test.rb test/services/turns/accept_pending_user_turn_test.rb test/services/conversations/metadata/user_edit_test.rb test/services/conversations/metadata/regenerate_test.rb test/services/conversations/metadata/agent_update_test.rb test/services/conversations/update_override_test.rb`

Expected: PASS

### Task 5: Make Fork And Operator Rebind Restore Safe Ownership Boundaries

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/create_managed_channel_conversation.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/channel_sessions/rebind_from_conversation_context.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/app_api/workspace_agents/ingress_bindings/sessions_controller.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/create_fork.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/creation_support.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/app_api/workspace_agents/ingress_bindings/sessions_controller_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversations/create_managed_channel_conversation_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/channel_sessions/rebind_from_conversation_context_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversations/create_fork_test.rb`

**Step 1: Lock the new rebinding and fork behavior in tests**

Add expectations that:

- session rebinding to a source conversation creates a new managed fork-like
  conversation instead of direct assignment
- the repair surface works for retained source conversations in the same
  workspace agent
- user fork from a managed conversation restores the ordinary interactive entry
  policy instead of inheriting managed restrictions

**Step 2: Implement the rebinding and fork reset**

- introduce a shared creator/factory for channel-managed conversations so
  operator rebinding does not hand-roll managed conversation setup
- add a dedicated operator/application rebinding service
- do not rely on direct conversation assignment
- reset child entry policy on user fork from managed parents

**Step 3: Run the focused tests**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && PARALLEL_WORKERS=1 bin/rails test test/requests/app_api/workspace_agents/ingress_bindings/sessions_controller_test.rb test/services/conversations/create_managed_channel_conversation_test.rb test/services/channel_sessions/rebind_from_conversation_context_test.rb test/services/conversations/create_fork_test.rb test/services/conversations/managed_policy_test.rb`

Expected: PASS

### Task 6: Rotate Channel Conversations After Archive Or Deletion

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/create_managed_channel_conversation.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/ingress_api/preprocessors/create_or_bind_conversation.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/ingress_api/preprocessors/authorize_and_pair.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/ingress_api/preprocessors/create_or_bind_conversation_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/integration/channel_ingress_conversation_rotation_test.rb`

**Step 1: Write the failing lifecycle tests**

Add expectations that:

- active retained channel-managed conversations are reused
- archived channel-managed conversations rebind to a fresh root conversation
- deleted channel-managed conversations rebind to a fresh root conversation
- `stop` alone does not rotate the conversation

**Step 2: Implement the rebinding logic**

- detect archived or deleting bound conversations before reuse
- reuse the shared channel-managed conversation creator to build a fresh managed
  root conversation for the same workspace agent and binding runtime selection
- update the session to point at the new conversation

**Step 3: Run the focused tests**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && PARALLEL_WORKERS=1 bin/rails test test/services/conversations/create_managed_channel_conversation_test.rb test/services/ingress_api/preprocessors/create_or_bind_conversation_test.rb test/integration/channel_ingress_conversation_rotation_test.rb`

Expected: PASS

### Task 7: Add Deterministic Managed Channel Titles And Block Metadata Drift Jobs

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/metadata/build_managed_channel_title.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/create_managed_channel_conversation.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/jobs/conversations/metadata/bootstrap_title_job.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/ingress_api/preprocessors/authorize_and_pair.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/ingress_api/preprocessors/create_or_bind_conversation.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversations/metadata/build_managed_channel_title_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/jobs/conversations/metadata/bootstrap_title_job_test.rb`

**Step 1: Write the failing title and drift tests**

Add expectations for:

- `Telegram DM @username`
- `Telegram DM 123456789`
- `Telegram Webhook DM @username`
- `Telegram Webhook DM 123456789`

Also assert that:

- managed channel conversations do not upgrade through the ordinary bootstrap
  title job
- managed channel conversations do not rely on generated title/summary paths

**Step 2: Implement the deterministic title path**

- set title directly in the shared channel-managed conversation creator so
  pairing, rebinding, and rotation all use the same title rules
- reuse an existing title source enum such as `agent`
- keep summary unset unless explicitly needed later

**Step 3: Run the focused tests**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && PARALLEL_WORKERS=1 bin/rails test test/services/conversations/create_managed_channel_conversation_test.rb test/services/conversations/metadata/build_managed_channel_title_test.rb test/jobs/conversations/metadata/bootstrap_title_job_test.rb test/services/conversations/managed_policy_test.rb`

Expected: PASS

### Task 8: Make `/stop` Return Acknowledged, Managed-Safe Control Output

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/ingress_commands/authorize.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/ingress_commands/dispatch.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/ingress_api/receive_event.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/ingress_api/command_surface_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/ingress_commands/authorize_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/ingress_commands/dispatch_test.rb`

**Step 1: Write the failing stop tests**

Add expectations that:

- `/stop` interrupts same-sender work and sends an explicit acknowledgement
- `/stop` on an already-stopped conversation returns an explicit no-op
  acknowledgement instead of a silent rejection
- ordinary mainline user turns are still rejected on managed conversations

**Step 2: Implement the command behavior**

- keep sender provenance checks for active-turn interruption
- return a handled control response with an outbound delivery payload
- allow a controlled idempotent no-active-work response from IM `/stop`

**Step 3: Run the focused tests**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && PARALLEL_WORKERS=1 bin/rails test test/services/ingress_api/command_surface_test.rb test/services/ingress_commands/authorize_test.rb test/services/ingress_commands/dispatch_test.rb test/services/conversations/managed_policy_test.rb`

Expected: PASS

### Task 9: Update Operator CLI, Fake Server Contracts, And Operator Docs

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/cli.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/runtime.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/ingress_telegram_command_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/ingress_telegram_webhook_command_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/full_setup_contract_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/runtime_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/support/fake_core_matrix_server.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/README.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/docs/operations/core-matrix-im-preparation-guide.md`

**Step 1: Write the failing CLI tests**

Add expectations that:

- `cmctl ingress telegram setup` configures polling and does not ask for
  webhook base URL
- `cmctl ingress telegram-webhook setup` configures webhook and prints webhook
  material
- status output distinguishes `telegram` and `telegram_webhook`
- operator docs mention that simultaneous polling and webhook require different
  Telegram bot tokens
- polling help text tells the operator that recurring scheduler and queue
  worker processes must be running

**Step 2: Implement the CLI split**

- repoint the existing Telegram command to polling
- add a dedicated webhook subcommand
- update readiness snapshots, stored binding keys, fake server contract, and
  help text

**Step 3: Run the CLI tests**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli && bundle exec ruby -Itest test/ingress_telegram_command_test.rb test/ingress_telegram_webhook_command_test.rb test/full_setup_contract_test.rb test/runtime_test.rb`

Expected: PASS

### Task 10: Cleanup, Full Verification, And Acceptance

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/plans/2026-04-17-telegram-managed-ingress-design.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/plans/2026-04-17-telegram-managed-ingress-implementation.md`
- Modify: stale Telegram-only tests, helpers, and docs across `/Users/jasl/Workspaces/Ruby/cybros/core_matrix` and `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli`

**Step 1: Remove stale Telegram webhook-only assumptions**

Clean up:

- helper code that treats Telegram as webhook-only
- tests that branch on `platform == "telegram"` to mean “all Telegram”
- outdated operator docs that imply Telegram always needs webhook setup

**Step 2: Run the full `core_matrix` verification suite**

Run:

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

Expected: all pass.

**Step 3: Run the required monorepo acceptance suite**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
ACTIVE_ACCEPTANCE_ENABLE_2048_CAPSTONE=1 bash acceptance/bin/run_active_suite.sh
```

Expected: acceptance suite passes and the resulting artifacts plus database
state confirm the intended business shapes.

**Step 4: Update docs if verification exposed behavior drift**

If behavior differs from the audited design, update the design and
implementation docs before closing the work.

## Schema Note

The audited preferred design avoids `Conversation` schema changes. Do **not**
rewrite `CreateConversations` or regenerate `db/schema.rb` unless implementation
discovers a real gap that cannot be expressed through current fields and
associations.

If such a schema rewrite becomes necessary after implementation evidence, use
the AGENTS.md rebuild flow from `/Users/jasl/Workspaces/Ruby/cybros/core_matrix`:

```bash
bin/rails db:drop
rm db/schema.rb
bin/rails db:create
bin/rails db:migrate
bin/rails db:reset
```
