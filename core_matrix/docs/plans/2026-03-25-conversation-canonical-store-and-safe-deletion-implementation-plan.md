# Conversation Canonical Store And Safe Deletion Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace conversation-scoped canonical variables with an immutable snapshot-backed conversation store and add safe conversation deletion that quiesces unfinished work before final purge.

**Architecture:** Introduce a lineage-local `CanonicalStore` with immutable snapshots, entry deltas, and deduplicated value rows. Conversations move from directly owning current conversation-scoped `CanonicalVariable` rows to owning a live reference to a store snapshot. Safe deletion adds a separate deletion-state axis, cancellation-request fields on active work, and asynchronous garbage collection over store reachability.

**Tech Stack:** Ruby on Rails 8.2, Active Record, PostgreSQL, Minitest, existing `AgentAPI` controllers, existing `Conversation` / `Turn` / `WorkflowRun` services.

**Execution Policy:** This rollout allows destructive refactor. Prefer rewriting existing migration files over additive compatibility migrations when changing already-landed schema that is not yet production-bound. Reset development and test databases after schema-history edits, regenerate `db/schema.rb`, do not add backfills or compatibility aliases, and finish by updating behavior docs plus both plan docs so they exactly match the landed code.

---

### Task 1: Add the New Store Schema

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260324090019_create_conversations.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260324090021_create_turns.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260324090028_create_workflow_runs.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260324090036_create_canonical_variables.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260324090042_create_canonical_stores.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/schema.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/canonical_store_snapshot_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/canonical_store_entry_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/canonical_store_value_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/canonical_store_reference_test.rb`

**Step 1: Write the failing schema and model tests**

```ruby
test "snapshot depth and base rules are enforced" do
  snapshot = CanonicalStoreSnapshot.new(snapshot_kind: "write", depth: 0, base_snapshot: nil)
  assert_not snapshot.valid?
  assert_includes snapshot.errors[:base_snapshot], "must exist for write snapshots"
end

test "value payload size is capped at 2 MiB" do
  payload = { "type" => "string", "value" => "a" * (2.megabytes + 1) }
  value = CanonicalStoreValue.new(typed_value_payload: payload, payload_bytesize: payload.to_json.bytesize)
  assert_not value.valid?
end
```

**Step 2: Run only the new tests and confirm they fail**

Run: `bin/rails test test/models/canonical_store_snapshot_test.rb test/models/canonical_store_entry_test.rb test/models/canonical_store_value_test.rb test/models/canonical_store_reference_test.rb`

Expected: FAIL because the models, tables, and constraints do not exist yet.

**Step 3: Add the migrations**

Rewrite schema history for:

- `conversations.deletion_state`, `conversations.deleted_at`
- `turns.cancellation_requested_at`, `turns.cancellation_reason_kind`
- `workflow_runs.cancellation_requested_at`, `workflow_runs.cancellation_reason_kind`
- workspace-only `canonical_variables`
- new canonical-store tables in one consolidated migration:
  `canonical_stores`, `canonical_store_snapshots`, `canonical_store_entries`,
  `canonical_store_values`, `canonical_store_references`

Schema requirements:

- `canonical_store_entries` unique index on `[:canonical_store_snapshot_id, :key]`
- `canonical_store_references` unique index on `[:owner_type, :owner_id]`
- check constraint on `octet_length(key) <= 128`
- check constraint on `payload_bytesize <= 2_097_152`
- remove conversation-scope uniqueness and storage assumptions from
  `canonical_variables`

**Step 4: Re-run the model tests**

Run:

```bash
bin/rails db:drop db:create db:migrate
bin/rails db:test:prepare
bin/rails test test/models/canonical_store_snapshot_test.rb test/models/canonical_store_entry_test.rb test/models/canonical_store_value_test.rb test/models/canonical_store_reference_test.rb
```

Expected: PASS or fail only on missing model code, not missing tables.

**Step 5: Commit**

```bash
git add db/migrate/20260324090019_create_conversations.rb \
  db/migrate/20260324090021_create_turns.rb \
  db/migrate/20260324090028_create_workflow_runs.rb \
  db/migrate/20260324090036_create_canonical_variables.rb \
  db/migrate/20260324090042_create_canonical_stores.rb \
  db/schema.rb \
  test/models/canonical_store_snapshot_test.rb \
  test/models/canonical_store_entry_test.rb \
  test/models/canonical_store_value_test.rb \
  test/models/canonical_store_reference_test.rb
git commit -m "feat: add canonical store schema"
```

### Task 2: Add Store Models And Validation Rules

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/canonical_store.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/canonical_store_snapshot.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/canonical_store_entry.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/canonical_store_value.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/canonical_store_reference.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/conversation.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/turn.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/workflow_run.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/canonical_store_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/conversation_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/turn_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/workflow_run_test.rb`

**Step 1: Write the failing validation tests**

```ruby
test "conversation supports deletion states" do
  conversation = Conversation.new(deletion_state: "pending_delete")
  assert conversation.valid?
end

test "turn cancellation reason requires timestamp" do
  turn = turns(:one)
  turn.cancellation_reason_kind = "conversation_deleted"
  assert_not turn.valid?
end
```

**Step 2: Run the targeted model tests**

Run: `bin/rails test test/models/canonical_store_test.rb test/models/conversation_test.rb test/models/turn_test.rb test/models/workflow_run_test.rb`

Expected: FAIL on missing associations, enums, or validation logic.

**Step 3: Implement the models**

Model requirements:

- `CanonicalStoreSnapshot` enforces `root` and `compaction` as base-less depth-0 snapshots
- `CanonicalStoreSnapshot` enforces `write` snapshots to have a base snapshot and `depth = base.depth + 1`
- `CanonicalStoreEntry` enforces `set` vs `tombstone` value-reference rules
- `CanonicalStoreValue` computes and validates `payload_bytesize`
- `Conversation`, `Turn`, and `WorkflowRun` add deletion and cancellation enums plus lightweight validation

**Step 4: Re-run the targeted model tests**

Run: `bin/rails test test/models/canonical_store_test.rb test/models/conversation_test.rb test/models/turn_test.rb test/models/workflow_run_test.rb`

Expected: PASS.

**Step 5: Commit**

```bash
git add app/models/canonical_store.rb \
  app/models/canonical_store_snapshot.rb \
  app/models/canonical_store_entry.rb \
  app/models/canonical_store_value.rb \
  app/models/canonical_store_reference.rb \
  app/models/conversation.rb \
  app/models/turn.rb \
  app/models/workflow_run.rb \
  test/models/canonical_store_test.rb \
  test/models/conversation_test.rb \
  test/models/turn_test.rb \
  test/models/workflow_run_test.rb
git commit -m "feat: add canonical store models"
```

### Task 3: Build Store Read Queries

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/queries/canonical_stores/get_query.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/queries/canonical_stores/multi_get_query.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/queries/canonical_stores/list_keys_query.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/test_helper.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/queries/canonical_stores/get_query_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/queries/canonical_stores/multi_get_query_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/queries/canonical_stores/list_keys_query_test.rb`

**Step 1: Write the failing query tests**

```ruby
test "get returns missing when newest visible entry is tombstone" do
  context = build_canonical_store_context!
  assert_nil CanonicalStores::GetQuery.call(reference_owner: context[:conversation], key: "tone")
end

test "list_keys does not load value rows" do
  context = build_canonical_store_context!
  assert_queries(1) do
    CanonicalStores::ListKeysQuery.call(reference_owner: context[:conversation], cursor: nil, limit: 20)
  end
end
```

**Step 2: Run the query tests**

Run: `bin/rails test test/queries/canonical_stores/get_query_test.rb test/queries/canonical_stores/multi_get_query_test.rb test/queries/canonical_stores/list_keys_query_test.rb`

Expected: FAIL because the query objects and test fixtures do not exist.

**Step 3: Implement recursive read queries**

Implementation requirements:

- resolve snapshots from the active `CanonicalStoreReference`
- traverse snapshot ancestry with a recursive CTE
- stop at the newest matching entry per key
- batch-load values in `MultiGetQuery`
- never join `canonical_store_values` inside `ListKeysQuery`

**Step 4: Re-run the query tests**

Run: `bin/rails test test/queries/canonical_stores/get_query_test.rb test/queries/canonical_stores/multi_get_query_test.rb test/queries/canonical_stores/list_keys_query_test.rb`

Expected: PASS.

**Step 5: Commit**

```bash
git add app/queries/canonical_stores/get_query.rb \
  app/queries/canonical_stores/multi_get_query.rb \
  app/queries/canonical_stores/list_keys_query.rb \
  test/test_helper.rb \
  test/queries/canonical_stores/get_query_test.rb \
  test/queries/canonical_stores/multi_get_query_test.rb \
  test/queries/canonical_stores/list_keys_query_test.rb
git commit -m "feat: add canonical store read queries"
```

### Task 4: Build Store Write, Delete, And Compaction Services

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/canonical_stores/set.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/canonical_stores/delete_key.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/canonical_stores/compact_snapshot.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/canonical_stores/bootstrap_for_conversation.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/canonical_stores/set_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/canonical_stores/delete_key_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/canonical_stores/compact_snapshot_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/canonical_stores/bootstrap_for_conversation_test.rb`

**Step 1: Write the failing service tests**

```ruby
test "set creates a new write snapshot and moves the conversation reference" do
  context = build_canonical_store_context!
  assert_difference("CanonicalStoreSnapshot.count", +1) do
    CanonicalStores::Set.call(conversation: context[:conversation], key: "tone", typed_value_payload: { "type" => "string", "value" => "direct" })
  end
end

test "identical set is a no-op" do
  context = build_canonical_store_context!
  CanonicalStores::Set.call(conversation: context[:conversation], key: "tone", typed_value_payload: { "type" => "string", "value" => "direct" })
  assert_no_difference("CanonicalStoreSnapshot.count") do
    CanonicalStores::Set.call(conversation: context[:conversation], key: "tone", typed_value_payload: { "type" => "string", "value" => "direct" })
  end
end
```

**Step 2: Run the service tests**

Run: `bin/rails test test/services/canonical_stores/set_test.rb test/services/canonical_stores/delete_key_test.rb test/services/canonical_stores/compact_snapshot_test.rb test/services/canonical_stores/bootstrap_for_conversation_test.rb`

Expected: FAIL because the service objects do not exist.

**Step 3: Implement the services**

Behavior requirements:

- bootstrap creates one store, one empty root snapshot, and one live reference
- set creates a new write snapshot unless the visible value is identical
- delete creates a tombstone snapshot unless the key is already missing
- compaction rewrites the visible key set into one depth-0 compaction snapshot
- writes compact first when the target depth is 32 or more

**Step 4: Re-run the service tests**

Run: `bin/rails test test/services/canonical_stores/set_test.rb test/services/canonical_stores/delete_key_test.rb test/services/canonical_stores/compact_snapshot_test.rb test/services/canonical_stores/bootstrap_for_conversation_test.rb`

Expected: PASS.

**Step 5: Commit**

```bash
git add app/services/canonical_stores/set.rb \
  app/services/canonical_stores/delete_key.rb \
  app/services/canonical_stores/compact_snapshot.rb \
  app/services/canonical_stores/bootstrap_for_conversation.rb \
  test/services/canonical_stores/set_test.rb \
  test/services/canonical_stores/delete_key_test.rb \
  test/services/canonical_stores/compact_snapshot_test.rb \
  test/services/canonical_stores/bootstrap_for_conversation_test.rb
git commit -m "feat: add canonical store write services"
```

### Task 5: Wire Conversation Creation And Branching To Store References

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/create_root.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/create_automation_root.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/create_branch.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/create_checkpoint.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/create_thread.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversations/create_root_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversations/create_automation_root_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversations/create_branch_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversations/create_checkpoint_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversations/create_thread_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/integration/conversation_canonical_store_branch_flow_test.rb`

**Step 1: Write the failing branch and checkpoint tests**

```ruby
test "branch reuses the same canonical store but gets its own reference" do
  root = Conversations::CreateRoot.call(workspace: workspaces(:one))
  CanonicalStores::Set.call(conversation: root, key: "tone", typed_value_payload: { "type" => "string", "value" => "direct" })

  branch = Conversations::CreateBranch.call(parent: root, historical_anchor_message_id: nil)

  assert_equal root.canonical_store_reference.canonical_store_snapshot.canonical_store_id,
    branch.canonical_store_reference.canonical_store_snapshot.canonical_store_id
  refute_equal root.canonical_store_reference.id, branch.canonical_store_reference.id
end
```

**Step 2: Run the conversation service tests**

Run: `bin/rails test test/services/conversations/create_root_test.rb test/services/conversations/create_automation_root_test.rb test/services/conversations/create_branch_test.rb test/services/conversations/create_checkpoint_test.rb test/services/conversations/create_thread_test.rb test/integration/conversation_canonical_store_branch_flow_test.rb`

Expected: FAIL because the services do not yet build or share store references.

**Step 3: Update the conversation-creation services**

Implementation requirements:

- root and automation root bootstrap a new store
- branch, checkpoint, and thread create a fresh reference to the current parent snapshot
- branching copies no keys and no values
- later parent writes do not affect the child snapshot

**Step 4: Re-run the conversation service tests**

Run: `bin/rails test test/services/conversations/create_root_test.rb test/services/conversations/create_automation_root_test.rb test/services/conversations/create_branch_test.rb test/services/conversations/create_checkpoint_test.rb test/services/conversations/create_thread_test.rb test/integration/conversation_canonical_store_branch_flow_test.rb`

Expected: PASS.

**Step 5: Commit**

```bash
git add app/services/conversations/create_root.rb \
  app/services/conversations/create_automation_root.rb \
  app/services/conversations/create_branch.rb \
  app/services/conversations/create_checkpoint.rb \
  app/services/conversations/create_thread.rb \
  test/services/conversations/create_root_test.rb \
  test/services/conversations/create_automation_root_test.rb \
  test/services/conversations/create_branch_test.rb \
  test/services/conversations/create_checkpoint_test.rb \
  test/services/conversations/create_thread_test.rb \
  test/integration/conversation_canonical_store_branch_flow_test.rb
git commit -m "feat: connect conversations to canonical store snapshots"
```

### Task 6: Cut Over Agent API Reads And Writes

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/config/routes.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/agent_api/conversation_variables_controller.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/agent_api/base_controller.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/agent_api/conversation_variables_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/agent-runtime-resource-apis.md`

**Step 1: Write the failing request tests for the new method surface**

```ruby
test "list_keys returns metadata without eager-loading values" do
  get "/agent_api/conversation_variables/list_keys", params: { conversation_id: conversations(:one).public_id }
  assert_response :success
  assert_nil response.parsed_body["items"].first["value"]
end
```

**Step 2: Run the request tests**

Run: `bin/rails test test/requests/agent_api/conversation_variables_test.rb`

Expected: FAIL because routes and controller actions do not match the new API.

**Step 3: Update the routes and controller**

Controller requirements:

- route `get`, `mget`, `set`, `delete`, `exists`, `list_keys`, `resolve`, `promote`
- use public ids only
- call the new `CanonicalStores` queries and services for conversation-local state
- keep workspace behavior unchanged
- remove legacy conversation `write` and `list` route names in the same change

**Step 4: Re-run the request tests**

Run: `bin/rails test test/requests/agent_api/conversation_variables_test.rb`

Expected: PASS.

**Step 5: Commit**

```bash
git add config/routes.rb \
  app/controllers/agent_api/conversation_variables_controller.rb \
  app/controllers/agent_api/base_controller.rb \
  test/requests/agent_api/conversation_variables_test.rb \
  docs/behavior/agent-runtime-resource-apis.md
git commit -m "feat: switch conversation variable api to canonical store"
```

### Task 7: Direct Promotion Integration And Legacy Path Removal

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/canonical_variable.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/variables/write.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/variables/promote_to_workspace.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/queries/conversation_variables/resolve_query.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/integration/canonical_variable_flow_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/variables/promote_to_workspace_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/queries/conversation_variables/resolve_query_test.rb`

**Step 1: Write the failing promotion and legacy-removal tests**

```ruby
test "conversation-scope canonical variable writes are no longer accepted" do
  context = build_canonical_variable_context!
  assert_raises(ActiveRecord::RecordInvalid) do
    Variables::Write.call(
      scope: "conversation",
      workspace: context[:workspace],
      conversation: context[:conversation],
      key: "tone",
      typed_value_payload: { "type" => "string", "value" => "direct" },
      source_kind: "manual_user"
    )
  end
end
```

**Step 2: Run the promotion and resolve tests**

Run: `bin/rails test test/services/variables/promote_to_workspace_test.rb test/queries/conversation_variables/resolve_query_test.rb test/integration/canonical_variable_flow_test.rb`

Expected: FAIL because promotion and resolve still depend on legacy conversation-scoped `CanonicalVariable` rows.

**Step 3: Implement direct-cutover promotion and legacy-path removal**

Requirements:

- leave workspace-scoped `CanonicalVariable` behavior intact
- `CanonicalVariable` becomes workspace-only in both schema assumptions and runtime validation
- `Variables::Write` no longer accepts conversation scope
- `conversation_variables_resolve` reads conversation-local state from the new store
- `PromoteToWorkspace` reads current conversation-local values from the new store and writes workspace `CanonicalVariable` rows

**Step 4: Re-run the targeted tests**

Run: `bin/rails test test/services/variables/promote_to_workspace_test.rb test/queries/conversation_variables/resolve_query_test.rb test/integration/canonical_variable_flow_test.rb`

Expected: PASS.

**Step 5: Commit**

```bash
git add app/models/canonical_variable.rb \
  app/services/variables/write.rb \
  app/services/variables/promote_to_workspace.rb \
  app/queries/conversation_variables/resolve_query.rb \
  test/services/variables/promote_to_workspace_test.rb \
  test/queries/conversation_variables/resolve_query_test.rb \
  test/integration/canonical_variable_flow_test.rb
git commit -m "refactor: remove legacy conversation variable path"
```

### Task 8: Implement Safe Deletion Request And Finalization

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/request_deletion.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/finalize_deletion.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/purge_deleted.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversations/cancel_active_work.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/turns/start_user_turn.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/turns/start_automation_turn.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/workflows/manual_resume.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_deployments/auto_resume_workflows.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/human_interactions/complete_task.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/human_interactions/submit_form.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/human_interactions/resolve_approval.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversations/request_deletion_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversations/finalize_deletion_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/conversations/purge_deleted_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/integration/conversation_safe_deletion_flow_test.rb`

**Step 1: Write the failing deletion tests**

```ruby
test "request deletion cancels queued turns and blocks new writes" do
  conversation = conversations(:one)
  Conversations::RequestDeletion.call(conversation: conversation)
  assert_equal "pending_delete", conversation.reload.deletion_state
  assert_raises(ActiveRecord::RecordInvalid) do
    Turns::StartUserTurn.call(conversation: conversation, agent_deployment: agent_deployments(:one), content: "hello")
  end
end
```

**Step 2: Run the deletion tests**

Run: `bin/rails test test/services/conversations/request_deletion_test.rb test/services/conversations/finalize_deletion_test.rb test/services/conversations/purge_deleted_test.rb test/integration/conversation_safe_deletion_flow_test.rb`

Expected: FAIL because the deletion services and guards do not exist.

**Step 3: Implement deletion request and finalization**

Requirements:

- `RequestDeletion` is idempotent
- queued turns cancel immediately
- active work receives a cancellation request and is not resumed
- human-interaction completion paths reject deleted or pending-delete conversations
- `FinalizeDeletion` removes the canonical store reference only after work is quiescent
- `PurgeDeleted` deletes the shell only when no dependency still requires it

**Step 4: Re-run the deletion tests**

Run: `bin/rails test test/services/conversations/request_deletion_test.rb test/services/conversations/finalize_deletion_test.rb test/services/conversations/purge_deleted_test.rb test/integration/conversation_safe_deletion_flow_test.rb`

Expected: PASS.

**Step 5: Commit**

```bash
git add app/services/conversations/request_deletion.rb \
  app/services/conversations/finalize_deletion.rb \
  app/services/conversations/purge_deleted.rb \
  app/services/conversations/cancel_active_work.rb \
  app/services/turns/start_user_turn.rb \
  app/services/turns/start_automation_turn.rb \
  app/services/workflows/manual_resume.rb \
  app/services/agent_deployments/auto_resume_workflows.rb \
  app/services/human_interactions/complete_task.rb \
  app/services/human_interactions/submit_form.rb \
  app/services/human_interactions/resolve_approval.rb \
  test/services/conversations/request_deletion_test.rb \
  test/services/conversations/finalize_deletion_test.rb \
  test/services/conversations/purge_deleted_test.rb \
  test/integration/conversation_safe_deletion_flow_test.rb
git commit -m "feat: add safe conversation deletion"
```

### Task 9: Add Store Garbage Collection

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/canonical_stores/garbage_collect.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/canonical_stores/garbage_collect_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/integration/conversation_safe_deletion_flow_test.rb`

**Step 1: Write the failing GC tests**

```ruby
test "gc preserves snapshots still reachable from a child conversation" do
  context = build_canonical_store_branch_context!
  assert_no_difference("CanonicalStoreSnapshot.count") do
    CanonicalStores::GarbageCollect.call
  end
end
```

**Step 2: Run the GC tests**

Run: `bin/rails test test/services/canonical_stores/garbage_collect_test.rb test/integration/conversation_safe_deletion_flow_test.rb`

Expected: FAIL because the GC service does not exist.

**Step 3: Implement mark-and-sweep GC**

Requirements:

- mark from live `CanonicalStoreReference` rows
- traverse `base_snapshot_id`
- delete unreachable entries, snapshots, and values
- keep the service idempotent and retry-safe

**Step 4: Re-run the GC tests**

Run: `bin/rails test test/services/canonical_stores/garbage_collect_test.rb test/integration/conversation_safe_deletion_flow_test.rb`

Expected: PASS.

**Step 5: Commit**

```bash
git add app/services/canonical_stores/garbage_collect.rb \
  test/services/canonical_stores/garbage_collect_test.rb \
  test/integration/conversation_safe_deletion_flow_test.rb
git commit -m "feat: garbage collect canonical store snapshots"
```

### Task 10: Synchronize Docs And Run Final Verification

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/canonical-variable-history-and-promotion.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/agent-runtime-resource-apis.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/conversation-structure-and-lineage.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/plans/2026-03-25-conversation-canonical-store-and-safe-deletion-design.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/plans/2026-03-25-conversation-canonical-store-and-safe-deletion-implementation-plan.md`

**Step 1: Re-read the landed code and write a doc-alignment checklist**

Checklist must cover:

- public runtime method names
- workspace-only `CanonicalVariable` responsibility
- canonical-store snapshot semantics
- deletion and unfinished-work behavior
- schema rewrite policy versus what actually landed

**Step 2: Update the behavior docs and both plan docs**

Requirements:

- remove stale compatibility or migration text
- document the final public runtime methods
- document the final deletion behavior
- update the design doc if any locked detail changed during implementation
- update this implementation plan if task ordering or content changed during execution

**Step 3: Run the focused regression suite**

Run: `bin/rails test test/requests/agent_api/conversation_variables_test.rb test/integration/conversation_canonical_store_branch_flow_test.rb test/integration/conversation_safe_deletion_flow_test.rb test/integration/canonical_variable_flow_test.rb`

Expected: PASS.

**Step 4: Run full project verification**

Run:

```bash
bin/rails db:drop db:create db:migrate
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails db:test:prepare test
bin/rails db:test:prepare test:system
```

Expected:

- `brakeman`: exit 0
- `bundler-audit`: exit 0
- `rubocop`: exit 0
- `bun run lint:js`: exit 0
- all tests: PASS

**Step 5: Commit**

```bash
git add docs/behavior/canonical-variable-history-and-promotion.md \
  docs/behavior/agent-runtime-resource-apis.md \
  docs/behavior/conversation-structure-and-lineage.md \
  docs/behavior/workflow-scheduler-and-wait-states.md \
  docs/plans/2026-03-25-conversation-canonical-store-and-safe-deletion-design.md \
  docs/plans/2026-03-25-conversation-canonical-store-and-safe-deletion-implementation-plan.md
git commit -m "docs: align canonical store behavior and plans"
```
