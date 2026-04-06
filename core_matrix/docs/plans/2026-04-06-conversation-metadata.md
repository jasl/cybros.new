# Conversation Metadata Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make conversation `title` and `summary` first-class metadata on `Conversation`, bootstrap `title` locally on first user input, allow explicit user and agent updates with field-level locking, and remove the old workflow-intent title path.

**Architecture:** Store canonical metadata state directly on `conversations`, and keep all metadata mutation rules in `Conversations::Metadata::*` application services. Bootstrap title generation stays local and synchronous in the user-turn path, while model-backed regeneration and supervision summary generation share one installation-scoped CoreMatrix provider gateway instead of each business service constructing provider clients directly.

**Tech Stack:** Rails 8.2, Active Record/Postgres, public-id-only app/tool boundaries, Minitest, ActionDispatch request tests

---

## Destructive Assumptions

- This plan intentionally does **not** preserve compatibility with
  `conversation_title_update` as a supported workflow metadata mutation path.
- Edit the baseline conversation migration in place instead of adding a later
  additive migration.
- Regenerate `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/schema.rb`
  from scratch after migration edits.
- Reset the local database from
  `/Users/jasl/Workspaces/Ruby/cybros/core_matrix` with:

```bash
rails db:drop && rm db/schema.rb && rails db:create && rails db:migrate && rails db:reset
```

## Task 1: Inline Metadata State Into `Conversation`

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260324090019_create_conversations.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/conversation.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/schema.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/conversation_test.rb`

**Step 1: Write the failing model tests**

Add tests that assert:

- `Conversation` exposes `title`, `summary`, `title_source`, `summary_source`,
  `title_lock_state`, `summary_lock_state`, `title_updated_at`,
  `summary_updated_at`
- valid sources are `none`, `bootstrap`, `generated`, `agent`, `user`
- valid lock states are `unlocked`, `user_locked`
- helper predicates such as `title_locked?` and `summary_locked?` work

**Step 2: Run the focused model test**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/models/conversation_test.rb
```

Expected: FAIL because the new columns and helpers do not exist yet.

**Step 3: Update the baseline conversation migration**

Modify `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260324090019_create_conversations.rb`
to add:

- `title`
- `summary`
- `title_source`
- `summary_source`
- `title_lock_state`
- `summary_lock_state`
- `title_updated_at`
- `summary_updated_at`

Add check constraints for the source and lock-state enums.

**Step 4: Update the `Conversation` model**

Add:

- enum validation support for the new source and lock-state fields
- field-level helper predicates
- small metadata helper methods only if needed by later services

Do not add metadata mutation callbacks here.

**Step 5: Rebuild the schema**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && rails db:drop && rm db/schema.rb && rails db:create && rails db:migrate && rails db:reset
```

Expected: migration succeeds and `db/schema.rb` contains the new columns and
constraints.

**Step 6: Re-run the focused model test**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/models/conversation_test.rb
```

Expected: PASS.

**Step 7: Commit**

```bash
git -C /Users/jasl/Workspaces/Ruby/cybros/core_matrix add db/migrate/20260324090019_create_conversations.rb app/models/conversation.rb db/schema.rb test/models/conversation_test.rb
git -C /Users/jasl/Workspaces/Ruby/cybros/core_matrix commit -m "feat: inline conversation metadata state"
```

## Task 2: Bootstrap Title On First User Message

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/metadata/bootstrap_title.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/turns/start_user_turn.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversations/metadata/bootstrap_title_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/turns/start_user_turn_test.rb`

**Step 1: Write the failing service and integration tests**

Cover:

- first user message sets `conversation.title`
- later user turns do not replace an existing title
- blank/whitespace-only input falls back to a neutral untitled result
- locked titles are not overwritten
- `Turns::StartUserTurn` is the path that actually triggers bootstrap

**Step 2: Run the focused tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/conversations/metadata/bootstrap_title_test.rb test/services/turns/start_user_turn_test.rb
```

Expected: FAIL because the service and hook do not exist.

**Step 3: Implement `Conversations::Metadata::BootstrapTitle`**

Add a small service with a signature like:

```ruby
Conversations::Metadata::BootstrapTitle.call(conversation:, message:, occurred_at: Time.current)
```

Rules:

- only act when `message.user?`
- only act when the conversation title is blank and unlocked
- normalize whitespace
- take the first sentence or first line
- truncate to a stable UI-safe length
- set `title_source = "bootstrap"` and `title_updated_at`

**Step 4: Hook the bootstrap into `Turns::StartUserTurn`**

After `UserMessage.create!` and before returning the turn, call the bootstrap
service with the newly created input message.

Keep the change inside the same locked conversation mutation block.

**Step 5: Re-run the focused tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/conversations/metadata/bootstrap_title_test.rb test/services/turns/start_user_turn_test.rb
```

Expected: PASS.

**Step 6: Commit**

```bash
git -C /Users/jasl/Workspaces/Ruby/cybros/core_matrix add app/services/conversations/metadata/bootstrap_title.rb app/services/turns/start_user_turn.rb test/services/conversations/metadata/bootstrap_title_test.rb test/services/turns/start_user_turn_test.rb
git -C /Users/jasl/Workspaces/Ruby/cybros/core_matrix commit -m "feat: bootstrap conversation titles locally"
```

## Task 3: Add Canonical Metadata Mutation Services And App API

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/metadata/user_edit.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/metadata/regenerate.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/metadata/agent_update.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/app_api/conversations/metadata_controller.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/config/routes.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversations/metadata/user_edit_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversations/metadata/regenerate_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversations/metadata/agent_update_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/app_api/conversations/metadata_test.rb`

**Step 1: Write the failing service tests**

Cover:

- user edit sets `source = "user"` and `lock_state = "user_locked"`
- editing `title` does not lock `summary`, and vice versa
- agent update is rejected for locked fields
- regenerate clears only the targeted field lock before generation

**Step 2: Write the failing request tests**

Add request coverage for:

- `GET /app_api/conversations/:conversation_id/metadata`
- `PATCH /app_api/conversations/:conversation_id/metadata`
- `POST /app_api/conversations/:conversation_id/metadata/regenerate`

Use public ids only. Assert bigint ids return `404`.

**Step 3: Run the focused service/request tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/conversations/metadata/user_edit_test.rb test/services/conversations/metadata/regenerate_test.rb test/services/conversations/metadata/agent_update_test.rb test/requests/app_api/conversations/metadata_test.rb
```

Expected: FAIL because the services, controller, and routes do not exist.

**Step 4: Implement the mutation services**

Implement three small application services:

- `UserEdit`
- `Regenerate`
- `AgentUpdate`

Rules:

- user edits write values directly and lock edited fields
- regenerate only unlocks the requested field
- agent update must reject locked fields and never write bigint ids or runtime
  internals into content

Keep all persistence inside these services rather than in controllers or tool
runner code.

**Step 5: Add the app API controller and routes**

Create a nested controller under `AppAPI::Conversations` and expose:

- `show`
- `update`
- `regenerate`

Return a single canonical metadata payload shape:

- `conversation_id`
- `title`
- `summary`
- `title_source`
- `summary_source`
- `title_locked`
- `summary_locked`

**Step 6: Re-run the focused tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/conversations/metadata/user_edit_test.rb test/services/conversations/metadata/regenerate_test.rb test/services/conversations/metadata/agent_update_test.rb test/requests/app_api/conversations/metadata_test.rb
```

Expected: PASS.

**Step 7: Commit**

```bash
git -C /Users/jasl/Workspaces/Ruby/cybros/core_matrix add app/services/conversations/metadata/user_edit.rb app/services/conversations/metadata/regenerate.rb app/services/conversations/metadata/agent_update.rb app/controllers/app_api/conversations/metadata_controller.rb config/routes.rb test/services/conversations/metadata/user_edit_test.rb test/services/conversations/metadata/regenerate_test.rb test/services/conversations/metadata/agent_update_test.rb test/requests/app_api/conversations/metadata_test.rb
git -C /Users/jasl/Workspaces/Ruby/cybros/core_matrix commit -m "feat: add canonical conversation metadata mutations"
```

## Task 4: Add A Shared Provider Gateway For Product-Owned Prompt Generation

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/provider_gateway/dispatch_text.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/metadata/generate_field.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/embedded_agents/conversation_supervision/responders/summary_model.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/config/llm_catalog.yml`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/provider_gateway/dispatch_text_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversations/metadata/generate_field_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/embedded_agents/conversation_supervision/responders/summary_model_test.rb`

**Step 1: Write the failing gateway and generation tests**

Cover:

- selector resolution through `ProviderCatalog::EffectiveCatalog`
- merged request settings through `ProviderRequestSettingsSchema`
- lease/governor/retry path usage
- `GenerateField` choosing `role:conversation_title` or
  `role:conversation_summary`
- `summary_model` routing through the gateway instead of constructing provider
  clients directly

**Step 2: Run the focused tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/provider_gateway/dispatch_text_test.rb test/services/conversations/metadata/generate_field_test.rb test/services/embedded_agents/conversation_supervision/responders/summary_model_test.rb
```

Expected: FAIL because the gateway does not exist and `summary_model` still
builds clients directly.

**Step 3: Implement `ProviderGateway::DispatchText`**

Create one installation-scoped gateway that:

- resolves selectors
- builds a `ProviderRequestContext`
- acquires the same provider lease/governor protections as workflow dispatch
- routes by wire API
- returns normalized text, usage, and provider request id

Do not require `workflow_run`.

**Step 4: Implement `Conversations::Metadata::GenerateField`**

Generation rules:

- title regeneration uses `role:conversation_title`
- summary regeneration uses `role:conversation_summary`
- initial bootstrap still does not use this service

`Regenerate` from Task 3 should call this service after clearing the field lock.

**Step 5: Refactor supervision `summary_model`**

Remove:

- direct credential lookup in the responder
- direct `SimpleInference::Client` construction
- direct `client.chat` / `client.responses` branching

Replace with a call to `ProviderGateway::DispatchText` using
`role:supervision_summary`.

**Step 6: Update the catalog**

Add or rename selectors so the catalog clearly exposes:

- `conversation_title`
- `conversation_summary`
- `supervision_summary`

**Step 7: Re-run the focused tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/provider_gateway/dispatch_text_test.rb test/services/conversations/metadata/generate_field_test.rb test/services/embedded_agents/conversation_supervision/responders/summary_model_test.rb
```

Expected: PASS.

**Step 8: Commit**

```bash
git -C /Users/jasl/Workspaces/Ruby/cybros/core_matrix add app/services/provider_gateway/dispatch_text.rb app/services/conversations/metadata/generate_field.rb app/services/embedded_agents/conversation_supervision/responders/summary_model.rb config/llm_catalog.yml test/services/provider_gateway/dispatch_text_test.rb test/services/conversations/metadata/generate_field_test.rb test/services/embedded_agents/conversation_supervision/responders/summary_model_test.rb
git -C /Users/jasl/Workspaces/Ruby/cybros/core_matrix commit -m "feat: unify conversation metadata generation dispatch"
```

## Task 5: Replace Agent Title Intent With A CoreMatrix Metadata Tool

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/runtime_capabilities/compose_effective_tool_catalog.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/provider_execution/execute_core_matrix_tool.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/runtime_capabilities/compose_effective_tool_catalog_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/provider_execution/route_tool_call_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/provider_execution/execute_core_matrix_tool_test.rb`

**Step 1: Write the failing tool tests**

Cover:

- the effective tool catalog exposes `conversation_metadata_update`
- tool execution calls `Conversations::Metadata::AgentUpdate`
- locked fields produce structured rejection
- returned payload includes only public ids and accepted field values

**Step 2: Run the focused tool tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/runtime_capabilities/compose_effective_tool_catalog_test.rb test/services/provider_execution/route_tool_call_test.rb test/services/provider_execution/execute_core_matrix_tool_test.rb
```

Expected: FAIL because the tool does not exist yet.

**Step 3: Extend the reserved CoreMatrix tool catalog**

Add `conversation_metadata_update` to
`RuntimeCapabilities::ComposeEffectiveToolCatalog::CORE_MATRIX_TOOL_CATALOG`
with:

- optional `title`
- optional `summary`
- at least one required by validation in the executor/service

**Step 4: Extend `ExecuteCoreMatrixTool`**

Add a branch that:

- resolves the current conversation from `workflow_node`
- calls `Conversations::Metadata::AgentUpdate`
- returns a compact structured result

**Step 5: Re-run the focused tool tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/runtime_capabilities/compose_effective_tool_catalog_test.rb test/services/provider_execution/route_tool_call_test.rb test/services/provider_execution/execute_core_matrix_tool_test.rb
```

Expected: PASS.

**Step 6: Commit**

```bash
git -C /Users/jasl/Workspaces/Ruby/cybros/core_matrix add app/services/runtime_capabilities/compose_effective_tool_catalog.rb app/services/provider_execution/execute_core_matrix_tool.rb test/services/runtime_capabilities/compose_effective_tool_catalog_test.rb test/services/provider_execution/route_tool_call_test.rb test/services/provider_execution/execute_core_matrix_tool_test.rb
git -C /Users/jasl/Workspaces/Ruby/cybros/core_matrix commit -m "feat: expose conversation metadata update as core matrix tool"
```

## Task 6: Remove Old Intent-Shaped Title Assumptions And Export Stored Metadata

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversation_exports/build_conversation_payload.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversation_exports/build_conversation_payload_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversation_debug_exports/build_payload_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/workflows/intent_batch_materialization_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/projections/workflows/projection_test.rb`

**Step 1: Write the failing export/debug cleanup assertions**

Update tests so they expect:

- export payloads contain stored `title`/`summary` metadata instead of derived
  `original_title`
- debug fixtures no longer need `conversation_title_update` nodes to represent
  conversation metadata
- workflow intent materialization tests stop using title updates as the example
  durable mutation

**Step 2: Run the focused cleanup tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/conversation_exports/build_conversation_payload_test.rb test/services/conversation_debug_exports/build_payload_test.rb test/services/workflows/intent_batch_materialization_test.rb test/projections/workflows/projection_test.rb
```

Expected: FAIL because the code still derives `original_title` and several
fixtures still assume title-intent workflow nodes.

**Step 3: Update conversation exports**

Replace:

- `original_title`

With:

- `title`
- `summary`
- `title_source`
- `summary_source`

Read only persisted conversation metadata. Do not infer title from transcript
content.

**Step 4: Remove title-intent examples from tests and fixtures**

Use a different generic intent kind already supported by workflow materialization
tests, or create a neutral test-only durable intent example that does not claim
to mutate conversation metadata.

**Step 5: Re-run the focused cleanup tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/conversation_exports/build_conversation_payload_test.rb test/services/conversation_debug_exports/build_payload_test.rb test/services/workflows/intent_batch_materialization_test.rb test/projections/workflows/projection_test.rb
```

Expected: PASS.

**Step 6: Commit**

```bash
git -C /Users/jasl/Workspaces/Ruby/cybros/core_matrix add app/services/conversation_exports/build_conversation_payload.rb test/services/conversation_exports/build_conversation_payload_test.rb test/services/conversation_debug_exports/build_payload_test.rb test/services/workflows/intent_batch_materialization_test.rb test/projections/workflows/projection_test.rb
git -C /Users/jasl/Workspaces/Ruby/cybros/core_matrix commit -m "refactor: remove workflow title metadata assumptions"
```

## Task 7: Run Destructive Reset And Verification Checkpoints

**Files:**
- Verify only; no new files

**Step 1: Rebuild the development database from scratch**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && rails db:drop && rm db/schema.rb && rails db:create && rails db:migrate && rails db:reset
```

Expected: success with regenerated schema.

**Step 2: Run the focused metadata suites**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/models/conversation_test.rb test/services/conversations/metadata test/services/turns/start_user_turn_test.rb test/services/provider_gateway/dispatch_text_test.rb test/services/embedded_agents/conversation_supervision/responders/summary_model_test.rb test/requests/app_api/conversations/metadata_test.rb test/services/conversation_exports/build_conversation_payload_test.rb
```

Expected: PASS.

**Step 3: Run the broader app verification**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/brakeman --no-pager && bin/bundler-audit && bin/rubocop -f github && bun run lint:js && bin/rails db:test:prepare test
```

Expected: PASS.

**Step 4: Commit the final verification-only checkpoint if needed**

If any code changed during verification fixes:

```bash
git -C /Users/jasl/Workspaces/Ruby/cybros/core_matrix add -A
git -C /Users/jasl/Workspaces/Ruby/cybros/core_matrix commit -m "chore: finish conversation metadata refactor"
```

If no fixes were needed, do not create an extra commit.
