# Workspace-Agent Profile Catalog Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a Fenix-owned prompt/profile catalog while keeping `WorkspaceAgent`
settings agent-owned, and keep the CoreMatrix↔Fenix protocol limited to raw
settings payload plus small resolved runtime facts.

**Architecture:** Fenix loads profile bundles from `prompts/` and `prompts.d/`,
assembles prompts and routing hints locally, and resolves profile/business
behavior from raw mount settings. CoreMatrix stores agent-owned settings,
freezes raw settings into execution contracts, resolves model selectors from the
generic model-selector fields it owns, and persists only resolved runtime facts.

**Tech Stack:** Ruby on Rails, Active Record JSON columns, existing execution snapshot/mailbox normalization paths, Fenix prompt assembly services, Minitest.

---

### Task 1: Lock the new catalog contract in Fenix tests

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/prompts/profile_catalog_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/prompts/profile_bundle_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/requests/prepare_round_test.rb`

**Step 1: Write failing tests for profile discovery and validation**

Cover:

- builtin `main` and `specialists` trees are discovered
- a profile without both `USER.md` and `WORKER.md` is invalid
- profile-local `SOUL.md` falls back to shared `prompts/SOUL.md`
- `prompts.d` same-key override replaces the whole profile directory

**Step 2: Write failing tests for prompt assembly profile selection**

Cover:

- interactive execution uses the selected interactive profile
- delegated execution uses the selected specialist profile
- routing summaries only include specialist keys supplied by the raw
  `workspace_agent_context.settings_payload`

**Step 3: Run the focused Fenix tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/rails test test/services/prompts/profile_catalog_test.rb test/services/prompts/profile_bundle_test.rb test/services/requests/prepare_round_test.rb
```

Expected: failing tests because the catalog loader and prompt-routing logic do
not exist yet.

**Step 4: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/prompts/profile_catalog_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/prompts/profile_bundle_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/requests/prepare_round_test.rb
git commit -m "test: lock fenix profile catalog contract"
```

### Task 2: Build the Fenix profile catalog and prompt bundle loader

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/prompts/profile_bundle.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/prompts/profile_catalog.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/prompts/profile_catalog_loader.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/prompts/main/pragmatic/meta.yml`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/prompts/main/pragmatic/USER.md`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/prompts/main/friendly/meta.yml`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/prompts/main/friendly/USER.md`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/prompts/specialists/researcher/meta.yml`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/prompts/specialists/researcher/WORKER.md`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/prompts/specialists/developer/meta.yml`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/prompts/specialists/developer/WORKER.md`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/prompts/specialists/tester/meta.yml`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/prompts/specialists/tester/WORKER.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/prompts/SOUL.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/prompts/assembler.rb`

**Step 1: Implement profile bundle loading**

Build a loader that:

- scans builtin and override trees
- resolves one effective directory per profile key
- validates `meta.yml`
- applies strict `USER.md` / `WORKER.md` fallback rules
- falls back to shared `prompts/SOUL.md` when profile-local `SOUL.md` is absent

**Step 2: Migrate prompt assembly to bundle-based selection**

Update `Prompts::Assembler` so it:

- receives the effective profile key and execution mode
- loads the correct prompt bundle through the catalog
- renders the selected bundle instead of hardcoding `USER.md` vs `WORKER.md`

**Step 3: Add the initial builtin profiles**

Ship only the minimum useful set in the first round:

- interactive `pragmatic`
- interactive `friendly`
- specialist `researcher`
- specialist `developer`
- specialist `tester`

Keep `researcher` as the existing specialist key. Interactive work should use
the readable keys `pragmatic` and `friendly`.

Author the initial prompt bundles using the reviewed mature projects as
reference patterns:

- Codex for role-oriented task framing
- Hermes Agent for delegated-scope and evidence instructions
- Claude Code for narrow focused-subagent wording
- Paperclip for structured metadata packaging

Treat those projects as inspiration only. The Fenix prompt text remains local
and authoritative.

**Step 4: Run the focused Fenix tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/rails test test/services/prompts/profile_catalog_test.rb test/services/prompts/profile_bundle_test.rb test/services/requests/prepare_round_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/prompts/profile_bundle.rb \
  /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/prompts/profile_catalog.rb \
  /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/prompts/profile_catalog_loader.rb \
  /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/prompts \
  /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/prompts/assembler.rb
git commit -m "feat: add fenix profile catalog"
```

### Task 3: Project compact routing settings into Fenix round preparation

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/shared/payload_context.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/prompts/routing_summary.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/build_round_instructions.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/shared/payload_context_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/requests/prepare_round_test.rb`

**Step 1: Write failing tests for compact routing context**

Cover:

- `workspace_agent_context.settings_payload` preserves the frozen mount payload
- only enabled specialist keys appear in the routing summary
- routing summary renders `delegation_mode`, default specialist key, and
  specialist usage metadata

**Step 2: Implement local routing summary construction**

Build a service that:

- reads enabled keys from `workspace_agent_context.settings_payload`
- looks up local specialist metadata by key
- constructs a short deterministic summary for the prompt

**Step 3: Update `BuildRoundInstructions`**

Add the routing summary to the system prompt in a stable section without
copying the full local catalog into the request payload.

**Step 4: Run focused Fenix tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/rails test test/services/shared/payload_context_test.rb test/services/requests/prepare_round_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/shared/payload_context.rb \
  /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/prompts/routing_summary.rb \
  /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/build_round_instructions.rb \
  /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/shared/payload_context_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/requests/prepare_round_test.rb
git commit -m "feat: add fenix routing summary for specialist profiles"
```

### Task 4: Add `WorkspaceAgent.settings_payload` and app-surface support in CoreMatrix

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/workspace_agent.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/app_api/workspaces/workspace_agents_controller.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/app_surface/presenters/workspace_agent_presenter.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/app_surface/presenters/workspace_presenter.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/app_api/base_controller.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/workflows/resolve_model_selector.rb`
- Modify one owning migration under `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/` that creates `workspace_agents`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/workspace_agent_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/app_api/workspaces/workspace_agents_controller_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/app_api/workspaces_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/app_surface/presenters/workspace_agent_presenter_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/app_surface/presenters/workspace_presenter_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/runtime_capabilities/compose_for_turn_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/workflows/resolve_model_selector_test.rb`

**Step 1: Write failing CoreMatrix tests for `settings_payload`**

Cover:

- supported keys normalize into a stable hash
- blank/absent values collapse cleanly
- unsupported keys are rejected
- app create/update/read surfaces expose only public ids and compact JSON
- workspace list fan-out remains preload-safe
- mounted interactive turns use only explicit model-selector preferences from
  settings, without CoreMatrix inferring selectors from profile keys
- explicit selectors/candidates remain authoritative over the mount override
- implicit mounted interactive turns fall back cleanly when the mounted
  model-selector preference is unavailable

**Step 2: Implement `WorkspaceAgent.settings_payload`**

Add:

- schema column through the owning destructive migration
- model normalization and validation
- controller strong-parameter handling
- presenter output
- mount-aware overlay logic only for generic model-selector preferences, without
  overriding explicit selector/candidate choices

Keep the supported schema narrow to the documented keys only.

**Step 3: Rebuild the CoreMatrix schema**

Run from project root:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
rails db:drop && rm db/schema.rb && rails db:create && rails db:migrate && rails db:reset
```

Expected: `db/schema.rb` regenerated with the new `workspace_agents` column.

**Step 4: Run focused CoreMatrix tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/models/workspace_agent_test.rb \
  test/requests/app_api/workspaces/workspace_agents_controller_test.rb \
  test/requests/app_api/workspaces_test.rb \
  test/services/app_surface/presenters/workspace_agent_presenter_test.rb \
  test/services/app_surface/presenters/workspace_presenter_test.rb \
  test/services/runtime_capabilities/compose_for_turn_test.rb \
  test/services/workflows/resolve_model_selector_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/workspace_agent.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/app_api/workspaces/workspace_agents_controller.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/app_surface/presenters/workspace_agent_presenter.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/app_surface/presenters/workspace_presenter.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/app_api/base_controller.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/runtime_capabilities/compose_visible_tool_catalog.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/workflows/resolve_model_selector.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/schema.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/workspace_agent_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/app_api/workspaces/workspace_agents_controller_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/app_api/workspaces_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/app_surface/presenters \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/runtime_capabilities/compose_for_turn_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/workflows/resolve_model_selector_test.rb
git commit -m "feat: add workspace agent profile settings"
```

### Task 5: Freeze raw agent settings into execution snapshots and mailbox reconstruction

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/execution_contract.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/workflows/build_execution_snapshot.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/turn_execution_snapshot.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/agent_control_mailbox_item.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/provider_execution/prepare_agent_round.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/create_agent_request.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260326113000_add_agent_control_contract.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/schema.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/execution_contract_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/workflows/build_execution_snapshot_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/turn_execution_snapshot_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/provider_execution/prepare_agent_round_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/agent_control_mailbox_item_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/create_agent_request_test.rb`

**Step 1: Write failing tests for `workspace_agent_context.settings_payload`**

Cover:

- snapshot projection includes the raw nested settings payload
- queued and reconstructed mailbox payloads reproduce the same shape
- changing mount settings after snapshot creation does not mutate frozen prior
  turns

**Step 2: Implement compact profile-settings projection**

Freeze only the documented settings subset inside `workspace_agent_context`.
Do not copy profile catalog metadata or prompt fragments into CoreMatrix.
Use a deduplicated `JsonDocument` reference on `ExecutionContract`, mirroring the
existing frozen `workspace_agent_global_instructions_document` pattern.

**Step 3: Run focused CoreMatrix tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/workflows/build_execution_snapshot_test.rb \
  test/models/execution_contract_test.rb \
  test/models/turn_execution_snapshot_test.rb \
  test/services/provider_execution/prepare_agent_round_test.rb \
  test/models/agent_control_mailbox_item_test.rb \
  test/services/agent_control/create_agent_request_test.rb
```

Expected: PASS.

**Step 4: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/workflows/build_execution_snapshot.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/execution_contract.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/turn_execution_snapshot.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/agent_control_mailbox_item.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/provider_execution/prepare_agent_round.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/create_agent_request.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260326113000_add_agent_control_contract.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/schema.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/execution_contract_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/workflows/build_execution_snapshot_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/turn_execution_snapshot_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/provider_execution/prepare_agent_round_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/agent_control_mailbox_item_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/create_agent_request_test.rb
git commit -m "feat: freeze workspace agent profile settings"
```

### Task 6: Extend subagent spawning with resolved selector hints and policy enforcement

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/runtime_capabilities/compose_effective_tool_catalog.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/runtime_capabilities/compose_visible_tool_catalog.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/provider_execution/execute_core_matrix_tool.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/subagent_connection.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/subagent_connections/spawn.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/workflows/build_execution_snapshot.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/turn_execution_snapshot.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260324090038_create_subagent_connections.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/schema.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/runtime_capabilities/preview_for_conversation_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/subagent_connection_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/subagent_connections/spawn_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/workflows/build_execution_snapshot_test.rb`

**Step 1: Write failing tests for selector-hint-aware spawning**

Cover:

- `subagent_spawn` advertises optional `model_selector_hint`
- `subagent_spawn` treats `profile_key` as an optional opaque agent-owned label
- child `delegation_package` and frozen execution state preserve the resolved
  selector hint when present
- persisted `SubagentConnection` rows keep the resolved selector hint as a
  stable fact for later export/review surfaces

**Step 2: Implement spawn-time resolution**

Add:

- optional `model_selector_hint` argument plumbing
- persistence of resolved profile key plus selector hint in child task payload,
  `SubagentConnection`, and child execution-visible snapshot state

Keep the new field optional and fallback-safe.

**Step 3: Run focused CoreMatrix tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/runtime_capabilities/preview_for_conversation_test.rb \
  test/services/subagent_connections/spawn_test.rb \
  test/services/workflows/build_execution_snapshot_test.rb
```

Expected: PASS.

**Step 4: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/runtime_capabilities/compose_effective_tool_catalog.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/runtime_capabilities/compose_visible_tool_catalog.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/provider_execution/execute_core_matrix_tool.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/subagent_connection.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/subagent_connections/spawn.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/workflows/build_execution_snapshot.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/turn_execution_snapshot.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260324090038_create_subagent_connections.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/schema.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/runtime_capabilities/preview_for_conversation_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/subagent_connection_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/subagent_connections/spawn_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/workflows/build_execution_snapshot_test.rb
git commit -m "feat: carry specialist selector hints through subagent spawn"
```

### Task 7: Add specialist-aware export surfaces and Mermaid workflow review output

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversation_exports/build_conversation_payload.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversation_debug_exports/build_payload.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversation_exports/build_conversation_payload_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversation_debug_exports/build_payload_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/capstone_review_artifacts.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb`
- Add a new generated review artifact contract for `review/workflow-mermaid.md`

**Step 1: Write failing export/review tests**

Cover:

- ordinary `conversation export` includes a compact `delegation_summary`
- `conversation debug export` includes `profile_key` and
  `resolved_model_selector_hint` when present
- acceptance review generation emits `review/workflow-mermaid.md`
- Mermaid output labels subagent spawn nodes with the selected
  profile key

**Step 2: Implement export payload changes**

Update export builders so:

- user-facing bundles include a compact specialist/subagent summary
- debug bundles keep the richer subagent trace shape
- no prompt/catalog content leaks into either export surface

**Step 3: Implement review Mermaid generation**

Generate a review artifact derived from existing workflow/debug evidence:

- one markdown file at `review/workflow-mermaid.md`
- fenced Mermaid graph
- short legend for node/state labeling
- visible spawn, wait, and barrier states when present

Do not make the Mermaid file a new canonical data source.

**Step 4: Run focused tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/conversation_exports/build_conversation_payload_test.rb \
  test/services/conversation_debug_exports/build_payload_test.rb
```

Then run the documented acceptance command that regenerates the capstone review
artifacts:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
ACTIVE_ACCEPTANCE_ENABLE_2048_CAPSTONE=1 bash acceptance/bin/run_active_suite.sh
```

Verify `review/workflow-mermaid.md` exists in the generated capstone artifact
directory and renders the expected specialist-labeled graph.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversation_exports/build_conversation_payload.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversation_debug_exports/build_payload.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversation_exports/build_conversation_payload_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversation_debug_exports/build_payload_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/capstone_review_artifacts.rb \
  /Users/jasl/Workspaces/Ruby/cybros/acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb
git commit -m "feat: export specialist summaries and workflow mermaid review"
```

### Task 8: Update docs, manifests, and run full verification

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/README.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/integration/runtime_manifest_test.rb`
- Modify any Fenix runtime manifest builder files needed under `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/runtime/manifest/`
- Modify any CoreMatrix docs or fixtures that expose `workspace_agent_context`

**Step 1: Update manifest/readme coverage**

Ensure the Fenix manifest and documentation describe:

- profile catalog ownership
- preserved external keys
- compact delegation settings over the wire

**Step 2: Run the documented project suites**

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

If the implementation touches acceptance-critical turn/bootstrap/runtime loop
behavior, finish with:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
ACTIVE_ACCEPTANCE_ENABLE_2048_CAPSTONE=1 bash acceptance/bin/run_active_suite.sh
```

**Step 3: Perform final audit**

Verify:

- CoreMatrix tables store only compact profile settings and frozen scalar facts
- no prompt fragment or local catalog content is persisted in CoreMatrix
- child delegation records preserve resolved profile key and selector hint

**Step 4: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/README.md \
  /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/runtime/manifest \
  /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/integration/runtime_manifest_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/plans
git commit -m "docs: finalize workspace agent profile catalog rollout"
```
