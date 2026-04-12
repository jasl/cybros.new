# Core Matrix Data Structure Optimization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rewrite the pre-launch Core Matrix base schema around `Workspace` and `Conversation`, preserve current product semantics, and land the supporting code, tests, and behavior docs so the system can rebuild cleanly from rewritten migrations.

**Architecture:** Keep current product behavior, but change where truth lives. `Workspace` and `Conversation` become self-describing center resources, runtime and supervision/control tables gain owner/context columns, current-state anchors become explicit `latest_active_*` pointers, and wide hot tables split into header/detail or document-backed layouts. Access stays owner- and agent-usability-bound, but moves from Ruby post-filtering into SQL lookup boundaries and denormalized columns.

**Tech Stack:** Ruby on Rails, Active Record, PostgreSQL, Minitest, `db/schema.rb`, app-surface query/presenter layer, behavior docs under `docs/behavior`.

---

### Task 1: Lock Down Existing Contract Before Rewriting Schema

**Files:**
- Create: `test/services/workspaces/resolve_default_reference_test.rb`
- Modify: `test/queries/workspaces/for_user_query_test.rb`
- Modify: `test/services/app_surface/policies/workspace_access_test.rb`
- Modify: `test/services/app_surface/policies/conversation_access_test.rb`
- Modify: `test/requests/app_api/agents_test.rb`
- Modify: `test/requests/app_api/agent_homes_test.rb`
- Modify: `test/requests/app_api/workspaces_test.rb`
- Modify: `test/requests/app_api/conversations_test.rb`
- Create: `test/services/conversation_control/resolve_target_runtime_test.rb`
- Modify: `test/services/conversation_supervision/build_activity_feed_test.rb`

**Step 1: Write failing contract tests for workspace and conversation visibility**

Add assertions that:
- workspaces disappear when their logical `Agent` becomes unusable
- conversations remain hidden under the same unusable-agent condition
- default workspace access still ignores runtime unavailability

**Step 2: Write failing contract tests for default workspace reference**

Add assertions that:
- the app-facing payload still returns `state: "virtual"` before materialization
- the payload flips to `state: "materialized"` after materialization
- `workspace_id`, `agent_id`, `user_id`, `name`, `privacy`, and `default_execution_runtime_id` remain present with the same public-id semantics

**Step 3: Write failing contract tests for latest-active semantics**

Add assertions that:
- the current feed anchor resolves to the latest active turn, not “the only active turn”
- runtime resolution uses the latest active workflow/turn when multiple active rows exist

**Step 4: Run targeted tests to verify failures**

Run from `/Users/jasl/Workspaces/Ruby/cybros/core_matrix`:

```bash
bin/rails test \
  test/queries/workspaces/for_user_query_test.rb \
  test/services/app_surface/policies/workspace_access_test.rb \
  test/services/app_surface/policies/conversation_access_test.rb \
  test/requests/app_api/agents_test.rb \
  test/requests/app_api/agent_homes_test.rb \
  test/requests/app_api/workspaces_test.rb \
  test/requests/app_api/conversations_test.rb \
  test/services/conversation_control/resolve_target_runtime_test.rb \
  test/services/conversation_supervision/build_activity_feed_test.rb \
  test/services/workspaces/resolve_default_reference_test.rb
```

Expected: failures describing missing resolver, missing latest-active fields, or mismatched access assumptions.

**Step 5: Commit**

```bash
git add test/queries/workspaces/for_user_query_test.rb \
  test/services/app_surface/policies/workspace_access_test.rb \
  test/services/app_surface/policies/conversation_access_test.rb \
  test/requests/app_api/agents_test.rb \
  test/requests/app_api/agent_homes_test.rb \
  test/requests/app_api/workspaces_test.rb \
  test/requests/app_api/conversations_test.rb \
  test/services/conversation_control/resolve_target_runtime_test.rb \
  test/services/conversation_supervision/build_activity_feed_test.rb \
  test/services/workspaces/resolve_default_reference_test.rb
git commit -m "test: lock data-structure rewrite contracts"
```

### Task 2: Rewrite Center Schema Migrations and Rebuild the Database

**Files:**
- Modify: `db/migrate/20260324090006_create_agents.rb`
- Modify: `db/migrate/20260324090007_create_execution_runtimes.rb`
- Modify: `db/migrate/20260324090010_create_agent_versioning_core.rb`
- Modify: `db/migrate/20260324090011_create_user_agent_bindings.rb`
- Modify: `db/migrate/20260324090012_create_workspaces.rb`
- Modify: `db/migrate/20260324090018_create_execution_profile_facts.rb`
- Modify: `db/migrate/20260324090019_create_conversations.rb`
- Modify: `db/migrate/20260324090021_create_turns.rb`
- Modify: `db/migrate/20260324090023_add_turn_message_foreign_keys.rb`
- Modify: `db/migrate/20260324090028_create_workflow_runs.rb`
- Modify: `db/migrate/20260324090029_create_workflow_nodes.rb`
- Modify: `db/migrate/20260324090031_add_wait_state_to_workflow_runs.rb`
- Modify: `db/migrate/20260324090034_create_process_runs.rb`
- Modify: `db/migrate/20260324090035_create_human_interaction_requests.rb`
- Modify: `db/migrate/20260324090038_create_subagent_connections.rb`
- Modify: `db/migrate/20260326100000_extend_workflow_substrate.rb`
- Modify: `db/migrate/20260326113000_add_agent_control_contract.rb`
- Modify: `db/migrate/20260330130000_add_feature_policy_to_conversations_and_work.rb`
- Modify: `db/migrate/20260330143000_add_tool_governance.rb`
- Modify: `db/migrate/20260330174000_add_command_runs.rb`
- Modify: `db/migrate/20260404090000_create_conversation_observation_sessions.rb`
- Modify: `db/migrate/20260404090100_create_conversation_observation_frames.rb`
- Modify: `db/migrate/20260404090200_create_conversation_observation_messages.rb`
- Modify: `db/migrate/20260405093000_create_conversation_supervision_states.rb`
- Modify: `db/migrate/20260405093100_create_conversation_control_requests.rb`
- Modify: `db/migrate/20260405093300_create_agent_task_progress_entries.rb`
- Modify: `db/migrate/20260405093410_create_conversation_supervision_feed_entries.rb`

**Step 1: Rewrite the center-table migrations**

Make the original create migrations produce:
- `agents.current_agent_definition_version_id`
- `execution_runtimes.current_execution_runtime_version_id`
- `workspaces.agent_id`
- workspace-native default uniqueness on `(installation_id, user_id, agent_id)` where `is_default = true`
- `conversations.user_id`
- `conversations.latest_active_turn_id`
- `conversations.latest_turn_id`
- `conversations.latest_active_workflow_run_id`
- `conversations.latest_message_id`
- `conversations.last_activity_at`
- `turns.user_id`, `turns.workspace_id`, `turns.agent_id`

Delete binding-owned default-workspace uniqueness from the schema and replace it with workspace-native uniqueness.
Where a referenced table does not yet exist, add the raw `*_id` column in the
earlier migration and move the foreign key creation into the first later
migration where the target table exists. Convert superseded later
`add_reference`/`change_table` steps into foreign-key-only patches or explicit
no-ops so a fresh rebuild does not try to add the same column twice.
For owner/context columns whose writers are not updated until later tasks, add
the column, index, and foreign key now but keep the column nullable until the
writer task lands. Do not introduce `null: false` requirements that would block
Task 3 through Task 5 before their write paths are rewritten.

**Step 2: Rewrite the runtime/control migrations**

Make the original create migrations also produce owner/context columns for:
- `workflow_runs`
- `workflow_nodes`
- `process_runs`
- `human_interaction_requests`
- `agent_task_runs`
- `subagent_connections`
- `conversation_control_requests`
- `conversation_supervision_states`
- `conversation_supervision_feed_entries`
- `conversation_supervision_sessions`
- `conversation_supervision_messages`
- `conversation_supervision_snapshots`
- `tool_invocations`
- `command_runs`
- `execution_profile_facts`

Use `latest_active_*` naming everywhere. Do not create `active_turn_id` or `active_workflow_run_id`.
If owner/context columns are moved into an earlier create migration, strip the
duplicate column-addition from the later patch migration and leave only the
remaining indexes, foreign keys, or unrelated fields that are still required.
Any new writer-independent invariants may land here, but defer hard nullability
for denormalized owner/context columns until the corresponding creation service
is updated and covered by tests in later tasks.

**Step 3: Add or strengthen schema constraints**

Keep schema-level protection for:
- owner/context alignment
- uniqueness
- lifecycle/deletion shape rules
- latest-active foreign keys
- row-shape pairing

Relax only value-whitelist constraints that the design doc moved to model/service enforcement.

**Step 4: Rebuild the database and regenerate `db/schema.rb`**

Run from `/Users/jasl/Workspaces/Ruby/cybros/core_matrix`:

```bash
rails db:drop && rm db/schema.rb && rails db:create && rails db:migrate
```

Expected:
- database recreates cleanly
- `db/schema.rb` regenerates with rewritten tables and indexes
- no duplicate or orphaned constraints remain from the old shape
- no seeds are required yet; reserve the full `db:reset` pass for the final
  verification task after bootstrap code and docs are aligned

**Step 5: Commit**

```bash
git add db/migrate db/schema.rb
git commit -m "db: rewrite center and runtime schema"
```

### Task 3: Land Workspace-Native Default Workspace Resolution

**Files:**
- Create: `app/services/workspaces/resolve_default_reference.rb`
- Modify: `app/services/workspaces/build_default_reference.rb`
- Modify: `test/services/workspaces/resolve_default_reference_test.rb`
- Modify: `app/models/workspace.rb`
- Modify: `app/services/workspaces/create_default.rb`
- Modify: `app/services/workspaces/materialize_default.rb`
- Modify: `app/services/user_agent_bindings/enable.rb`
- Modify: `app/services/app_surface/queries/agent_home.rb`
- Modify: `app/services/app_surface/queries/workspaces_for_agent.rb`
- Modify: `app/services/workbench/create_conversation_from_agent.rb`
- Modify: `app/controllers/app_api/agents/homes_controller.rb`
- Modify: `app/controllers/app_api/agents/workspaces_controller.rb`
- Modify: `test/services/workspaces/create_default_test.rb`
- Modify: `test/services/workspaces/materialize_default_test.rb`
- Modify: `test/services/user_agent_bindings/enable_test.rb`
- Modify: `test/services/workbench/create_conversation_from_agent_test.rb`
- Modify: `test/requests/app_api/agents_test.rb`

**Step 1: Write the failing resolver implementation test**

The new service should support:

```ruby
Workspaces::ResolveDefaultReference.call(user: user, agent: agent)
```

and return the same value shape currently exposed by `BuildDefaultReference`.

**Step 2: Implement the workspace-native resolver**

Implement `Workspaces::ResolveDefaultReference` so it:
- looks up a default workspace by `(installation_id, user_id, agent_id, is_default: true)`
- returns `state: "materialized"` with the workspace public id when found
- returns `state: "virtual"` without writing a row when absent
- derives the fallback runtime from `agent.default_execution_runtime`

**Step 3: Rewire materialization and conversation creation**

Update:
- `Workspaces::CreateDefault`
- `Workspaces::MaterializeDefault`
- `Workbench::CreateConversationFromAgent`

to accept `user:` and `agent:` as the primary ownership inputs. `UserAgentBinding` may still be created for preference tracking, but it must no longer own default workspace lookup or uniqueness.

**Step 4: Replace binding-backed query usage**

Update `AgentHome` and workspace-list flows to call `ResolveDefaultReference`, not `BuildDefaultReference`. Remove any “virtual binding” shim behavior from hot paths.

**Step 5: Run targeted tests**

```bash
bin/rails test \
  test/services/workspaces/resolve_default_reference_test.rb \
  test/services/workspaces/create_default_test.rb \
  test/services/workspaces/materialize_default_test.rb \
  test/services/user_agent_bindings/enable_test.rb \
  test/services/workbench/create_conversation_from_agent_test.rb \
  test/requests/app_api/agents_test.rb
```

Expected: all default-workspace tests pass without depending on `user_agent_binding_id`.

**Step 6: Commit**

```bash
git add app/models/workspace.rb \
  app/services/workspaces/build_default_reference.rb \
  app/services/workspaces/resolve_default_reference.rb \
  app/services/workspaces/create_default.rb \
  app/services/workspaces/materialize_default.rb \
  app/services/user_agent_bindings/enable.rb \
  app/services/app_surface/queries/agent_home.rb \
  app/services/app_surface/queries/workspaces_for_agent.rb \
  app/services/workbench/create_conversation_from_agent.rb \
  app/controllers/app_api/agents/homes_controller.rb \
  app/controllers/app_api/agents/workspaces_controller.rb \
  test/services/workspaces/resolve_default_reference_test.rb \
  test/services/workspaces/create_default_test.rb \
  test/services/workspaces/materialize_default_test.rb \
  test/services/user_agent_bindings/enable_test.rb \
  test/services/workbench/create_conversation_from_agent_test.rb \
  test/requests/app_api/agents_test.rb
git commit -m "refactor: move default workspace resolution off bindings"
```

### Task 4: Move Access Boundaries Into SQL Without Relaxing Semantics

**Files:**
- Modify: `app/models/agent.rb`
- Modify: `app/models/execution_runtime.rb`
- Modify: `app/models/workspace.rb`
- Modify: `app/models/conversation.rb`
- Modify: `app/controllers/concerns/installation_scoped_lookup.rb`
- Modify: `app/controllers/app_api/base_controller.rb`
- Modify: `app/services/resource_visibility/usability.rb`
- Modify: `app/services/app_surface/policies/agent_visibility.rb`
- Modify: `app/services/app_surface/policies/execution_runtime_access.rb`
- Modify: `app/services/app_surface/policies/workspace_access.rb`
- Modify: `app/services/app_surface/policies/conversation_access.rb`
- Modify: `app/queries/agents/visible_to_user_query.rb`
- Modify: `app/queries/execution_runtimes/visible_to_user_query.rb`
- Modify: `app/queries/workspaces/for_user_query.rb`
- Modify: `app/queries/human_interactions/open_for_user_query.rb`
- Modify: `test/queries/agents/visible_to_user_query_test.rb`
- Modify: `test/queries/execution_runtimes/visible_to_user_query_test.rb`
- Modify: `test/services/app_surface/policies/agent_visibility_test.rb`
- Modify: `test/services/app_surface/policies/execution_runtime_access_test.rb`
- Modify: `test/queries/workspaces/for_user_query_test.rb`
- Modify: `test/services/app_surface/policies/workspace_access_test.rb`
- Modify: `test/services/resource_visibility/usability_test.rb`
- Modify: `test/services/app_surface/policies/conversation_access_test.rb`
- Modify: `test/queries/human_interactions/open_for_user_query_test.rb`
- Modify: `test/requests/app_api/workspaces_test.rb`
- Modify: `test/requests/app_api/conversations_test.rb`

**Step 1: Add accessible scopes on center models**

Add scopes such as:

```ruby
Workspace.accessible_to_user(user)
Conversation.accessible_to_user(user)
```

These scopes must preserve current behavior:
- owner-bound filtering
- retained-only conversation lookup
- agent-usability semantics

**Step 2: Replace Ruby-side filtering**

Remove `.to_a.select { policy }` from hot paths. `Workspaces::ForUserQuery` and app-facing lookup code should return already-filtered relations or arrays loaded from SQL-filtered scopes.

**Step 3: Simplify controller lookup**

Update `InstallationScopedLookup` and `AppAPI::BaseController` so:
- `public_id` lookup and access filtering happen in the same boundary query when practical
- `ResourceVisibility::Usability` no longer owns production hot-path filtering

Keep `ResourceVisibility::Usability` only as a low-frequency assertion helper if still useful.

**Step 4: Run targeted tests**

```bash
bin/rails test \
  test/queries/agents/visible_to_user_query_test.rb \
  test/queries/execution_runtimes/visible_to_user_query_test.rb \
  test/services/app_surface/policies/agent_visibility_test.rb \
  test/services/app_surface/policies/execution_runtime_access_test.rb \
  test/queries/workspaces/for_user_query_test.rb \
  test/services/app_surface/policies/workspace_access_test.rb \
  test/services/resource_visibility/usability_test.rb \
  test/services/app_surface/policies/conversation_access_test.rb \
  test/queries/human_interactions/open_for_user_query_test.rb \
  test/requests/app_api/workspaces_test.rb \
  test/requests/app_api/conversations_test.rb
```

Expected: no visibility regression; inaccessible resources still 404.

**Step 5: Commit**

```bash
git add app/models/agent.rb \
  app/models/execution_runtime.rb \
  app/models/workspace.rb \
  app/models/conversation.rb \
  app/controllers/concerns/installation_scoped_lookup.rb \
  app/controllers/app_api/base_controller.rb \
  app/services/resource_visibility/usability.rb \
  app/services/app_surface/policies/agent_visibility.rb \
  app/services/app_surface/policies/execution_runtime_access.rb \
  app/services/app_surface/policies/workspace_access.rb \
  app/services/app_surface/policies/conversation_access.rb \
  app/queries/agents/visible_to_user_query.rb \
  app/queries/execution_runtimes/visible_to_user_query.rb \
  app/queries/workspaces/for_user_query.rb \
  app/queries/human_interactions/open_for_user_query.rb \
  test/queries/agents/visible_to_user_query_test.rb \
  test/queries/execution_runtimes/visible_to_user_query_test.rb \
  test/services/app_surface/policies/agent_visibility_test.rb \
  test/services/app_surface/policies/execution_runtime_access_test.rb \
  test/queries/workspaces/for_user_query_test.rb \
  test/services/app_surface/policies/workspace_access_test.rb \
  test/services/resource_visibility/usability_test.rb \
  test/services/app_surface/policies/conversation_access_test.rb \
  test/queries/human_interactions/open_for_user_query_test.rb \
  test/requests/app_api/workspaces_test.rb \
  test/requests/app_api/conversations_test.rb
git commit -m "refactor: move app access checks into sql boundaries"
```

### Task 5: Land Conversation Latest-Active Anchors and Their Writers

**Files:**
- Modify: `app/models/conversation.rb`
- Modify: `app/models/message.rb`
- Modify: `app/models/turn.rb`
- Modify: `app/models/workflow_run.rb`
- Modify: `app/services/conversations/create_root.rb`
- Modify: `app/services/conversations/creation_support.rb`
- Modify: `app/services/conversation_bundle_imports/rehydrate_conversation.rb`
- Modify: `app/services/workbench/send_message.rb`
- Modify: `app/services/subagent_connections/send_message.rb`
- Modify: `app/services/turns/start_user_turn.rb`
- Modify: `app/services/turns/start_agent_turn.rb`
- Modify: `app/services/turns/start_automation_turn.rb`
- Modify: `app/services/turns/queue_follow_up.rb`
- Modify: `app/services/turns/edit_tail_input.rb`
- Modify: `app/services/turns/steer_current_input.rb`
- Modify: `app/services/turns/create_output_variant.rb`
- Modify: `app/services/turns/retry_output.rb`
- Modify: `app/services/turns/rerun_output.rb`
- Modify: `app/services/workflows/create_for_turn.rb`
- Modify: `app/services/conversation_supervision/append_feed_entries.rb`
- Modify: `app/services/conversation_control/resolve_target_runtime.rb`
- Modify: `app/services/conversation_supervision/build_activity_feed.rb`
- Modify: `app/services/conversations/update_supervision_state.rb`
- Modify: `app/services/embedded_agents/conversation_supervision/build_snapshot.rb`
- Modify: `test/services/conversations/create_root_test.rb`
- Modify: `test/models/message_test.rb`
- Modify: `test/services/conversation_bundle_imports/rehydrate_conversation_test.rb`
- Modify: `test/services/workbench/send_message_test.rb`
- Modify: `test/services/subagent_connections/send_message_test.rb`
- Modify: `test/services/turns/queue_follow_up_test.rb`
- Modify: `test/services/turns/edit_tail_input_test.rb`
- Modify: `test/services/turns/steer_current_input_test.rb`
- Modify: `test/services/turns/create_output_variant_test.rb`
- Modify: `test/services/conversation_control/resolve_target_runtime_test.rb`
- Modify: `test/services/conversation_supervision/append_feed_entries_test.rb`
- Modify: `test/services/conversation_supervision/build_activity_feed_test.rb`
- Modify: `test/services/conversations/update_supervision_state_test.rb`
- Modify: `test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb`
- Modify: `test/queries/conversations/blocker_snapshot_query_test.rb`

**Step 1: Write failing tests for `latest_active_*` writes**

Assert that:
- creating the first turn updates `latest_turn_id` and `latest_active_turn_id`
- creating a workflow updates `latest_active_workflow_run_id`
- adding a message updates `latest_message_id` and `last_activity_at`
- multiple active turns still produce correct blocker counts

**Step 2: Implement explicit write ownership**

Update the creation, reply, retry, follow-up, and import services so the
conversation row is synchronized inside the same transaction that creates the
new turn/message/workflow row.

This explicitly includes every app-facing message creation boundary touched in
the current codebase:
- `Turns::StartUserTurn`
- `Turns::StartAgentTurn`
- `Turns::StartAutomationTurn`
- `Workbench::SendMessage`
- `Turns::QueueFollowUp`
- `Turns::EditTailInput`
- `Turns::SteerCurrentInput`
- `Turns::CreateOutputVariant`
- `SubagentConnections::SendMessage`
- `ConversationBundleImports::RehydrateConversation`

Every one of those paths must advance `conversations.latest_message_id` and
`conversations.last_activity_at` transactionally.

**Step 3: Replace scan-heavy read anchors**

Update:
- `ConversationControl::ResolveTargetRuntime`
- `ConversationSupervision::AppendFeedEntries`
- `ConversationSupervision::BuildActivityFeed`
- `EmbeddedAgents::ConversationSupervision::BuildSnapshot`
- any nearby read helper touched by the tests

to prefer conversation anchor columns first and fall back only where the transition period requires it.

**Step 4: Run targeted tests**

```bash
bin/rails test \
  test/services/conversations/create_root_test.rb \
  test/models/message_test.rb \
  test/services/conversation_bundle_imports/rehydrate_conversation_test.rb \
  test/services/workbench/send_message_test.rb \
  test/services/subagent_connections/send_message_test.rb \
  test/services/turns/queue_follow_up_test.rb \
  test/services/turns/edit_tail_input_test.rb \
  test/services/turns/steer_current_input_test.rb \
  test/services/turns/create_output_variant_test.rb \
  test/services/conversation_control/resolve_target_runtime_test.rb \
  test/services/conversation_supervision/append_feed_entries_test.rb \
  test/services/conversation_supervision/build_activity_feed_test.rb \
  test/services/conversations/update_supervision_state_test.rb \
  test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb \
  test/queries/conversations/blocker_snapshot_query_test.rb
```

Expected: feed and control paths use `latest_active_*` semantics without changing blocker-count behavior.

**Step 5: Commit**

```bash
git add app/models/conversation.rb \
  app/models/message.rb \
  app/models/turn.rb \
  app/models/workflow_run.rb \
  app/services/conversations/create_root.rb \
  app/services/conversations/creation_support.rb \
  app/services/conversation_bundle_imports/rehydrate_conversation.rb \
  app/services/workbench/send_message.rb \
  app/services/subagent_connections/send_message.rb \
  app/services/turns/start_user_turn.rb \
  app/services/turns/start_agent_turn.rb \
  app/services/turns/start_automation_turn.rb \
  app/services/turns/queue_follow_up.rb \
  app/services/turns/edit_tail_input.rb \
  app/services/turns/steer_current_input.rb \
  app/services/turns/create_output_variant.rb \
  app/services/turns/retry_output.rb \
  app/services/turns/rerun_output.rb \
  app/services/workflows/create_for_turn.rb \
  app/services/conversation_supervision/append_feed_entries.rb \
  app/services/conversation_control/resolve_target_runtime.rb \
  app/services/conversation_supervision/build_activity_feed.rb \
  app/services/conversations/update_supervision_state.rb \
  app/services/embedded_agents/conversation_supervision/build_snapshot.rb \
  test/services/conversations/create_root_test.rb \
  test/models/message_test.rb \
  test/services/conversation_bundle_imports/rehydrate_conversation_test.rb \
  test/services/workbench/send_message_test.rb \
  test/services/subagent_connections/send_message_test.rb \
  test/services/turns/queue_follow_up_test.rb \
  test/services/turns/edit_tail_input_test.rb \
  test/services/turns/steer_current_input_test.rb \
  test/services/turns/create_output_variant_test.rb \
  test/services/conversation_control/resolve_target_runtime_test.rb \
  test/services/conversation_supervision/append_feed_entries_test.rb \
  test/services/conversation_supervision/build_activity_feed_test.rb \
  test/services/conversations/update_supervision_state_test.rb \
  test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb \
  test/queries/conversations/blocker_snapshot_query_test.rb
git commit -m "refactor: add latest-active conversation anchors"
```

### Task 6: Propagate Owner/Context Through Runtime and Control Aggregates

**Files:**
- Modify: `app/models/workflow_run.rb`
- Modify: `app/models/workflow_node.rb`
- Modify: `app/models/human_interaction_request.rb`
- Modify: `app/models/agent_task_run.rb`
- Modify: `app/models/process_run.rb`
- Modify: `app/models/subagent_connection.rb`
- Modify: `app/models/conversation_control_request.rb`
- Modify: `app/models/conversation_supervision_state.rb`
- Modify: `app/models/conversation_supervision_feed_entry.rb`
- Modify: `app/models/conversation_supervision_session.rb`
- Modify: `app/models/conversation_supervision_message.rb`
- Modify: `app/models/conversation_supervision_snapshot.rb`
- Modify: `app/models/tool_invocation.rb`
- Modify: `app/models/command_run.rb`
- Modify: `app/models/execution_profile_fact.rb`
- Modify: `app/services/processes/provision.rb`
- Modify: `app/services/workflows/create_for_turn.rb`
- Modify: `app/services/workflows/mutate.rb`
- Modify: `app/services/human_interactions/request.rb`
- Modify: `app/services/subagent_connections/spawn.rb`
- Modify: `app/services/conversation_control/create_request.rb`
- Modify: `app/services/embedded_agents/conversation_supervision/create_session.rb`
- Modify: `app/services/embedded_agents/conversation_supervision/append_message.rb`
- Modify: `app/services/embedded_agents/conversation_supervision/build_snapshot.rb`
- Modify: `app/services/conversation_control/build_guidance_projection.rb`
- Modify: `app/services/tool_invocations/start.rb`
- Modify: `app/services/command_runs/provision.rb`
- Modify: `app/services/execution_profiling/record_fact.rb`
- Modify: `app/queries/human_interactions/open_for_user_query.rb`
- Modify: `test/models/human_interaction_request_test.rb`
- Modify: `test/models/agent_task_run_test.rb` 
- Modify: `test/models/workflow_run_test.rb`
- Modify: `test/models/workflow_node_test.rb`
- Modify: `test/models/process_run_test.rb`
- Modify: `test/models/subagent_connection_test.rb`
- Modify: `test/models/conversation_control_request_test.rb`
- Modify: `test/models/conversation_supervision_state_test.rb`
- Modify: `test/models/conversation_supervision_feed_entry_test.rb`
- Modify: `test/models/conversation_supervision_session_test.rb`
- Modify: `test/models/conversation_supervision_message_test.rb`
- Modify: `test/models/conversation_supervision_snapshot_test.rb`
- Create: `test/models/command_run_test.rb`
- Modify: `test/models/tool_invocation_test.rb`
- Modify: `test/models/execution_profile_fact_test.rb`
- Modify: `test/queries/human_interactions/open_for_user_query_test.rb`
- Modify: `test/services/processes/provision_test.rb`
- Modify: `test/services/subagent_connections/spawn_test.rb`
- Modify: `test/services/human_interactions/request_test.rb`
- Modify: `test/services/conversation_control/create_request_test.rb`
- Modify: `test/services/conversation_control/build_guidance_projection_test.rb`
- Modify: `test/services/embedded_agents/conversation_supervision/create_session_test.rb`
- Modify: `test/services/embedded_agents/conversation_supervision/append_message_test.rb`
- Modify: `test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb`
- Modify: `test/services/workflows/create_for_turn_test.rb`
- Modify: `test/services/workflows/mutate_test.rb`
- Create: `test/services/command_runs/provision_test.rb`
- Modify: `test/services/tool_invocations/lifecycle_test.rb`
- Modify: `test/services/command_runs/terminalize_test.rb`
- Modify: `test/services/execution_profiling/record_fact_test.rb`
- Modify: `test/services/provider_execution/persist_turn_step_success_test.rb`

**Step 1: Write failing invariant tests**

Add model and service coverage that rejects rows where `user_id`, `workspace_id`, or `agent_id` drift away from their parent conversation/turn ownership chain.

Cover not just the primary runtime tables, but also:
- `workflow_nodes`
- `tool_invocations`
- `command_runs`
- `execution_profile_facts`

**Step 2: Implement propagation at creation boundaries**

Make each create path copy owner/context from `Conversation` or `Turn` once, at creation time. Do not backfill with callbacks.

Explicitly update:
- process-run allocation in `Processes::Provision`
- workflow-node allocation in `Workflows::CreateForTurn` and `Workflows::Mutate`
- tool-invocation allocation in `ToolInvocations::Start`
- command-run allocation in `CommandRuns::Provision`
- profiling-fact allocation in `ExecutionProfiling::RecordFact`

**Step 3: Update direct readers**

Where list/read services filter these tables directly, switch them to the new
owner/context columns so the joins can collapse.

This explicitly includes:
- `HumanInteractions::OpenForUserQuery`
- `ConversationControl::BuildGuidanceProjection`
- any supervision/session reader touched by the new tests

**Step 4: Run targeted tests**

```bash
bin/rails test \
  test/models/human_interaction_request_test.rb \
  test/models/agent_task_run_test.rb \
  test/models/workflow_run_test.rb \
  test/models/workflow_node_test.rb \
  test/models/process_run_test.rb \
  test/models/subagent_connection_test.rb \
  test/models/conversation_control_request_test.rb \
  test/models/conversation_supervision_state_test.rb \
  test/models/conversation_supervision_feed_entry_test.rb \
  test/models/conversation_supervision_session_test.rb \
  test/models/conversation_supervision_message_test.rb \
  test/models/conversation_supervision_snapshot_test.rb \
  test/models/command_run_test.rb \
  test/models/tool_invocation_test.rb \
  test/models/execution_profile_fact_test.rb \
  test/queries/human_interactions/open_for_user_query_test.rb \
  test/services/processes/provision_test.rb \
  test/services/subagent_connections/spawn_test.rb \
  test/services/human_interactions/request_test.rb \
  test/services/conversation_control/create_request_test.rb \
  test/services/conversation_control/build_guidance_projection_test.rb \
  test/services/embedded_agents/conversation_supervision/create_session_test.rb \
  test/services/embedded_agents/conversation_supervision/append_message_test.rb \
  test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb \
  test/services/workflows/create_for_turn_test.rb \
  test/services/workflows/mutate_test.rb \
  test/services/command_runs/provision_test.rb \
  test/services/tool_invocations/lifecycle_test.rb \
  test/services/command_runs/terminalize_test.rb \
  test/services/execution_profiling/record_fact_test.rb \
  test/services/provider_execution/persist_turn_step_success_test.rb
```

Expected: owner/context duplication is treated as first-class truth and stays aligned under transactional writes.

**Step 5: Commit**

```bash
git add app/models/workflow_run.rb \
  app/models/workflow_node.rb \
  app/models/human_interaction_request.rb \
  app/models/agent_task_run.rb \
  app/models/process_run.rb \
  app/models/subagent_connection.rb \
  app/models/conversation_control_request.rb \
  app/models/conversation_supervision_state.rb \
  app/models/conversation_supervision_feed_entry.rb \
  app/models/conversation_supervision_session.rb \
  app/models/conversation_supervision_message.rb \
  app/models/conversation_supervision_snapshot.rb \
  app/models/tool_invocation.rb \
  app/models/command_run.rb \
  app/models/execution_profile_fact.rb \
  app/services/processes/provision.rb \
  app/services/workflows/create_for_turn.rb \
  app/services/workflows/mutate.rb \
  app/services/human_interactions/request.rb \
  app/services/subagent_connections/spawn.rb \
  app/services/conversation_control/create_request.rb \
  app/services/embedded_agents/conversation_supervision/create_session.rb \
  app/services/embedded_agents/conversation_supervision/append_message.rb \
  app/services/embedded_agents/conversation_supervision/build_snapshot.rb \
  app/services/conversation_control/build_guidance_projection.rb \
  app/services/tool_invocations/start.rb \
  app/services/command_runs/provision.rb \
  app/services/execution_profiling/record_fact.rb \
  app/queries/human_interactions/open_for_user_query.rb \
  test/models/human_interaction_request_test.rb \
  test/models/agent_task_run_test.rb \
  test/models/workflow_run_test.rb \
  test/models/workflow_node_test.rb \
  test/models/process_run_test.rb \
  test/models/subagent_connection_test.rb \
  test/models/conversation_control_request_test.rb \
  test/models/conversation_supervision_state_test.rb \
  test/models/conversation_supervision_feed_entry_test.rb \
  test/models/conversation_supervision_session_test.rb \
  test/models/conversation_supervision_message_test.rb \
  test/models/conversation_supervision_snapshot_test.rb \
  test/models/command_run_test.rb \
  test/models/tool_invocation_test.rb \
  test/models/execution_profile_fact_test.rb \
  test/queries/human_interactions/open_for_user_query_test.rb \
  test/services/processes/provision_test.rb \
  test/services/subagent_connections/spawn_test.rb \
  test/services/human_interactions/request_test.rb \
  test/services/conversation_control/create_request_test.rb \
  test/services/conversation_control/build_guidance_projection_test.rb \
  test/services/embedded_agents/conversation_supervision/create_session_test.rb \
  test/services/embedded_agents/conversation_supervision/append_message_test.rb \
  test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb \
  test/services/workflows/create_for_turn_test.rb \
  test/services/workflows/mutate_test.rb \
  test/services/command_runs/provision_test.rb \
  test/services/tool_invocations/lifecycle_test.rb \
  test/services/command_runs/terminalize_test.rb \
  test/services/execution_profiling/record_fact_test.rb \
  test/services/provider_execution/persist_turn_step_success_test.rb
git commit -m "refactor: propagate owner context through runtime controls"
```

### Task 7: Split Wide Hot Tables Into Header/Detail or Document-Backed Layouts

**Files:**
- Create: `app/models/agent_task_run_detail.rb`
- Create: `app/models/human_interaction_request_detail.rb`
- Create: `app/models/conversation_supervision_state_detail.rb`
- Create: `app/models/workflow_run_wait_detail.rb`
- Create: `app/models/conversation_detail.rb`
- Modify: `db/migrate/20260326113000_add_agent_control_contract.rb`
- Modify: `db/migrate/20260324090035_create_human_interaction_requests.rb`
- Modify: `db/migrate/20260405093000_create_conversation_supervision_states.rb`
- Modify: `db/migrate/20260324090028_create_workflow_runs.rb`
- Modify: `db/migrate/20260324090019_create_conversations.rb`
- Modify: `app/models/agent_task_run.rb`
- Modify: `app/models/human_interaction_request.rb`
- Modify: `app/models/conversation_supervision_state.rb`
- Modify: `app/models/workflow_run.rb`
- Modify: `app/models/conversation.rb`
- Modify: `app/services/agent_control/apply_close_outcome.rb`
- Modify: `app/services/agent_control/handle_close_report.rb`
- Modify: `app/services/agent_control/handle_execution_report.rb`
- Modify: `app/services/human_interactions/request.rb`
- Modify: `app/services/conversations/update_override.rb`
- Modify: `app/services/conversations/update_supervision_state.rb`
- Modify: `app/services/workflows/block_node_for_failure.rb`
- Modify: `app/services/workflows/block_node_for_agent_request.rb`
- Modify: `app/services/workflows/block_node_for_execution_runtime_request.rb`
- Modify: `app/services/conversation_supervision/list_board_cards.rb`
- Modify: `app/services/conversation_supervision/build_board_card.rb`
- Modify: `test/models/agent_task_run_test.rb`
- Modify: `test/models/human_interaction_request_test.rb`
- Modify: `test/models/conversation_supervision_state_test.rb`
- Modify: `test/models/workflow_run_test.rb`
- Modify: `test/models/conversation_test.rb`
- Modify: `test/services/agent_control/apply_close_outcome_test.rb`
- Modify: `test/services/agent_control/handle_close_report_test.rb`
- Modify: `test/services/agent_control/handle_execution_report_test.rb`
- Modify: `test/services/agent_control/handle_execution_report_turn_todo_plan_test.rb`
- Modify: `test/services/human_interactions/request_test.rb`
- Modify: `test/services/conversations/update_override_test.rb`
- Modify: `test/services/conversations/update_supervision_state_test.rb`
- Modify: `test/services/workflows/block_node_for_failure_test.rb`
- Modify: `test/services/workflows/block_node_for_agent_request_test.rb`
- Create: `test/services/workflows/block_node_for_execution_runtime_request_test.rb`
- Modify: `test/services/conversation_supervision/list_board_cards_test.rb`
- Modify: `test/services/conversation_supervision/build_board_card_test.rb`
- Modify: `test/queries/human_interactions/open_for_user_query_test.rb`
- Modify: `test/services/agent_task_runs/append_progress_entry_test.rb`

**Step 1: Write failing tests that prove list reads do not need cold payloads**

Add expectations that:
- board-card reads succeed from header rows
- open human-interaction lists do not require full payload blobs
- agent task progress/update flows still persist cold detail rows transactionally
- task close-outcome writes still persist cold detail rows transactionally
- conversation override updates persist through the conversation detail/doc
  boundary without leaving header/detail drift
- workflow wait-state writers persist and clear wait-detail payloads
  transactionally
- supervision-state updates persist board/header fields separately from cold
  status payload details

**Step 2: Rewrite the create migrations**

Have the original migrations create companion detail tables or document references for:
- `agent_task_runs`
- `human_interaction_requests`
- `conversation_supervision_states`
- `workflow_runs`
- `conversations`

Keep summary/status/header columns on the main table. Move large payloads to one-to-one detail records or document-backed references.

Use the following explicit split map:
- `agent_task_runs`: keep lifecycle/supervision summaries, timestamps, counts, and ownership fields on the header row; move `task_payload`, `progress_payload`, `supervision_payload`, `terminal_payload`, and `close_outcome_payload` to the detail row
- `human_interaction_requests`: keep lifecycle, type, blocking, expiry, resolution, and ownership fields on the header row; move `request_payload` and `result_payload` to the detail row
- `conversation_supervision_states`: keep lane/state/summaries/counts and ownership fields on the header row; move `status_payload` to the detail row
- `workflow_runs`: keep lifecycle, wait-state selectors, blocking references, and ownership fields on the header row; move `wait_reason_payload` and any equivalent cold wait-debug payloads to the detail row
- `conversations`: keep title/summary/lifecycle/current anchors and ownership fields on the header row; move `override_payload` and `override_reconciliation_report` to the detail row or a document-backed payload reference

Do not move columns that are already adequately externalized through `JsonDocument`
references, such as the large payload bodies on `tool_invocations`.

**Step 3: Update writers and readers**

Writers must create/update header and detail rows in one transaction. List readers must stay on header tables unless a detail payload is explicitly needed.

This explicitly includes:
- `AgentControl::ApplyCloseOutcome` and `AgentControl::HandleCloseReport` for
  task close-outcome detail writes
- `AgentControl::HandleExecutionReport` for task progress and terminal payload updates
- `HumanInteractions::Request` for request/result payload writes
- `Conversations::UpdateOverride` for conversation override payload writes
- `Conversations::UpdateSupervisionState` for supervision-state detail writes
- `Workflows::BlockNodeForFailure` for retry/wait payload writes
- `Workflows::BlockNodeForAgentRequest` for agent-request wait payload writes
- `Workflows::BlockNodeForExecutionRuntimeRequest` for execution-runtime wait payload writes
- any companion wait-state clearer that currently mutates `workflow_runs`

**Step 4: Rebuild the database and regenerate `db/schema.rb`**

Run:

```bash
rails db:drop && rm db/schema.rb && rails db:create && rails db:migrate
```

Expected:
- detail tables or document references exist in `db/schema.rb`
- the current development database matches the rewritten migration set before
  the targeted tests run

**Step 5: Run targeted tests**

```bash
bin/rails test \
  test/models/agent_task_run_test.rb \
  test/models/human_interaction_request_test.rb \
  test/models/conversation_supervision_state_test.rb \
  test/models/workflow_run_test.rb \
  test/models/conversation_test.rb \
  test/services/agent_control/apply_close_outcome_test.rb \
  test/services/agent_control/handle_close_report_test.rb \
  test/services/agent_control/handle_execution_report_test.rb \
  test/services/agent_control/handle_execution_report_turn_todo_plan_test.rb \
  test/services/human_interactions/request_test.rb \
  test/services/conversations/update_override_test.rb \
  test/services/conversations/update_supervision_state_test.rb \
  test/services/workflows/block_node_for_failure_test.rb \
  test/services/workflows/block_node_for_agent_request_test.rb \
  test/services/workflows/block_node_for_execution_runtime_request_test.rb \
  test/services/conversation_supervision/list_board_cards_test.rb \
  test/services/conversation_supervision/build_board_card_test.rb \
  test/queries/human_interactions/open_for_user_query_test.rb \
  test/services/agent_task_runs/append_progress_entry_test.rb
```

Expected: hot list paths stay narrow; detail writes remain atomic.

**Step 6: Commit**

```bash
git add app/models/agent_task_run_detail.rb \
  app/models/human_interaction_request_detail.rb \
  app/models/conversation_supervision_state_detail.rb \
  app/models/workflow_run_wait_detail.rb \
  app/models/conversation_detail.rb \
  db/migrate/20260326113000_add_agent_control_contract.rb \
  db/migrate/20260324090035_create_human_interaction_requests.rb \
  db/migrate/20260405093000_create_conversation_supervision_states.rb \
  db/migrate/20260324090028_create_workflow_runs.rb \
  db/migrate/20260324090019_create_conversations.rb \
  app/models/agent_task_run.rb \
  app/models/human_interaction_request.rb \
  app/models/conversation_supervision_state.rb \
  app/models/workflow_run.rb \
  app/models/conversation.rb \
  app/services/agent_control/apply_close_outcome.rb \
  app/services/agent_control/handle_close_report.rb \
  app/services/agent_control/handle_execution_report.rb \
  app/services/human_interactions/request.rb \
  app/services/conversations/update_override.rb \
  app/services/conversations/update_supervision_state.rb \
  app/services/workflows/block_node_for_failure.rb \
  app/services/workflows/block_node_for_agent_request.rb \
  app/services/workflows/block_node_for_execution_runtime_request.rb \
  app/services/conversation_supervision/list_board_cards.rb \
  app/services/conversation_supervision/build_board_card.rb \
  test/models/agent_task_run_test.rb \
  test/models/human_interaction_request_test.rb \
  test/models/conversation_supervision_state_test.rb \
  test/models/workflow_run_test.rb \
  test/models/conversation_test.rb \
  test/services/agent_control/apply_close_outcome_test.rb \
  test/services/agent_control/handle_close_report_test.rb \
  test/services/agent_control/handle_execution_report_test.rb \
  test/services/agent_control/handle_execution_report_turn_todo_plan_test.rb \
  test/services/human_interactions/request_test.rb \
  test/services/conversations/update_override_test.rb \
  test/services/conversations/update_supervision_state_test.rb \
  test/services/workflows/block_node_for_failure_test.rb \
  test/services/workflows/block_node_for_agent_request_test.rb \
  test/services/workflows/block_node_for_execution_runtime_request_test.rb \
  test/services/conversation_supervision/list_board_cards_test.rb \
  test/services/conversation_supervision/build_board_card_test.rb \
  test/queries/human_interactions/open_for_user_query_test.rb \
  test/services/agent_task_runs/append_progress_entry_test.rb
git commit -m "refactor: split wide hot runtime rows"
```

### Task 8: Sync Behavior Docs and Run Full Verification

**Files:**
- Modify: `db/seeds.rb`
- Modify: `test/integration/seed_baseline_test.rb`
- Modify: `docs/behavior/user-bindings-and-workspaces.md`
- Modify: `docs/behavior/bundled-default-agent-bootstrap.md`
- Modify: `docs/behavior/read-side-queries-and-seed-baseline.md`
- Modify: `docs/behavior/conversation-structure-and-lineage.md`
- Modify: `docs/behavior/conversation-supervision-and-control.md`
- Modify: `docs/behavior/conversation-observation-and-supervisor-status.md`
- Modify: `docs/behavior/subagent-connections-and-execution-leases.md`
- Modify: `docs/behavior/human-interactions-and-conversation-events.md`
- Modify: `docs/behavior/agent-runtime-resource-apis.md`
- Modify: `docs/behavior/turn-entry-and-selector-state.md`
- Modify: `docs/behavior/agent-definition-version-bootstrap-and-recovery-flows.md`
- Modify: `docs/behavior/workflow-scheduler-and-wait-states.md`
- Modify: `docs/behavior/workflow-artifacts-node-events-and-process-runs.md`
- Modify: `docs/behavior/execution-profiling-facts.md`
- Modify: `docs/plans/2026-04-13-core-matrix-data-structure-optimization-design.md`

**Step 1: Update behavior docs to match the landed structure**

Document:
- workspace-native default reference resolution
- `latest_active_*` anchor naming
- preserved agent-usability semantics
- widened owner/context columns on runtime/control tables
- wide-row header/detail splits
- observation-session/message/snapshot ownership
- execution-profiling ownership fields
- workflow wait-detail splits and their seed/bootstrap implications

Update `db/seeds.rb` and `test/integration/seed_baseline_test.rb` if the
rewritten schema changes any bootstrap or bundled-runtime assumptions needed by
the final `db:reset` command.

**Step 2: Rebuild the database one final time**

Run:

```bash
rails db:drop && rm db/schema.rb && rails db:create && rails db:migrate && rails db:reset
bin/rails db:test:prepare
```

Expected: schema rebuild is deterministic; test database prepares cleanly.

**Step 3: Run the full project verification suite**

```bash
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails test
bin/rails test:system
```

Expected: all commands pass.

**Step 4: Commit**

```bash
git add docs/behavior \
  db/seeds.rb \
  test/integration/seed_baseline_test.rb \
  docs/plans/2026-04-13-core-matrix-data-structure-optimization-design.md \
  db/schema.rb
git commit -m "docs: sync behavior for data-structure rewrite"
```
