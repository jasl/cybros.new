# Workspace-Agent Settings Infrastructure Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the current flat `WorkspaceAgent.settings_payload` ad hoc keys with a structured settings infrastructure backed by agent-version-owned schema/default documents, while keeping runtime turn payloads compact and making mount model-selector preferences real soft selector overrides.

**Architecture:** Fenix publishes `workspace_agent_settings_schema` and
`default_workspace_agent_settings` in its definition package. CoreMatrix stores
nested mount overrides on `WorkspaceAgent.settings_payload`, validates writes
against the versioned settings contract without interpreting profile business
rules, freezes the raw settings payload into execution snapshots, uses only the
generic model-selector fields during model resolution, and treats any
profile/specialist keys as opaque strings.

**Tech Stack:** Ruby on Rails, Active Record JSON columns, `JsonDocument` deduplication, existing execution snapshot/mailbox paths, Fenix runtime manifest, Minitest.

---

### Task 1: Lock the new settings contract in docs and tests

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/plans/2026-04-16-workspace-agent-settings-infrastructure-design.md`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/plans/2026-04-16-workspace-agent-settings-infrastructure-implementation.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/workspace_agent_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/app_api/workspaces/workspace_agents_controller_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/app_api/workspaces_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/app_surface/presenters/workspace_agent_presenter_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/app_surface/presenters/workspace_presenter_test.rb`

**Step 1: Write failing tests for the structured mount payload**

Cover:

- nested `interactive` / `subagents` settings normalize into a stable shape
- unsupported nested keys are rejected
- `settings_payload` blank values collapse cleanly
- app surfaces expose:
  - nested `settings_payload`
  - `settings_schema`
  - `default_settings_payload`

**Step 2: Run the focused CoreMatrix tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/models/workspace_agent_test.rb \
  test/requests/app_api/workspaces/workspace_agents_controller_test.rb \
  test/requests/app_api/workspaces_test.rb \
  test/services/app_surface/presenters/workspace_agent_presenter_test.rb \
  test/services/app_surface/presenters/workspace_presenter_test.rb
```

Expected: failing tests because the structured settings contract is not yet implemented.

### Task 2: Add agent-version-owned settings schema/default documents

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/agent_definition_version.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_definition_versions/upsert_from_package.rb`
- Modify one owning migration under `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/` that creates `agent_definition_versions`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/schema.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/runtime_capability_contract.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/agent_api/capabilities_controller.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/agent_definition_version_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/runtime_capability_contract_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/agent_api/capabilities_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_definition_versions/register_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_definition_versions/handshake_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/agent_api/registrations_test.rb`

**Step 1: Write failing tests for the new versioned docs**

Cover:

- `AgentDefinitionVersion` stores and exposes:
  - `workspace_agent_settings_schema`
  - `default_workspace_agent_settings`
- registration/handshake requires those fields to be hashes
- runtime capability payload includes them in the agent plane

**Step 2: Implement the new document refs**

Add:

- `workspace_agent_settings_schema_document`
- `default_workspace_agent_settings_document`

to `AgentDefinitionVersion`, `UpsertFromPackage`, the destructive migration, and
`RuntimeCapabilityContract`.

**Step 3: Rebuild schema**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
rails db:drop && rm db/schema.rb && rails db:create && rails db:migrate && rails db:reset
```

**Step 4: Run focused CoreMatrix tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/models/agent_definition_version_test.rb \
  test/models/runtime_capability_contract_test.rb \
  test/requests/agent_api/capabilities_test.rb \
  test/services/agent_definition_versions/register_test.rb \
  test/services/agent_definition_versions/handshake_test.rb \
  test/requests/agent_api/registrations_test.rb
```

Expected: PASS.

### Task 3: Publish settings schema/defaults from Fenix

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/runtime/manifest/definition_package.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/integration/runtime_manifest_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/shared/control_plane/client_test.rb`

**Step 1: Write failing Fenix manifest tests**

Cover:

- runtime manifest definition package includes:
  - `workspace_agent_settings_schema`
  - `default_workspace_agent_settings`
- defaults reflect the builtin profile catalog
- generic CoreMatrix defaults stay conservative:
  `core_matrix.interactive.model_selector = role:main`
  and `core_matrix.subagents.default_model_selector = role:main`
- label-specific selector preferences are optional mount overrides, not shipped
  defaults

**Step 2: Implement manifest publication**

Build a small settings-schema/default generator in Fenix that:

- uses the current builtin profile catalog
- keeps prompt ownership local
- publishes only settings contract metadata and defaults

**Step 3: Run focused Fenix tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/rails test test/integration/runtime_manifest_test.rb test/services/shared/control_plane/client_test.rb
```

Expected: PASS.

### Task 4: Implement structured mount settings validation and app-surface exposure

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/workspace_agent.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/workspace_agent_settings/schema.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/workspace_agent_settings/validator.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/app_api/workspaces/workspace_agents_controller.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/app_surface/presenters/workspace_agent_presenter.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/app_surface/presenters/workspace_presenter.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/app_api/base_controller.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/test_helper.rb`
- Modify the tests from Task 1

**Step 1: Write failing tests for schema/default-based validation**

Cover:

- `WorkspaceAgent` validates nested payloads against the current agent version
  settings schema/default contract
- CoreMatrix does not apply extra profile-membership rules beyond the schema
- presenter exposes nested `settings_payload` plus schema/default payloads
- workspace list fan-out stays preload-safe

**Step 2: Implement the new settings infrastructure**

Add:

- a small schema/default resolver for the current mounted agent definition
- a validator that normalizes the nested payload against schema types only
- app-surface exposure for schema/default payloads

Keep `settings_payload` as the persisted column name.

**Step 3: Run focused CoreMatrix tests**

Run the Task 1 command again.

Expected: PASS.

### Task 5: Freeze raw runtime settings into execution contracts

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/execution_contract.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/workflows/build_execution_snapshot.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/turn_execution_snapshot.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/agent_control_mailbox_item.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/provider_execution/prepare_agent_round.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/create_agent_request.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/execution_contract_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/workflows/build_execution_snapshot_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/turn_execution_snapshot_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/agent_control_mailbox_item_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/provider_execution/prepare_agent_round_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/create_agent_request_test.rb`

**Step 1: Write failing tests for the runtime settings payload**

Cover:

- nested mount settings freeze as the raw `settings_payload` shape
- snapshot/mailbox reconstruction stays stable
- changing mount settings later does not mutate earlier frozen turns

**Step 2: Implement the compact projection**

Keep the existing deduplicated `JsonDocument` strategy, but freeze the raw
nested stored payload instead of a profile-aware compact projection.

**Step 3: Run focused CoreMatrix tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/models/execution_contract_test.rb \
  test/services/workflows/build_execution_snapshot_test.rb \
  test/models/turn_execution_snapshot_test.rb \
  test/models/agent_control_mailbox_item_test.rb \
  test/services/provider_execution/prepare_agent_round_test.rb \
  test/services/agent_control/create_agent_request_test.rb
```

Expected: PASS.

### Task 6: Make interactive mount model selectors real soft preferences

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/workflows/resolve_model_selector.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/workflows/resolve_model_selector_test.rb`

**Step 1: Write failing tests**

Cover:

- explicit selector/candidate still wins
- if no explicit selector exists, `interactive.model_selector` is tried first
- if that selector is unavailable/unknown, resolution falls back to the normal
  catalog default

**Step 2: Implement soft interactive selector fallback**

Do not treat mount-provided selector preferences as hard failures.

**Step 3: Run focused tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/workflows/resolve_model_selector_test.rb
```

Expected: PASS.

### Task 7: Make subagent model selectors real soft preferences during spawn

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/subagent_connections/spawn.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/runtime_capabilities/compose_visible_tool_catalog.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/subagent_connections/spawn_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/runtime_capabilities/compose_for_turn_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/provider_execution/execute_core_matrix_tool_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/provider_execution/tool_call_runners/agent_mediated_test.rb`

**Step 1: Write failing tests**

Cover:

- subagent explicit `model_selector_hint` becomes the child workflow selector
  when resolvable
- otherwise the mount tries:
  - `subagents.profile_overrides.<profile>.model_selector`
  - `subagents.default_model_selector`
- if none resolve, the child falls back to the origin turn selector
- `resolved_model_selector_hint` stores the chosen successful selector
- `subagent_spawn` no longer requires CoreMatrix-side profile enumeration or
  enabled-profile validation

**Step 2: Implement spawn-side selector selection**

Keep the tool argument name `model_selector_hint`, but treat it as a soft
selector preference and apply it to child workflow creation. Any profile-label
lookups against `label_model_selectors` are opaque string matches only, and the
absence of a label-specific entry must fall through to the default selector.

**Step 3: Run focused tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/subagent_connections/spawn_test.rb \
  test/services/runtime_capabilities/compose_for_turn_test.rb \
  test/services/provider_execution/execute_core_matrix_tool_test.rb \
  test/services/provider_execution/tool_call_runners/agent_mediated_test.rb
```

Expected: PASS.

### Task 8: Full verification, acceptance, and artifact audit

**Files:**
- No new files by default; update tests/docs if audit findings require fixes.

**Step 1: Run full verification**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bin/rails db:test:prepare
bin/rails test
```

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

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
ACTIVE_ACCEPTANCE_ENABLE_2048_CAPSTONE=1 bash acceptance/bin/run_active_suite.sh
```

**Step 2: Inspect acceptance artifacts and DB state**

Verify:

- latest 2048 capstone export/debug artifacts
- latest `review/workflow-mermaid.md`
- whether subagent/specialist data is present when exercised
- conversation / turn / message / message_attachment / active_storage rows
- selector snapshots and any subagent connection selector evidence

**Step 3: Milestone review**

Open subagents for:

- Rails/domain architecture
- test coverage and acceptance path
- data model / migration / snapshot state
- subagent / selector semantics

Address findings, rerun affected verification, then checkpoint commit.
