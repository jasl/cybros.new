# Conversation Canonical Store And Safe Deletion Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace conversation-scoped canonical variables with an immutable snapshot-backed conversation store and add safe conversation deletion that quiesces unfinished work before final purge.

**Architecture:** Introduce a lineage-local `CanonicalStore` with immutable snapshots, entry deltas, and deduplicated value rows. Conversations move from directly owning current conversation-scoped `CanonicalVariable` rows to owning a live reference to a store snapshot. Safe deletion adds a separate deletion-state axis, cancellation-request fields on active work, and asynchronous garbage collection over store reachability.

**Tech Stack:** Ruby on Rails 8.2, Active Record, PostgreSQL, Minitest, existing `AgentAPI` controllers, existing `Conversation` / `Turn` / `WorkflowRun` services.

---

### Task 1: Add the New Store Schema

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260325110000_create_canonical_store_tables.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260325110500_add_conversation_deletion_fields.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260325111000_add_turn_and_workflow_cancellation_requests.rb`
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

Implement tables and constraints for:

- `canonical_stores`
- `canonical_store_snapshots`
- `canonical_store_entries`
- `canonical_store_values`
- `canonical_store_references`
- `conversations.deletion_state`, `conversations.deleted_at`
- `turns.cancellation_requested_at`, `turns.cancellation_reason_kind`
- `workflow_runs.cancellation_requested_at`, `workflow_runs.cancellation_reason_kind`

Schema requirements:

- `canonical_store_entries` unique index on `[:canonical_store_snapshot_id, :key]`
- `canonical_store_references` unique index on `[:owner_type, :owner_id]`
- check constraint on `octet_length(key) <= 128`
- check constraint on `payload_bytesize <= 2_097_152`

**Step 4: Re-run the model tests**

Run: `bin/rails test test/models/canonical_store_snapshot_test.rb test/models/canonical_store_entry_test.rb test/models/canonical_store_value_test.rb test/models/canonical_store_reference_test.rb`

Expected: PASS or fail only on missing model code, not missing tables.

**Step 5: Commit**

```bash
git add db/migrate/20260325110000_create_canonical_store_tables.rb \
  db/migrate/20260325110500_add_conversation_deletion_fields.rb \
  db/migrate/20260325111000_add_turn_and_workflow_cancellation_requests.rb \
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
- keep temporary aliases for `write` and `list`
- use public ids only
- call the new `CanonicalStores` queries and services for conversation-local state
- keep workspace behavior unchanged

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

### Task 7: Backfill And Promotion Integration

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/canonical_stores/backfill_conversation.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/variables/promote_to_workspace.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/queries/conversation_variables/resolve_query.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/integration/canonical_variable_flow_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/canonical_stores/backfill_conversation_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/variables/promote_to_workspace_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/queries/conversation_variables/resolve_query_test.rb`

**Step 1: Write the failing backfill and promotion tests**

```ruby
test "backfill creates empty root snapshot and populated compaction snapshot" do
  conversation = conversations(:one)
  backfill = CanonicalStores::BackfillConversation.call(conversation: conversation)
  assert_equal "root", backfill.root_snapshot.snapshot_kind
  assert_equal "compaction", backfill.reference.canonical_store_snapshot.snapshot_kind
end
```

**Step 2: Run the backfill and resolve tests**

Run: `bin/rails test test/services/canonical_stores/backfill_conversation_test.rb test/services/variables/promote_to_workspace_test.rb test/queries/conversation_variables/resolve_query_test.rb test/integration/canonical_variable_flow_test.rb`

Expected: FAIL because backfill and promotion still depend on legacy conversation-scoped `CanonicalVariable` rows.

**Step 3: Implement backfill and resolve integration**

Requirements:

- backfill only current visible conversation-local keys
- leave workspace-scoped `CanonicalVariable` behavior untouched
- `conversation_variables_resolve` reads conversation-local state from the new store
- `PromoteToWorkspace` reads current conversation-local values from the new store and writes workspace `CanonicalVariable` rows

**Step 4: Re-run the targeted tests**

Run: `bin/rails test test/services/canonical_stores/backfill_conversation_test.rb test/services/variables/promote_to_workspace_test.rb test/queries/conversation_variables/resolve_query_test.rb test/integration/canonical_variable_flow_test.rb`

Expected: PASS.

**Step 5: Commit**

```bash
git add app/services/canonical_stores/backfill_conversation.rb \
  app/services/variables/promote_to_workspace.rb \
  app/queries/conversation_variables/resolve_query.rb \
  test/services/canonical_stores/backfill_conversation_test.rb \
  test/services/variables/promote_to_workspace_test.rb \
  test/queries/conversation_variables/resolve_query_test.rb \
  test/integration/canonical_variable_flow_test.rb
git commit -m "feat: backfill and promote from canonical store"
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

### Task 10: Remove Legacy Conversation-Scoped Write Path And Run Full Verification

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/canonical_variable.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/variables/write.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/canonical-variable-history-and-promotion.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/conversation-structure-and-lineage.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`

**Step 1: Write or update the final regression tests**

Focus on:

- no new conversation-scoped `CanonicalVariable` rows after cutover
- `conversation_variables_*` request coverage
- deletion with waiting workflow coverage
- branch snapshot freeze coverage

**Step 2: Run the focused regression suite**

Run: `bin/rails test test/requests/agent_api/conversation_variables_test.rb test/integration/conversation_canonical_store_branch_flow_test.rb test/integration/conversation_safe_deletion_flow_test.rb test/integration/canonical_variable_flow_test.rb`

Expected: PASS.

**Step 3: Remove or fence off the legacy conversation-scope write path**

Implementation requirements:

- workspace-scoped `CanonicalVariable` behavior stays
- conversation-scoped reads and writes are no longer the primary runtime path
- legacy conversation-scope code is either removed or guarded so it cannot be used by new runtime flows

**Step 4: Run full project verification**

Run:

```bash
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
git add app/models/canonical_variable.rb \
  app/services/variables/write.rb \
  docs/behavior/canonical-variable-history-and-promotion.md \
  docs/behavior/conversation-structure-and-lineage.md \
  docs/behavior/workflow-scheduler-and-wait-states.md
git commit -m "refactor: retire legacy conversation variable path"
```
