# Conversation Bootstrap Phase Two Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Execute one coherent next iteration for the `Conversation` domain:
first remove container bootstrap preallocation, then slim app-facing manual user
turn entry so workflow substrate is created asynchronously after accepted-turn
truth is durably recorded.

**Architecture:** This plan is intentionally phased. Phase A collapses
conversation-local authority and lazy lineage into the `Conversation` boundary.
Phase B then adds a scoped deferred workflow-bootstrap contract for
`Workbench::CreateConversationFromAgent` and `Workbench::SendMessage`, backed by
turn-owned workflow-bootstrap state plus a minimal pending projector.

**Tech Stack:** Ruby on Rails, Active Record, PostgreSQL, Active Job,
Minitest, `db/schema.rb`, behavior docs under `docs/behavior`.

---

### Task 1: Lock Phase A Contracts And Baselines

**Files:**
- Create: `test/services/conversations/create_root_weight_test.rb`
- Create: `test/services/conversations/child_lineage_bootstrap_weight_test.rb`
- Modify: `test/services/conversations/create_root_test.rb`
- Modify: `test/services/conversations/create_automation_root_test.rb`
- Modify: `test/services/conversations/create_branch_test.rb`
- Modify: `test/services/conversations/create_checkpoint_test.rb`
- Modify: `test/services/conversations/create_fork_test.rb`
- Modify: `test/services/app_surface/policies/conversation_supervision_access_test.rb`
- Modify: `test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb`
- Modify: `test/services/conversation_control/authorize_request_test.rb`
- Modify: `test/services/conversations/update_supervision_state_test.rb`
- Modify: `test/services/lineage_stores/bootstrap_for_conversation_test.rb`
- Modify: `test/services/lineage_stores/set_test.rb`
- Modify: `test/services/lineage_stores/delete_key_test.rb`
- Modify: `test/services/lineage_stores/compact_snapshot_test.rb`
- Modify: `test/services/lineage_stores/garbage_collect_test.rb`
- Modify: `test/queries/lineage_stores/get_query_test.rb`
- Modify: `test/queries/lineage_stores/list_keys_query_test.rb`
- Modify: `test/queries/lineage_stores/multi_get_query_test.rb`
- Modify: `test/requests/app_api/workspace_policies_test.rb`
- Modify: `test/models/conversation_supervision_snapshot_test.rb`
- Modify: `test/services/conversations/purge_deleted_test.rb`
- Modify: `test/services/conversations/purge_plan_test.rb`
- Modify: `test/test_helper.rb`

**Step 1: Write failing tests for capability-authority collapse**

Lock the Phase A end state:

- `Conversation` stores the four authority booleans directly
- a new conversation no longer creates a `ConversationCapabilityPolicy` row
- `ConversationSupervisionAccess`, `EmbeddedAgents::ConversationSupervision::Authority`,
  and `ConversationControl::AuthorizeRequest` no longer expose an AR policy row
- supervision snapshots stop recording
  `conversation_capability_policy_public_id`

Keep the current business rule:

- workspace policy updates affect future conversations
- existing conversations keep the projected authority frozen at creation time

**Step 2: Write failing tests for lazy lineage bootstrap**

Lock:

- bare root conversation creation creates no lineage substrate
- automation root creation also creates no lineage substrate
- child creation copies a lineage reference only when the parent already has one
- lineage queries tolerate missing references by returning empty or nil results
- the first lineage write materializes the store/snapshot/reference exactly once

**Step 3: Add failing weight tests**

In `create_root_weight_test.rb`, add explicit expectations for:

- root bootstrap without capability row: `<= 13` SQL
- root bootstrap after lazy lineage: `<= 8` SQL

In `child_lineage_bootstrap_weight_test.rb`, lock:

- child creation with no parent lineage reference creates no lineage rows
- child creation with parent lineage creates exactly one child reference

**Step 4: Run the targeted failure set**

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/services/conversations/create_root_test.rb \
  test/services/conversations/create_automation_root_test.rb \
  test/services/conversations/create_branch_test.rb \
  test/services/conversations/create_checkpoint_test.rb \
  test/services/conversations/create_fork_test.rb \
  test/services/conversations/create_root_weight_test.rb \
  test/services/conversations/child_lineage_bootstrap_weight_test.rb \
  test/services/app_surface/policies/conversation_supervision_access_test.rb \
  test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb \
  test/services/conversation_control/authorize_request_test.rb \
  test/services/conversations/update_supervision_state_test.rb \
  test/services/lineage_stores/bootstrap_for_conversation_test.rb \
  test/services/lineage_stores/set_test.rb \
  test/services/lineage_stores/delete_key_test.rb \
  test/services/lineage_stores/compact_snapshot_test.rb \
  test/services/lineage_stores/garbage_collect_test.rb \
  test/queries/lineage_stores/get_query_test.rb \
  test/queries/lineage_stores/list_keys_query_test.rb \
  test/queries/lineage_stores/multi_get_query_test.rb \
  test/requests/app_api/workspace_policies_test.rb \
  test/models/conversation_supervision_snapshot_test.rb \
  test/services/conversations/purge_deleted_test.rb \
  test/services/conversations/purge_plan_test.rb
```

**Step 5: Commit**

```bash
git add \
  test/services/conversations/create_root_weight_test.rb \
  test/services/conversations/child_lineage_bootstrap_weight_test.rb \
  test/services/conversations/create_root_test.rb \
  test/services/conversations/create_automation_root_test.rb \
  test/services/conversations/create_branch_test.rb \
  test/services/conversations/create_checkpoint_test.rb \
  test/services/conversations/create_fork_test.rb \
  test/services/app_surface/policies/conversation_supervision_access_test.rb \
  test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb \
  test/services/conversation_control/authorize_request_test.rb \
  test/services/conversations/update_supervision_state_test.rb \
  test/services/lineage_stores/bootstrap_for_conversation_test.rb \
  test/services/lineage_stores/set_test.rb \
  test/services/lineage_stores/delete_key_test.rb \
  test/services/lineage_stores/compact_snapshot_test.rb \
  test/services/lineage_stores/garbage_collect_test.rb \
  test/queries/lineage_stores/get_query_test.rb \
  test/queries/lineage_stores/list_keys_query_test.rb \
  test/queries/lineage_stores/multi_get_query_test.rb \
  test/requests/app_api/workspace_policies_test.rb \
  test/models/conversation_supervision_snapshot_test.rb \
  test/services/conversations/purge_deleted_test.rb \
  test/services/conversations/purge_plan_test.rb \
  test/test_helper.rb
git commit -m "test: lock phase-a conversation bootstrap contracts"
```

### Task 2: Rewrite Conversation Schema For Phase A

**Files:**
- Modify: `db/migrate/20260324090019_create_conversations.rb`
- Modify: `db/migrate/20260404090100_create_conversation_observation_frames.rb`
- Modify: `db/migrate/20260405092950_create_conversation_capability_policies.rb`
- Modify: `db/migrate/20260324090042_create_lineage_stores.rb`
- Modify: `db/schema.rb`

**Step 1: Inline authority booleans onto `conversations`**

Move:

- `supervision_enabled`
- `detailed_progress_enabled`
- `side_chat_enabled`
- `control_enabled`

onto `conversations` as non-null booleans.

**Step 2: Remove `conversation_capability_policies` from schema**

Rewrite its original migration into a no-op with a short comment explaining that
the table was removed before launch.

**Step 3: Rename lineage ownership to `owner_conversation`**

Rewrite lineage migrations so the durable owner field is owner-based rather than
root-based, and so missing references are valid for bare conversations.

**Step 4: Remove dead snapshot foreign-reference columns**

Remove `conversation_capability_policy_public_id` from supervision snapshot
schema. Keep frozen authority inside the snapshot payload only.

**Step 5: Rebuild the database**

```bash
bin/rails db:drop && rm db/schema.rb && bin/rails db:create && bin/rails db:migrate && bin/rails db:reset
```

**Step 6: Commit**

```bash
git add db/migrate db/schema.rb
git commit -m "db: rewrite phase-a conversation bootstrap schema"
```

### Task 3: Implement Capability Collapse

**Files:**
- Delete: `app/models/conversation_capability_policy.rb`
- Delete: `test/models/conversation_capability_policy_test.rb`
- Modify: `app/models/conversation.rb`
- Modify: `app/services/conversations/creation_support.rb`
- Modify: `app/services/workspace_policies/capabilities.rb`
- Modify: `app/services/app_surface/policies/conversation_supervision_access.rb`
- Modify: `app/services/embedded_agents/conversation_supervision/authority.rb`
- Modify: `app/services/embedded_agents/conversation_supervision/build_snapshot.rb`
- Modify: `app/services/conversations/update_supervision_state.rb`
- Modify: `app/services/conversation_control/authorize_request.rb`
- Modify: `app/controllers/app_api/conversations/supervision/base_controller.rb`
- Modify: `app/services/conversations/purge_plan.rb`
- Modify: `test/support/conversation_supervision_fixture_builder.rb`
- Modify: `test/models/data_lifecycle_test.rb`
- Modify: `test/services/embedded_agents/conversation_supervision/create_session_test.rb`
- Modify: `test/requests/app_api/conversation_supervision_sessions_test.rb`

**Step 1: Make `Conversation` the authority owner**

- remove the `has_one :conversation_capability_policy`
- add a small `capability_authority_snapshot` helper
- keep any row-local normalization needed so the four booleans stay coherent

**Step 2: Project workspace authority directly into conversation creation**

Change `Conversations::CreationSupport` so it writes the booleans directly onto
`Conversation.create!` instead of allocating a policy row.

**Step 3: Rewrite supervision and control readers**

Rename row-shaped `policy` outputs to snapshot-shaped names where that improves
clarity under the destructive-refactor rule.

**Step 4: Remove dead lifecycle and purge references**

Delete remaining purge or lifecycle cleanup that only existed for the removed
policy table.

**Step 5: Run focused tests**

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/services/conversations/create_root_test.rb \
  test/services/conversations/create_root_weight_test.rb \
  test/services/app_surface/policies/conversation_supervision_access_test.rb \
  test/services/embedded_agents/conversation_supervision/create_session_test.rb \
  test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb \
  test/services/conversation_control/authorize_request_test.rb \
  test/services/conversations/update_supervision_state_test.rb \
  test/requests/app_api/workspace_policies_test.rb \
  test/services/conversations/purge_deleted_test.rb \
  test/services/conversations/purge_plan_test.rb
```

**Step 6: Commit**

```bash
git add \
  app/models/conversation.rb \
  app/services/conversations/creation_support.rb \
  app/services/workspace_policies/capabilities.rb \
  app/services/app_surface/policies/conversation_supervision_access.rb \
  app/services/embedded_agents/conversation_supervision/authority.rb \
  app/services/embedded_agents/conversation_supervision/build_snapshot.rb \
  app/services/conversations/update_supervision_state.rb \
  app/services/conversation_control/authorize_request.rb \
  app/controllers/app_api/conversations/supervision/base_controller.rb \
  app/services/conversations/purge_plan.rb \
  test/support/conversation_supervision_fixture_builder.rb \
  test/models/data_lifecycle_test.rb \
  test/services/embedded_agents/conversation_supervision/create_session_test.rb \
  test/requests/app_api/conversation_supervision_sessions_test.rb
git add -u app/models/conversation_capability_policy.rb test/models/conversation_capability_policy_test.rb
git commit -m "refactor: collapse conversation capability authority"
```

### Task 4: Implement Lazy Lineage Bootstrap

**Files:**
- Modify: `app/models/conversation.rb`
- Modify: `app/models/lineage_store.rb`
- Modify: `app/models/lineage_store_reference.rb`
- Modify: `app/services/conversations/creation_support.rb`
- Modify: `app/services/lineage_stores/bootstrap_for_conversation.rb`
- Modify: `app/services/lineage_stores/set.rb`
- Modify: `app/services/lineage_stores/delete_key.rb`
- Modify: `app/services/lineage_stores/compact_snapshot.rb`
- Modify: `app/services/lineage_stores/garbage_collect.rb`
- Modify: `app/queries/lineage_stores/get_query.rb`
- Modify: `app/queries/lineage_stores/list_keys_query.rb`
- Modify: `app/queries/lineage_stores/multi_get_query.rb`
- Modify: `test/services/conversations/create_root_test.rb`
- Modify: `test/services/conversations/create_automation_root_test.rb`
- Modify: `test/services/conversations/create_branch_test.rb`
- Modify: `test/services/conversations/create_checkpoint_test.rb`
- Modify: `test/services/conversations/create_fork_test.rb`
- Modify: `test/services/conversations/create_root_weight_test.rb`
- Modify: `test/services/conversations/child_lineage_bootstrap_weight_test.rb`
- Modify: `test/services/lineage_stores/bootstrap_for_conversation_test.rb`
- Modify: `test/services/lineage_stores/set_test.rb`
- Modify: `test/services/lineage_stores/delete_key_test.rb`
- Modify: `test/services/lineage_stores/compact_snapshot_test.rb`
- Modify: `test/services/lineage_stores/garbage_collect_test.rb`
- Modify: `test/queries/lineage_stores/get_query_test.rb`
- Modify: `test/queries/lineage_stores/list_keys_query_test.rb`
- Modify: `test/queries/lineage_stores/multi_get_query_test.rb`

**Step 1: Stop root creation from preallocating lineage**

`CreateRoot` and `CreateAutomationRoot` should create no lineage rows unless
real lineage state is needed.

**Step 2: Copy lineage references only when they already exist**

Child creation should tolerate a parent with no lineage reference.

**Step 3: Make first lineage write own bootstrap**

Materialize owner store + root snapshot + live reference at the first write,
not at conversation creation.

**Step 4: Update queries to tolerate missing references**

Missing lineage reference is now a valid empty-state, not an error.

**Step 5: Run focused tests and capture Phase A reductions**

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/services/conversations/create_root_test.rb \
  test/services/conversations/create_automation_root_test.rb \
  test/services/conversations/create_branch_test.rb \
  test/services/conversations/create_checkpoint_test.rb \
  test/services/conversations/create_fork_test.rb \
  test/services/conversations/create_root_weight_test.rb \
  test/services/conversations/child_lineage_bootstrap_weight_test.rb \
  test/services/lineage_stores/bootstrap_for_conversation_test.rb \
  test/services/lineage_stores/set_test.rb \
  test/services/lineage_stores/delete_key_test.rb \
  test/services/lineage_stores/compact_snapshot_test.rb \
  test/services/lineage_stores/garbage_collect_test.rb \
  test/queries/lineage_stores/get_query_test.rb \
  test/queries/lineage_stores/list_keys_query_test.rb \
  test/queries/lineage_stores/multi_get_query_test.rb
```

Then record the real before/after numbers in the design doc before starting
Phase B.

**Step 6: Commit**

```bash
git add \
  app/models/conversation.rb \
  app/models/lineage_store.rb \
  app/models/lineage_store_reference.rb \
  app/services/conversations/creation_support.rb \
  app/services/lineage_stores/bootstrap_for_conversation.rb \
  app/services/lineage_stores/set.rb \
  app/services/lineage_stores/delete_key.rb \
  app/services/lineage_stores/compact_snapshot.rb \
  app/services/lineage_stores/garbage_collect.rb \
  app/queries/lineage_stores/get_query.rb \
  app/queries/lineage_stores/list_keys_query.rb \
  app/queries/lineage_stores/multi_get_query.rb \
  test/services/conversations/create_root_test.rb \
  test/services/conversations/create_automation_root_test.rb \
  test/services/conversations/create_branch_test.rb \
  test/services/conversations/create_checkpoint_test.rb \
  test/services/conversations/create_fork_test.rb \
  test/services/conversations/create_root_weight_test.rb \
  test/services/conversations/child_lineage_bootstrap_weight_test.rb \
  test/services/lineage_stores/bootstrap_for_conversation_test.rb \
  test/services/lineage_stores/set_test.rb \
  test/services/lineage_stores/delete_key_test.rb \
  test/services/lineage_stores/compact_snapshot_test.rb \
  test/services/lineage_stores/garbage_collect_test.rb \
  test/queries/lineage_stores/get_query_test.rb \
  test/queries/lineage_stores/list_keys_query_test.rb \
  test/queries/lineage_stores/multi_get_query_test.rb \
  docs/plans/2026-04-13-conversation-bootstrap-phase-two-design.md
git commit -m "refactor: make conversation lineage bootstrap lazy"
```

### Task 5: Lock Phase B Contracts And Fresh Baselines

**Files:**
- Create: `test/services/workbench/create_conversation_from_agent_weight_test.rb`
- Create: `test/services/workbench/send_message_weight_test.rb`
- Create: `test/services/conversations/project_turn_bootstrap_state_test.rb`
- Create: `test/services/turns/accept_pending_user_turn_test.rb`
- Create: `test/services/turns/materialize_workflow_bootstrap_test.rb`
- Create: `test/jobs/turns/materialize_and_dispatch_job_test.rb`
- Create: `test/jobs/turns/recover_workflow_bootstrap_backlog_job_test.rb`
- Create: `test/services/turns/recover_workflow_bootstrap_backlog_test.rb`
- Create: `test/models/turn_workflow_bootstrap_constraint_test.rb`
- Modify: `test/models/turn_test.rb`
- Modify: `test/requests/app_api/conversations_test.rb`
- Modify: `test/requests/app_api/conversation_messages_test.rb`
- Modify: `test/services/workbench/create_conversation_from_agent_test.rb`
- Modify: `test/services/workbench/send_message_test.rb`
- Modify: `test/services/turns/start_user_turn_test.rb`
- Modify: `test/services/conversations/update_supervision_state_test.rb`
- Modify: `test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb`
- Modify: `test/services/conversation_supervision/publish_update_test.rb`
- Modify: `test/services/conversation_supervision/build_board_card_test.rb`
- Modify: `test/services/conversation_supervision/list_board_cards_test.rb`
- Modify: `test/requests/app_api/conversation_turn_feeds_controller_test.rb`
- Modify: `test/requests/app_api/conversation_turn_todo_plans_controller_test.rb`

**Step 1: Freeze fresh before-values after Phase A**

Measure and record the current exact SQL and row deltas for:

- `Workbench::CreateConversationFromAgent`
- `Workbench::SendMessage`
- `POST /app_api/conversations`
- `POST /app_api/conversations/:id/messages`

Write those values into:

- the new weight tests
- the design doc baseline section

Do not start Phase B from stale pre-Phase-A numbers.

**Step 2: Write failing tests for the scoped deferred contract**

Lock the new end state:

- only app-facing manual user entry returns `execution_status = "pending"`
- synchronous request success no longer requires `WorkflowRun.count +1`
- a pending projector writes queued supervision state immediately
- a bootstrap job is enqueued instead of immediate workflow execution
- if that immediate enqueue is skipped or fails, the pending turn still remains
  durable backlog recoverable by the backlog-recovery boundary
- the maintenance recovery job can reclaim both lost-enqueue `pending` turns and
  stale `materializing` turns

**Step 3: Add model and DB constraint failures**

Cover:

- valid `workflow_bootstrap_state` values
- payload fields must be hashes
- active-contract payloads must include exactly the fixed top-level contract keys
- failure payloads must include exactly the fixed top-level error keys when
  state is `failed`
- time fields must pair correctly with state
- only the allowed state transitions are legal
- `ready` implies workflow substrate exists for deferred turns
- `failed` can exist before a workflow row exists
- default `workflow_bootstrap_state = "not_requested"` is valid for turn paths
  outside this phase
- stale `materializing` reclamation does not require a new durable state; it is
  still a timed-out `materializing` row

**Step 4: Lock bootstrap-failed visibility**

Add failing read-side tests proving:

- bootstrap failure must not regress back to `idle`
- board cards, feed reads, and todo-plan refreshes preserve either queued or
  bootstrap-failed turn-owned state until richer runtime state exists

**Step 5: Run the targeted failure set**

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/models/turn_test.rb \
  test/models/turn_workflow_bootstrap_constraint_test.rb \
  test/requests/app_api/conversations_test.rb \
  test/requests/app_api/conversation_messages_test.rb \
  test/services/workbench/create_conversation_from_agent_test.rb \
  test/services/workbench/send_message_test.rb \
  test/services/workbench/create_conversation_from_agent_weight_test.rb \
  test/services/workbench/send_message_weight_test.rb \
  test/services/turns/start_user_turn_test.rb \
  test/services/conversations/project_turn_bootstrap_state_test.rb \
  test/services/turns/accept_pending_user_turn_test.rb \
  test/jobs/turns/recover_workflow_bootstrap_backlog_job_test.rb \
  test/services/turns/recover_workflow_bootstrap_backlog_test.rb \
  test/services/conversations/update_supervision_state_test.rb \
  test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb \
  test/services/conversation_supervision/publish_update_test.rb \
  test/services/conversation_supervision/build_board_card_test.rb \
  test/services/conversation_supervision/list_board_cards_test.rb \
  test/requests/app_api/conversation_turn_feeds_controller_test.rb \
  test/requests/app_api/conversation_turn_todo_plans_controller_test.rb \
  test/services/turns/materialize_workflow_bootstrap_test.rb \
  test/jobs/turns/materialize_and_dispatch_job_test.rb
```

**Step 6: Commit**

```bash
git add \
  test/models/turn_test.rb \
  test/models/turn_workflow_bootstrap_constraint_test.rb \
  test/requests/app_api/conversations_test.rb \
  test/requests/app_api/conversation_messages_test.rb \
  test/services/workbench/create_conversation_from_agent_test.rb \
  test/services/workbench/send_message_test.rb \
  test/services/workbench/create_conversation_from_agent_weight_test.rb \
  test/services/workbench/send_message_weight_test.rb \
  test/services/turns/start_user_turn_test.rb \
  test/services/conversations/project_turn_bootstrap_state_test.rb \
  test/services/turns/accept_pending_user_turn_test.rb \
  test/jobs/turns/recover_workflow_bootstrap_backlog_job_test.rb \
  test/services/turns/recover_workflow_bootstrap_backlog_test.rb \
  test/services/conversations/update_supervision_state_test.rb \
  test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb \
  test/services/conversation_supervision/publish_update_test.rb \
  test/services/conversation_supervision/build_board_card_test.rb \
  test/services/conversation_supervision/list_board_cards_test.rb \
  test/requests/app_api/conversation_turn_feeds_controller_test.rb \
  test/requests/app_api/conversation_turn_todo_plans_controller_test.rb \
  test/services/turns/materialize_workflow_bootstrap_test.rb \
  test/jobs/turns/materialize_and_dispatch_job_test.rb \
  docs/plans/2026-04-13-conversation-bootstrap-phase-two-design.md
git commit -m "test: lock phase-b deferred turn bootstrap contracts"
```

### Task 6: Rewrite Turn Schema For Scoped Workflow Bootstrap

**Files:**
- Modify: `db/migrate/20260324090021_create_turns.rb`
- Modify: `db/schema.rb`

**Step 1: Add workflow-specific bootstrap columns**

Add:

- `workflow_bootstrap_state`, `null: false`, default `"not_requested"`
- `workflow_bootstrap_payload`, `jsonb`, default `{}`
- `workflow_bootstrap_failure_payload`, `jsonb`, default `{}`
- `workflow_bootstrap_requested_at`
- `workflow_bootstrap_started_at`
- `workflow_bootstrap_finished_at`

**Step 2: Add schema-level shape constraints**

At minimum:

- `not_requested` requires empty payloads and nil timestamps
- `pending` requires:
  - non-empty payload
  - exact top-level payload keys
  - requested_at present
  - started_at/finished_at nil
  - empty failure payload
- `materializing` requires:
  - the same payload contract as `pending`
  - requested_at and started_at present
  - finished_at nil
  - empty failure payload
- `ready` requires:
  - the same payload contract as `pending`
  - requested_at, started_at, and finished_at present
  - empty failure payload
- `failed` requires:
  - the same payload contract as `pending`
  - requested_at, started_at, and finished_at present
  - failure payload present with exact top-level error keys

Prefer exact top-level shape checks in SQL, not just “contains these keys”. For
example, use:

- key-presence checks such as `?& ARRAY[...]`
- object-size checks such as `jsonb_object_length(...) = N`
- state/timestamp pairing checks

Do not encode cross-table workflow existence in SQL, but do protect every
single-row impossible shape in the database.

**Step 3: Rebuild the database**

```bash
bin/rails db:drop && rm db/schema.rb && bin/rails db:create && bin/rails db:migrate && bin/rails db:reset
```

**Step 4: Commit**

```bash
git add db/migrate/20260324090021_create_turns.rb db/schema.rb
git commit -m "db: add scoped turn workflow bootstrap state"
```

### Task 7: Implement Pending Acceptance As One Durable Boundary

**Files:**
- Modify: `app/models/turn.rb`
- Modify: `app/services/turns/start_user_turn.rb`
- Create: `app/services/turns/accept_pending_user_turn.rb`
- Create: `app/services/conversations/project_turn_bootstrap_state.rb`
- Modify: `app/services/workbench/create_conversation_from_agent.rb`
- Modify: `app/services/workbench/send_message.rb`
- Modify: `app/controllers/app_api/conversations_controller.rb`
- Modify: `app/controllers/app_api/conversations/messages_controller.rb`
- Modify: `test/services/turns/start_user_turn_test.rb`
- Modify: `test/services/turns/accept_pending_user_turn_test.rb`
- Modify: `test/services/workbench/create_conversation_from_agent_test.rb`
- Modify: `test/services/workbench/send_message_test.rb`
- Modify: `test/requests/app_api/conversations_test.rb`
- Modify: `test/requests/app_api/conversation_messages_test.rb`

**Step 1: Add turn helpers for the workflow-bootstrap state machine**

Expose:

- `workflow_bootstrap_not_requested?`
- `workflow_bootstrap_pending?`
- `workflow_bootstrap_materializing?`
- `workflow_bootstrap_ready?`
- `workflow_bootstrap_failed?`

Also add one small transition API on `Turn` or a companion value object that
guards the legal transitions. Do not rely on scattered ad-hoc `update!`
calls for bootstrap-state mutation.

That API should also normalize payloads to the exact top-level contract shape so
extra keys cannot drift into durable rows.

**Step 2: Keep generic `StartUserTurn`, but add an explicit pending-acceptance service**

Do not globally change every `StartUserTurn` caller to pending semantics.

Create `Turns::AcceptPendingUserTurn` as the single transaction boundary for the
app-facing manual user entry contract. It should atomically persist:

- turn + message
- `workflow_bootstrap_state = "pending"`
- `workflow_bootstrap_payload`
- cleared failure payload
- refreshed anchors
- minimal queued supervision projection

It may call into `StartUserTurn` internally, but the acceptance contract itself
must live at this higher boundary. `Workbench::CreateConversationFromAgent` and
`Workbench::SendMessage` should call it instead of open-coding multiple
post-turn writes.

The service may request an immediate post-commit enqueue, but that enqueue is an
acceleration path only. A failed enqueue must not change the committed `pending`
truth.

**Step 3: Project queued supervision state before returning**

Call `Conversations::ProjectTurnBootstrapState` from inside
`Turns::AcceptPendingUserTurn`, not as a later best-effort write.

Project the state as `queued`, with the compact turn-owned shape defined in the
design doc.

**Step 4: Return an honest API contract**

Expose:

- `execution_status = "pending"`
- `accepted_at`
- `request_summary`

Do not fabricate workflow ids during pending.

**Step 5: Run focused tests**

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/models/turn_test.rb \
  test/requests/app_api/conversations_test.rb \
  test/requests/app_api/conversation_messages_test.rb \
  test/services/workbench/create_conversation_from_agent_test.rb \
  test/services/workbench/send_message_test.rb \
  test/services/workbench/create_conversation_from_agent_weight_test.rb \
  test/services/workbench/send_message_weight_test.rb \
  test/services/turns/start_user_turn_test.rb \
  test/services/conversations/project_turn_bootstrap_state_test.rb \
  test/services/turns/accept_pending_user_turn_test.rb
```

**Step 6: Commit**

```bash
git add \
  app/models/turn.rb \
  app/services/turns/start_user_turn.rb \
  app/services/turns/accept_pending_user_turn.rb \
  app/services/conversations/project_turn_bootstrap_state.rb \
  app/services/workbench/create_conversation_from_agent.rb \
  app/services/workbench/send_message.rb \
  app/controllers/app_api/conversations_controller.rb \
  app/controllers/app_api/conversations/messages_controller.rb \
  test/models/turn_test.rb \
  test/requests/app_api/conversations_test.rb \
  test/requests/app_api/conversation_messages_test.rb \
  test/services/workbench/create_conversation_from_agent_test.rb \
  test/services/workbench/send_message_test.rb \
  test/services/workbench/create_conversation_from_agent_weight_test.rb \
  test/services/workbench/send_message_weight_test.rb \
  test/services/turns/start_user_turn_test.rb \
  test/services/conversations/project_turn_bootstrap_state_test.rb \
  test/services/turns/accept_pending_user_turn_test.rb
git commit -m "refactor: accept pending user turns without workflow substrate"
```

### Task 8: Add Async Materialization And Failed-State Visibility

**Files:**
- Create: `app/jobs/turns/materialize_and_dispatch_job.rb`
- Create: `app/jobs/turns/recover_workflow_bootstrap_backlog_job.rb`
- Create: `app/services/turns/materialize_workflow_bootstrap.rb`
- Create: `app/services/turns/recover_workflow_bootstrap_backlog.rb`
- Modify: `config/recurring.yml`
- Create: `test/config/turn_workflow_bootstrap_recurring_configuration_test.rb`
- Modify: `app/services/workflows/create_for_turn.rb`
- Modify: `app/services/workflows/execute_run.rb`
- Modify: `app/services/workflows/dispatch_runnable_nodes.rb`
- Modify: `app/services/conversations/update_supervision_state.rb`
- Modify: `app/services/embedded_agents/conversation_supervision/build_snapshot.rb`
- Modify: `test/services/turns/materialize_workflow_bootstrap_test.rb`
- Modify: `test/jobs/turns/materialize_and_dispatch_job_test.rb`
- Modify: `test/jobs/turns/recover_workflow_bootstrap_backlog_job_test.rb`
- Modify: `test/services/turns/recover_workflow_bootstrap_backlog_test.rb`
- Modify: `test/services/workflows/create_for_turn_test.rb`
- Modify: `test/services/conversations/update_supervision_state_test.rb`
- Modify: `test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb`
- Modify: `test/requests/app_api/conversation_turn_feeds_controller_test.rb`
- Modify: `test/requests/app_api/conversation_turn_todo_plans_controller_test.rb`

**Step 1: Extract the bootstrap materializer**

The service should:

- lock the turn
- no-op for deleted/canceled/terminal turns
- no-op if workflow substrate already exists and bootstrap already completed
- move `pending/failed -> materializing`
- create substrate exactly once
- mark `ready`
- return the materialized `workflow_run`

If a retry sees `materializing` with partially created substrate, reconcile
that substrate under the turn lock and drive the state forward to either
`ready` or `failed`. Do not leave stale `materializing` rows hanging.

**Step 2: Add the job boundary**

The job should:

- load turn by public id
- call the materializer
- continue into the existing dispatch path
- persist `workflow_bootstrap_state = "failed"` and
  `workflow_bootstrap_failure_payload` on failure
- call `Conversations::ProjectTurnBootstrapState` with the failed shape on
  failure
- make retry behavior explicit

**Step 3: Add backlog recovery for stranded pending/materializing turns**

Create `Turns::RecoverWorkflowBootstrapBacklog` so correctness does not depend
on the one immediate post-commit enqueue.

It should:

- scan claimable `pending` turns
- scan stale `materializing` turns older than the chosen timeout
- re-enqueue or directly re-drive them through
  `Turns::MaterializeWorkflowBootstrap`
- never create a second durable queue source outside the `Turn` row

Add `Turns::RecoverWorkflowBootstrapBacklogJob` on the `maintenance` queue and
wire it into the existing maintenance cadence used by the app. The per-turn
post-commit enqueue remains the fast path; the maintenance job is the durable
backstop.

In this phase, make that cadence explicit in `config/recurring.yml` at a short
interval suitable for user-visible recovery, not the once-per-day data
retention schedule.

Cover both cases in tests:

- accepted turn left `pending` because enqueue was skipped or lost
- stale `materializing` turn after worker crash

**Step 4: Make read-side projection pending and failure aware**

`Conversations::UpdateSupervisionState` and snapshot reads must preserve:

- queued state for pending/materializing turns when no richer owner exists
- failed state for bootstrap-failed turns when no richer owner exists

That branch must never regress back to `idle` just because workflow substrate is
still absent.

**Step 5: Run focused tests**

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/models/turn_workflow_bootstrap_constraint_test.rb \
  test/services/turns/materialize_workflow_bootstrap_test.rb \
  test/jobs/turns/materialize_and_dispatch_job_test.rb \
  test/jobs/turns/recover_workflow_bootstrap_backlog_job_test.rb \
  test/services/turns/recover_workflow_bootstrap_backlog_test.rb \
  test/config/turn_workflow_bootstrap_recurring_configuration_test.rb \
  test/services/workflows/create_for_turn_test.rb \
  test/services/conversations/update_supervision_state_test.rb \
  test/services/conversations/project_turn_bootstrap_state_test.rb \
  test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb \
  test/requests/app_api/conversation_turn_feeds_controller_test.rb \
  test/requests/app_api/conversation_turn_todo_plans_controller_test.rb
```

**Step 6: Commit**

```bash
git add \
  app/jobs/turns/materialize_and_dispatch_job.rb \
  app/jobs/turns/recover_workflow_bootstrap_backlog_job.rb \
  app/services/turns/materialize_workflow_bootstrap.rb \
  app/services/turns/recover_workflow_bootstrap_backlog.rb \
  config/recurring.yml \
  app/services/workflows/create_for_turn.rb \
  app/services/workflows/execute_run.rb \
  app/services/workflows/dispatch_runnable_nodes.rb \
  app/services/conversations/update_supervision_state.rb \
  app/services/conversations/project_turn_bootstrap_state.rb \
  app/services/embedded_agents/conversation_supervision/build_snapshot.rb \
  test/models/turn_workflow_bootstrap_constraint_test.rb \
  test/services/turns/materialize_workflow_bootstrap_test.rb \
  test/jobs/turns/materialize_and_dispatch_job_test.rb \
  test/jobs/turns/recover_workflow_bootstrap_backlog_job_test.rb \
  test/services/turns/recover_workflow_bootstrap_backlog_test.rb \
  test/config/turn_workflow_bootstrap_recurring_configuration_test.rb \
  test/services/workflows/create_for_turn_test.rb \
  test/services/conversations/update_supervision_state_test.rb \
  test/services/conversations/project_turn_bootstrap_state_test.rb \
  test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb \
  test/requests/app_api/conversation_turn_feeds_controller_test.rb \
  test/requests/app_api/conversation_turn_todo_plans_controller_test.rb
git commit -m "feat: materialize workflow substrate asynchronously per turn"
```

### Task 9: Final Regression, Behavior Docs, And Measured Reductions

**Files:**
- Modify: `docs/behavior/turn-entry-and-selector-state.md`
- Modify: `docs/behavior/conversation-supervision-and-control.md`
- Modify: `docs/behavior/workflow-context-assembly-and-execution-snapshot.md`
- Modify: `docs/behavior/workflow-graph-foundations.md`
- Modify: `docs/behavior/workflow-model-selector-resolution.md`
- Modify: `docs/behavior/workflow-scheduler-and-wait-states.md`
- Modify: `docs/behavior/conversation-structure-and-lineage.md`
- Modify: `docs/plans/2026-04-13-conversation-bootstrap-phase-two-design.md`

**Step 1: Rewrite behavior docs for the landed boundaries**

Synchronize both phases:

- container bootstrap no longer preallocates capability rows or lineage
- app-facing manual user entry returns pending acceptance
- workflow substrate is created later by a turn-bootstrap job
- queued and bootstrap-failed UI states come from turn-owned bootstrap truth plus
  the pending/failure-aware projector
- workflow graph ownership remains turn-scoped, but `WorkflowRun` is no longer a
  prerequisite for a turn to be durably accepted

**Step 2: Record measured before/after values**

Write the actual observed reductions into the design doc:

- Phase A root bootstrap SQL and row deltas
- Phase B `CreateConversationFromAgent` SQL and row deltas
- Phase B `SendMessage` SQL and row deltas
- async first-bootstrap row deltas

**Step 3: Run the full project verification suite**

```bash
bin/rails db:drop && rm db/schema.rb && bin/rails db:create && bin/rails db:migrate && bin/rails db:reset
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails db:test:prepare
PARALLEL_WORKERS=1 bin/rails test
bin/rails test:system
```

If this phase lands on the main long-running branch close path, run the broader
acceptance and capstone suite after the local project suite is green.

**Step 4: Commit**

```bash
git add \
  docs/behavior/turn-entry-and-selector-state.md \
  docs/behavior/conversation-supervision-and-control.md \
  docs/behavior/workflow-context-assembly-and-execution-snapshot.md \
  docs/behavior/workflow-graph-foundations.md \
  docs/behavior/workflow-model-selector-resolution.md \
  docs/behavior/workflow-scheduler-and-wait-states.md \
  docs/behavior/conversation-structure-and-lineage.md \
  docs/plans/2026-04-13-conversation-bootstrap-phase-two-design.md
git commit -m "docs: sync phase-two conversation bootstrap behavior"
```

## Execution Notes

- Phase A must land before Phase B starts.
- Record real before/after weight numbers at the end of each phase.
- If implementation reveals a plan defect, fix the plan first, then continue.
- Keep the synchronous boundary limited to durable accepted-turn truth; do not
  let workflow substrate creep back onto the request path.
- Do not let bootstrap-failed turns disappear into `idle`.
