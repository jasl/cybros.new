# CoreMatrix Extensions Refactor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the current service-shaped ingress, embedded-agent, and embedded-feature layout with host-owned extension contracts and built-in plugin packages that are explicit, testable, and ready for future ecosystem growth.

**Architecture:** CoreMatrix will own narrow extension contracts in `app/extensions`, `app/ingresses`, `app/embedded_agents`, and `app/embedded_features`. Concrete built-in behavior will move into `app/plugins/core/*` packages that declare manifests, gem fragments, migrations, endpoints, and management actions. Host routes, controllers, jobs, and dispatchers will become registry-driven, and legacy service namespaces will be deleted once replacements are green.

**Tech Stack:** Ruby on Rails, Active Record, Active Job, Bundler, Minitest, JSON-schema-like contract validation patterns already used in CoreMatrix.

**Execution Rules:**
- Breaking changes are allowed and expected; do not preserve legacy compatibility shims longer than necessary to complete the migration.
- Keep the work scoped to `core_matrix` and `core_matrix_cli`, plus the root `AGENTS.md` pointer update and verification commands that must run from the repo root.
- Use `public_id` at external or agent-facing boundaries.
- Treat this as verification-critical work under `/Users/jasl/Workspaces/Ruby/cybros/AGENTS.md:32-40`.

**Final Acceptance Checklist:**
- All concrete built-in ingress, embedded-agent, and embedded-feature implementations live in plugin packages under `core_matrix/app/plugins/core/*`.
- Host-owned contracts exist in `app/extensions`, `app/ingresses`, `app/embedded_agents`, and `app/embedded_features`.
- Host-owned ingress pipeline objects live under `app/ingresses`, and legacy host ownership does not remain in `core_matrix/app/services/ingress_api`.
- Legacy host ownership does not remain in `core_matrix/app/services/embedded_agents`, `core_matrix/app/services/runtime_features`, or `core_matrix/app/services/embedded_features`.
- Generic public endpoint and management-action routes replace plugin-specific App API/UI/controller branching.
- Plugin gem fragments and plugin migration paths are loaded only through host-controlled boot/build flow.
- Host files targeted by the design no longer branch on `"telegram"`, `"telegram_webhook"`, or `"weixin"` for control flow.
- Hard-coded embedded agent and runtime feature registries are removed or reduced to temporary boot bridges that are deleted by the end.
- `core_matrix_cli` uses the generic ingress create/show/action RPC surfaces instead of platform-specific ingress endpoints while preserving `telegram`, `telegram-webhook`, and `weixin` operator flows.
- `core_matrix/AGENTS.md` and extension authoring docs exist and are consistent with the code.
- Focused tests, full `core_matrix` and `core_matrix_cli` verification, and the active verification suite all pass.

**Dependency Order:**
1. Tasks 1-5 create the host extension framework and generic host surfaces.
2. Tasks 6-11 move embedded agents and features onto the host framework.
3. Tasks 12-14 move ingress implementations and remove host platform branching.
4. Task 15 migrates bundled provisioning onto plugin definitions.
5. Task 16 updates `core_matrix_cli` to consume the new public ingress RPC surface.
6. Task 17 adds docs and contributor rules after the code shape is real.
7. Tasks 18-19 verify the whole system and enforce the acceptance checklist.

---

### Task 1: Build The Extension Manifest Framework

**Depends on:** none

**Files:**
- Create: `core_matrix/app/extensions/manifest.rb`
- Create: `core_matrix/app/extensions/manifest_validator.rb`
- Create: `core_matrix/app/extensions/dependency_resolver.rb`
- Create: `core_matrix/app/extensions/registry.rb`
- Create: `core_matrix/app/extensions/loader.rb`
- Create: `core_matrix/config/initializers/extensions.rb`
- Modify: `core_matrix/config/application.rb`
- Test: `core_matrix/test/extensions/manifest_validator_test.rb`
- Test: `core_matrix/test/extensions/dependency_resolver_test.rb`
- Test: `core_matrix/test/extensions/registry_test.rb`
- Test: `core_matrix/test/extensions/loader_test.rb`

**Step 1: Write the failing tests**

Add tests that prove:

- manifests validate required fields and reject invalid payloads
- manifest dependency ordering and compatibility requirements are resolved deterministically
- duplicate plugin ids are rejected
- Zeitwerk resolves `Extensions::*`, `Ingresses::*`, `EmbeddedAgents::*`, `EmbeddedFeatures::*`, and `Plugins::*` from the new top-level `app/*` directories
- loader publishes a deterministic, frozen registry

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/extensions/manifest_validator_test.rb test/extensions/dependency_resolver_test.rb test/extensions/registry_test.rb test/extensions/loader_test.rb`
Expected: FAIL because the extension framework files do not exist yet.

**Step 3: Write minimal implementation**

Implement:

- immutable manifest value object
- validator with actionable error messages
- dependency resolver for lexical discovery plus explicit plugin/contract compatibility ordering
- explicit Zeitwerk namespace registration for `app/extensions`, `app/ingresses`, `app/embedded_agents`, `app/embedded_features`, and `app/plugins`
- registry with explicit registration and freeze semantics
- loader wired through `config/initializers/extensions.rb`

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/extensions/manifest_validator_test.rb test/extensions/dependency_resolver_test.rb test/extensions/registry_test.rb test/extensions/loader_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/extensions core_matrix/config/application.rb core_matrix/config/initializers/extensions.rb core_matrix/test/extensions
git commit -m "refactor: add extension manifest framework"
```

### Task 2: Add Plugin Dependency And Migration Path Aggregation

**Depends on:** Task 1

**Files:**
- Modify: `core_matrix/Gemfile`
- Modify: `core_matrix/Gemfile.lock`
- Modify: `core_matrix/config/application.rb`
- Create: `core_matrix/app/plugins/core/README.md`
- Create: `core_matrix/app/plugins/core/telegram/db/migrate/.keep`
- Create: `core_matrix/app/plugins/core/telegram/gems.rb`
- Create: `core_matrix/app/plugins/core/weixin/db/migrate/.keep`
- Create: `core_matrix/app/plugins/core/weixin/gems.rb`
- Test: `core_matrix/test/extensions/plugin_dependency_loading_test.rb`
- Test: `core_matrix/test/extensions/plugin_migration_paths_test.rb`

**Step 1: Write the failing test**

Add boot-level tests that prove:

- plugin gem fragments are discovered and plugin-owned dependencies can be required through the unified bundle
- plugin migration directories are registered through host-controlled migration paths rather than ad hoc per-plugin boot code

**Step 2: Run test to verify it fails**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/extensions/plugin_dependency_loading_test.rb test/extensions/plugin_migration_paths_test.rb`
Expected: FAIL because plugin gem fragment aggregation does not exist yet.

**Step 3: Write minimal implementation**

Update the root `Gemfile` to `eval_gemfile` plugin gem fragments, register plugin migration directories through application configuration, seed core plugin gem fragment files, and keep dependency loading build-time only.

**Step 4: Run test to verify it passes**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/extensions/plugin_dependency_loading_test.rb test/extensions/plugin_migration_paths_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/Gemfile core_matrix/Gemfile.lock core_matrix/config/application.rb core_matrix/app/plugins/core/README.md core_matrix/app/plugins/core/telegram/db/migrate/.keep core_matrix/app/plugins/core/telegram/gems.rb core_matrix/app/plugins/core/weixin/db/migrate/.keep core_matrix/app/plugins/core/weixin/gems.rb core_matrix/test/extensions/plugin_dependency_loading_test.rb core_matrix/test/extensions/plugin_migration_paths_test.rb
git commit -m "refactor: aggregate plugin dependencies and migrations"
```

### Task 3: Create Host Definition Types And Contract Registries

**Depends on:** Task 1

**Files:**
- Create: `core_matrix/app/extensions/definition_index.rb`
- Create: `core_matrix/app/ingresses/ingress_definition.rb`
- Create: `core_matrix/app/ingresses/registry.rb`
- Create: `core_matrix/app/embedded_agents/embedded_agent_definition.rb`
- Create: `core_matrix/app/embedded_agents/registry.rb`
- Create: `core_matrix/app/embedded_features/embedded_feature_definition.rb`
- Create: `core_matrix/app/embedded_features/registry.rb`
- Test: `core_matrix/test/extensions/definition_index_test.rb`
- Test: `core_matrix/test/ingresses/ingress_definition_test.rb`
- Test: `core_matrix/test/ingresses/registry_test.rb`
- Test: `core_matrix/test/embedded_agents/embedded_agent_definition_test.rb`
- Test: `core_matrix/test/embedded_agents/registry_test.rb`
- Test: `core_matrix/test/embedded_features/embedded_feature_definition_test.rb`
- Test: `core_matrix/test/embedded_features/registry_test.rb`

**Step 1: Write the failing tests**

Add tests that verify each definition type and registry:

- compile manifest contributions into a stable definition index before publishing contract registries
- normalizes required fields
- rejects invalid keys and malformed handlers
- exposes frozen lookups by plugin key and contract key

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/extensions/definition_index_test.rb test/ingresses/ingress_definition_test.rb test/ingresses/registry_test.rb test/embedded_agents/embedded_agent_definition_test.rb test/embedded_agents/registry_test.rb test/embedded_features/embedded_feature_definition_test.rb test/embedded_features/registry_test.rb`
Expected: FAIL because the host definition and registry classes do not exist yet.

**Step 3: Write minimal implementation**

Implement a manifest-backed definition index plus host-owned definition value objects and registries for all three contract categories.

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/extensions/definition_index_test.rb test/ingresses/ingress_definition_test.rb test/ingresses/registry_test.rb test/embedded_agents/embedded_agent_definition_test.rb test/embedded_agents/registry_test.rb test/embedded_features/embedded_feature_definition_test.rb test/embedded_features/registry_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/extensions/definition_index.rb core_matrix/app/ingresses core_matrix/app/embedded_agents core_matrix/app/embedded_features core_matrix/test/extensions/definition_index_test.rb core_matrix/test/ingresses core_matrix/test/embedded_agents core_matrix/test/embedded_features
git commit -m "refactor: add host extension definition registries"
```

### Task 4: Add Generic Public Endpoint And Management Action Controllers

**Depends on:** Tasks 1 and 3

**Files:**
- Create: `core_matrix/app/controllers/ingress_api/public_endpoints_controller.rb`
- Create: `core_matrix/app/controllers/app_api/workspace_agents/ingress_binding_actions_controller.rb`
- Modify: `core_matrix/config/routes.rb`
- Test: `core_matrix/test/requests/ingress_api/public_endpoints_controller_test.rb`
- Test: `core_matrix/test/requests/app_api/workspace_agents/ingress_binding_actions_controller_test.rb`

**Step 1: Write the failing tests**

Add request tests that prove:

- generic public endpoints route by plugin and endpoint key
- generic authenticated ingress binding actions route by action key
- unauthorized and unknown plugin/action cases return normalized errors

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/requests/ingress_api/public_endpoints_controller_test.rb test/requests/app_api/workspace_agents/ingress_binding_actions_controller_test.rb`
Expected: FAIL because the generic controllers and routes do not exist yet.

**Step 3: Write minimal implementation**

Add host-owned generic route/controller surfaces for public endpoints and authenticated management actions.

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/requests/ingress_api/public_endpoints_controller_test.rb test/requests/app_api/workspace_agents/ingress_binding_actions_controller_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/controllers/ingress_api/public_endpoints_controller.rb core_matrix/app/controllers/app_api/workspace_agents/ingress_binding_actions_controller.rb core_matrix/config/routes.rb core_matrix/test/requests/ingress_api/public_endpoints_controller_test.rb core_matrix/test/requests/app_api/workspace_agents/ingress_binding_actions_controller_test.rb
git commit -m "refactor: add generic extension route surfaces"
```

### Task 5: Build Host Ingress Pipeline And Dispatchers

**Depends on:** Tasks 3 and 4

**Files:**
- Create: `core_matrix/app/ingresses/context.rb`
- Create: `core_matrix/app/ingresses/envelope.rb`
- Create: `core_matrix/app/ingresses/result.rb`
- Create: `core_matrix/app/ingresses/receive_event.rb`
- Create: `core_matrix/app/ingresses/materialize_turn_entry.rb`
- Create: `core_matrix/app/ingresses/attach_materialized_attachments.rb`
- Create: `core_matrix/app/ingresses/transport_adapter.rb`
- Create: `core_matrix/app/ingresses/middleware/capture_raw_payload.rb`
- Create: `core_matrix/app/ingresses/middleware/deduplicate_inbound.rb`
- Create: `core_matrix/app/ingresses/middleware/verify_request.rb`
- Create: `core_matrix/app/ingresses/preprocessors/authorize_and_pair.rb`
- Create: `core_matrix/app/ingresses/preprocessors/coalesce_burst.rb`
- Create: `core_matrix/app/ingresses/preprocessors/create_or_bind_conversation.rb`
- Create: `core_matrix/app/ingresses/preprocessors/dispatch_command.rb`
- Create: `core_matrix/app/ingresses/preprocessors/materialize_attachments.rb`
- Create: `core_matrix/app/ingresses/preprocessors/resolve_channel_session.rb`
- Create: `core_matrix/app/ingresses/preprocessors/resolve_dispatch_decision.rb`
- Create: `core_matrix/app/ingresses/endpoint_dispatcher.rb`
- Create: `core_matrix/app/ingresses/management_action_dispatcher.rb`
- Create: `core_matrix/app/ingresses/poller_dispatcher.rb`
- Create: `core_matrix/app/ingresses/delivery_dispatcher.rb`
- Modify: `core_matrix/app/services/ingress_api/attach_materialized_attachments.rb`
- Modify: `core_matrix/app/services/ingress_api/context.rb`
- Modify: `core_matrix/app/services/ingress_api/envelope.rb`
- Modify: `core_matrix/app/services/ingress_api/materialize_turn_entry.rb`
- Modify: `core_matrix/app/services/ingress_api/middleware/capture_raw_payload.rb`
- Modify: `core_matrix/app/services/ingress_api/middleware/deduplicate_inbound.rb`
- Modify: `core_matrix/app/services/ingress_api/middleware/verify_request.rb`
- Modify: `core_matrix/app/services/ingress_api/preprocessors/authorize_and_pair.rb`
- Modify: `core_matrix/app/services/ingress_api/preprocessors/coalesce_burst.rb`
- Modify: `core_matrix/app/services/ingress_api/preprocessors/create_or_bind_conversation.rb`
- Modify: `core_matrix/app/services/ingress_api/preprocessors/dispatch_command.rb`
- Modify: `core_matrix/app/services/ingress_api/preprocessors/materialize_attachments.rb`
- Modify: `core_matrix/app/services/ingress_api/preprocessors/resolve_channel_session.rb`
- Modify: `core_matrix/app/services/ingress_api/preprocessors/resolve_dispatch_decision.rb`
- Modify: `core_matrix/app/services/ingress_api/receive_event.rb`
- Modify: `core_matrix/app/services/ingress_api/result.rb`
- Modify: `core_matrix/app/services/ingress_api/transport_adapter.rb`
- Create: `core_matrix/test/ingresses/endpoint_dispatcher_test.rb`
- Create: `core_matrix/test/ingresses/management_action_dispatcher_test.rb`
- Create: `core_matrix/test/ingresses/poller_dispatcher_test.rb`
- Create: `core_matrix/test/ingresses/delivery_dispatcher_test.rb`
- Modify: `core_matrix/test/services/ingress_api/receive_event_test.rb`
- Modify: `core_matrix/test/services/ingress_api/materialize_turn_entry_test.rb`
- Modify: `core_matrix/test/services/ingress_api/preprocessors/authorize_and_pair_test.rb`
- Modify: `core_matrix/test/services/ingress_api/preprocessors/coalesce_burst_test.rb`
- Modify: `core_matrix/test/services/ingress_api/preprocessors/create_or_bind_conversation_test.rb`
- Modify: `core_matrix/test/services/ingress_api/preprocessors/dispatch_command_test.rb`
- Modify: `core_matrix/test/services/ingress_api/preprocessors/materialize_attachments_test.rb`
- Modify: `core_matrix/test/services/ingress_api/preprocessors/resolve_dispatch_decision_test.rb`
- Modify: `core_matrix/test/services/ingress_api/command_surface_test.rb`

**Step 1: Write the failing tests**

Add contract tests that prove the host can dispatch:

- public ingress endpoint requests
- authenticated management actions
- poller work
- outbound deliveries

without any platform branching.

Update ingress pipeline integration tests so host-owned ingress pipeline objects move under `app/ingresses`, and so `ReceiveEvent`, `MaterializeTurnEntry`, preprocessors, and command-surface flows resolve transport behavior only through the new ingress contracts and dispatchers.

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/ingresses/endpoint_dispatcher_test.rb test/ingresses/management_action_dispatcher_test.rb test/ingresses/poller_dispatcher_test.rb test/ingresses/delivery_dispatcher_test.rb test/services/ingress_api/receive_event_test.rb test/services/ingress_api/materialize_turn_entry_test.rb test/services/ingress_api/preprocessors/authorize_and_pair_test.rb test/services/ingress_api/preprocessors/coalesce_burst_test.rb test/services/ingress_api/preprocessors/create_or_bind_conversation_test.rb test/services/ingress_api/preprocessors/dispatch_command_test.rb test/services/ingress_api/preprocessors/materialize_attachments_test.rb test/services/ingress_api/preprocessors/resolve_dispatch_decision_test.rb test/services/ingress_api/command_surface_test.rb`
Expected: FAIL because the dispatchers do not exist yet.

**Step 3: Write minimal implementation**

Implement host ingress pipeline objects and dispatchers under `app/ingresses`, wire the pipeline to consume definitions instead of platform-specific adapter selection, and leave only temporary compatibility bridges in `app/services/ingress_api` until Task 14 deletes them.

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/ingresses/endpoint_dispatcher_test.rb test/ingresses/management_action_dispatcher_test.rb test/ingresses/poller_dispatcher_test.rb test/ingresses/delivery_dispatcher_test.rb test/services/ingress_api/receive_event_test.rb test/services/ingress_api/materialize_turn_entry_test.rb test/services/ingress_api/preprocessors/authorize_and_pair_test.rb test/services/ingress_api/preprocessors/coalesce_burst_test.rb test/services/ingress_api/preprocessors/create_or_bind_conversation_test.rb test/services/ingress_api/preprocessors/dispatch_command_test.rb test/services/ingress_api/preprocessors/materialize_attachments_test.rb test/services/ingress_api/preprocessors/resolve_dispatch_decision_test.rb test/services/ingress_api/command_surface_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/ingresses core_matrix/app/services/ingress_api core_matrix/test/ingresses core_matrix/test/services/ingress_api
git commit -m "refactor: move host ingress pipeline into app"
```

### Task 6: Move Embedded-Agent Host Ownership Out Of `app/services`

**Depends on:** Task 3

**Files:**
- Create: `core_matrix/app/embedded_agents/invoke.rb`
- Create: `core_matrix/app/embedded_agents/result.rb`
- Create: `core_matrix/app/embedded_agents/errors.rb`
- Delete: `core_matrix/app/services/embedded_agents/invoke.rb`
- Delete: `core_matrix/app/services/embedded_agents/result.rb`
- Delete: `core_matrix/app/services/embedded_agents/errors.rb`
- Delete: `core_matrix/app/services/embedded_agents/registry.rb`
- Test: `core_matrix/test/services/embedded_agents/invoke_test.rb`

**Step 1: Write the failing test**

Update `test/services/embedded_agents/invoke_test.rb` so it expects resolution through `app/embedded_agents/registry.rb` rather than the old service registry.

**Step 2: Run test to verify it fails**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/embedded_agents/invoke_test.rb`
Expected: FAIL because host ownership is still centered in `app/services/embedded_agents`.

**Step 3: Write minimal implementation**

Move host-owned invoke/result/error behavior into `app/embedded_agents` and delete the old service entrypoints instead of leaving them as a second ownership center.

**Step 4: Run test to verify it passes**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/embedded_agents/invoke_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/embedded_agents core_matrix/test/services/embedded_agents/invoke_test.rb
git rm core_matrix/app/services/embedded_agents/invoke.rb core_matrix/app/services/embedded_agents/result.rb core_matrix/app/services/embedded_agents/errors.rb core_matrix/app/services/embedded_agents/registry.rb
git commit -m "refactor: move embedded agent host surface out of services"
```

### Task 7: Move Embedded-Feature Host Ownership Out Of `app/services`

**Depends on:** Task 3

**Files:**
- Create: `core_matrix/app/embedded_features/invoke.rb`
- Create: `core_matrix/app/embedded_features/policy_resolver.rb`
- Create: `core_matrix/app/embedded_features/capability_resolver.rb`
- Create: `core_matrix/app/embedded_features/runtime_delegate.rb`
- Create: `core_matrix/app/embedded_features/feature_request_exchange.rb`
- Delete: `core_matrix/app/services/runtime_features/invoke.rb`
- Delete: `core_matrix/app/services/runtime_features/policy_resolver.rb`
- Delete: `core_matrix/app/services/runtime_features/capability_resolver.rb`
- Delete: `core_matrix/app/services/runtime_features/feature_request_exchange.rb`
- Delete: `core_matrix/app/services/runtime_features/registry.rb`
- Test: `core_matrix/test/services/runtime_features/invoke_test.rb`
- Test: `core_matrix/test/services/runtime_features/policy_resolver_test.rb`
- Test: `core_matrix/test/services/runtime_features/capability_resolver_test.rb`
- Test: `core_matrix/test/services/runtime_features/feature_request_exchange_test.rb`
- Test: `core_matrix/test/services/runtime_features/registry_test.rb`

**Step 1: Write the failing tests**

Update the runtime-feature tests so they expect host ownership in `app/embedded_features`, generic runtime delegation through the moved feature-request exchange object, and no hard-coded service registry.

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/runtime_features/invoke_test.rb test/services/runtime_features/policy_resolver_test.rb test/services/runtime_features/capability_resolver_test.rb test/services/runtime_features/feature_request_exchange_test.rb test/services/runtime_features/registry_test.rb`
Expected: FAIL because host ownership is still centered in `app/services/runtime_features`.

**Step 3: Write minimal implementation**

Move host-owned feature invocation, policy/capability resolution, and feature-request exchange into `app/embedded_features`, and delete the old service entrypoints instead of leaving them as permanent bridges.

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/runtime_features/invoke_test.rb test/services/runtime_features/policy_resolver_test.rb test/services/runtime_features/capability_resolver_test.rb test/services/runtime_features/feature_request_exchange_test.rb test/services/runtime_features/registry_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/embedded_features core_matrix/test/services/runtime_features/invoke_test.rb core_matrix/test/services/runtime_features/policy_resolver_test.rb core_matrix/test/services/runtime_features/capability_resolver_test.rb core_matrix/test/services/runtime_features/feature_request_exchange_test.rb core_matrix/test/services/runtime_features/registry_test.rb
git rm core_matrix/app/services/runtime_features/invoke.rb core_matrix/app/services/runtime_features/policy_resolver.rb core_matrix/app/services/runtime_features/capability_resolver.rb core_matrix/app/services/runtime_features/feature_request_exchange.rb core_matrix/app/services/runtime_features/registry.rb
git commit -m "refactor: move embedded feature host surface out of services"
```

### Task 8: Package `conversation_title` As A Plugin

**Depends on:** Tasks 1, 3, and 6

**Files:**
- Create: `core_matrix/app/plugins/core/conversation_title/plugin.rb`
- Create: `core_matrix/app/plugins/core/conversation_title/embedded_agents/conversation_title.rb`
- Delete: `core_matrix/app/services/embedded_agents/conversation_title/invoke.rb`
- Test: `core_matrix/test/services/embedded_agents/conversation_title/invoke_test.rb`
- Test: `core_matrix/test/services/embedded_agents/invoke_test.rb`

**Step 1: Write the failing tests**

Update conversation title tests to resolve the agent through the plugin package and host registry.

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/embedded_agents/conversation_title/invoke_test.rb test/services/embedded_agents/invoke_test.rb`
Expected: FAIL because `conversation_title` is not plugin-backed yet.

**Step 3: Write minimal implementation**

Move the conversation title implementation into the plugin package and register it through the host embedded-agent registry.

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/embedded_agents/conversation_title/invoke_test.rb test/services/embedded_agents/invoke_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/plugins/core/conversation_title core_matrix/test/services/embedded_agents/conversation_title/invoke_test.rb core_matrix/test/services/embedded_agents/invoke_test.rb
git rm core_matrix/app/services/embedded_agents/conversation_title/invoke.rb
git commit -m "refactor: package conversation title as plugin"
```

### Task 9: Package `conversation_supervision` As A Plugin

**Depends on:** Tasks 1, 3, and 6

**Files:**
- Create: `core_matrix/app/plugins/core/conversation_supervision/plugin.rb`
- Create: `core_matrix/app/plugins/core/conversation_supervision/embedded_agents/conversation_supervision.rb`
- Move: `core_matrix/app/services/embedded_agents/conversation_supervision/append_message.rb`
- Move: `core_matrix/app/services/embedded_agents/conversation_supervision/authority.rb`
- Move: `core_matrix/app/services/embedded_agents/conversation_supervision/build_snapshot.rb`
- Move: `core_matrix/app/services/embedded_agents/conversation_supervision/classify_control_intent.rb`
- Move: `core_matrix/app/services/embedded_agents/conversation_supervision/close_session.rb`
- Move: `core_matrix/app/services/embedded_agents/conversation_supervision/create_session.rb`
- Move: `core_matrix/app/services/embedded_agents/conversation_supervision/maybe_dispatch_control_intent.rb`
- Delete: `core_matrix/app/services/embedded_agents/conversation_supervision/invoke.rb`
- Test: `core_matrix/test/services/embedded_agents/conversation_supervision/append_message_test.rb`
- Test: `core_matrix/test/services/embedded_agents/conversation_supervision/authority_test.rb`
- Test: `core_matrix/test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb`
- Test: `core_matrix/test/services/embedded_agents/conversation_supervision/classify_control_intent_test.rb`
- Test: `core_matrix/test/services/embedded_agents/conversation_supervision/close_session_test.rb`
- Test: `core_matrix/test/services/embedded_agents/conversation_supervision/create_session_test.rb`
- Test: `core_matrix/test/services/embedded_agents/conversation_supervision/maybe_dispatch_control_intent_test.rb`
- Test: `core_matrix/test/services/embedded_agents/conversation_supervision/responders/builtin_test.rb`
- Test: `core_matrix/test/services/embedded_agents/conversation_supervision/responders/summary_model_test.rb`

**Step 1: Write the failing tests**

Update the conversation supervision tests so they expect plugin-backed ownership and host-registry invocation.

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/embedded_agents/conversation_supervision/append_message_test.rb test/services/embedded_agents/conversation_supervision/authority_test.rb test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb test/services/embedded_agents/conversation_supervision/classify_control_intent_test.rb test/services/embedded_agents/conversation_supervision/close_session_test.rb test/services/embedded_agents/conversation_supervision/create_session_test.rb test/services/embedded_agents/conversation_supervision/maybe_dispatch_control_intent_test.rb test/services/embedded_agents/conversation_supervision/responders/builtin_test.rb test/services/embedded_agents/conversation_supervision/responders/summary_model_test.rb`
Expected: FAIL because `conversation_supervision` is not plugin-backed yet.

**Step 3: Write minimal implementation**

Move conversation supervision implementation files into the plugin package, register the plugin, and remove the old service invoke entrypoint.

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/embedded_agents/conversation_supervision/append_message_test.rb test/services/embedded_agents/conversation_supervision/authority_test.rb test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb test/services/embedded_agents/conversation_supervision/classify_control_intent_test.rb test/services/embedded_agents/conversation_supervision/close_session_test.rb test/services/embedded_agents/conversation_supervision/create_session_test.rb test/services/embedded_agents/conversation_supervision/maybe_dispatch_control_intent_test.rb test/services/embedded_agents/conversation_supervision/responders/builtin_test.rb test/services/embedded_agents/conversation_supervision/responders/summary_model_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/plugins/core/conversation_supervision core_matrix/test/services/embedded_agents/conversation_supervision
git rm core_matrix/app/services/embedded_agents/conversation_supervision/invoke.rb
git commit -m "refactor: package conversation supervision as plugin"
```

### Task 10: Package `title_bootstrap` As A Plugin Feature

**Depends on:** Tasks 1, 3, and 7

**Files:**
- Create: `core_matrix/app/plugins/core/title_bootstrap/plugin.rb`
- Create: `core_matrix/app/plugins/core/title_bootstrap/embedded_features/title_bootstrap.rb`
- Delete: `core_matrix/app/services/embedded_features/title_bootstrap/invoke.rb`
- Delete: `core_matrix/app/services/runtime_features/title_bootstrap/orchestrator.rb`
- Test: `core_matrix/test/services/embedded_features/title_bootstrap/invoke_test.rb`
- Test: `core_matrix/test/services/runtime_features/invoke_test.rb`
- Test: `core_matrix/test/services/runtime_features/feature_request_exchange_test.rb`
- Test: `core_matrix/test/services/runtime_features/policy_resolver_test.rb`
- Test: `core_matrix/test/services/conversations/metadata/runtime_bootstrap_title_test.rb`
- Test: `core_matrix/test/jobs/conversations/metadata/bootstrap_title_job_test.rb`

**Step 1: Write the failing tests**

Update runtime-feature and title-bootstrap integration tests so `title_bootstrap` resolves through a plugin-backed embedded feature.

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/embedded_features/title_bootstrap/invoke_test.rb test/services/runtime_features/invoke_test.rb test/services/runtime_features/feature_request_exchange_test.rb test/services/runtime_features/policy_resolver_test.rb test/services/conversations/metadata/runtime_bootstrap_title_test.rb test/jobs/conversations/metadata/bootstrap_title_job_test.rb`
Expected: FAIL because `title_bootstrap` is not plugin-backed yet.

**Step 3: Write minimal implementation**

Move the title bootstrap feature implementation into a plugin package, register it through the host embedded-feature registry, and keep conversation-title bootstrap flows green through the new definition path.

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/embedded_features/title_bootstrap/invoke_test.rb test/services/runtime_features/invoke_test.rb test/services/runtime_features/feature_request_exchange_test.rb test/services/runtime_features/policy_resolver_test.rb test/services/conversations/metadata/runtime_bootstrap_title_test.rb test/jobs/conversations/metadata/bootstrap_title_job_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/plugins/core/title_bootstrap core_matrix/test/services/embedded_features/title_bootstrap/invoke_test.rb core_matrix/test/services/runtime_features/invoke_test.rb core_matrix/test/services/runtime_features/feature_request_exchange_test.rb core_matrix/test/services/runtime_features/policy_resolver_test.rb core_matrix/test/services/conversations/metadata/runtime_bootstrap_title_test.rb core_matrix/test/jobs/conversations/metadata/bootstrap_title_job_test.rb
git rm core_matrix/app/services/embedded_features/title_bootstrap/invoke.rb core_matrix/app/services/runtime_features/title_bootstrap/orchestrator.rb
git commit -m "refactor: package title bootstrap as plugin feature"
```

### Task 11: Package `prompt_compaction` As A Plugin Feature

**Depends on:** Tasks 1, 3, and 7

**Files:**
- Create: `core_matrix/app/plugins/core/prompt_compaction/plugin.rb`
- Create: `core_matrix/app/plugins/core/prompt_compaction/embedded_features/prompt_compaction.rb`
- Delete: `core_matrix/app/services/embedded_features/prompt_compaction/invoke.rb`
- Test: `core_matrix/test/services/embedded_features/prompt_compaction/invoke_test.rb`
- Test: `core_matrix/test/services/runtime_features/invoke_test.rb`
- Test: `core_matrix/test/services/runtime_features/capability_resolver_test.rb`
- Test: `core_matrix/test/services/provider_execution/prompt_compaction_strategy_test.rb`
- Test: `core_matrix/test/services/provider_execution/execute_prompt_compaction_node_test.rb`

**Step 1: Write the failing tests**

Update runtime-feature and prompt-compaction execution tests so `prompt_compaction` resolves through a plugin-backed embedded feature.

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/embedded_features/prompt_compaction/invoke_test.rb test/services/runtime_features/invoke_test.rb test/services/runtime_features/capability_resolver_test.rb test/services/provider_execution/prompt_compaction_strategy_test.rb test/services/provider_execution/execute_prompt_compaction_node_test.rb`
Expected: FAIL because `prompt_compaction` is not plugin-backed yet.

**Step 3: Write minimal implementation**

Move the prompt compaction feature implementation into a plugin package and register it through the host embedded-feature registry.

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/embedded_features/prompt_compaction/invoke_test.rb test/services/runtime_features/invoke_test.rb test/services/runtime_features/capability_resolver_test.rb test/services/provider_execution/prompt_compaction_strategy_test.rb test/services/provider_execution/execute_prompt_compaction_node_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/plugins/core/prompt_compaction core_matrix/test/services/embedded_features/prompt_compaction/invoke_test.rb core_matrix/test/services/runtime_features/invoke_test.rb core_matrix/test/services/runtime_features/capability_resolver_test.rb core_matrix/test/services/provider_execution/prompt_compaction_strategy_test.rb core_matrix/test/services/provider_execution/execute_prompt_compaction_node_test.rb
git rm core_matrix/app/services/embedded_features/prompt_compaction/invoke.rb
git commit -m "refactor: package prompt compaction as plugin feature"
```

### Task 12: Package Telegram As An Ingress Plugin

**Depends on:** Tasks 2, 4, and 5

**Files:**
- Create: `core_matrix/app/plugins/core/telegram/plugin.rb`
- Create: `core_matrix/app/plugins/core/telegram/ingresses/telegram.rb`
- Create: `core_matrix/app/plugins/core/telegram/management_actions/configure.rb`
- Create: `core_matrix/app/plugins/core/telegram/management_actions/status.rb`
- Create: `core_matrix/app/plugins/core/telegram/management_actions/rotate_secret.rb`
- Create: `core_matrix/app/plugins/core/telegram/public_endpoints/webhook_update.rb`
- Create: `core_matrix/app/plugins/core/telegram/pollers/poll_updates.rb`
- Create: `core_matrix/app/plugins/core/telegram/deliveries/send_reply.rb`
- Move: `core_matrix/app/services/ingress_api/telegram/client.rb`
- Move: `core_matrix/app/services/ingress_api/telegram/download_attachment.rb`
- Move: `core_matrix/app/services/ingress_api/telegram/normalize_update.rb`
- Move: `core_matrix/app/services/ingress_api/telegram/progress_bridge.rb`
- Move: `core_matrix/app/services/ingress_api/telegram/receive_polled_update.rb`
- Move: `core_matrix/app/services/ingress_api/telegram/verify_request.rb`
- Test: `core_matrix/test/services/ingress_api/telegram/client_test.rb`
- Test: `core_matrix/test/services/ingress_api/telegram/download_attachment_test.rb`
- Test: `core_matrix/test/services/ingress_api/telegram/normalize_update_test.rb`
- Test: `core_matrix/test/services/ingress_api/telegram/progress_bridge_test.rb`
- Test: `core_matrix/test/services/ingress_api/telegram/receive_polled_update_test.rb`
- Test: `core_matrix/test/services/ingress_api/telegram/verify_request_test.rb`
- Test: `core_matrix/test/services/channel_deliveries/send_telegram_reply_test.rb`
- Test: `core_matrix/test/jobs/channel_connectors/telegram_poll_updates_job_test.rb`
- Test: `core_matrix/test/requests/ingress_api/public_endpoints_controller_test.rb`

**Step 1: Write the failing tests**

Update Telegram tests to resolve webhook handling, polling, and outbound delivery through the plugin package and host dispatchers. Collapse the old `telegram` and `telegram_webhook` split into one Telegram plugin-backed ingress definition with transport mode chosen through binding configuration.

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/ingress_api/telegram/client_test.rb test/services/ingress_api/telegram/download_attachment_test.rb test/services/ingress_api/telegram/normalize_update_test.rb test/services/ingress_api/telegram/progress_bridge_test.rb test/services/ingress_api/telegram/receive_polled_update_test.rb test/services/ingress_api/telegram/verify_request_test.rb test/services/channel_deliveries/send_telegram_reply_test.rb test/jobs/channel_connectors/telegram_poll_updates_job_test.rb test/requests/ingress_api/public_endpoints_controller_test.rb`
Expected: FAIL because Telegram is not plugin-backed yet.

**Step 3: Write minimal implementation**

Move Telegram ingress behavior into the plugin package and route webhook/poller/delivery flow through ingress definitions. Temporary bridges for old controller/job/service entrypoints are allowed only until Task 14 deletes the legacy ingress surfaces.

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/ingress_api/telegram/client_test.rb test/services/ingress_api/telegram/download_attachment_test.rb test/services/ingress_api/telegram/normalize_update_test.rb test/services/ingress_api/telegram/progress_bridge_test.rb test/services/ingress_api/telegram/receive_polled_update_test.rb test/services/ingress_api/telegram/verify_request_test.rb test/services/channel_deliveries/send_telegram_reply_test.rb test/jobs/channel_connectors/telegram_poll_updates_job_test.rb test/requests/ingress_api/public_endpoints_controller_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/plugins/core/telegram core_matrix/test/services/ingress_api/telegram core_matrix/test/services/channel_deliveries/send_telegram_reply_test.rb core_matrix/test/jobs/channel_connectors/telegram_poll_updates_job_test.rb core_matrix/test/requests/ingress_api/public_endpoints_controller_test.rb
git commit -m "refactor: package telegram ingress as plugin"
```

### Task 13: Package Weixin As An Ingress Plugin

**Depends on:** Tasks 2, 4, and 5

**Files:**
- Create: `core_matrix/app/plugins/core/weixin/plugin.rb`
- Create: `core_matrix/app/plugins/core/weixin/ingresses/weixin.rb`
- Create: `core_matrix/app/plugins/core/weixin/management_actions/configure.rb`
- Create: `core_matrix/app/plugins/core/weixin/management_actions/status.rb`
- Create: `core_matrix/app/plugins/core/weixin/management_actions/start_pairing.rb`
- Create: `core_matrix/app/plugins/core/weixin/management_actions/pairing_status.rb`
- Create: `core_matrix/app/plugins/core/weixin/management_actions/disconnect.rb`
- Create: `core_matrix/app/plugins/core/weixin/pollers/poll_account.rb`
- Create: `core_matrix/app/plugins/core/weixin/deliveries/send_reply.rb`
- Create: `core_matrix/app/plugins/core/weixin/models/login_session.rb`
- Create: `core_matrix/app/plugins/core/weixin/db/migrate/20260418000001_create_core_weixin_login_sessions.rb`
- Move: `core_matrix/app/services/ingress_api/weixin/progress_bridge.rb`
- Move: `core_matrix/app/services/ingress_api/weixin/receive_polled_message.rb`
- Test: `core_matrix/test/services/ingress_api/weixin/progress_bridge_test.rb`
- Test: `core_matrix/test/services/ingress_api/weixin/receive_polled_message_test.rb`
- Test: `core_matrix/test/services/channel_deliveries/send_weixin_reply_test.rb`
- Test: `core_matrix/test/jobs/channel_connectors/weixin_poll_account_job_test.rb`
- Test: `core_matrix/test/requests/app_api/workspace_agents/ingress_binding_actions_controller_test.rb`

**Step 1: Write the failing tests**

Update Weixin tests to resolve pairing, polling, and outbound delivery through the plugin package and generic action surface.

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/ingress_api/weixin/progress_bridge_test.rb test/services/ingress_api/weixin/receive_polled_message_test.rb test/services/channel_deliveries/send_weixin_reply_test.rb test/jobs/channel_connectors/weixin_poll_account_job_test.rb test/requests/app_api/workspace_agents/ingress_binding_actions_controller_test.rb`
Expected: FAIL because Weixin is not plugin-backed yet.

**Step 3: Write minimal implementation**

Move Weixin behavior into a plugin package, introduce plugin-owned login-session persistence, and route management through generic ingress actions instead of Weixin-specific controller methods. Temporary bridges for old Weixin-specific entrypoints are allowed only until Task 14 deletes the legacy ingress surfaces.

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/ingress_api/weixin/progress_bridge_test.rb test/services/ingress_api/weixin/receive_polled_message_test.rb test/services/channel_deliveries/send_weixin_reply_test.rb test/jobs/channel_connectors/weixin_poll_account_job_test.rb test/requests/app_api/workspace_agents/ingress_binding_actions_controller_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/plugins/core/weixin core_matrix/test/services/ingress_api/weixin core_matrix/test/services/channel_deliveries/send_weixin_reply_test.rb core_matrix/test/jobs/channel_connectors/weixin_poll_account_job_test.rb core_matrix/test/requests/app_api/workspace_agents/ingress_binding_actions_controller_test.rb
git commit -m "refactor: package weixin ingress as plugin"
```

### Task 14: Remove Host Platform Branching And Legacy Ingress Surfaces

**Depends on:** Tasks 5, 12, and 13

**Files:**
- Modify: `core_matrix/config/routes.rb`
- Modify: `core_matrix/app/controllers/app_api/workspace_agents/ingress_bindings_controller.rb`
- Delete: `core_matrix/app/controllers/app_api/workspace_agents/ingress_bindings/pairing_requests_controller.rb`
- Delete: `core_matrix/app/controllers/app_api/workspace_agents/ingress_bindings/sessions_controller.rb`
- Delete: `core_matrix/app/controllers/ingress_api/telegram/updates_controller.rb`
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
- Modify: `core_matrix/app/jobs/channel_connectors/dispatch_active_pollers_job.rb`
- Delete: `core_matrix/app/jobs/channel_connectors/telegram_poll_updates_job.rb`
- Delete: `core_matrix/app/jobs/channel_connectors/weixin_poll_account_job.rb`
- Modify: `core_matrix/app/services/channel_deliveries/dispatch_conversation_output.rb`
- Delete: `core_matrix/app/services/channel_deliveries/send_telegram_reply.rb`
- Delete: `core_matrix/app/services/channel_deliveries/send_weixin_reply.rb`
- Modify: `core_matrix/app/services/ingress_bindings/update_connector.rb`
- Delete: `core_matrix/test/requests/ingress_api/telegram/updates_controller_test.rb`
- Modify: `core_matrix/test/requests/app_api/workspace_agents/ingress_bindings_controller_test.rb`
- Modify: `core_matrix/test/requests/app_api/workspace_agents/ingress_binding_actions_controller_test.rb`
- Delete: `core_matrix/test/requests/app_api/workspace_agents/ingress_bindings/pairing_requests_controller_test.rb`
- Delete: `core_matrix/test/requests/app_api/workspace_agents/ingress_bindings/sessions_controller_test.rb`
- Modify: `core_matrix/test/jobs/channel_connectors/dispatch_active_pollers_job_test.rb`
- Modify: `core_matrix/test/services/channel_deliveries/dispatch_conversation_output_test.rb`
- Modify: `core_matrix/test/services/ingress_bindings/update_connector_test.rb`

**Step 1: Write the failing tests**

Update host-facing ingress management, generic action, and dispatcher tests so they expect plugin dispatch instead of hard-coded platform logic.

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/requests/app_api/workspace_agents/ingress_bindings_controller_test.rb test/requests/app_api/workspace_agents/ingress_binding_actions_controller_test.rb test/jobs/channel_connectors/dispatch_active_pollers_job_test.rb test/services/channel_deliveries/dispatch_conversation_output_test.rb test/services/ingress_bindings/update_connector_test.rb`
Expected: FAIL because host ingress management still branches by platform.

**Step 3: Write minimal implementation**

Replace platform branching in the host controller, route set, job, and dispatcher with ingress definition lookups and generic management actions. Delete the old Telegram webhook controller, Weixin-specific action routes, pairing/session helper controllers, per-platform poll jobs, per-platform delivery services, and the temporary `app/services/ingress_api` bridges left behind by Task 5.

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/requests/app_api/workspace_agents/ingress_bindings_controller_test.rb test/requests/app_api/workspace_agents/ingress_binding_actions_controller_test.rb test/jobs/channel_connectors/dispatch_active_pollers_job_test.rb test/services/channel_deliveries/dispatch_conversation_output_test.rb test/services/ingress_bindings/update_connector_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/config/routes.rb core_matrix/app/controllers/app_api/workspace_agents/ingress_bindings_controller.rb core_matrix/app/jobs/channel_connectors/dispatch_active_pollers_job.rb core_matrix/app/services/channel_deliveries/dispatch_conversation_output.rb core_matrix/app/services/ingress_bindings/update_connector.rb core_matrix/test/requests/app_api/workspace_agents/ingress_bindings_controller_test.rb core_matrix/test/requests/app_api/workspace_agents/ingress_binding_actions_controller_test.rb core_matrix/test/jobs/channel_connectors/dispatch_active_pollers_job_test.rb core_matrix/test/services/channel_deliveries/dispatch_conversation_output_test.rb core_matrix/test/services/ingress_bindings/update_connector_test.rb
git rm core_matrix/app/controllers/app_api/workspace_agents/ingress_bindings/pairing_requests_controller.rb core_matrix/app/controllers/app_api/workspace_agents/ingress_bindings/sessions_controller.rb core_matrix/app/controllers/ingress_api/telegram/updates_controller.rb core_matrix/app/jobs/channel_connectors/telegram_poll_updates_job.rb core_matrix/app/jobs/channel_connectors/weixin_poll_account_job.rb core_matrix/app/services/ingress_api/attach_materialized_attachments.rb core_matrix/app/services/ingress_api/context.rb core_matrix/app/services/ingress_api/envelope.rb core_matrix/app/services/ingress_api/materialize_turn_entry.rb core_matrix/app/services/ingress_api/middleware/capture_raw_payload.rb core_matrix/app/services/ingress_api/middleware/deduplicate_inbound.rb core_matrix/app/services/ingress_api/middleware/verify_request.rb core_matrix/app/services/ingress_api/preprocessors/authorize_and_pair.rb core_matrix/app/services/ingress_api/preprocessors/coalesce_burst.rb core_matrix/app/services/ingress_api/preprocessors/create_or_bind_conversation.rb core_matrix/app/services/ingress_api/preprocessors/dispatch_command.rb core_matrix/app/services/ingress_api/preprocessors/materialize_attachments.rb core_matrix/app/services/ingress_api/preprocessors/resolve_channel_session.rb core_matrix/app/services/ingress_api/preprocessors/resolve_dispatch_decision.rb core_matrix/app/services/ingress_api/receive_event.rb core_matrix/app/services/ingress_api/result.rb core_matrix/app/services/ingress_api/transport_adapter.rb core_matrix/app/services/channel_deliveries/send_telegram_reply.rb core_matrix/app/services/channel_deliveries/send_weixin_reply.rb core_matrix/test/requests/ingress_api/telegram/updates_controller_test.rb core_matrix/test/requests/app_api/workspace_agents/ingress_bindings/pairing_requests_controller_test.rb core_matrix/test/requests/app_api/workspace_agents/ingress_bindings/sessions_controller_test.rb
git commit -m "refactor: remove host ingress platform branching"
```

### Task 15: Rework Bundled Agent Provisioning Around Plugin Definitions

**Depends on:** Tasks 8-11

**Files:**
- Modify: `core_matrix/app/services/installations/register_bundled_agent_runtime.rb`
- Modify: `core_matrix/app/services/installations/bootstrap_bundled_agent_binding.rb`
- Modify: `core_matrix/app/services/agent_definition_versions/upsert_from_package.rb`
- Modify: `core_matrix/test/services/installations/register_bundled_agent_runtime_test.rb`
- Modify: `core_matrix/test/services/installations/bootstrap_bundled_agent_binding_test.rb`
- Modify: `core_matrix/test/services/installations/bootstrap_first_admin_test.rb`

**Step 1: Write the failing tests**

Update bundled provisioning tests so they expect agent/runtime capability packages to be composed from plugin definitions instead of the old configuration hash.

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/installations/register_bundled_agent_runtime_test.rb test/services/installations/bootstrap_bundled_agent_binding_test.rb test/services/installations/bootstrap_first_admin_test.rb`
Expected: FAIL because bundled provisioning is still config-hash driven.

**Step 3: Write minimal implementation**

Compose bundled agent and feature surfaces from loaded plugin definitions and remove dead configuration fields that only existed to fake plugin behavior.

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/installations/register_bundled_agent_runtime_test.rb test/services/installations/bootstrap_bundled_agent_binding_test.rb test/services/installations/bootstrap_first_admin_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/services/installations/register_bundled_agent_runtime.rb core_matrix/app/services/installations/bootstrap_bundled_agent_binding.rb core_matrix/app/services/agent_definition_versions/upsert_from_package.rb core_matrix/test/services/installations/register_bundled_agent_runtime_test.rb core_matrix/test/services/installations/bootstrap_bundled_agent_binding_test.rb core_matrix/test/services/installations/bootstrap_first_admin_test.rb
git commit -m "refactor: provision bundled capabilities from plugins"
```

### Task 16: Adapt `core_matrix_cli` To The Generic Ingress RPC Surface

**Depends on:** Tasks 4 and 14

**Files:**
- Modify: `core_matrix_cli/lib/core_matrix_cli/core_matrix_api.rb`
- Modify: `core_matrix_cli/lib/core_matrix_cli/use_cases/base.rb`
- Modify: `core_matrix_cli/lib/core_matrix_cli/use_cases/setup_telegram_polling.rb`
- Modify: `core_matrix_cli/lib/core_matrix_cli/use_cases/setup_telegram_webhook.rb`
- Modify: `core_matrix_cli/lib/core_matrix_cli/use_cases/setup_weixin.rb`
- Modify: `core_matrix_cli/lib/core_matrix_cli/use_cases/show_status.rb`
- Modify: `core_matrix_cli/lib/core_matrix_cli/commands/ingress.rb`
- Modify: `core_matrix_cli/test/core_matrix_api_test.rb`
- Modify: `core_matrix_cli/test/commands/ingress_telegram_command_test.rb`
- Modify: `core_matrix_cli/test/commands/ingress_telegram_webhook_command_test.rb`
- Modify: `core_matrix_cli/test/commands/ingress_weixin_command_test.rb`
- Modify: `core_matrix_cli/test/commands/status_command_test.rb`
- Modify: `core_matrix_cli/test/full_setup_contract_test.rb`
- Modify: `core_matrix_cli/test/support/fake_core_matrix_api.rb`
- Modify: `core_matrix_cli/test/support/fake_core_matrix_server.rb`

**Step 1: Write the failing tests**

Update CLI API and command tests so they expect:

- generic ingress binding creation with plugin-aware payloads instead of raw `platform` branching
- generic ingress management actions for Weixin pairing and status flows
- status/setup commands to remain operator-friendly while calling the new host-owned RPC surface

**Step 2: Run tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec rake test TEST=test/core_matrix_api_test.rb
bundle exec rake test TEST=test/commands/ingress_telegram_command_test.rb
bundle exec rake test TEST=test/commands/ingress_telegram_webhook_command_test.rb
bundle exec rake test TEST=test/commands/ingress_weixin_command_test.rb
bundle exec rake test TEST=test/commands/status_command_test.rb
bundle exec rake test TEST=test/full_setup_contract_test.rb
```

Expected: FAIL because the CLI still targets platform-specific ingress endpoints and payload shapes.

**Step 3: Write minimal implementation**

Update `core_matrix_cli` so it remains a host-owned RPC consumer:

- keep the `telegram`, `telegram-webhook`, and `weixin` commands as operator conveniences
- create/show ingress bindings through the new generic CoreMatrix surface
- execute pairing, status, disconnect, and secret rotation through generic ingress management actions
- update fake API/server support so contract tests model the new generic RPC shape

**Step 4: Run tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec rake test TEST=test/core_matrix_api_test.rb
bundle exec rake test TEST=test/commands/ingress_telegram_command_test.rb
bundle exec rake test TEST=test/commands/ingress_telegram_webhook_command_test.rb
bundle exec rake test TEST=test/commands/ingress_weixin_command_test.rb
bundle exec rake test TEST=test/commands/status_command_test.rb
bundle exec rake test TEST=test/full_setup_contract_test.rb
```

Expected: PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix_cli/lib/core_matrix_cli/core_matrix_api.rb core_matrix_cli/lib/core_matrix_cli/use_cases/base.rb core_matrix_cli/lib/core_matrix_cli/use_cases/setup_telegram_polling.rb core_matrix_cli/lib/core_matrix_cli/use_cases/setup_telegram_webhook.rb core_matrix_cli/lib/core_matrix_cli/use_cases/setup_weixin.rb core_matrix_cli/lib/core_matrix_cli/use_cases/show_status.rb core_matrix_cli/lib/core_matrix_cli/commands/ingress.rb core_matrix_cli/test/core_matrix_api_test.rb core_matrix_cli/test/commands/ingress_telegram_command_test.rb core_matrix_cli/test/commands/ingress_telegram_webhook_command_test.rb core_matrix_cli/test/commands/ingress_weixin_command_test.rb core_matrix_cli/test/commands/status_command_test.rb core_matrix_cli/test/full_setup_contract_test.rb core_matrix_cli/test/support/fake_core_matrix_api.rb core_matrix_cli/test/support/fake_core_matrix_server.rb
git commit -m "refactor: route cmctl ingress flows through generic rpc"
```

### Task 17: Add Extension Governance And Authoring Docs

**Depends on:** Tasks 1-16

**Files:**
- Create: `core_matrix/AGENTS.md`
- Create: `core_matrix/docs/architecture/extensions.md`
- Create: `core_matrix/docs/extensions/authoring.md`
- Create: `core_matrix/docs/extensions/ingress.md`
- Create: `core_matrix/docs/extensions/embedded-agents.md`
- Create: `core_matrix/docs/extensions/embedded-features.md`
- Create: `core_matrix/docs/extensions/migrations-and-dependencies.md`
- Modify: `core_matrix/docs/INTEGRATIONS.md`
- Modify: `core_matrix/docs/INSTALL.md`
- Modify: `core_matrix/docs/ADMIN-QUICK-START-GUIDE.md`
- Modify: `core_matrix_cli/README.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/AGENTS.md`

**Step 1: Write the doc checklist**

Create a checklist covering:

- plugin packaging rules
- host contract ownership
- manifest and gem fragment conventions
- migration boundaries
- management-action and public-endpoint rules
- `core_matrix_cli` as a stable consumer of the generic RPC surface rather than a plugin host
- explicit prohibition on new platform branching in host code

**Step 2: Write the documents**

Author docs so a future contributor can add a new plugin without reverse-engineering `app/services`, and so operators can still follow `cmctl` ingress setup against the new generic RPC surface.

**Step 3: Review the docs for consistency**

Verify that:

- docs consistently require `public_id`
- docs reflect the final route/controller surfaces
- docs make it clear that `cmctl` remains a host-owned RPC client, not an extension mechanism
- docs explain why plugins are packaging units and contract types are host-owned categories

**Step 4: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add AGENTS.md core_matrix/AGENTS.md core_matrix/docs/architecture/extensions.md core_matrix/docs/extensions core_matrix/docs/INTEGRATIONS.md core_matrix/docs/INSTALL.md core_matrix/docs/ADMIN-QUICK-START-GUIDE.md core_matrix_cli/README.md
git commit -m "docs: add extension governance and authoring guides"
```

### Task 18: Run Focused Structural Verification

**Depends on:** Tasks 1-17

**Files:**
- No planned files. If any check fails, identify the exact offending file(s), make a small repair commit against those files, and rerun this task before proceeding.

**Step 1: Run focused tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test \
  test/extensions \
  test/ingresses \
  test/embedded_agents \
  test/embedded_features \
  test/services/embedded_agents \
  test/services/embedded_features \
  test/services/runtime_features \
  test/services/ingress_api \
  test/services/conversations/metadata \
  test/services/provider_execution \
  test/services/channel_deliveries \
  test/services/ingress_bindings \
  test/services/installations \
  test/requests/ingress_api \
  test/requests/app_api/workspace_agents \
  test/jobs/channel_connectors \
  test/jobs/conversations/metadata

cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec rake test TEST=test/core_matrix_api_test.rb
bundle exec rake test TEST=test/commands/ingress_telegram_command_test.rb
bundle exec rake test TEST=test/commands/ingress_telegram_webhook_command_test.rb
bundle exec rake test TEST=test/commands/ingress_weixin_command_test.rb
bundle exec rake test TEST=test/commands/status_command_test.rb
bundle exec rake test TEST=test/full_setup_contract_test.rb
```

Expected: PASS

**Step 2: Run structural grep acceptance checks**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
rg -n 'when "telegram"|when "telegram_webhook"|when "weixin"|PLATFORM_CONNECTOR_DEFAULTS|TELEGRAM_FAMILY_PLATFORMS|EmbeddedAgents::Registry|RuntimeFeatures::Registry|/weixin/start_login|/weixin/login_status|/weixin/disconnect|/ingress_api/telegram/bindings/' core_matrix/app core_matrix/config core_matrix_cli/lib core_matrix_cli/test
find core_matrix/app/services -path '*/ingress_api/*' -type f
find core_matrix/app/services -path '*/embedded_agents/*' -type f
find core_matrix/app/services -path '*/runtime_features/*' -type f
find core_matrix/app/services -path '*/embedded_features/*' -type f
```

Expected: the `rg -n` command returns either no matches or only matches inside plugin package implementations or explicit migration history comments, and the `find` commands return no files for `ingress_api`, `embedded_agents`, `runtime_features`, or `embedded_features` under `core_matrix/app/services`.

**Step 3: Run lint and boot checks**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rubocop -f github
bundle exec ruby -e 'require "./config/application"'
```

Expected: PASS

**Step 4: Fix failures and rerun only failed checks**

Make the minimal fixes needed to satisfy all focused tests, grep checks, lint, and boot checks, then rerun the failed commands until green.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix core_matrix_cli
git commit -m "test: verify extension refactor structure"
```

### Task 19: Run Full CoreMatrix Verification And Final Acceptance Audit

**Depends on:** Task 18

**Files:**
- No planned files. If a full verification command fails, repair the specific file(s) named by the failure, rerun the failed command to green, and then restart this task's audit sequence.

**Step 1: Run the full CoreMatrix verification commands**

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

**Step 2: Run the full `core_matrix_cli` verification command**

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
- ingress/bootstrap/conversation surfaces still produce correct public-id-based shapes
- `core_matrix_cli` exercises the generic ingress RPC surface successfully in its contract coverage
- the final acceptance checklist at the top of this plan is satisfied line by line

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix core_matrix_cli verification
git commit -m "chore: complete extension refactor verification"
```
