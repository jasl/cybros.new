# Agent Definition Version And Pairing Session V2 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the current `AgentSnapshot` and `AgentEnrollment` centered substrate with a cleaner platform model built around `AgentDefinitionVersion`, `AgentConfigState`, `PairingSession`, and `ExecutionRuntimeVersion`.

**Architecture:** Rewrite the early Core Matrix schema in place, keep local authoring in `agents/fenix` and `execution_runtimes/nexus`, normalize agent/runtime definition packages into immutable version rows, and keep turn-time freezing limited to version refs plus the exact effective execution projection. This plan is intentionally destructive: it favors a cleaner base schema over compatibility with current development data.

**Tech Stack:** Rails 8.2, PostgreSQL JSONB, Active Record, Minitest, monorepo apps (`core_matrix`, `agents/fenix`, `execution_runtimes/nexus`)

---

## Plan Rules

- Treat this as a base-schema rewrite, not an additive compatibility layer.
- Do not keep `AgentSnapshot` or `AgentEnrollment` as hidden semantic aliases.
- Keep external and agent-facing boundaries on `public_id` or credentials only.
- Keep `ExecutionRuntime` pairing-based; do not turn this plan into managed deployment work.
- Do not implement `callable_agents` or broader multi-agent topology changes in this branch.

### Task 1: Rewrite the foundational schema around the new aggregates

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260324090006_create_agents.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260324090007_create_execution_runtimes.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260324090008_create_agent_enrollments.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260324090009_create_agent_snapshots.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260324090010_create_capability_snapshots.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260324090016_create_usage_events.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260324090017_create_usage_rollups.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260324090021_create_turns.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260326113000_add_agent_control_contract.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260330143000_add_tool_governance.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/schema.rb`

**Step 1: Repurpose the early migration sequence into the new base model**

- rewrite `20260324090008_create_agent_enrollments.rb` so it creates `json_documents`
- rewrite `20260324090009_create_agent_snapshots.rb` so it creates `pairing_sessions`
- rewrite `20260324090010_create_capability_snapshots.rb` so it creates:
  - `agent_definition_versions`
  - `agent_config_states`
  - `execution_runtime_versions`
- add `public_id` to the new tables from day one
- keep the new tables installation-scoped with explicit `installation_id`
  foreign keys, matching the rest of Core Matrix

**Step 2: Rebuild `agents` and `execution_runtimes` around active version refs**

- keep `agents` as the logical identity table
- keep `execution_runtimes` as the logical runtime identity table
- remove definition-like JSON blobs from `execution_runtimes`
- add active-version refs such as:
  - `agents.active_agent_definition_version_id`
  - `execution_runtimes.active_execution_runtime_version_id`
- keep `agents.default_execution_runtime_id` as an operational preference only

**Step 3: Rebuild `turns` around version refs instead of `agent_snapshot`**

- replace `agent_snapshot_id` with `agent_definition_version_id`
- remove `pinned_agent_snapshot_fingerprint`
- add:
  - `agent_config_version`
  - `agent_config_content_fingerprint`
  - `execution_runtime_version_id`
- keep `resolved_config_snapshot` and `resolved_model_selection_snapshot`
- move `json_documents` creation out of this migration, since the table now exists earlier
- keep the `conversations.override_payload` family, but make it explicitly
  validate against the definition version’s conversation-override schema

**Step 4: Re-anchor later schema that still points at `agent_snapshot`**

- rewrite `usage_events` and `usage_rollups` to reference `agent_definition_version`
- rewrite `execution_contracts`, `execution_capability_snapshots`, `agent_connections`, and mailbox delivery tables to reference `agent_definition_version`
- add `execution_runtime_version` refs where runtime-version identity matters, especially on `execution_contracts` and `execution_runtime_connections`
- rewrite `tool_definitions` to belong to `agent_definition_version`
- rename legacy columns in later migrations where clarity matters, for example:
  - `agent_snapshot_fingerprint` -> `agent_definition_fingerprint`
  - `target_agent_snapshot_id` -> `target_agent_definition_version_id`

**Step 5: Regenerate the schema from scratch after migration edits**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
rails db:drop && rm db/schema.rb && rails db:create && rails db:migrate && rails db:reset
```

Expected:

- a clean `db/schema.rb` with no `agent_snapshots` or `agent_enrollments` tables
- `pairing_sessions`, `agent_definition_versions`, `agent_config_states`, and `execution_runtime_versions` present

### Task 2: Replace the old Ruby aggregates with the new model layer

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/agent_definition_version.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/agent_config_state.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/pairing_session.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/execution_runtime_version.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/agent.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/execution_runtime.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/agent_connection.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/execution_runtime_connection.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/turn.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/tool_definition.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/usage_event.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/usage_rollup.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/agent_snapshot.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/agent_enrollment.rb`

**Step 1: Add the new immutable version models**

- `AgentDefinitionVersion` should hold normalized definition documents and fingerprints
- `ExecutionRuntimeVersion` should hold lightweight runtime-defining content and document refs
- both should be append-only in behavior and include `HasPublicId`

**Step 2: Add the new mutable control models**

- `AgentConfigState` should hold the current override/effective config state for one logical `Agent`
- `PairingSession` should hold the bounded token-driven pairing lifecycle
- `Agent` and `ExecutionRuntime` should each point at their current active version row

**Step 3: Retarget live connection models**

- `AgentConnection` should belong to `agent` and `agent_definition_version`
- `ExecutionRuntimeConnection` should belong to `execution_runtime` and `execution_runtime_version`
- keep connection credential and token semantics unchanged
- keep `public_id` on these connection rows

**Step 4: Remove old semantic aliases instead of carrying shims**

- do not keep `AgentSnapshot` and `AgentEnrollment` as hidden compatibility wrappers
- update all model associations and validations to the new names directly
- fix any remaining code paths that still rely on the old constants

### Task 3: Publish normalized definition packages from Fenix and Nexus

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/config/canonical_config.schema.json`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/config/canonical_config.defaults.json`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/config/reflected_surface.json`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/runtime/manifest/definition_package.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/runtime/manifest/pairing_manifest.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/integration/runtime_manifest_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/app/services/runtime/manifest/version_package.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/app/services/runtime/manifest/pairing_manifest.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/integration/runtime_manifest_test.rb`

**Step 1: Make Fenix publish an explicit definition package**

- local files should remain the authoring source
- the pairing manifest should carry a normalized payload that includes:
  - `program_manifest_fingerprint`
  - `prompt_pack_ref`
  - `prompt_pack_fingerprint`
  - `protocol_version`
  - `sdk_version`
  - protocol methods
  - tool contract
  - profile policy
  - canonical config schema
  - conversation override schema
  - default canonical config
  - reflected surface

**Step 2: Keep selector policy and fallback structure explicit**

- keep role-slot configuration in the kernel-readable definition payload
- allow selectors to be role-based or explicit provider/model selectors
- keep `main` as the reserved fallback role slot
- keep display text and examples in the reflected surface, not in runtime-effective config

**Step 3: Make Nexus publish an explicit runtime version package**

- include:
  - `execution_runtime_fingerprint`
  - `kind`
  - `protocol_version`
  - `sdk_version`
  - normalized capability payload
  - normalized tool catalog
  - optional reflected host metadata
- keep runtime package intentionally lightweight; do not add agent semantics here

### Task 4: Rewrite pairing and registration flows around `PairingSession`

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/pairing_sessions/issue.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/pairing_sessions/resolve_from_token.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/pairing_sessions/record_progress.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_definition_versions/register.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_definition_versions/handshake.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_definition_versions/build_recovery_plan.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_definition_versions/resolve_recovery_target.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_config_states/reconcile.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/execution_runtime_versions/register.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/execution_runtimes/register.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/agent_api/registrations_controller.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/agent_api/capabilities_controller.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/execution_runtime_api/registrations_controller.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/execution_runtime_api/capabilities_controller.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_enrollments/issue.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_snapshots/register.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_snapshots/handshake.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_snapshots/build_recovery_plan.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_snapshots/resolve_recovery_target.rb`

**Step 1: Replace one-shot enrollment semantics with bounded pairing-session semantics**

- issue tokens through `PairingSessions::Issue`
- resolve tokens through `PairingSessions::ResolveFromToken`
- allow repeated runtime and agent refresh within expiry
- update:
  - `last_used_at`
  - `runtime_registered_at`
  - `agent_registered_at`
  - `closed_at`
  - `revoked_at`

**Step 2: Make runtime registration reconcile logical runtime plus current version**

- reconcile or create the logical `ExecutionRuntime`
- create or reuse the current `ExecutionRuntimeVersion`
- rotate the active `ExecutionRuntimeConnection`
- update `Agent.default_execution_runtime_id` only as an operational preference

**Step 3: Make agent registration reconcile logical definition plus current config state**

- normalize the incoming Fenix definition package into `AgentDefinitionVersion`
- create or update the singleton `AgentConfigState` for the logical `Agent`
- rotate the active `AgentConnection`
- update `Agent.active_agent_definition_version_id`

**Step 4: Keep capabilities refresh separate from logical identity**

- runtime capability refresh should create a new `ExecutionRuntimeVersion` only when version-defining content changes
- agent capability refresh should create a new `AgentDefinitionVersion` only when the normalized definition package changes
- heartbeat and health signals should update connection rows, not version rows
- any remaining `agent_snapshots/*` services should either move under `agent_definition_versions/*` or be deleted if the responsibility now belongs on turns, connections, or config state

**Step 5: Keep external boundaries clean**

- controllers should continue returning `public_id` or token-bearing payloads only
- no external or agent-facing response should leak bigint ids

### Task 5: Rebuild config-state reconciliation and capability composition on top of definition versions

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_config_states/update.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_config_states/resolve_effective.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_config_states/validate_schema.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/validate_override_payload.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/execution_contract.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/execution_capability_snapshot.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/agent_control_mailbox_item.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/runtime_capability_contract.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/runtime_capabilities/preview_for_conversation.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/runtime_capabilities/compose_for_turn.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/runtime_capabilities/compose_effective_tool_catalog.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/runtime_capabilities/compose_visible_tool_catalog.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/agent_api/capabilities_controller.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/tool_definition.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/tool_binding.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/Gemfile`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/Gemfile.lock`

**Step 1: Add schema validation for the constrained canonical-config subset**

- validate against the supported JSON Schema subset from the design doc
- reject unsupported schema shapes early
- make schema validation part of definition-version registration, not an afterthought

**Step 2: Reconcile mutable config state against immutable definition versions**

- keep one `AgentConfigState` row per logical `Agent`
- preserve invalid overrides but move the row into `reconciliation_required`
- recompute `effective_document` only when definition or overrides change
- use optimistic versioning on the mutable config row

**Step 2.5: Validate conversation-scoped override payloads explicitly**

- keep conversation override payload separate from `AgentConfigState`
- validate `Conversation.override_payload` against the published
  conversation-override schema for the active `AgentDefinitionVersion`
- fail fast on invalid override payloads rather than silently dropping fields
- keep the merged turn-time effective config as the only frozen execution
  result

**Step 3: Move tool governance to `AgentDefinitionVersion`**

- `tool_definitions` should belong to `agent_definition_version`
- governed effective tool catalog should be composed from:
  - definition-level tool contract
  - runtime-level tool catalog
  - Core Matrix reserved tools
  - config-state and profile-policy effects

**Step 4: Keep read models embedded in the definition version**

- do not introduce a separate reflection aggregate
- keep reflected read-only metadata on `AgentDefinitionVersion`
- let preview and future product surfaces read from the normalized definition version

### Task 6: Rewrite turn entry, freezing, and recovery around version refs

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/conversation.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/turns/start_agent_turn.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/turns/start_user_turn.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/turns/start_automation_turn.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/turns/select_execution_runtime.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/workflows/build_execution_snapshot.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/workflows/create_for_turn.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/subagent_connections/spawn.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/turn_execution_snapshot.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/agent_snapshot_recovery_plan.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/agent_snapshot_recovery_target.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/turns/freeze_agent_snapshot.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/execution_identity_recovery_plan.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/execution_identity_recovery_target.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/turns/freeze_execution_identity.rb`

**Step 1: Resolve versioned execution identity at turn start**

- resolve the active `AgentDefinitionVersion`
- resolve the current `AgentConfigState`
- resolve the selected `ExecutionRuntime` and `ExecutionRuntimeVersion`
- validate the conversation override payload against the active definition
  version’s conversation-override schema
- compute the effective config and resolved model selection before workflow execution begins

**Step 2: Freeze the minimal execution contract on the turn**

- persist:
  - `agent_definition_version_id`
  - `agent_config_version`
  - `agent_config_content_fingerprint`
  - `execution_runtime_id`
  - `execution_runtime_version_id`
- keep `resolved_config_snapshot` and `resolved_model_selection_snapshot` as frozen execution payloads

**Step 3: Retarget execution-contract and recovery logic**

- execution-capability snapshots should compare against definition-version identity, not `agent_snapshot`
- recovery logic should compare frozen:
  - definition version identity
  - config fingerprint
  - runtime version identity
- move recovery plan/target helpers onto execution-identity vocabulary, not
  `agent_snapshot` vocabulary
- do not require a mixed-purpose snapshot aggregate to answer recovery questions

**Step 4: Keep subagent spawning aligned with the same rules**

- spawned work should inherit or resolve config state the same way as top-level turns
- do not introduce new subagent topology semantics in this plan

### Task 7: Rewrite tests, behavior docs, and verification around the new vocabulary

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/agent-registry-and-connectivity-foundations.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/agent-registration-and-capability-handshake.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/workflow-context-assembly-and-execution-snapshot.md`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/agent-definition-version-and-pairing-session.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/agent_connection_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/agent_definition_version_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/agent_config_state_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/pairing_session_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/execution_runtime_version_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/conversation_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/execution_runtimes/register_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_definition_versions/register_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_config_states/reconcile_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversations/validate_override_payload_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/pairing_sessions/issue_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/execution_runtime_versions/register_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/agent_api/registrations_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/agent_api/capabilities_controller_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/execution_runtime_api/registrations_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/execution_runtime_api/capabilities_controller_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/integration/bring_your_own_agent_pairing_flow_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/integration/agent_recovery_flow_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/integration/workflow_selector_flow_test.rb`

**Step 1: Replace the old vocabulary in behavior docs and tests**

- use `PairingSession`, not `AgentEnrollment`
- use `AgentDefinitionVersion`, not `AgentSnapshot`
- use `ExecutionRuntimeVersion` where versioned runtime identity matters

**Step 2: Add focused model and service coverage for the new invariants**

- append-only definition versions
- singleton mutable `AgentConfigState`
- bounded pairing-session lifecycle
- validated conversation override payload behavior
- runtime-version creation only on logical runtime-definition change

**Step 3: Add end-to-end regression coverage for the primary target scenario**

- bundled `Fenix + Nexus`
- `Fenix + external workstation runtime`
- turn freezing and recovery across definition-version or runtime-version changes

**Step 4: Verify with the destructive reset workflow and project test suites**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
rails db:drop && rm db/schema.rb && rails db:create && rails db:migrate && rails db:reset
bin/rails test
bin/rails test:system
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
```

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/rails test test/integration/runtime_manifest_test.rb
bin/rails test test/services/build_round_instructions_test.rb
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
```

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus
bin/rails test test/integration/runtime_manifest_test.rb
```

### Notes For Execution

- Prefer renaming files, classes, and migrations to the target vocabulary instead of keeping hidden compatibility shims.
- If a later migration still references `agent_snapshot`, rewrite it now rather than layering another rename migration on top.
- Keep `ExecutionRuntime` fast for hot-path reads; the version table exists for identity, history, and diffing, not to replace the mutable aggregate.
- Keep the runtime-compatibility story diagnostic-only in this branch; do not turn it into a hard scheduling gate.
- If a test, doc, or controller still requires the old vocabulary, treat that as unfinished migration work rather than acceptable debt.
