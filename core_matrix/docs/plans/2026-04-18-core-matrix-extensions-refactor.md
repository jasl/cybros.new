# CoreMatrix Packages, Conversation Surfaces, and Capabilities Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the current ingress/channel plus embedded-agent/runtime-feature split with plugin packages, a host-owned conversation-surface kernel, and a host-owned capability kernel that are explicit, testable, and lighter on the hot path.

**Architecture:** CoreMatrix will own narrow extension contracts under `app/extensions/conversation_surfaces` and `app/extensions/capabilities`, plus a thin package loader under `app/extensions`. Host persistence will be rewritten around `SurfaceBinding` and `ConversationScopeBinding`, concrete built-in behavior will live under `app/plugins/core/*`, and the first reference surface will be a generic SaaS-style webhook package before Telegram and Weixin are migrated.

**Tech Stack:** Ruby on Rails, Active Record, Active Job, Bundler, Minitest, existing agent/runtime control primitives, and the destructive migration rebuild flow mandated by `/Users/jasl/Workspaces/Ruby/cybros/AGENTS.md`.

**Execution Rules:**
- Breaking changes are allowed and expected; do not preserve compatibility shims past the task that needs them.
- Keep the work scoped to `core_matrix` and `core_matrix_cli`, plus the root `AGENTS.md` pointer update.
- Use `public_id` at all external or agent-facing boundaries.
- Treat this as verification-critical work under `/Users/jasl/Workspaces/Ruby/cybros/AGENTS.md:32-40`.
- Because host schema migrations are being rewritten in place, use the destructive rebuild flow from project root whenever the plan says to regenerate the database and `db/schema.rb`.
- Execute autonomously through any issue that can be resolved locally; stop only for unresolved product or architecture contradictions that require a new decision.
- By the end of the refactor, legacy terminology from the replaced architecture may remain only in archived/historical material and these migration plans, not in active code, active tests, active docs, CLI help, routes, or public APIs.

**Final Acceptance Checklist:**
- All built-in extension behavior lives in plugin packages under `core_matrix/app/plugins/core/*`.
- Host-owned extension contracts exist only under `core_matrix/app/extensions/conversation_surfaces`, `core_matrix/app/extensions/capabilities`, and the shared loader under `core_matrix/app/extensions`.
- The host no longer owns `IngressBinding`, `ChannelConnector`, `ChannelSession`, `ChannelPairingRequest`, `ChannelInboundMessage`, or `ChannelDelivery`.
- The host instead owns `SurfaceBinding` and `ConversationScopeBinding`, plus only the additional receipt/delivery models that remain genuinely generic after implementation.
- Generic public endpoint and management-action routes replace plugin-specific App API/controller branching.
- Plugin gem fragments and plugin migration paths are loaded only through host-controlled boot/build flow.
- The generic `webhook_inbox` package works as a first-class conversation surface and is covered by tests.
- Telegram and Weixin package behavior runs through the same conversation-surface kernel without host branching on platform names.
- `embedded_agents`, `embedded_features`, and `runtime_features` are replaced by one host capability invoke path.
- `core_matrix_cli` uses generic `surface_bindings` create/show/action RPC surfaces and exposes a `surface` command family; legacy `ingress` command names do not remain in active CLI code, tests, help output, or README examples.
- `core_matrix/AGENTS.md` and extension authoring docs exist and match the new architecture.
- Legacy ingress/channel/embedded/runtime terminology survives only in archived or historical materials, not in active code, routes, jobs, tests, formal docs, or CLI help.
- Focused tests, query-budget checks, full `core_matrix` and `core_matrix_cli` verification, schema rebuild, and the active verification suite all pass.

**Dependency Order:**
1. Tasks 1-2 build the package loader and boot-time dependency aggregation.
2. Task 3 rewrites the host schema so later tasks do not build on `channel_*` history.
3. Tasks 4-7 create the new host kernels, routes, and hot-path protections.
4. Task 8 packages the generic webhook surface as the first architecture probe.
5. Tasks 9-11 migrate capability behavior onto the new kernel.
6. Tasks 12-13 migrate Telegram and Weixin onto the new conversation-surface kernel.
7. Tasks 14-17 remove old branching, rewrite remaining provenance and command semantics, migrate bundled provisioning, and adapt the CLI.
8. Task 18 refreshes docs and contributor rules.
9. Tasks 19-20 verify structure, schema, overhead, and end-to-end behavior.

---

### Task 1: Build The Package Manifest Framework

**Depends on:** none

**Files:**
- Create: `core_matrix/app/extensions/manifest.rb`
- Create: `core_matrix/app/extensions/manifest_validator.rb`
- Create: `core_matrix/app/extensions/dependency_resolver.rb`
- Create: `core_matrix/app/extensions/registry.rb`
- Create: `core_matrix/app/extensions/loader.rb`
- Create: `core_matrix/app/extensions/definition_index.rb`
- Create: `core_matrix/config/initializers/extensions.rb`
- Modify: `core_matrix/config/application.rb`
- Test: `core_matrix/test/extensions/manifest_validator_test.rb`
- Test: `core_matrix/test/extensions/dependency_resolver_test.rb`
- Test: `core_matrix/test/extensions/registry_test.rb`
- Test: `core_matrix/test/extensions/loader_test.rb`
- Test: `core_matrix/test/extensions/definition_index_test.rb`

**Step 1: Write the failing tests**

Add tests that prove:

- manifests validate required fields and reject invalid payloads
- duplicate package ids are rejected
- dependency ordering is deterministic
- Zeitwerk resolves `Extensions::*` and `Plugins::*` from the new directories
- package-local `app/plugins/*/*/lib` helpers resolve under the owning package namespace without an extra `Lib` module segment
- the loader publishes a deterministic, frozen definition index

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/extensions/manifest_validator_test.rb test/extensions/dependency_resolver_test.rb test/extensions/registry_test.rb test/extensions/loader_test.rb test/extensions/definition_index_test.rb`
Expected: FAIL because the package framework does not exist yet.

**Step 3: Write minimal implementation**

Implement:

- immutable manifest value objects
- actionable validation errors
- deterministic package discovery and dependency resolution
- explicit namespace registration for `Extensions::*` and `Plugins::*`
- collapse package-local `app/plugins/*/*/lib` directories in Zeitwerk so package helper code keeps the package namespace
- a frozen definition index produced during boot

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/extensions/manifest_validator_test.rb test/extensions/dependency_resolver_test.rb test/extensions/registry_test.rb test/extensions/loader_test.rb test/extensions/definition_index_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/extensions core_matrix/config/application.rb core_matrix/config/initializers/extensions.rb core_matrix/test/extensions
git commit -m "refactor: add package manifest framework"
```

### Task 2: Aggregate Plugin Dependencies And Migration Paths

**Depends on:** Task 1

**Files:**
- Modify: `core_matrix/Gemfile`
- Modify: `core_matrix/Gemfile.lock`
- Modify: `core_matrix/config/application.rb`
- Create: `core_matrix/lib/extensions/gem_dependency_registry.rb`
- Create: `core_matrix/app/plugins/core/README.md`
- Create: `core_matrix/app/plugins/core/webhook_inbox/gems.rb`
- Create: `core_matrix/app/plugins/core/telegram/gems.rb`
- Create: `core_matrix/app/plugins/core/weixin/gems.rb`
- Test: `core_matrix/test/extensions/plugin_dependency_loading_test.rb`
- Test: `core_matrix/test/extensions/plugin_migration_paths_test.rb`

**Step 1: Write the failing tests**

Add boot-level tests that prove:

- package gem fragments are discovered through one unified bundle
- duplicate identical package gem declarations are collapsed by the host aggregator before Bundler sees them
- compatible version constraints from multiple package declarations are merged into one final Bundler declaration
- conflicting source or non-version loader options for the same package gem fail with an explicit host error
- the package gem DSL is available from `Gemfile` without depending on Rails autoloaded application code
- package migration directories are registered through host-controlled application config

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/extensions/plugin_dependency_loading_test.rb test/extensions/plugin_migration_paths_test.rb`
Expected: FAIL because package dependency and migration aggregation do not exist yet.

**Step 3: Write minimal implementation**

Update the root `Gemfile` and package dependency loader so package `gems.rb` fragments register dependency metadata through a plain Ruby host helper DSL that `Gemfile` can `require_relative` before Rails boot, the host deduplicates exact matches, merges compatible version requirement strings for the same gem before emitting real Bundler `gem` declarations, conflicting source or non-version loader options fail fast with an explicit host error, package migration directories are registered through application configuration, and dependency loading stays build-time only.

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/extensions/plugin_dependency_loading_test.rb test/extensions/plugin_migration_paths_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/Gemfile core_matrix/Gemfile.lock core_matrix/config/application.rb core_matrix/lib/extensions/gem_dependency_registry.rb core_matrix/app/plugins/core/README.md core_matrix/app/plugins/core/webhook_inbox/gems.rb core_matrix/app/plugins/core/telegram/gems.rb core_matrix/app/plugins/core/weixin/gems.rb core_matrix/test/extensions/plugin_dependency_loading_test.rb core_matrix/test/extensions/plugin_migration_paths_test.rb
git commit -m "refactor: aggregate package dependencies and migrations"
```

### Task 3: Rewrite The Host Surface Schema And Rebuild The Database

**Depends on:** Task 2

**Files:**
- Move: `core_matrix/db/migrate/20260415090000_create_ingress_bindings.rb` to `core_matrix/db/migrate/20260415090000_create_surface_bindings.rb`
- Move: `core_matrix/db/migrate/20260415090100_create_channel_connectors.rb` to `core_matrix/db/migrate/20260415090100_create_conversation_scope_bindings.rb`
- Move: `core_matrix/db/migrate/20260415090200_create_channel_sessions.rb` to `core_matrix/db/migrate/20260415090200_create_surface_event_receipts.rb`
- Delete: `core_matrix/db/migrate/20260415090300_create_channel_pairing_requests.rb`
- Move: `core_matrix/db/migrate/20260415090400_create_channel_inbound_messages.rb` to `core_matrix/db/migrate/20260415090400_create_surface_delivery_attempts.rb`
- Delete: `core_matrix/db/migrate/20260415090500_create_channel_deliveries.rb`
- Create: `core_matrix/app/models/surface_binding.rb`
- Create: `core_matrix/app/models/conversation_scope_binding.rb`
- Create: `core_matrix/app/models/surface_event_receipt.rb`
- Create: `core_matrix/app/models/surface_delivery_attempt.rb`
- Delete: `core_matrix/app/models/ingress_binding.rb`
- Delete: `core_matrix/app/models/channel_connector.rb`
- Delete: `core_matrix/app/models/channel_session.rb`
- Delete: `core_matrix/app/models/channel_pairing_request.rb`
- Delete: `core_matrix/app/models/channel_inbound_message.rb`
- Delete: `core_matrix/app/models/channel_delivery.rb`
- Delete: `core_matrix/test/models/ingress_binding_test.rb`
- Delete: `core_matrix/test/models/channel_connector_test.rb`
- Delete: `core_matrix/test/models/channel_session_test.rb`
- Delete: `core_matrix/test/models/channel_pairing_request_test.rb`
- Delete: `core_matrix/test/models/channel_inbound_message_test.rb`
- Delete: `core_matrix/test/models/channel_delivery_test.rb`
- Modify: `core_matrix/app/models/workspace_agent.rb`
- Modify: `core_matrix/app/models/conversation.rb`
- Modify: `core_matrix/app/services/conversations/managed_policy.rb`
- Modify: `core_matrix/db/schema.rb`
- Test: `core_matrix/test/models/surface_binding_test.rb`
- Test: `core_matrix/test/models/conversation_scope_binding_test.rb`
- Test: `core_matrix/test/models/surface_event_receipt_test.rb`
- Test: `core_matrix/test/models/surface_delivery_attempt_test.rb`
- Test: `core_matrix/test/services/conversations/managed_policy_test.rb`

**Step 1: Write the failing tests**

Add tests that prove:

- `SurfaceBinding` owns binding lifecycle, public surface ids, and secrets
- `ConversationScopeBinding` maps one normalized scope key to one conversation
- `SurfaceEventReceipt` supports idempotency lookup by external event key
- `SurfaceDeliveryAttempt` supports generic outbound auditing without platform enums
- conversation managed-policy reporting still works through the new host models

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/models/surface_binding_test.rb test/models/conversation_scope_binding_test.rb test/models/surface_event_receipt_test.rb test/models/surface_delivery_attempt_test.rb test/services/conversations/managed_policy_test.rb`
Expected: FAIL because the new schema and models do not exist yet.

**Step 3: Rewrite the migrations and models**

Implement the new host models and rewrite the original host migrations in place so they create:

- `surface_bindings`
- `conversation_scope_bindings`
- `surface_event_receipts`
- `surface_delivery_attempts`

Delete the old channel/ingress models instead of wrapping them.

**Step 4: Rebuild the database and regenerate `db/schema.rb`**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:drop
rm db/schema.rb
bin/rails db:create
bin/rails db:migrate
bin/rails db:reset
```

Expected: PASS with a regenerated schema matching the rewritten migrations.

**Step 5: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/models/surface_binding_test.rb test/models/conversation_scope_binding_test.rb test/models/surface_event_receipt_test.rb test/models/surface_delivery_attempt_test.rb test/services/conversations/managed_policy_test.rb`
Expected: PASS

**Step 6: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/db/migrate core_matrix/app/models/surface_binding.rb core_matrix/app/models/conversation_scope_binding.rb core_matrix/app/models/surface_event_receipt.rb core_matrix/app/models/surface_delivery_attempt.rb core_matrix/app/models/workspace_agent.rb core_matrix/app/models/conversation.rb core_matrix/app/services/conversations/managed_policy.rb core_matrix/db/schema.rb core_matrix/test/models/surface_binding_test.rb core_matrix/test/models/conversation_scope_binding_test.rb core_matrix/test/models/surface_event_receipt_test.rb core_matrix/test/models/surface_delivery_attempt_test.rb core_matrix/test/services/conversations/managed_policy_test.rb
git rm core_matrix/app/models/ingress_binding.rb core_matrix/app/models/channel_connector.rb core_matrix/app/models/channel_session.rb core_matrix/app/models/channel_pairing_request.rb core_matrix/app/models/channel_inbound_message.rb core_matrix/app/models/channel_delivery.rb
git rm core_matrix/test/models/ingress_binding_test.rb core_matrix/test/models/channel_connector_test.rb core_matrix/test/models/channel_session_test.rb core_matrix/test/models/channel_pairing_request_test.rb core_matrix/test/models/channel_inbound_message_test.rb core_matrix/test/models/channel_delivery_test.rb
git commit -m "refactor: replace channel schema with surface schema"
```

### Task 4: Create Conversation-Surface And Capability Definitions

**Depends on:** Task 3

**Files:**
- Create: `core_matrix/app/extensions/conversation_surfaces/surface_definition.rb`
- Create: `core_matrix/app/extensions/conversation_surfaces/registry.rb`
- Create: `core_matrix/app/extensions/capabilities/capability_definition.rb`
- Create: `core_matrix/app/extensions/capabilities/registry.rb`
- Test: `core_matrix/test/extensions/conversation_surfaces/surface_definition_test.rb`
- Test: `core_matrix/test/extensions/conversation_surfaces/registry_test.rb`
- Test: `core_matrix/test/extensions/capabilities/capability_definition_test.rb`
- Test: `core_matrix/test/extensions/capabilities/registry_test.rb`

**Step 1: Write the failing tests**

Add tests that verify:

- package manifest contributions compile into stable surface and capability definitions
- surface definitions carry transport declarations, subject/thread resolution hooks, and scope policies
- capability definitions carry schema, authorization, backend strategy, and result shape
- registries expose frozen lookups by package key and contract key

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/extensions/conversation_surfaces/surface_definition_test.rb test/extensions/conversation_surfaces/registry_test.rb test/extensions/capabilities/capability_definition_test.rb test/extensions/capabilities/registry_test.rb`
Expected: FAIL because the definition classes do not exist yet.

**Step 3: Write minimal implementation**

Implement manifest-backed definition objects and frozen registries for both contract families.

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/extensions/conversation_surfaces/surface_definition_test.rb test/extensions/conversation_surfaces/registry_test.rb test/extensions/capabilities/capability_definition_test.rb test/extensions/capabilities/registry_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/extensions/conversation_surfaces/surface_definition.rb core_matrix/app/extensions/conversation_surfaces/registry.rb core_matrix/app/extensions/capabilities/capability_definition.rb core_matrix/app/extensions/capabilities/registry.rb core_matrix/test/extensions/conversation_surfaces/surface_definition_test.rb core_matrix/test/extensions/conversation_surfaces/registry_test.rb core_matrix/test/extensions/capabilities/capability_definition_test.rb core_matrix/test/extensions/capabilities/registry_test.rb
git commit -m "refactor: add surface and capability definitions"
```

### Task 5: Build The Capability Invoke Kernel

**Depends on:** Task 4

**Files:**
- Create: `core_matrix/app/extensions/capabilities/invoke.rb`
- Create: `core_matrix/app/extensions/capabilities/result.rb`
- Create: `core_matrix/app/extensions/capabilities/backend_selector.rb`
- Create: `core_matrix/app/extensions/capabilities/runtime_exchange.rb`
- Modify: `core_matrix/app/services/runtime_features/feature_request_exchange.rb`
- Test: `core_matrix/test/extensions/capabilities/invoke_test.rb`
- Test: `core_matrix/test/extensions/capabilities/backend_selector_test.rb`
- Test: `core_matrix/test/extensions/capabilities/runtime_exchange_test.rb`

**Step 1: Write the failing tests**

Add tests that prove:

- one host invoke path can execute an embedded capability
- one host invoke path can select a runtime-delegated capability backend
- result normalization is consistent regardless of backend

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/extensions/capabilities/invoke_test.rb test/extensions/capabilities/backend_selector_test.rb test/extensions/capabilities/runtime_exchange_test.rb`
Expected: FAIL because the capability invoke kernel does not exist yet.

**Step 3: Write minimal implementation**

Implement:

- a single capability invoke entrypoint
- backend selection by capability strategy
- a thin runtime-exchange wrapper around the existing mailbox/request flow

If this task introduces any temporary internal shims so follow-on tasks can migrate incrementally, keep them private to the host implementation and remove them completely in Task 11. No temporary compatibility surface should survive past the capability package migration.

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/extensions/capabilities/invoke_test.rb test/extensions/capabilities/backend_selector_test.rb test/extensions/capabilities/runtime_exchange_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/extensions/capabilities/invoke.rb core_matrix/app/extensions/capabilities/result.rb core_matrix/app/extensions/capabilities/backend_selector.rb core_matrix/app/extensions/capabilities/runtime_exchange.rb core_matrix/app/services/runtime_features/feature_request_exchange.rb core_matrix/test/extensions/capabilities/invoke_test.rb core_matrix/test/extensions/capabilities/backend_selector_test.rb core_matrix/test/extensions/capabilities/runtime_exchange_test.rb
git commit -m "refactor: add capability invoke kernel"
```

### Task 6: Add Generic Surface Controllers And Routes

**Depends on:** Tasks 3 and 4

**Files:**
- Create: `core_matrix/app/controllers/conversation_surfaces/public_endpoints_controller.rb`
- Create: `core_matrix/app/controllers/app_api/workspace_agents/surface_bindings_controller.rb`
- Create: `core_matrix/app/controllers/app_api/workspace_agents/surface_binding_actions_controller.rb`
- Modify: `core_matrix/config/routes.rb`
- Test: `core_matrix/test/requests/conversation_surfaces/public_endpoints_controller_test.rb`
- Test: `core_matrix/test/requests/app_api/workspace_agents/surface_bindings_controller_test.rb`
- Test: `core_matrix/test/requests/app_api/workspace_agents/surface_binding_actions_controller_test.rb`

**Step 1: Write the failing tests**

Add request tests that prove:

- generic public endpoints route by package key and endpoint key
- generic authenticated binding actions route by action key
- binding creation and show payloads are package-aware and use `surface_bindings`
- public surface endpoints do not assume a CoreMatrix user account

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/requests/conversation_surfaces/public_endpoints_controller_test.rb test/requests/app_api/workspace_agents/surface_bindings_controller_test.rb test/requests/app_api/workspace_agents/surface_binding_actions_controller_test.rb`
Expected: FAIL because the generic controllers and routes do not exist yet.

**Step 3: Write minimal implementation**

Add host-owned generic route/controller surfaces for public endpoints, binding CRUD, and authenticated management actions.

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/requests/conversation_surfaces/public_endpoints_controller_test.rb test/requests/app_api/workspace_agents/surface_bindings_controller_test.rb test/requests/app_api/workspace_agents/surface_binding_actions_controller_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/controllers/conversation_surfaces/public_endpoints_controller.rb core_matrix/app/controllers/app_api/workspace_agents/surface_bindings_controller.rb core_matrix/app/controllers/app_api/workspace_agents/surface_binding_actions_controller.rb core_matrix/config/routes.rb core_matrix/test/requests/conversation_surfaces/public_endpoints_controller_test.rb core_matrix/test/requests/app_api/workspace_agents/surface_bindings_controller_test.rb core_matrix/test/requests/app_api/workspace_agents/surface_binding_actions_controller_test.rb
git commit -m "refactor: add generic surface routes"
```

### Task 7: Build The Host Conversation-Surface Kernel And Hot-Path Guards

**Depends on:** Tasks 4 and 6

**Files:**
- Create: `core_matrix/app/extensions/conversation_surfaces/envelope.rb`
- Create: `core_matrix/app/extensions/conversation_surfaces/scope_key.rb`
- Create: `core_matrix/app/extensions/conversation_surfaces/receive_event.rb`
- Create: `core_matrix/app/extensions/conversation_surfaces/create_or_bind_conversation.rb`
- Create: `core_matrix/app/extensions/conversation_surfaces/materialize_turn_entry.rb`
- Create: `core_matrix/app/extensions/conversation_surfaces/attach_materialized_attachments.rb`
- Create: `core_matrix/app/extensions/conversation_surfaces/endpoint_dispatcher.rb`
- Create: `core_matrix/app/extensions/conversation_surfaces/management_action_dispatcher.rb`
- Create: `core_matrix/app/extensions/conversation_surfaces/poller_dispatcher.rb`
- Create: `core_matrix/app/extensions/conversation_surfaces/delivery_dispatcher.rb`
- Create: `core_matrix/app/jobs/conversation_surfaces/dispatch_active_pollers_job.rb`
- Test: `core_matrix/test/extensions/conversation_surfaces/receive_event_test.rb`
- Test: `core_matrix/test/extensions/conversation_surfaces/create_or_bind_conversation_test.rb`
- Test: `core_matrix/test/extensions/conversation_surfaces/endpoint_dispatcher_test.rb`
- Test: `core_matrix/test/extensions/conversation_surfaces/management_action_dispatcher_test.rb`
- Test: `core_matrix/test/extensions/conversation_surfaces/poller_dispatcher_test.rb`
- Test: `core_matrix/test/extensions/conversation_surfaces/delivery_dispatcher_test.rb`
- Test: `core_matrix/test/extensions/conversation_surfaces/create_or_bind_conversation_query_budget_test.rb`
- Test: `core_matrix/test/extensions/conversation_surfaces/receive_event_query_budget_test.rb`
- Test: `core_matrix/test/extensions/conversation_surfaces/delivery_dispatcher_query_budget_test.rb`
- Delete: `core_matrix/test/services/ingress_api/command_surface_test.rb`
- Delete: `core_matrix/test/services/ingress_api/materialize_turn_entry_test.rb`
- Delete: `core_matrix/test/services/ingress_api/preprocessors/authorize_and_pair_test.rb`
- Delete: `core_matrix/test/services/ingress_api/preprocessors/coalesce_burst_test.rb`
- Delete: `core_matrix/test/services/ingress_api/preprocessors/create_or_bind_conversation_test.rb`
- Delete: `core_matrix/test/services/ingress_api/preprocessors/dispatch_command_test.rb`
- Delete: `core_matrix/test/services/ingress_api/preprocessors/materialize_attachments_test.rb`
- Delete: `core_matrix/test/services/ingress_api/preprocessors/resolve_dispatch_decision_test.rb`
- Delete: `core_matrix/test/services/ingress_api/receive_event_test.rb`

**Step 1: Write the failing tests**

Add tests that prove the host can:

- normalize a surface event into one envelope shape
- derive one deterministic `scope_key` from subject/thread claims
- bind or reuse a conversation from one indexed lookup path
- dispatch public endpoints, management actions, pollers, and deliveries without package branching in the host
- stay within explicit query budgets for `CreateOrBindConversation`, `ReceiveEvent`, and `DeliveryDispatcher`
- replace the old ingress-api/preprocessor tests instead of leaving the legacy host path in the suite

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/extensions/conversation_surfaces/receive_event_test.rb test/extensions/conversation_surfaces/create_or_bind_conversation_test.rb test/extensions/conversation_surfaces/endpoint_dispatcher_test.rb test/extensions/conversation_surfaces/management_action_dispatcher_test.rb test/extensions/conversation_surfaces/poller_dispatcher_test.rb test/extensions/conversation_surfaces/delivery_dispatcher_test.rb test/extensions/conversation_surfaces/create_or_bind_conversation_query_budget_test.rb test/extensions/conversation_surfaces/receive_event_query_budget_test.rb test/extensions/conversation_surfaces/delivery_dispatcher_query_budget_test.rb`
Expected: FAIL because the host conversation-surface kernel does not exist yet.

**Step 3: Write minimal implementation**

Implement the host conversation-surface kernel so runtime dispatch is registry lookup plus handler execution, and so conversation binding is derived from `scope_key` instead of platform-specific session logic.

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/extensions/conversation_surfaces/receive_event_test.rb test/extensions/conversation_surfaces/create_or_bind_conversation_test.rb test/extensions/conversation_surfaces/endpoint_dispatcher_test.rb test/extensions/conversation_surfaces/management_action_dispatcher_test.rb test/extensions/conversation_surfaces/poller_dispatcher_test.rb test/extensions/conversation_surfaces/delivery_dispatcher_test.rb test/extensions/conversation_surfaces/create_or_bind_conversation_query_budget_test.rb test/extensions/conversation_surfaces/receive_event_query_budget_test.rb test/extensions/conversation_surfaces/delivery_dispatcher_query_budget_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/extensions/conversation_surfaces core_matrix/app/jobs/conversation_surfaces/dispatch_active_pollers_job.rb core_matrix/test/extensions/conversation_surfaces
git rm core_matrix/test/services/ingress_api/command_surface_test.rb core_matrix/test/services/ingress_api/materialize_turn_entry_test.rb core_matrix/test/services/ingress_api/preprocessors/authorize_and_pair_test.rb core_matrix/test/services/ingress_api/preprocessors/coalesce_burst_test.rb core_matrix/test/services/ingress_api/preprocessors/create_or_bind_conversation_test.rb core_matrix/test/services/ingress_api/preprocessors/dispatch_command_test.rb core_matrix/test/services/ingress_api/preprocessors/materialize_attachments_test.rb core_matrix/test/services/ingress_api/preprocessors/resolve_dispatch_decision_test.rb core_matrix/test/services/ingress_api/receive_event_test.rb
git commit -m "refactor: add conversation surface kernel"
```

### Task 8: Package The Generic Webhook Surface

**Depends on:** Tasks 2, 4, 6, and 7

**Files:**
- Create: `core_matrix/app/plugins/core/webhook_inbox/plugin.rb`
- Create: `core_matrix/app/plugins/core/webhook_inbox/conversation_surfaces/webhook_inbox.rb`
- Create: `core_matrix/app/plugins/core/webhook_inbox/public_endpoints/events.rb`
- Create: `core_matrix/app/plugins/core/webhook_inbox/management_actions/configure.rb`
- Create: `core_matrix/app/plugins/core/webhook_inbox/management_actions/status.rb`
- Create: `core_matrix/app/plugins/core/webhook_inbox/management_actions/rotate_secret.rb`
- Create: `core_matrix/app/plugins/core/webhook_inbox/deliveries/post_callback.rb`
- Test: `core_matrix/test/plugins/core/webhook_inbox/public_endpoints/events_test.rb`
- Test: `core_matrix/test/plugins/core/webhook_inbox/deliveries/post_callback_test.rb`
- Test: `core_matrix/test/requests/app_api/workspace_agents/surface_binding_actions_controller_test.rb`

**Step 1: Write the failing tests**

Add tests that prove:

- a SaaS-style webhook sender can POST canonical event payloads into a surface binding
- the webhook package authenticates requests and rotates secrets through generic actions
- outbound replies can be delivered through a configured callback URL

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/plugins/core/webhook_inbox/public_endpoints/events_test.rb test/plugins/core/webhook_inbox/deliveries/post_callback_test.rb test/requests/app_api/workspace_agents/surface_binding_actions_controller_test.rb`
Expected: FAIL because the webhook package does not exist yet.

**Step 3: Write minimal implementation**

Implement the `webhook_inbox` package as the first reference conversation surface using:

- `webhook` ingress transport
- canonical JSON payload normalization
- generic management actions
- `callback_delivery` for outbound responses

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/plugins/core/webhook_inbox/public_endpoints/events_test.rb test/plugins/core/webhook_inbox/deliveries/post_callback_test.rb test/requests/app_api/workspace_agents/surface_binding_actions_controller_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/plugins/core/webhook_inbox core_matrix/test/plugins/core/webhook_inbox core_matrix/test/requests/app_api/workspace_agents/surface_binding_actions_controller_test.rb
git commit -m "feat: add generic webhook conversation surface"
```

### Task 9: Package `conversation_title` As A Capability

**Depends on:** Tasks 4 and 5

**Files:**
- Create: `core_matrix/app/plugins/core/conversation_title/plugin.rb`
- Create: `core_matrix/app/plugins/core/conversation_title/capabilities/conversation_title.rb`
- Delete: `core_matrix/app/services/embedded_agents/conversation_title/invoke.rb`
- Delete: `core_matrix/test/services/embedded_agents/conversation_title/invoke_test.rb`
- Test: `core_matrix/test/plugins/core/conversation_title/capability_test.rb`
- Test: `core_matrix/test/extensions/capabilities/invoke_test.rb`

**Step 1: Write the failing tests**

Update capability tests so `conversation_title` resolves through the package registry and capability invoke path.

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/plugins/core/conversation_title/capability_test.rb test/extensions/capabilities/invoke_test.rb`
Expected: FAIL because `conversation_title` is not package-backed yet.

**Step 3: Write minimal implementation**

Move `conversation_title` into a capability package and invoke it through the host capability kernel.

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/plugins/core/conversation_title/capability_test.rb test/extensions/capabilities/invoke_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/plugins/core/conversation_title core_matrix/test/plugins/core/conversation_title/capability_test.rb core_matrix/test/extensions/capabilities/invoke_test.rb
git rm core_matrix/app/services/embedded_agents/conversation_title/invoke.rb
git rm core_matrix/test/services/embedded_agents/conversation_title/invoke_test.rb
git commit -m "refactor: package conversation title as capability"
```

### Task 10: Package `conversation_supervision` As A Capability

**Depends on:** Tasks 4 and 5

**Files:**
- Create: `core_matrix/app/plugins/core/conversation_supervision/plugin.rb`
- Create: `core_matrix/app/plugins/core/conversation_supervision/capabilities/conversation_supervision.rb`
- Move: `core_matrix/app/services/embedded_agents/conversation_supervision/append_message.rb`
- Move: `core_matrix/app/services/embedded_agents/conversation_supervision/authority.rb`
- Move: `core_matrix/app/services/embedded_agents/conversation_supervision/build_human_sidechat.rb`
- Move: `core_matrix/app/services/embedded_agents/conversation_supervision/build_human_summary.rb`
- Move: `core_matrix/app/services/embedded_agents/conversation_supervision/build_machine_status.rb`
- Move: `core_matrix/app/services/embedded_agents/conversation_supervision/build_snapshot.rb`
- Move: `core_matrix/app/services/embedded_agents/conversation_supervision/classify_control_intent.rb`
- Move: `core_matrix/app/services/embedded_agents/conversation_supervision/close_session.rb`
- Move: `core_matrix/app/services/embedded_agents/conversation_supervision/create_session.rb`
- Move: `core_matrix/app/services/embedded_agents/conversation_supervision/maybe_dispatch_control_intent.rb`
- Move: `core_matrix/app/services/embedded_agents/conversation_supervision/responders/build_prompt_payload.rb`
- Move: `core_matrix/app/services/embedded_agents/conversation_supervision/responders/builtin.rb`
- Move: `core_matrix/app/services/embedded_agents/conversation_supervision/responders/hybrid.rb`
- Move: `core_matrix/app/services/embedded_agents/conversation_supervision/responders/summary_model.rb`
- Delete: `core_matrix/app/services/embedded_agents/conversation_supervision/invoke.rb`
- Test: `core_matrix/test/plugins/core/conversation_supervision/capability_test.rb`
- Test: `core_matrix/test/plugins/core/conversation_supervision/append_message_test.rb`
- Test: `core_matrix/test/plugins/core/conversation_supervision/authority_test.rb`
- Test: `core_matrix/test/plugins/core/conversation_supervision/build_snapshot_test.rb`
- Test: `core_matrix/test/plugins/core/conversation_supervision/classify_control_intent_test.rb`
- Test: `core_matrix/test/plugins/core/conversation_supervision/close_session_test.rb`
- Test: `core_matrix/test/plugins/core/conversation_supervision/create_session_test.rb`
- Test: `core_matrix/test/plugins/core/conversation_supervision/maybe_dispatch_control_intent_test.rb`
- Test: `core_matrix/test/plugins/core/conversation_supervision/responders/builtin_test.rb`
- Test: `core_matrix/test/plugins/core/conversation_supervision/responders/summary_model_test.rb`

**Step 1: Write the failing tests**

Update the supervision tests so they expect package-backed capability ownership and host capability invocation.

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/plugins/core/conversation_supervision/capability_test.rb test/plugins/core/conversation_supervision/append_message_test.rb test/plugins/core/conversation_supervision/authority_test.rb test/plugins/core/conversation_supervision/build_snapshot_test.rb test/plugins/core/conversation_supervision/classify_control_intent_test.rb test/plugins/core/conversation_supervision/close_session_test.rb test/plugins/core/conversation_supervision/create_session_test.rb test/plugins/core/conversation_supervision/maybe_dispatch_control_intent_test.rb test/plugins/core/conversation_supervision/responders/builtin_test.rb test/plugins/core/conversation_supervision/responders/summary_model_test.rb`
Expected: FAIL because `conversation_supervision` is not package-backed yet.

**Step 3: Write minimal implementation**

Move `conversation_supervision` into a capability package and remove the old service invoke entrypoint.

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/plugins/core/conversation_supervision/capability_test.rb test/plugins/core/conversation_supervision/append_message_test.rb test/plugins/core/conversation_supervision/authority_test.rb test/plugins/core/conversation_supervision/build_snapshot_test.rb test/plugins/core/conversation_supervision/classify_control_intent_test.rb test/plugins/core/conversation_supervision/close_session_test.rb test/plugins/core/conversation_supervision/create_session_test.rb test/plugins/core/conversation_supervision/maybe_dispatch_control_intent_test.rb test/plugins/core/conversation_supervision/responders/builtin_test.rb test/plugins/core/conversation_supervision/responders/summary_model_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/plugins/core/conversation_supervision core_matrix/test/plugins/core/conversation_supervision
git rm core_matrix/app/services/embedded_agents/conversation_supervision/invoke.rb
git rm -r core_matrix/test/services/embedded_agents/conversation_supervision
git commit -m "refactor: package conversation supervision as capability"
```

### Task 11: Package `title_bootstrap` And `prompt_compaction` Through The Capability Kernel

**Depends on:** Tasks 5 and 9

**Files:**
- Create: `core_matrix/app/plugins/core/title_bootstrap/plugin.rb`
- Create: `core_matrix/app/plugins/core/title_bootstrap/capabilities/title_bootstrap.rb`
- Create: `core_matrix/app/plugins/core/prompt_compaction/plugin.rb`
- Create: `core_matrix/app/plugins/core/prompt_compaction/capabilities/prompt_compaction.rb`
- Delete: `core_matrix/app/services/embedded_agents/invoke.rb`
- Delete: `core_matrix/app/services/embedded_agents/registry.rb`
- Delete: `core_matrix/app/services/embedded_agents/result.rb`
- Delete: `core_matrix/app/services/embedded_agents/errors.rb`
- Delete: `core_matrix/app/services/embedded_features/title_bootstrap/invoke.rb`
- Delete: `core_matrix/app/services/embedded_features/prompt_compaction/invoke.rb`
- Delete: `core_matrix/app/services/runtime_features/feature_request_exchange.rb`
- Delete: `core_matrix/app/services/runtime_features/invoke.rb`
- Delete: `core_matrix/app/services/runtime_features/policy_resolver.rb`
- Delete: `core_matrix/app/services/runtime_features/capability_resolver.rb`
- Delete: `core_matrix/app/services/runtime_features/registry.rb`
- Delete: `core_matrix/app/services/runtime_features/title_bootstrap/orchestrator.rb`
- Test: `core_matrix/test/plugins/core/title_bootstrap/capability_test.rb`
- Test: `core_matrix/test/plugins/core/prompt_compaction/capability_test.rb`
- Test: `core_matrix/test/services/conversations/metadata/runtime_bootstrap_title_test.rb`
- Test: `core_matrix/test/jobs/conversations/metadata/bootstrap_title_job_test.rb`
- Test: `core_matrix/test/services/provider_execution/prompt_compaction_strategy_test.rb`
- Test: `core_matrix/test/services/provider_execution/execute_prompt_compaction_node_test.rb`
- Delete: `core_matrix/test/services/embedded_agents/invoke_test.rb`
- Delete: `core_matrix/test/services/embedded_features/title_bootstrap/invoke_test.rb`
- Delete: `core_matrix/test/services/embedded_features/prompt_compaction/invoke_test.rb`
- Delete: `core_matrix/test/services/runtime_features/feature_request_exchange_test.rb`
- Delete: `core_matrix/test/services/runtime_features/invoke_test.rb`
- Delete: `core_matrix/test/services/runtime_features/policy_resolver_test.rb`
- Delete: `core_matrix/test/services/runtime_features/capability_resolver_test.rb`
- Delete: `core_matrix/test/services/runtime_features/registry_test.rb`

**Step 1: Write the failing tests**

Update bootstrap and prompt-compaction tests so they expect package-backed capabilities and the new capability kernel instead of `runtime_features`, and remove the remaining legacy service tests once the capability kernel owns those paths.

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/plugins/core/title_bootstrap/capability_test.rb test/plugins/core/prompt_compaction/capability_test.rb test/extensions/capabilities/runtime_exchange_test.rb test/services/conversations/metadata/runtime_bootstrap_title_test.rb test/jobs/conversations/metadata/bootstrap_title_job_test.rb test/services/provider_execution/prompt_compaction_strategy_test.rb test/services/provider_execution/execute_prompt_compaction_node_test.rb`
Expected: FAIL because the old feature systems still own these paths.

**Step 3: Write minimal implementation**

Move `title_bootstrap` and `prompt_compaction` into capability packages, route backend selection through the capability kernel, and delete the old `embedded_agents`, `embedded_features`, and `runtime_features` service entrypoints instead of leaving compatibility wrappers behind.

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/plugins/core/title_bootstrap/capability_test.rb test/plugins/core/prompt_compaction/capability_test.rb test/extensions/capabilities/runtime_exchange_test.rb test/services/conversations/metadata/runtime_bootstrap_title_test.rb test/jobs/conversations/metadata/bootstrap_title_job_test.rb test/services/provider_execution/prompt_compaction_strategy_test.rb test/services/provider_execution/execute_prompt_compaction_node_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/plugins/core/title_bootstrap core_matrix/app/plugins/core/prompt_compaction core_matrix/test/plugins/core/title_bootstrap/capability_test.rb core_matrix/test/plugins/core/prompt_compaction/capability_test.rb core_matrix/test/services/conversations/metadata/runtime_bootstrap_title_test.rb core_matrix/test/jobs/conversations/metadata/bootstrap_title_job_test.rb core_matrix/test/services/provider_execution/prompt_compaction_strategy_test.rb core_matrix/test/services/provider_execution/execute_prompt_compaction_node_test.rb
git rm core_matrix/app/services/embedded_agents/invoke.rb core_matrix/app/services/embedded_agents/registry.rb core_matrix/app/services/embedded_agents/result.rb core_matrix/app/services/embedded_agents/errors.rb core_matrix/app/services/embedded_features/title_bootstrap/invoke.rb core_matrix/app/services/embedded_features/prompt_compaction/invoke.rb core_matrix/app/services/runtime_features/feature_request_exchange.rb core_matrix/app/services/runtime_features/invoke.rb core_matrix/app/services/runtime_features/policy_resolver.rb core_matrix/app/services/runtime_features/capability_resolver.rb core_matrix/app/services/runtime_features/registry.rb core_matrix/app/services/runtime_features/title_bootstrap/orchestrator.rb
git rm core_matrix/test/services/embedded_agents/invoke_test.rb core_matrix/test/services/embedded_features/title_bootstrap/invoke_test.rb core_matrix/test/services/embedded_features/prompt_compaction/invoke_test.rb core_matrix/test/services/runtime_features/feature_request_exchange_test.rb core_matrix/test/services/runtime_features/invoke_test.rb core_matrix/test/services/runtime_features/policy_resolver_test.rb core_matrix/test/services/runtime_features/capability_resolver_test.rb core_matrix/test/services/runtime_features/registry_test.rb
git commit -m "refactor: replace runtime features with capabilities"
```

### Task 12: Package Telegram As A Conversation Surface

**Depends on:** Tasks 7 and 8

**Files:**
- Create: `core_matrix/app/plugins/core/telegram/plugin.rb`
- Create: `core_matrix/app/plugins/core/telegram/conversation_surfaces/telegram.rb`
- Create: `core_matrix/app/plugins/core/telegram/public_endpoints/webhook_update.rb`
- Create: `core_matrix/app/plugins/core/telegram/pollers/poll_updates.rb`
- Create: `core_matrix/app/plugins/core/telegram/deliveries/send_reply.rb`
- Create: `core_matrix/app/plugins/core/telegram/management_actions/configure.rb`
- Create: `core_matrix/app/plugins/core/telegram/management_actions/status.rb`
- Create: `core_matrix/app/plugins/core/telegram/management_actions/rotate_secret.rb`
- Move: `core_matrix/app/services/ingress_api/telegram/client.rb`
- Move: `core_matrix/app/services/ingress_api/telegram/download_attachment.rb`
- Move: `core_matrix/app/services/ingress_api/telegram/normalize_update.rb`
- Move: `core_matrix/app/services/ingress_api/telegram/progress_bridge.rb`
- Move: `core_matrix/app/services/ingress_api/telegram/receive_polled_update.rb`
- Move: `core_matrix/app/services/ingress_api/telegram/verify_request.rb`
- Move: `core_matrix/test/services/ingress_api/telegram/client_test.rb` to `core_matrix/test/plugins/core/telegram/client_test.rb`
- Move: `core_matrix/test/services/ingress_api/telegram/download_attachment_test.rb` to `core_matrix/test/plugins/core/telegram/download_attachment_test.rb`
- Move: `core_matrix/test/services/ingress_api/telegram/normalize_update_test.rb` to `core_matrix/test/plugins/core/telegram/normalize_update_test.rb`
- Move: `core_matrix/test/services/ingress_api/telegram/progress_bridge_test.rb` to `core_matrix/test/plugins/core/telegram/progress_bridge_test.rb`
- Move: `core_matrix/test/services/ingress_api/telegram/receive_polled_update_test.rb` to `core_matrix/test/plugins/core/telegram/receive_polled_update_test.rb`
- Move: `core_matrix/test/services/ingress_api/telegram/verify_request_test.rb` to `core_matrix/test/plugins/core/telegram/verify_request_test.rb`
- Delete: `core_matrix/test/requests/ingress_api/telegram/updates_controller_test.rb`
- Delete: `core_matrix/test/jobs/channel_connectors/telegram_poll_updates_job_test.rb`
- Delete: `core_matrix/test/services/channel_deliveries/send_telegram_reply_test.rb`
- Modify: `core_matrix/test/requests/conversation_surfaces/public_endpoints_controller_test.rb`
- Test: `core_matrix/test/plugins/core/telegram/normalize_update_test.rb`
- Test: `core_matrix/test/plugins/core/telegram/client_test.rb`
- Test: `core_matrix/test/plugins/core/telegram/download_attachment_test.rb`
- Test: `core_matrix/test/plugins/core/telegram/group_scope_test.rb`
- Test: `core_matrix/test/plugins/core/telegram/progress_bridge_test.rb`
- Test: `core_matrix/test/plugins/core/telegram/verify_request_test.rb`
- Test: `core_matrix/test/plugins/core/telegram/receive_polled_update_test.rb`
- Test: `core_matrix/test/plugins/core/telegram/send_reply_test.rb`

**Step 1: Write the failing tests**

Update Telegram tests so they expect package-backed webhook handling, polling, outbound delivery, and shared-surface normalization for groups and threaded topics.

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/plugins/core/telegram/client_test.rb test/plugins/core/telegram/download_attachment_test.rb test/plugins/core/telegram/normalize_update_test.rb test/plugins/core/telegram/group_scope_test.rb test/plugins/core/telegram/progress_bridge_test.rb test/plugins/core/telegram/verify_request_test.rb test/plugins/core/telegram/receive_polled_update_test.rb test/plugins/core/telegram/send_reply_test.rb test/requests/conversation_surfaces/public_endpoints_controller_test.rb`
Expected: FAIL because Telegram is not package-backed yet.

**Step 3: Write minimal implementation**

Move Telegram behavior into the conversation-surface package and preserve support for:

- DM and group chats
- thread/topic keys
- unfamiliar senders in shared chats
- webhook and poller transports through one surface definition

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/plugins/core/telegram/client_test.rb test/plugins/core/telegram/download_attachment_test.rb test/plugins/core/telegram/normalize_update_test.rb test/plugins/core/telegram/group_scope_test.rb test/plugins/core/telegram/progress_bridge_test.rb test/plugins/core/telegram/verify_request_test.rb test/plugins/core/telegram/receive_polled_update_test.rb test/plugins/core/telegram/send_reply_test.rb test/requests/conversation_surfaces/public_endpoints_controller_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/plugins/core/telegram core_matrix/test/plugins/core/telegram core_matrix/test/requests/conversation_surfaces/public_endpoints_controller_test.rb
git rm core_matrix/test/requests/ingress_api/telegram/updates_controller_test.rb core_matrix/test/jobs/channel_connectors/telegram_poll_updates_job_test.rb core_matrix/test/services/channel_deliveries/send_telegram_reply_test.rb
git commit -m "refactor: package telegram as conversation surface"
```

### Task 13: Package Weixin As A Conversation Surface

**Depends on:** Tasks 7 and 8

**Files:**
- Create: `core_matrix/app/plugins/core/weixin/plugin.rb`
- Create: `core_matrix/app/plugins/core/weixin/conversation_surfaces/weixin.rb`
- Create: `core_matrix/app/plugins/core/weixin/pollers/poll_account.rb`
- Create: `core_matrix/app/plugins/core/weixin/deliveries/send_reply.rb`
- Create: `core_matrix/app/plugins/core/weixin/management_actions/configure.rb`
- Create: `core_matrix/app/plugins/core/weixin/management_actions/status.rb`
- Create: `core_matrix/app/plugins/core/weixin/management_actions/start_pairing.rb`
- Create: `core_matrix/app/plugins/core/weixin/management_actions/pairing_status.rb`
- Create: `core_matrix/app/plugins/core/weixin/management_actions/disconnect.rb`
- Create: `core_matrix/app/plugins/core/weixin/models/login_session.rb`
- Create: `core_matrix/app/plugins/core/weixin/db/migrate/20260418000001_create_core_weixin_login_sessions.rb`
- Create: `core_matrix/app/plugins/core/weixin/lib/client.rb`
- Create: `core_matrix/app/plugins/core/weixin/lib/context_token_store.rb`
- Create: `core_matrix/app/plugins/core/weixin/lib/media_client.rb`
- Create: `core_matrix/app/plugins/core/weixin/lib/normalize_message.rb`
- Create: `core_matrix/app/plugins/core/weixin/lib/poller.rb`
- Create: `core_matrix/app/plugins/core/weixin/lib/qr_login.rb`
- Move: `core_matrix/app/services/ingress_api/weixin/progress_bridge.rb`
- Move: `core_matrix/app/services/ingress_api/weixin/receive_polled_message.rb`
- Move: `core_matrix/test/services/ingress_api/weixin/progress_bridge_test.rb` to `core_matrix/test/plugins/core/weixin/progress_bridge_test.rb`
- Move: `core_matrix/test/services/ingress_api/weixin/receive_polled_message_test.rb` to `core_matrix/test/plugins/core/weixin/receive_polled_message_test.rb`
- Delete: `core_matrix/test/jobs/channel_connectors/weixin_poll_account_job_test.rb`
- Delete: `core_matrix/test/services/channel_deliveries/send_weixin_reply_test.rb`
- Test: `core_matrix/test/plugins/core/weixin/receive_polled_message_test.rb`
- Test: `core_matrix/test/plugins/core/weixin/progress_bridge_test.rb`
- Test: `core_matrix/test/plugins/core/weixin/send_reply_test.rb`
- Test: `core_matrix/test/plugins/core/weixin/lib/client_test.rb`
- Test: `core_matrix/test/plugins/core/weixin/lib/context_token_store_test.rb`
- Test: `core_matrix/test/plugins/core/weixin/lib/media_client_test.rb`
- Test: `core_matrix/test/plugins/core/weixin/lib/normalize_message_test.rb`
- Test: `core_matrix/test/plugins/core/weixin/lib/poller_test.rb`
- Test: `core_matrix/test/plugins/core/weixin/lib/qr_login_test.rb`
- Test: `core_matrix/test/requests/app_api/workspace_agents/surface_binding_actions_controller_test.rb`

**Step 1: Write the failing tests**

Update Weixin tests so they expect package-backed polling, delivery, and generic management actions for pairing flows.

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/plugins/core/weixin/receive_polled_message_test.rb test/plugins/core/weixin/progress_bridge_test.rb test/plugins/core/weixin/send_reply_test.rb test/plugins/core/weixin/lib/client_test.rb test/plugins/core/weixin/lib/context_token_store_test.rb test/plugins/core/weixin/lib/media_client_test.rb test/plugins/core/weixin/lib/normalize_message_test.rb test/plugins/core/weixin/lib/poller_test.rb test/plugins/core/weixin/lib/qr_login_test.rb test/requests/app_api/workspace_agents/surface_binding_actions_controller_test.rb`
Expected: FAIL because Weixin is not package-backed yet.

**Step 3: Write minimal implementation**

Move Weixin behavior and package-private support code into a surface package, keep pairing/login state in package-owned persistence, and route all operator actions through generic surface management actions. Delete the root `core_matrix/lib/claw_bot_sdk/weixin/*` tree once the package-local replacements exist.

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/plugins/core/weixin/receive_polled_message_test.rb test/plugins/core/weixin/progress_bridge_test.rb test/plugins/core/weixin/send_reply_test.rb test/plugins/core/weixin/lib/client_test.rb test/plugins/core/weixin/lib/context_token_store_test.rb test/plugins/core/weixin/lib/media_client_test.rb test/plugins/core/weixin/lib/normalize_message_test.rb test/plugins/core/weixin/lib/poller_test.rb test/plugins/core/weixin/lib/qr_login_test.rb test/requests/app_api/workspace_agents/surface_binding_actions_controller_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/plugins/core/weixin core_matrix/test/plugins/core/weixin core_matrix/test/requests/app_api/workspace_agents/surface_binding_actions_controller_test.rb
git rm core_matrix/lib/claw_bot_sdk/weixin/client.rb core_matrix/lib/claw_bot_sdk/weixin/context_token_store.rb core_matrix/lib/claw_bot_sdk/weixin/media_client.rb core_matrix/lib/claw_bot_sdk/weixin/normalize_message.rb core_matrix/lib/claw_bot_sdk/weixin/poller.rb core_matrix/lib/claw_bot_sdk/weixin/qr_login.rb
git rm core_matrix/test/lib/claw_bot_sdk/weixin/client_test.rb core_matrix/test/lib/claw_bot_sdk/weixin/context_token_store_test.rb core_matrix/test/lib/claw_bot_sdk/weixin/media_client_test.rb core_matrix/test/lib/claw_bot_sdk/weixin/normalize_message_test.rb core_matrix/test/lib/claw_bot_sdk/weixin/poller_test.rb core_matrix/test/lib/claw_bot_sdk/weixin/qr_login_test.rb
git rm core_matrix/test/jobs/channel_connectors/weixin_poll_account_job_test.rb core_matrix/test/services/channel_deliveries/send_weixin_reply_test.rb
git commit -m "refactor: package weixin as conversation surface"
```

### Task 14: Remove Legacy Ingress, Channel, And Platform Branching

**Depends on:** Tasks 7, 12, and 13

**Files:**
- Delete: `core_matrix/app/controllers/app_api/workspace_agents/ingress_bindings_controller.rb`
- Delete: `core_matrix/app/controllers/app_api/workspace_agents/ingress_bindings/pairing_requests_controller.rb`
- Delete: `core_matrix/app/controllers/app_api/workspace_agents/ingress_bindings/sessions_controller.rb`
- Delete: `core_matrix/app/controllers/ingress_api/telegram/updates_controller.rb`
- Delete: `core_matrix/app/jobs/channel_connectors/dispatch_active_pollers_job.rb`
- Delete: `core_matrix/app/jobs/channel_connectors/telegram_poll_updates_job.rb`
- Delete: `core_matrix/app/jobs/channel_connectors/weixin_poll_account_job.rb`
- Delete: `core_matrix/app/services/ingress_api/attach_materialized_attachments.rb`
- Delete: `core_matrix/app/services/ingress_api/context.rb`
- Delete: `core_matrix/app/services/ingress_api/envelope.rb`
- Delete: `core_matrix/app/services/ingress_api/materialize_turn_entry.rb`
- Delete: `core_matrix/app/services/ingress_api/middleware/capture_raw_payload.rb`
- Delete: `core_matrix/app/services/ingress_api/middleware/deduplicate_inbound.rb`
- Delete: `core_matrix/app/services/ingress_api/middleware/verify_request.rb`
- Delete: `core_matrix/app/services/ingress_api/preprocessors/authorize_and_pair.rb`
- Delete: `core_matrix/app/services/ingress_api/preprocessors/coalesce_burst.rb`
- Delete: `core_matrix/app/services/ingress_api/preprocessors/create_or_bind_conversation.rb`
- Delete: `core_matrix/app/services/ingress_api/preprocessors/dispatch_command.rb`
- Delete: `core_matrix/app/services/ingress_api/preprocessors/materialize_attachments.rb`
- Delete: `core_matrix/app/services/ingress_api/preprocessors/resolve_channel_session.rb`
- Delete: `core_matrix/app/services/ingress_api/preprocessors/resolve_dispatch_decision.rb`
- Delete: `core_matrix/app/services/ingress_api/receive_event.rb`
- Delete: `core_matrix/app/services/ingress_api/result.rb`
- Delete: `core_matrix/app/services/ingress_api/transport_adapter.rb`
- Delete: `core_matrix/app/services/channel_deliveries/dispatch_conversation_output.rb`
- Delete: `core_matrix/app/services/channel_deliveries/dispatch_runtime_progress.rb`
- Delete: `core_matrix/app/services/channel_deliveries/send_telegram_reply.rb`
- Delete: `core_matrix/app/services/channel_deliveries/send_weixin_reply.rb`
- Delete: `core_matrix/app/services/ingress_bindings/update_connector.rb`
- Delete: `core_matrix/test/requests/app_api/workspace_agents/ingress_bindings_controller_test.rb`
- Delete: `core_matrix/test/requests/app_api/workspace_agents/ingress_bindings/pairing_requests_controller_test.rb`
- Delete: `core_matrix/test/requests/app_api/workspace_agents/ingress_bindings/sessions_controller_test.rb`
- Delete: `core_matrix/test/jobs/channel_connectors/dispatch_active_pollers_job_test.rb`
- Delete: `core_matrix/test/services/channel_deliveries/dispatch_conversation_output_test.rb`
- Delete: `core_matrix/test/services/ingress_bindings/update_connector_test.rb`
- Modify: `core_matrix/app/services/provider_execution/persist_turn_step_success.rb`
- Modify: `core_matrix/test/services/provider_execution/persist_turn_step_success_test.rb`
- Modify: `core_matrix/config/recurring.yml`
- Modify: `core_matrix/test/config/data_retention_configuration_test.rb`
- Modify: `core_matrix/test/requests/app_api/workspace_agents/surface_bindings_controller_test.rb`
- Modify: `core_matrix/test/requests/app_api/workspace_agents/surface_binding_actions_controller_test.rb`
- Modify: `core_matrix/test/extensions/conversation_surfaces/poller_dispatcher_test.rb`
- Modify: `core_matrix/test/extensions/conversation_surfaces/delivery_dispatcher_test.rb`

**Step 1: Write the failing tests**

Update the remaining host tests so they expect:

- no `ingress_bindings` controller namespace
- no `channel_connectors` or `channel_deliveries` dispatch path
- no recurring job or provider-execution references to the deleted channel dispatchers
- host dispatch only through conversation-surface registries and bindings

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/requests/app_api/workspace_agents/surface_bindings_controller_test.rb test/requests/app_api/workspace_agents/surface_binding_actions_controller_test.rb test/extensions/conversation_surfaces/poller_dispatcher_test.rb test/extensions/conversation_surfaces/delivery_dispatcher_test.rb test/services/provider_execution/persist_turn_step_success_test.rb test/config/data_retention_configuration_test.rb`
Expected: FAIL because old host branching and legacy wrappers still exist.

**Step 3: Write minimal implementation**

Delete the old ingress/channel/service paths, retarget provider execution and recurring poller dispatch onto the new surface kernel, and remove the remaining platform branching from host code.

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/requests/app_api/workspace_agents/surface_bindings_controller_test.rb test/requests/app_api/workspace_agents/surface_binding_actions_controller_test.rb test/extensions/conversation_surfaces/poller_dispatcher_test.rb test/extensions/conversation_surfaces/delivery_dispatcher_test.rb test/services/provider_execution/persist_turn_step_success_test.rb test/config/data_retention_configuration_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/controllers/app_api/workspace_agents/surface_bindings_controller.rb core_matrix/app/controllers/app_api/workspace_agents/surface_binding_actions_controller.rb core_matrix/app/controllers/conversation_surfaces/public_endpoints_controller.rb core_matrix/config/routes.rb core_matrix/config/recurring.yml core_matrix/app/extensions/conversation_surfaces core_matrix/app/services/provider_execution/persist_turn_step_success.rb core_matrix/test/requests/app_api/workspace_agents/surface_bindings_controller_test.rb core_matrix/test/requests/app_api/workspace_agents/surface_binding_actions_controller_test.rb core_matrix/test/extensions/conversation_surfaces/poller_dispatcher_test.rb core_matrix/test/extensions/conversation_surfaces/delivery_dispatcher_test.rb core_matrix/test/services/provider_execution/persist_turn_step_success_test.rb core_matrix/test/config/data_retention_configuration_test.rb
git rm core_matrix/app/controllers/app_api/workspace_agents/ingress_bindings_controller.rb core_matrix/app/controllers/app_api/workspace_agents/ingress_bindings/pairing_requests_controller.rb core_matrix/app/controllers/app_api/workspace_agents/ingress_bindings/sessions_controller.rb core_matrix/app/controllers/ingress_api/telegram/updates_controller.rb
git rm core_matrix/app/jobs/channel_connectors/dispatch_active_pollers_job.rb core_matrix/app/jobs/channel_connectors/telegram_poll_updates_job.rb core_matrix/app/jobs/channel_connectors/weixin_poll_account_job.rb core_matrix/app/services/ingress_api/attach_materialized_attachments.rb core_matrix/app/services/ingress_api/context.rb core_matrix/app/services/ingress_api/envelope.rb core_matrix/app/services/ingress_api/materialize_turn_entry.rb core_matrix/app/services/ingress_api/middleware/capture_raw_payload.rb core_matrix/app/services/ingress_api/middleware/deduplicate_inbound.rb core_matrix/app/services/ingress_api/middleware/verify_request.rb core_matrix/app/services/ingress_api/preprocessors/authorize_and_pair.rb core_matrix/app/services/ingress_api/preprocessors/coalesce_burst.rb core_matrix/app/services/ingress_api/preprocessors/create_or_bind_conversation.rb core_matrix/app/services/ingress_api/preprocessors/dispatch_command.rb core_matrix/app/services/ingress_api/preprocessors/materialize_attachments.rb core_matrix/app/services/ingress_api/preprocessors/resolve_channel_session.rb core_matrix/app/services/ingress_api/preprocessors/resolve_dispatch_decision.rb core_matrix/app/services/ingress_api/receive_event.rb core_matrix/app/services/ingress_api/result.rb core_matrix/app/services/ingress_api/transport_adapter.rb core_matrix/app/services/channel_deliveries/dispatch_conversation_output.rb core_matrix/app/services/channel_deliveries/dispatch_runtime_progress.rb core_matrix/app/services/channel_deliveries/send_telegram_reply.rb core_matrix/app/services/channel_deliveries/send_weixin_reply.rb core_matrix/app/services/ingress_bindings/update_connector.rb
git rm core_matrix/test/requests/app_api/workspace_agents/ingress_bindings_controller_test.rb core_matrix/test/requests/app_api/workspace_agents/ingress_bindings/pairing_requests_controller_test.rb core_matrix/test/requests/app_api/workspace_agents/ingress_bindings/sessions_controller_test.rb core_matrix/test/jobs/channel_connectors/dispatch_active_pollers_job_test.rb core_matrix/test/services/channel_deliveries/dispatch_conversation_output_test.rb core_matrix/test/services/ingress_bindings/update_connector_test.rb
git commit -m "refactor: delete legacy ingress and channel paths"
```

### Task 15: Rewrite Remaining Surface Provenance, Commands, And Conversation Semantics

**Depends on:** Tasks 3, 7, and 14

**Files:**
- Create or Move: `core_matrix/app/extensions/conversation_surfaces/rebind_from_conversation_context.rb`
- Create or Move: `core_matrix/app/extensions/conversation_surfaces/command_router.rb`
- Create or Move: `core_matrix/app/services/conversations/create_managed_surface_conversation.rb`
- Create or Move: `core_matrix/app/services/turns/queue_surface_follow_up.rb`
- Delete: `core_matrix/app/services/channel_sessions/rebind_from_conversation_context.rb`
- Delete: `core_matrix/app/services/ingress_commands/authorize.rb`
- Delete: `core_matrix/app/services/ingress_commands/dispatch.rb`
- Delete: `core_matrix/app/services/ingress_commands/parse.rb`
- Delete: `core_matrix/app/services/turns/start_channel_ingress_turn.rb`
- Delete: `core_matrix/app/services/turns/queue_channel_follow_up.rb`
- Modify: `core_matrix/app/jobs/conversations/metadata/bootstrap_title_job.rb`
- Modify: `core_matrix/app/models/conversation.rb`
- Modify: `core_matrix/app/models/turn.rb`
- Modify: `core_matrix/app/models/workspace_agent.rb`
- Modify: `core_matrix/app/services/conversations/managed_policy.rb`
- Delete: `core_matrix/app/services/conversations/create_managed_channel_conversation.rb`
- Modify: `core_matrix/app/services/provider_execution/build_work_context_view.rb`
- Modify: `core_matrix/app/services/provider_execution/prepare_agent_round.rb`
- Modify: `core_matrix/app/services/turns/queue_follow_up.rb`
- Modify: `core_matrix/app/services/turns/steer_current_input.rb`
- Modify: `core_matrix/app/services/workflows/scheduler.rb`
- Modify: `core_matrix/test/test_helper.rb`
- Move or Rewrite: `core_matrix/test/services/channel_sessions/rebind_from_conversation_context_test.rb`
- Delete or Rewrite: `core_matrix/test/services/ingress_commands/authorize_test.rb`
- Delete or Rewrite: `core_matrix/test/services/ingress_commands/dispatch_test.rb`
- Delete or Rewrite: `core_matrix/test/services/ingress_commands/parse_test.rb`
- Delete or Rewrite: `core_matrix/test/services/turns/start_channel_ingress_turn_test.rb`
- Delete or Rewrite: `core_matrix/test/services/turns/queue_channel_follow_up_test.rb`
- Delete or Rewrite: `core_matrix/test/integration/channel_ingress_conversation_rotation_test.rb`
- Delete or Rewrite: `core_matrix/test/integration/channel_ingress_follow_up_flow_test.rb`
- Modify: `core_matrix/test/jobs/conversations/metadata/bootstrap_title_job_test.rb`
- Modify: `core_matrix/test/models/workspace_agent_test.rb`
- Modify: `core_matrix/test/services/app_surface/presenters/conversation_presenter_test.rb`
- Modify: `core_matrix/test/services/conversation_debug_exports/build_payload_test.rb`
- Modify: `core_matrix/test/services/conversation_exports/build_conversation_payload_test.rb`
- Modify: `core_matrix/test/services/conversations/create_fork_test.rb`
- Create or Move: `core_matrix/test/services/conversations/create_managed_surface_conversation_test.rb`
- Modify: `core_matrix/test/services/conversations/managed_policy_test.rb`
- Modify: `core_matrix/test/services/conversations/metadata/agent_update_test.rb`
- Modify: `core_matrix/test/services/conversations/metadata/regenerate_test.rb`
- Modify: `core_matrix/test/services/conversations/metadata/user_edit_test.rb`
- Modify: `core_matrix/test/services/conversations/update_override_test.rb`
- Modify: `core_matrix/test/services/provider_execution/build_work_context_view_test.rb`
- Modify: `core_matrix/test/services/provider_execution/prepare_agent_round_test.rb`
- Modify: `core_matrix/test/services/provider_execution/persist_turn_step_success_test.rb`
- Modify: `core_matrix/test/services/turns/accept_pending_user_turn_test.rb`
- Modify: `core_matrix/test/services/turns/queue_follow_up_test.rb`
- Modify: `core_matrix/test/services/turns/start_user_turn_test.rb`
- Modify: `core_matrix/test/services/turns/steer_current_input_test.rb`

Any additional active code or active test file matched by the legacy grep gate in Task 19 belongs to this task even if it is not listed above.

**Step 1: Write the failing tests**

Update the remaining host and application tests so they expect:

- `conversation_surface` or `surface_event` semantics instead of `channel_ingress`
- `SurfaceEventReceipt` provenance instead of `ChannelInboundMessage`
- generic surface-managed conversation policy helpers instead of `channel_managed_entry_policy_payload`
- generic surface command routing instead of `ingress_commands`
- generic follow-up and rebinding behavior without `channel_sessions` or `queue_channel_follow_up`

**Step 2: Run tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test \
  test/jobs/conversations/metadata/bootstrap_title_job_test.rb \
  test/models/workspace_agent_test.rb \
  test/services/app_surface/presenters/conversation_presenter_test.rb \
  test/services/conversation_debug_exports/build_payload_test.rb \
  test/services/conversation_exports/build_conversation_payload_test.rb \
  test/services/conversations/create_fork_test.rb \
  test/services/conversations/create_managed_surface_conversation_test.rb \
  test/services/conversations/managed_policy_test.rb \
  test/services/conversations/metadata/agent_update_test.rb \
  test/services/conversations/metadata/regenerate_test.rb \
  test/services/conversations/metadata/user_edit_test.rb \
  test/services/conversations/update_override_test.rb \
  test/services/provider_execution/build_work_context_view_test.rb \
  test/services/provider_execution/prepare_agent_round_test.rb \
  test/services/provider_execution/persist_turn_step_success_test.rb \
  test/services/turns/accept_pending_user_turn_test.rb \
  test/services/turns/queue_follow_up_test.rb \
  test/services/turns/start_user_turn_test.rb \
  test/services/turns/steer_current_input_test.rb
```

Expected: FAIL because the remaining provenance, policy, and command semantics still point at the deleted architecture.

**Step 3: Write minimal implementation**

Remove the remaining live `channel_*` and `channel_ingress` semantics from host behavior by:

- replacing turn provenance with generic surface event receipt semantics
- renaming conversation entry-policy and manager vocabulary onto surface terminology
- moving command parsing/dispatch to a generic surface-owned path
- moving rebinding and follow-up behavior to generic surface helpers
- updating exports, presenters, scheduler behavior, and provider-execution context builders so they no longer project deleted model names

**Step 4: Run tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test \
  test/jobs/conversations/metadata/bootstrap_title_job_test.rb \
  test/models/workspace_agent_test.rb \
  test/services/app_surface/presenters/conversation_presenter_test.rb \
  test/services/conversation_debug_exports/build_payload_test.rb \
  test/services/conversation_exports/build_conversation_payload_test.rb \
  test/services/conversations/create_fork_test.rb \
  test/services/conversations/create_managed_surface_conversation_test.rb \
  test/services/conversations/managed_policy_test.rb \
  test/services/conversations/metadata/agent_update_test.rb \
  test/services/conversations/metadata/regenerate_test.rb \
  test/services/conversations/metadata/user_edit_test.rb \
  test/services/conversations/update_override_test.rb \
  test/services/provider_execution/build_work_context_view_test.rb \
  test/services/provider_execution/prepare_agent_round_test.rb \
  test/services/provider_execution/persist_turn_step_success_test.rb \
  test/services/turns/accept_pending_user_turn_test.rb \
  test/services/turns/queue_follow_up_test.rb \
  test/services/turns/start_user_turn_test.rb \
  test/services/turns/steer_current_input_test.rb
```

Expected: PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/extensions/conversation_surfaces core_matrix/app/jobs/conversations/metadata/bootstrap_title_job.rb core_matrix/app/models/conversation.rb core_matrix/app/models/turn.rb core_matrix/app/models/workspace_agent.rb core_matrix/app/services/conversations/managed_policy.rb core_matrix/app/services/conversations/create_managed_surface_conversation.rb core_matrix/app/services/provider_execution/build_work_context_view.rb core_matrix/app/services/provider_execution/prepare_agent_round.rb core_matrix/app/services/turns core_matrix/app/services/workflows/scheduler.rb core_matrix/test/jobs/conversations/metadata/bootstrap_title_job_test.rb core_matrix/test/models/workspace_agent_test.rb core_matrix/test/services/app_surface/presenters/conversation_presenter_test.rb core_matrix/test/services/conversation_debug_exports/build_payload_test.rb core_matrix/test/services/conversation_exports/build_conversation_payload_test.rb core_matrix/test/services/conversations/create_fork_test.rb core_matrix/test/services/conversations/create_managed_surface_conversation_test.rb core_matrix/test/services/conversations/managed_policy_test.rb core_matrix/test/services/conversations/metadata/agent_update_test.rb core_matrix/test/services/conversations/metadata/regenerate_test.rb core_matrix/test/services/conversations/metadata/user_edit_test.rb core_matrix/test/services/conversations/update_override_test.rb core_matrix/test/services/provider_execution/build_work_context_view_test.rb core_matrix/test/services/provider_execution/prepare_agent_round_test.rb core_matrix/test/services/provider_execution/persist_turn_step_success_test.rb core_matrix/test/services/turns/accept_pending_user_turn_test.rb core_matrix/test/services/turns/queue_follow_up_test.rb core_matrix/test/services/turns/start_user_turn_test.rb core_matrix/test/services/turns/steer_current_input_test.rb core_matrix/test/test_helper.rb
git rm core_matrix/app/services/channel_sessions/rebind_from_conversation_context.rb core_matrix/app/services/ingress_commands/authorize.rb core_matrix/app/services/ingress_commands/dispatch.rb core_matrix/app/services/ingress_commands/parse.rb core_matrix/app/services/conversations/create_managed_channel_conversation.rb core_matrix/app/services/turns/start_channel_ingress_turn.rb core_matrix/app/services/turns/queue_channel_follow_up.rb
git rm core_matrix/test/services/channel_sessions/rebind_from_conversation_context_test.rb core_matrix/test/services/ingress_commands/authorize_test.rb core_matrix/test/services/ingress_commands/dispatch_test.rb core_matrix/test/services/ingress_commands/parse_test.rb core_matrix/test/services/conversations/create_managed_channel_conversation_test.rb core_matrix/test/services/turns/start_channel_ingress_turn_test.rb core_matrix/test/services/turns/queue_channel_follow_up_test.rb core_matrix/test/integration/channel_ingress_conversation_rotation_test.rb core_matrix/test/integration/channel_ingress_follow_up_flow_test.rb
git commit -m "refactor: replace remaining channel ingress semantics"
```

### Task 16: Migrate Bundled Provisioning Onto Package Definitions

**Depends on:** Tasks 5, 11, and 15

**Files:**
- Modify: `core_matrix/app/services/installations/register_bundled_agent_runtime.rb`
- Modify: `core_matrix/app/services/installations/bootstrap_bundled_agent_binding.rb`
- Modify: `core_matrix/app/services/agent_definition_versions/upsert_from_package.rb`
- Test: `core_matrix/test/services/installations/register_bundled_agent_runtime_test.rb`
- Test: `core_matrix/test/services/installations/bootstrap_bundled_agent_binding_test.rb`
- Test: `core_matrix/test/services/installations/bootstrap_first_admin_test.rb`

**Step 1: Write the failing tests**

Update bundled provisioning tests so they expect capability and package metadata to compose the bundled runtime definition instead of the old giant configuration hash.

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/installations/register_bundled_agent_runtime_test.rb test/services/installations/bootstrap_bundled_agent_binding_test.rb test/services/installations/bootstrap_first_admin_test.rb`
Expected: FAIL because bundled provisioning still assumes the old contracts.

**Step 3: Write minimal implementation**

Resolve bundled provisioning from package definitions and capability metadata, keeping CoreMatrix on the host side of the Agent/ExecutionRuntime boundary.

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/installations/register_bundled_agent_runtime_test.rb test/services/installations/bootstrap_bundled_agent_binding_test.rb test/services/installations/bootstrap_first_admin_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/services/installations/register_bundled_agent_runtime.rb core_matrix/app/services/installations/bootstrap_bundled_agent_binding.rb core_matrix/app/services/agent_definition_versions/upsert_from_package.rb core_matrix/test/services/installations/register_bundled_agent_runtime_test.rb core_matrix/test/services/installations/bootstrap_bundled_agent_binding_test.rb core_matrix/test/services/installations/bootstrap_first_admin_test.rb
git commit -m "refactor: provision bundled runtime from package definitions"
```

### Task 17: Update `core_matrix_cli` To Use Generic Surface RPC And Surface Commands

**Depends on:** Tasks 6, 8, 12, 13, 14, and 15

**Files:**
- Modify: `core_matrix_cli/lib/core_matrix_cli.rb`
- Modify: `core_matrix_cli/lib/core_matrix_cli/cli.rb`
- Modify: `core_matrix_cli/lib/core_matrix_cli/core_matrix_api.rb`
- Modify: `core_matrix_cli/lib/core_matrix_cli/use_cases/base.rb`
- Modify: `core_matrix_cli/lib/core_matrix_cli/use_cases/setup_telegram_polling.rb`
- Modify: `core_matrix_cli/lib/core_matrix_cli/use_cases/setup_telegram_webhook.rb`
- Modify: `core_matrix_cli/lib/core_matrix_cli/use_cases/setup_weixin.rb`
- Modify: `core_matrix_cli/lib/core_matrix_cli/use_cases/show_status.rb`
- Create or Move: `core_matrix_cli/lib/core_matrix_cli/commands/surface.rb`
- Delete: `core_matrix_cli/lib/core_matrix_cli/commands/ingress.rb`
- Test: `core_matrix_cli/test/core_matrix_api_test.rb`
- Create or Move: `core_matrix_cli/test/commands/surface_command_test.rb`
- Create or Move: `core_matrix_cli/test/commands/surface_telegram_command_test.rb`
- Create or Move: `core_matrix_cli/test/commands/surface_telegram_webhook_command_test.rb`
- Create or Move: `core_matrix_cli/test/commands/surface_weixin_command_test.rb`
- Modify: `core_matrix_cli/test/cli_smoke_test.rb`
- Test: `core_matrix_cli/test/commands/status_command_test.rb`
- Test: `core_matrix_cli/test/full_setup_contract_test.rb`
- Modify: `core_matrix_cli/test/support/fake_core_matrix_api.rb`
- Modify: `core_matrix_cli/test/support/fake_core_matrix_server.rb`

**Step 1: Write the failing tests**

Update CLI tests so they expect:

- generic `surface_bindings` creation instead of raw `platform` ingress creation
- generic action invocation for Weixin pairing and status
- setup/status output built from generic surface payloads
- top-level `surface` commands and help output, with no live `ingress` command namespace

**Step 2: Run tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec rake test TEST=test/cli_smoke_test.rb
bundle exec rake test TEST=test/core_matrix_api_test.rb
bundle exec rake test TEST=test/commands/surface_command_test.rb
bundle exec rake test TEST=test/commands/surface_telegram_command_test.rb
bundle exec rake test TEST=test/commands/surface_telegram_webhook_command_test.rb
bundle exec rake test TEST=test/commands/surface_weixin_command_test.rb
bundle exec rake test TEST=test/commands/status_command_test.rb
bundle exec rake test TEST=test/full_setup_contract_test.rb
```

Expected: FAIL because the CLI still talks to the old ingress routes and still exposes the old command namespace.

**Step 3: Write minimal implementation**

Replace the user-facing CLI noun from `ingress` to `surface`, and reimplement the flows on top of:

- generic `surface_bindings` create/show/update
- generic surface actions
- package-aware setup payloads

**Step 4: Run tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec rake test TEST=test/cli_smoke_test.rb
bundle exec rake test TEST=test/core_matrix_api_test.rb
bundle exec rake test TEST=test/commands/surface_command_test.rb
bundle exec rake test TEST=test/commands/surface_telegram_command_test.rb
bundle exec rake test TEST=test/commands/surface_telegram_webhook_command_test.rb
bundle exec rake test TEST=test/commands/surface_weixin_command_test.rb
bundle exec rake test TEST=test/commands/status_command_test.rb
bundle exec rake test TEST=test/full_setup_contract_test.rb
```

Expected: PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix_cli/lib/core_matrix_cli.rb core_matrix_cli/lib/core_matrix_cli/cli.rb core_matrix_cli/lib/core_matrix_cli/core_matrix_api.rb core_matrix_cli/lib/core_matrix_cli/use_cases/base.rb core_matrix_cli/lib/core_matrix_cli/use_cases/setup_telegram_polling.rb core_matrix_cli/lib/core_matrix_cli/use_cases/setup_telegram_webhook.rb core_matrix_cli/lib/core_matrix_cli/use_cases/setup_weixin.rb core_matrix_cli/lib/core_matrix_cli/use_cases/show_status.rb core_matrix_cli/lib/core_matrix_cli/commands/surface.rb core_matrix_cli/test/cli_smoke_test.rb core_matrix_cli/test/core_matrix_api_test.rb core_matrix_cli/test/commands/surface_command_test.rb core_matrix_cli/test/commands/surface_telegram_command_test.rb core_matrix_cli/test/commands/surface_telegram_webhook_command_test.rb core_matrix_cli/test/commands/surface_weixin_command_test.rb core_matrix_cli/test/commands/status_command_test.rb core_matrix_cli/test/full_setup_contract_test.rb core_matrix_cli/test/support/fake_core_matrix_api.rb core_matrix_cli/test/support/fake_core_matrix_server.rb
git rm core_matrix_cli/lib/core_matrix_cli/commands/ingress.rb core_matrix_cli/test/commands/ingress_telegram_command_test.rb core_matrix_cli/test/commands/ingress_telegram_webhook_command_test.rb core_matrix_cli/test/commands/ingress_weixin_command_test.rb
git commit -m "refactor: update cli to generic surface rpc"
```

### Task 18: Refresh Docs And Contributor Rules

**Depends on:** Tasks 8-17

**Files:**
- Create: `core_matrix/AGENTS.md`
- Create: `core_matrix/docs/architecture/extensions.md`
- Create: `core_matrix/docs/extensions/packages.md`
- Create: `core_matrix/docs/extensions/conversation-surfaces.md`
- Create: `core_matrix/docs/extensions/capabilities.md`
- Create: `core_matrix/docs/extensions/migrations-and-dependencies.md`
- Modify: `core_matrix/docs/README.md`
- Modify: `core_matrix/docs/INTEGRATIONS.md`
- Modify: `core_matrix/docs/INSTALL.md`
- Modify: `core_matrix/docs/ADMIN-QUICK-START-GUIDE.md`
- Modify: `core_matrix_cli/README.md`
- Modify: `AGENTS.md`

**Step 1: Write the docs/tests or lints that would fail without the new guidance**

If doc checks exist, update them; otherwise write the docs directly against the implemented code shape.

**Step 2: Write minimal documentation**

Document:

- package authoring
- conversation-surface authoring
- capability authoring
- migration rewriting and rebuild flow
- webhook, Telegram, and Weixin operator setup through the new generic RPC
- the new `cmctl surface ...` command family instead of the deleted `cmctl ingress ...` family
- any formerly active doc that still teaches the deleted architecture must be rewritten or removed rather than left as stale guidance

**Step 3: Review active docs for consistency**

Verify that active product/operator/contributor docs refer to:

- `surface_bindings`, not `ingress_bindings`
- `conversation_surfaces`, not `ingress_api`
- `capabilities`, not `embedded_agents` / `runtime_features`
- `cmctl surface`, not `cmctl ingress`

Allowed exceptions are archived or historical trees such as `core_matrix/docs/plans`, `core_matrix/docs/archived*`, `core_matrix/docs/finished-plans`, `core_matrix/docs/future-plans`, `core_matrix/docs/design`, `core_matrix/docs/research-notes`, and `core_matrix/docs/reports`.

**Step 4: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/AGENTS.md core_matrix/docs core_matrix_cli/README.md AGENTS.md
git commit -m "docs: describe packages surfaces and capabilities"
```

### Task 19: Run Focused Structural, Schema, And Overhead Verification

**Depends on:** Tasks 1-18

**Files:**
- No planned files. If any check fails, repair only the named files and rerun until green.

**Step 1: Run focused tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test \
  test/extensions \
  test/extensions/conversation_surfaces \
  test/extensions/capabilities \
  test/plugins/core \
  test/models/surface_binding_test.rb \
  test/models/conversation_scope_binding_test.rb \
  test/models/surface_event_receipt_test.rb \
  test/models/surface_delivery_attempt_test.rb \
  test/services/app_surface/presenters \
  test/services/conversation_debug_exports \
  test/services/conversation_exports \
  test/services/conversations/metadata \
  test/services/conversations/managed_policy_test.rb \
  test/services/conversations/create_managed_surface_conversation_test.rb \
  test/services/provider_execution \
  test/services/installations \
  test/services/turns \
  test/plugins/core/weixin \
  test/requests/conversation_surfaces \
  test/requests/app_api/workspace_agents \
  test/jobs/conversation_surfaces \
  test/config/data_retention_configuration_test.rb

cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec rake test TEST=test/cli_smoke_test.rb
bundle exec rake test TEST=test/core_matrix_api_test.rb
bundle exec rake test TEST=test/commands/surface_command_test.rb
bundle exec rake test TEST=test/commands/surface_telegram_command_test.rb
bundle exec rake test TEST=test/commands/surface_telegram_webhook_command_test.rb
bundle exec rake test TEST=test/commands/surface_weixin_command_test.rb
bundle exec rake test TEST=test/commands/status_command_test.rb
bundle exec rake test TEST=test/full_setup_contract_test.rb
```

Expected: PASS

**Step 2: Run structural grep acceptance checks**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
rg -n 'when "telegram"|when "telegram_webhook"|when "weixin"|PLATFORM_CONNECTOR_DEFAULTS|TELEGRAM_FAMILY_PLATFORMS|IngressBinding|ChannelConnector|ChannelSession|ChannelInboundMessage|ChannelDelivery|ChannelPairingRequest|EmbeddedAgents::|RuntimeFeatures::|EmbeddedFeatures::|ingress_binding|ingress_bindings|channel_connector|channel_connectors|channel_session|channel_sessions|channel_delivery|channel_deliveries|channel_pairing_request|channel_inbound_message|/weixin/start_login|/weixin/login_status|/weixin/disconnect|/ingress_api/telegram/bindings/|/app_api/workspace_agents/.*/ingress_bindings|ChannelConnectors::DispatchActivePollersJob|ChannelDeliveries::DispatchConversationOutput|Commands::Ingress|ingress SUBCOMMAND|Manage ingress|channel_ingress|channel_managed_entry_policy_payload|Turns::QueueChannelFollowUp|StartChannelIngressTurn|cmctl ingress|/commands/ingress\\.rb' core_matrix/app core_matrix/lib core_matrix/config core_matrix/test core_matrix_cli/lib core_matrix_cli/test
find core_matrix/app/services -path '*/ingress_api/*' -type f
find core_matrix/app/services -path '*/ingress_commands/*' -type f
find core_matrix/app/services -path '*/embedded_agents/*' -type f
find core_matrix/app/services -path '*/runtime_features/*' -type f
find core_matrix/app/services -path '*/embedded_features/*' -type f
find core_matrix/app/services -path '*/channel_sessions/*' -type f
find core_matrix/app/services -path '*/channel_deliveries/*' -type f
find core_matrix/app/services \( -path '*/turns/start_channel_ingress_turn.rb' -o -path '*/turns/queue_channel_follow_up.rb' \) -type f
find core_matrix/app/services -path '*/conversations/create_managed_channel_conversation.rb' -type f
find core_matrix/app/models -maxdepth 1 \( -name 'ingress_binding.rb' -o -name 'channel_*.rb' \)
find core_matrix/db/migrate \( -name '*ingress*' -o -name '*channel*' \)
find core_matrix/test -path '*/ingress_api/*' -type f
find core_matrix/test -path '*/ingress_commands/*' -type f
find core_matrix/test -path '*/embedded_agents/*' -type f
find core_matrix/test -path '*/runtime_features/*' -type f
find core_matrix/test -path '*/embedded_features/*' -type f
find core_matrix/test -path '*/channel_sessions/*' -type f
find core_matrix/test -path '*/channel_connectors/*' -type f
find core_matrix/test -path '*/channel_deliveries/*' -type f
find core_matrix/test -path '*/ingress_bindings/*' -type f
find core_matrix/test -path '*/channel_ingress_*' -type f
find core_matrix/test \( -path '*/start_channel_ingress_turn_test.rb' -o -path '*/queue_channel_follow_up_test.rb' -o -path '*/create_managed_channel_conversation_test.rb' \) -type f
find core_matrix_cli/lib -path '*/commands/ingress.rb' -type f
find core_matrix_cli/test -path '*/ingress_*' -type f
rg -n '\bingress\b|IngressBinding|ChannelConnector|ChannelSession|ChannelInboundMessage|ChannelDelivery|ChannelPairingRequest|ingress_binding|ingress_bindings|embedded_agents|embedded_features|runtime_features|ingress_api|channel_deliveries|channel_connectors|cmctl ingress|channel_ingress|channel_managed_entry_policy_payload' core_matrix/docs core_matrix_cli/README.md AGENTS.md core_matrix/AGENTS.md --glob '!core_matrix/docs/plans/**' --glob '!core_matrix/docs/archived*/**' --glob '!core_matrix/docs/finished-plans/**' --glob '!core_matrix/docs/future-plans/**' --glob '!core_matrix/docs/design/**' --glob '!core_matrix/docs/research-notes/**' --glob '!core_matrix/docs/reports/**' --glob '!core_matrix/docs/proposed-*/**'
```

Expected: the `rg -n` commands return no live architectural matches outside archived or historical material, the `find` commands return no old host service/model/test/CLI files, and the migration tree no longer contains channel/ingress host migrations.

**Step 3: Run lint, boot, and rebuild checks**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rubocop -f github
bundle exec ruby -e 'require "./config/application"'
bin/rails db:drop
rm db/schema.rb
bin/rails db:create
bin/rails db:migrate
bin/rails db:reset
```

Expected: PASS with a cleanly regenerated schema.

**Step 4: Fix failures and rerun only failed checks**

Make the minimal fixes needed to satisfy focused tests, grep checks, lint, boot, query-budget tests, and rebuild checks, then rerun until green.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix core_matrix_cli
git commit -m "test: verify package surface and capability structure"
```

### Task 20: Run Full Verification And Final Acceptance Audit

**Depends on:** Task 19

**Files:**
- No planned files. If any full verification command fails, repair only the specific files named by the failure, rerun the failed command to green, and restart this task's audit sequence.

**Step 1: Run full `core_matrix` verification**

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

Expected: PASS

**Step 2: Run full `core_matrix_cli` verification**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec rake test
```

Expected: PASS

**Step 3: Run the required active verification suite from repo root**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
ACTIVE_VERIFICATION_ENABLE_2048_CAPSTONE=1 bash verification/bin/run_active_suite.sh
```

Expected: PASS with artifacts available for inspection.

**Step 4: Inspect artifacts and database state against the acceptance checklist**

Verify:

- business state transitions look correct in verification output
- conversation working-memory surfaces still produce correct public-id-based shapes
- webhook, Telegram, and Weixin surfaces all route through the same host kernel
- query-budget tests remained green after the full implementation
- `core_matrix_cli` exercises the generic surface RPC successfully and no longer exposes `ingress` as the live command family
- active product/operator/contributor docs no longer teach the deleted ingress/channel/embedded/runtime architecture
- the final acceptance checklist at the top of this plan is satisfied line by line

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix core_matrix_cli
git commit -m "test: complete package surface and capability verification"
```
