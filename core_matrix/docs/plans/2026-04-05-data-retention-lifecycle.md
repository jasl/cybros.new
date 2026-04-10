# Data Retention And Lifecycle Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make data lifecycle semantics explicit in `core_matrix` so business truth, shared documents, diagnostics, observation artifacts, and usage history each have safe retention behavior.

**Architecture:** Add static lifecycle declarations to key models, harden read paths so derived or ephemeral rows can disappear safely, and document the boundary between bounded raw usage history and retained rollups. Do not add cleanup jobs yet; prepare the system so cleanup can be introduced safely later.

**Tech Stack:** Rails 8.2, PostgreSQL, Active Record, Minitest

---

### Task 1: Add lifecycle declarations to the core models

**Files:**
- Create: `core_matrix/app/models/concerns/data_lifecycle.rb`
- Modify: `core_matrix/app/models/conversation.rb`
- Modify: `core_matrix/app/models/message.rb`
- Modify: `core_matrix/app/models/conversation_import.rb`
- Modify: `core_matrix/app/models/conversation_summary_segment.rb`
- Modify: `core_matrix/app/models/conversation_event.rb`
- Modify: `core_matrix/app/models/workflow_node_event.rb`
- Modify: `core_matrix/app/models/usage_event.rb`
- Modify: `core_matrix/app/models/usage_rollup.rb`
- Modify: `core_matrix/app/models/json_document.rb`
- Modify: `core_matrix/app/models/conversation_diagnostics_snapshot.rb`
- Modify: `core_matrix/app/models/turn_diagnostics_snapshot.rb`
- Modify: `core_matrix/app/models/conversation_observation_session.rb`
- Modify: `core_matrix/app/models/conversation_observation_frame.rb`
- Modify: `core_matrix/app/models/conversation_observation_message.rb`
- Modify: `core_matrix/app/models/conversation_export_request.rb`
- Modify: `core_matrix/app/models/conversation_debug_export_request.rb`

**Step 1: Write the failing tests**

- Add model tests that assert each representative model exposes the expected
  lifecycle class symbol.

**Step 2: Run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails test test/models
```

Expected: failures for missing lifecycle declarations.

**Step 3: Add `DataLifecycle` concern**

- Define supported lifecycle classes:
  - `owner_bound`
  - `reference_owned`
  - `shared_frozen_contract`
  - `recomputable`
  - `ephemeral_observability`
  - `bounded_audit`
  - `retained_aggregate`
- Add a class macro such as `data_lifecycle_class! :owner_bound`
- Expose `self.data_lifecycle_class`

**Step 4: Apply declarations to the listed models**

- Use `kind` if any new categorical naming is needed; do not introduce `type`
  unless STI is actually required.

**Step 5: Re-run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails test test/models
```

Expected: the new lifecycle declaration tests pass.

**Step 6: Commit**

```bash
git add core_matrix/app/models/concerns/data_lifecycle.rb core_matrix/app/models
git commit -m "Declare data lifecycle classes"
```

### Task 2: Harden diagnostics reads against missing snapshots

**Files:**
- Modify: `core_matrix/app/controllers/app_api/conversation_diagnostics_controller.rb`
- Modify: `core_matrix/app/services/conversation_diagnostics/recompute_conversation_snapshot.rb`
- Modify: `core_matrix/app/services/conversation_diagnostics/recompute_turn_snapshot.rb`
- Test: `core_matrix/test/requests/app_api/conversation_diagnostics_test.rb`
- Test: `core_matrix/test/services/conversation_diagnostics/recompute_conversation_snapshot_test.rb`
- Test: `core_matrix/test/services/conversation_diagnostics/recompute_turn_snapshot_test.rb`

**Step 1: Write the failing tests**

- Delete existing diagnostics snapshots in test setup.
- Assert the controller and recompute services still return valid results.

**Step 2: Run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails test test/requests/app_api/conversation_diagnostics_test.rb test/services/conversation_diagnostics/recompute_conversation_snapshot_test.rb test/services/conversation_diagnostics/recompute_turn_snapshot_test.rb
```

Expected: failures if any path assumes the snapshots already exist.

**Step 3: Implement the missing-data behavior**

- Ensure diagnostics endpoints always recompute or recreate snapshots on demand.
- Avoid any dependency on stale preexisting derived rows.

**Step 4: Re-run the targeted tests**

Run the same command from Step 2.

Expected: PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/controllers/app_api/conversation_diagnostics_controller.rb core_matrix/app/services/conversation_diagnostics core_matrix/test/requests/app_api/conversation_diagnostics_test.rb core_matrix/test/services/conversation_diagnostics
git commit -m "Allow diagnostics snapshots to be recomputed on demand"
```

### Task 3: Harden observation reads against expired or missing ephemeral rows

**Files:**
- Modify: `core_matrix/app/services/embedded_agents/conversation_observation/create_session.rb`
- Modify: `core_matrix/app/services/embedded_agents/conversation_observation/append_message.rb`
- Modify: `core_matrix/app/controllers/app_api/conversation_observation_sessions_controller.rb`
- Modify: `core_matrix/app/controllers/app_api/conversation_observation_messages_controller.rb`
- Test: `core_matrix/test/requests/app_api/conversation_observation_sessions_test.rb`
- Test: `core_matrix/test/requests/app_api/conversation_observation_messages_test.rb`
- Test: `core_matrix/test/services/embedded_agents/conversation_observation/create_session_test.rb`
- Test: `core_matrix/test/services/embedded_agents/conversation_observation/append_message_test.rb`

**Step 1: Write the failing tests**

- Simulate missing session rows, missing frame rows, or closed sessions.
- Assert APIs respond with not found / closed / unavailable rather than leaking
  internal exceptions.

**Step 2: Run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails test test/requests/app_api/conversation_observation_sessions_test.rb test/requests/app_api/conversation_observation_messages_test.rb test/services/embedded_agents/conversation_observation/create_session_test.rb test/services/embedded_agents/conversation_observation/append_message_test.rb
```

Expected: failures where the current behavior is not explicit enough.

**Step 3: Implement missing-data and expired-data behavior**

- Distinguish between target conversation availability and observation session
  availability.
- Keep target conversation reads independent from observation history.

**Step 4: Re-run the targeted tests**

Run the same command from Step 2.

Expected: PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/embedded_agents/conversation_observation core_matrix/app/controllers/app_api/conversation_observation_sessions_controller.rb core_matrix/app/controllers/app_api/conversation_observation_messages_controller.rb core_matrix/test/requests/app_api/conversation_observation_sessions_test.rb core_matrix/test/requests/app_api/conversation_observation_messages_test.rb core_matrix/test/services/embedded_agents/conversation_observation
git commit -m "Define observation missing-data behavior"
```

### Task 4: Harden export and debug export artifact expiration semantics

**Files:**
- Modify: `core_matrix/app/models/conversation_export_request.rb`
- Modify: `core_matrix/app/models/conversation_debug_export_request.rb`
- Modify: `core_matrix/app/controllers/app_api/conversation_export_requests_controller.rb`
- Modify: `core_matrix/app/controllers/app_api/conversation_debug_export_requests_controller.rb`
- Test: `core_matrix/test/requests/app_api/conversation_export_requests_test.rb`
- Test: `core_matrix/test/requests/app_api/conversation_debug_export_requests_test.rb`

**Step 1: Write the failing tests**

- Simulate succeeded request rows whose `bundle_file` has been removed.
- Assert the API reports expired or unavailable, not a 500.

**Step 2: Run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails test test/requests/app_api/conversation_export_requests_test.rb test/requests/app_api/conversation_debug_export_requests_test.rb
```

Expected: failures if the current API assumes the file always exists.

**Step 3: Implement explicit expired-artifact semantics**

- Treat missing or expired bundle files as expected lifecycle states.
- Keep request rows useful as audit breadcrumbs without requiring the artifact
  to remain forever.

**Step 4: Re-run the targeted tests**

Run the same command from Step 2.

Expected: PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/models/conversation_export_request.rb core_matrix/app/models/conversation_debug_export_request.rb core_matrix/app/controllers/app_api/conversation_export_requests_controller.rb core_matrix/app/controllers/app_api/conversation_debug_export_requests_controller.rb core_matrix/test/requests/app_api/conversation_export_requests_test.rb core_matrix/test/requests/app_api/conversation_debug_export_requests_test.rb
git commit -m "Handle expired export artifacts safely"
```

### Task 5: Clarify usage retention semantics without adding cleanup jobs

**Files:**
- Modify: `core_matrix/app/models/usage_event.rb`
- Modify: `core_matrix/app/models/usage_rollup.rb`
- Modify: `core_matrix/app/queries/provider_usage/window_usage_query.rb`
- Modify: `core_matrix/app/services/provider_usage/project_rollups.rb`
- Test: `core_matrix/test/models/usage_event_test.rb`
- Test: `core_matrix/test/models/usage_rollup_test.rb`
- Test: `core_matrix/test/queries/provider_usage/window_usage_query_test.rb`

**Step 1: Write the failing tests**

- Assert `UsageEvent` and `UsageRollup` expose different lifecycle classes.
- Assert the rollup query remains valid even when older raw event rows are not
  part of the test setup.

**Step 2: Run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails test test/models/usage_event_test.rb test/models/usage_rollup_test.rb test/queries/provider_usage/window_usage_query_test.rb
```

Expected: failures until lifecycle semantics are explicit.

**Step 3: Implement the retention semantics**

- Mark `UsageEvent` as `bounded_audit`
- Mark `UsageRollup` as `retained_aggregate`
- Keep provider usage code within the provider usage domain; do not generalize
  it into a global rollup framework

**Step 4: Re-run the targeted tests**

Run the same command from Step 2.

Expected: PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/models/usage_event.rb core_matrix/app/models/usage_rollup.rb core_matrix/app/queries/provider_usage/window_usage_query.rb core_matrix/app/services/provider_usage/project_rollups.rb core_matrix/test/models/usage_event_test.rb core_matrix/test/models/usage_rollup_test.rb core_matrix/test/queries/provider_usage/window_usage_query_test.rb
git commit -m "Define usage event and rollup retention classes"
```

### Task 6: Prepare purge planning for future derived-data cleanup

**Files:**
- Modify: `core_matrix/app/services/conversations/purge_plan.rb`
- Test: `core_matrix/test/services/conversations/purge_plan_test.rb`
- Test: `core_matrix/test/services/conversations/purge_deleted_test.rb`

**Step 1: Write the failing tests**

- Add a test conversation with diagnostics, observation rows, and export
  request rows.
- Assert purge either explicitly removes or explicitly tolerates those rows
  without foreign-key failures.

**Step 2: Run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails test test/services/conversations/purge_plan_test.rb test/services/conversations/purge_deleted_test.rb
```

Expected: failures if purge currently leaves lifecycle-owned derived rows behind.

**Step 3: Implement explicit derived-row handling**

- Teach the purge plan to recognize lifecycle-owned derived rows instead of
  leaving them implicit.
- Keep canonical owner deletion semantics unchanged.

**Step 4: Re-run the targeted tests**

Run the same command from Step 2.

Expected: PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/conversations/purge_plan.rb core_matrix/test/services/conversations/purge_plan_test.rb core_matrix/test/services/conversations/purge_deleted_test.rb
git commit -m "Make purge aware of derived lifecycle rows"
```

### Task 7: Document the lifecycle policy in behavior docs

**Files:**
- Create: `core_matrix/docs/behavior/data-retention-and-lifecycle-classes.md`
- Modify: `core_matrix/docs/behavior/provider-usage-events-and-rollups.md`
- Modify: `core_matrix/docs/behavior/conversation-observation-and-supervisor-status.md`
- Modify: `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`

**Step 1: Write the docs**

- explain the lifecycle classes
- explain `kind` vs `type`
- explain that recurring cleanup runs through `DataRetention::RunMaintenanceJob`
  and the recurring schedule in `config/recurring.yml`
- explain `UsageEvent` vs `UsageRollup` retention roles
- explain observation/export expiration semantics

**Step 2: Review the docs for consistency with the model declarations**

- avoid introducing lifecycle promises that the code does not implement

**Step 3: Commit**

```bash
git add core_matrix/docs/behavior/data-retention-and-lifecycle-classes.md core_matrix/docs/behavior/provider-usage-events-and-rollups.md core_matrix/docs/behavior/conversation-observation-and-supervisor-status.md core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md
git commit -m "Document lifecycle and retention classes"
```

### Task 8: Run full verification

**Files:**
- Inspect: affected test output only

**Step 1: Run focused suites from Tasks 1-6**

Run all targeted commands from the earlier tasks.

**Step 2: Run full verification**

Run:

```bash
cd core_matrix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails db:test:prepare test
bin/rails db:test:prepare test:system
bin/ci
```

Expected: all checks pass.

**Step 3: Commit any final fixes**

```bash
git add -A
git commit -m "Finish lifecycle and retention hardening"
```
