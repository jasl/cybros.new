# Turn Todo Plan Supervision Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace summary-derived supervision progress reporting with an explicit turn-scoped todo plan domain that powers UI checklist rendering, turn feed entries, and supervision conversation answers.

**Architecture:** Introduce `TurnTodoPlan` and `TurnTodoPlanItem` as the only plan truth for active `AgentTaskRun` work, including child-agent work. Route execution-time plan updates through a dedicated `turn_todo_plan_update` payload, generate append-only turn feed entries from plan diffs, rebuild conversation supervision to consume plan views, and delete the old `AgentTaskPlanItem` and `supervision_update.plan_items` pathways.

**Tech Stack:** Rails 8.2, Active Record/Postgres, JSONB/public-id boundaries, Minitest, app API request tests, supervision services under `app/services`

---

### Task 1: Add the `TurnTodoPlan` schema and model contract

**Files:**
- Create: `core_matrix/db/migrate/20260406110000_create_turn_todo_plans.rb`
- Create: `core_matrix/app/models/turn_todo_plan.rb`
- Test: `core_matrix/test/models/turn_todo_plan_test.rb`
- Modify later for deletion prep: `core_matrix/app/models/agent_task_run.rb`

**Step 1: Write the failing model test**

Add a test that proves:

- `TurnTodoPlan` belongs to one `AgentTaskRun`
- it must align with the owner task's installation, conversation, and turn
- statuses are limited to `draft active blocked completed canceled failed`
- one active plan per owner task is enforced

```ruby
test "validates owner alignment and one active plan per agent task run" do
  context = build_agent_control_context!
  scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
  agent_task_run = scenario.fetch(:agent_task_run)

  TurnTodoPlan.create!(
    installation: agent_task_run.installation,
    owner: agent_task_run,
    conversation: agent_task_run.conversation,
    turn: agent_task_run.turn,
    status: "active",
    goal_summary: "Rebuild supervision around turn todo plans",
    current_item_key: "define-domain",
    counts_payload: {}
  )

  duplicate = TurnTodoPlan.new(
    installation: agent_task_run.installation,
    owner: agent_task_run,
    conversation: agent_task_run.conversation,
    turn: agent_task_run.turn,
    status: "active",
    goal_summary: "Second active plan",
    current_item_key: "duplicate",
    counts_payload: {}
  )

  assert_not duplicate.valid?
  assert_includes duplicate.errors[:owner], "already has an active turn todo plan"
end
```

**Step 2: Run the test to verify it fails**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/models/turn_todo_plan_test.rb
```

Expected: FAIL because the model and table do not exist.

**Step 3: Write the migration and model**

Create `turn_todo_plans` with:

- `installation_id`
- `owner_type`, `owner_id`
- `conversation_id`
- `turn_id`
- `status`
- `goal_summary`
- `current_item_key`
- `counts_payload`
- `closed_at`
- timestamps

Model rules:

- polymorphic `belongs_to :owner`
- owner must currently be `AgentTaskRun`
- unique active plan per owner
- counts payload must be a hash

**Step 4: Run the model test to verify it passes**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare test test/models/turn_todo_plan_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
git add db/migrate/20260406110000_create_turn_todo_plans.rb app/models/turn_todo_plan.rb test/models/turn_todo_plan_test.rb
git commit -m "feat: add turn todo plan model"
```

### Task 2: Add the `TurnTodoPlanItem` schema and item contract

**Files:**
- Modify: `core_matrix/db/migrate/20260406110000_create_turn_todo_plans.rb`
- Create: `core_matrix/app/models/turn_todo_plan_item.rb`
- Test: `core_matrix/test/models/turn_todo_plan_item_test.rb`

**Step 1: Write the failing item test**

Add a test that proves:

- item statuses are limited to `pending in_progress completed blocked canceled failed`
- `item_key` is unique per plan
- delegated subagent sessions must belong to the plan conversation
- `depends_on_item_keys` must be an array

```ruby
test "validates item key uniqueness and delegated subagent alignment" do
  fixture = build_turn_todo_plan_fixture!

  fixture.fetch(:plan).turn_todo_plan_items.create!(
    installation: fixture.fetch(:installation),
    item_key: "define-domain",
    title: "Define the plan domain",
    status: "completed",
    position: 0,
    kind: "implementation",
    details_payload: {},
    depends_on_item_keys: []
  )

  duplicate = fixture.fetch(:plan).turn_todo_plan_items.new(
    installation: fixture.fetch(:installation),
    item_key: "define-domain",
    title: "Duplicate",
    status: "pending",
    position: 1,
    kind: "implementation",
    details_payload: {},
    depends_on_item_keys: []
  )

  assert_not duplicate.valid?
  assert_includes duplicate.errors[:item_key], "has already been taken"
end
```

**Step 2: Run the test to verify it fails**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/models/turn_todo_plan_item_test.rb
```

Expected: FAIL because the item model and table do not exist.

**Step 3: Add the table shape and item model**

Create `turn_todo_plan_items` with:

- `turn_todo_plan_id`
- `installation_id`
- `item_key`
- `title`
- `status`
- `position`
- `kind`
- `details_payload`
- `delegated_subagent_session_id`
- `depends_on_item_keys`
- `last_status_changed_at`

Implement the validations from the test and add:

- `belongs_to :turn_todo_plan`
- `belongs_to :delegated_subagent_session, optional: true`
- installation and conversation alignment checks

**Step 4: Run the model test to verify it passes**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare test test/models/turn_todo_plan_item_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
git add db/migrate/20260406110000_create_turn_todo_plans.rb app/models/turn_todo_plan_item.rb test/models/turn_todo_plan_item_test.rb
git commit -m "feat: add turn todo plan items"
```

### Task 3: Add the plan update application service

**Files:**
- Create: `core_matrix/app/services/turn_todo_plans/apply_update.rb`
- Create: `core_matrix/app/services/turn_todo_plans/build_counts.rb`
- Test: `core_matrix/test/services/turn_todo_plans/apply_update_test.rb`

**Step 1: Write the failing service test**

Add a test that proves a full plan snapshot:

- creates the plan head when missing
- replaces current items by `item_key`
- updates `current_item_key`
- recalculates counts payload

```ruby
test "replaces the mutable plan head from a full snapshot" do
  fixture = build_turn_todo_plan_owner_fixture!

  TurnTodoPlans::ApplyUpdate.call(
    agent_task_run: fixture.fetch(:agent_task_run),
    payload: {
      "goal_summary" => "Replace old plan pathways",
      "current_item_key" => "remove-legacy",
      "items" => [
        { "item_key" => "define-domain", "title" => "Define new plan model", "status" => "completed", "position" => 0, "kind" => "implementation" },
        { "item_key" => "remove-legacy", "title" => "Remove AgentTaskPlanItem", "status" => "in_progress", "position" => 1, "kind" => "implementation" }
      ]
    },
    occurred_at: Time.current
  )

  plan = fixture.fetch(:agent_task_run).reload.turn_todo_plan
  assert_equal "Replace old plan pathways", plan.goal_summary
  assert_equal "remove-legacy", plan.current_item_key
  assert_equal 2, plan.turn_todo_plan_items.count
  assert_equal 1, plan.counts_payload.fetch("completed")
  assert_equal 1, plan.counts_payload.fetch("in_progress")
end
```

**Step 2: Run the test to verify it fails**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/turn_todo_plans/apply_update_test.rb
```

Expected: FAIL because the service does not exist.

**Step 3: Write the service**

Implement `TurnTodoPlans::ApplyUpdate` to:

- load or create the current plan head for the owner task
- validate the incoming payload
- replace all current plan items
- compute counts via `TurnTodoPlans::BuildCounts`
- update the plan head atomically

Do not generate feed yet in this task.

**Step 4: Run the service test to verify it passes**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare test test/services/turn_todo_plans/apply_update_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
git add app/services/turn_todo_plans/apply_update.rb app/services/turn_todo_plans/build_counts.rb test/services/turn_todo_plans/apply_update_test.rb
git commit -m "feat: apply turn todo plan updates"
```

### Task 4: Route execution reports through `turn_todo_plan_update`

**Files:**
- Modify: `core_matrix/app/services/agent_control/handle_execution_report.rb`
- Create: `core_matrix/test/services/agent_control/handle_execution_report_turn_todo_plan_test.rb`
- Modify later for cleanup: `core_matrix/app/services/agent_control/apply_supervision_update.rb`

**Step 1: Write the failing report test**

Add a test that proves `execution_progress.progress_payload.turn_todo_plan_update`:

- updates the owner task's current `TurnTodoPlan`
- does not require `supervision_update.plan_items`
- refreshes the conversation supervision projection

```ruby
test "execution_progress applies turn_todo_plan_update through the dedicated plan path" do
  context = build_agent_control_context!
  scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)

  report_execution_started!(
    deployment: context.fetch(:deployment),
    mailbox_item: scenario.fetch(:mailbox_item),
    agent_task_run: scenario.fetch(:agent_task_run)
  )

  AgentControl::HandleExecutionReport.call(
    deployment: context.fetch(:deployment),
    method_id: "execution_progress",
    payload: {
      "mailbox_item_id" => scenario.fetch(:mailbox_item).public_id,
      "agent_task_run_id" => scenario.fetch(:agent_task_run).public_id,
      "logical_work_id" => scenario.fetch(:agent_task_run).logical_work_id,
      "attempt_no" => scenario.fetch(:agent_task_run).attempt_no,
      "progress_payload" => {
        "turn_todo_plan_update" => {
          "goal_summary" => "Route plan updates through the new domain",
          "current_item_key" => "wire-supervision",
          "items" => [
            { "item_key" => "define-domain", "title" => "Define the new plan model", "status" => "completed", "position" => 0, "kind" => "implementation" },
            { "item_key" => "wire-supervision", "title" => "Wire plan views into supervision", "status" => "in_progress", "position" => 1, "kind" => "implementation" }
          ]
        }
      }
    },
    occurred_at: Time.current
  )

  plan = scenario.fetch(:agent_task_run).reload.turn_todo_plan
  assert_equal "wire-supervision", plan.current_item_key
  assert_equal %w[define-domain wire-supervision], plan.turn_todo_plan_items.order(:position).pluck(:item_key)
end
```

**Step 2: Run the test to verify it fails**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/agent_control/handle_execution_report_turn_todo_plan_test.rb
```

Expected: FAIL because the report handler does not route the new payload.

**Step 3: Implement the report routing**

Update `HandleExecutionReport#handle_execution_progress!` to:

- detect `turn_todo_plan_update`
- call `TurnTodoPlans::ApplyUpdate`
- keep the rest of progress handling intact

Do not keep dual plan writing.

**Step 4: Run the report test to verify it passes**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare test test/services/agent_control/handle_execution_report_turn_todo_plan_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
git add app/services/agent_control/handle_execution_report.rb test/services/agent_control/handle_execution_report_turn_todo_plan_test.rb
git commit -m "feat: route execution reports through turn todo plan updates"
```

### Task 5: Rebuild canonical feed generation around plan diffs

**Files:**
- Modify: `core_matrix/app/models/conversation_supervision_feed_entry.rb`
- Modify: `core_matrix/app/services/conversation_supervision/append_feed_entries.rb`
- Create: `core_matrix/app/services/turn_todo_plans/build_feed_changeset.rb`
- Test: `core_matrix/test/services/turn_todo_plans/build_feed_changeset_test.rb`
- Test: `core_matrix/test/services/conversation_supervision/append_feed_entries_test.rb`

**Step 1: Write the failing feed diff test**

Add a test that proves old/new plan heads produce canonical event kinds:

- `turn_todo_item_started`
- `turn_todo_item_completed`
- `turn_todo_item_delegated`

```ruby
test "builds canonical feed entries from old and new plan snapshots" do
  changeset = TurnTodoPlans::BuildFeedChangeset.call(
    previous_plan: {
      "goal_summary" => "Replace legacy plan paths",
      "current_item_key" => "define-domain",
      "items" => [
        { "item_key" => "define-domain", "title" => "Define new plan", "status" => "in_progress", "position" => 0 }
      ]
    },
    current_plan: {
      "goal_summary" => "Replace legacy plan paths",
      "current_item_key" => "wire-supervision",
      "items" => [
        { "item_key" => "define-domain", "title" => "Define new plan", "status" => "completed", "position" => 0 },
        { "item_key" => "wire-supervision", "title" => "Wire supervision", "status" => "in_progress", "position" => 1 }
      ]
    },
    occurred_at: Time.current
  )

  assert_equal %w[turn_todo_item_completed turn_todo_item_started], changeset.map { |entry| entry.fetch("event_kind") }
end
```

**Step 2: Run the tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/turn_todo_plans/build_feed_changeset_test.rb test/services/conversation_supervision/append_feed_entries_test.rb
```

Expected: FAIL because the new canonical feed diff path does not exist.

**Step 3: Implement the new feed path**

- narrow `ConversationSupervisionFeedEntry::EVENT_KINDS` to the new canonical set
- make `AppendFeedEntries` accept only canonical changesets
- implement `TurnTodoPlans::BuildFeedChangeset`
- invoke it from `TurnTodoPlans::ApplyUpdate`

Do not keep `progress_recorded`, `subagent_started`, or `subagent_completed` in the new path.

**Step 4: Run the tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare test test/services/turn_todo_plans/build_feed_changeset_test.rb test/services/conversation_supervision/append_feed_entries_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
git add app/models/conversation_supervision_feed_entry.rb app/services/conversation_supervision/append_feed_entries.rb app/services/turn_todo_plans/build_feed_changeset.rb test/services/turn_todo_plans/build_feed_changeset_test.rb test/services/conversation_supervision/append_feed_entries_test.rb
git commit -m "feat: generate canonical supervision feed entries from plan diffs"
```

### Task 6: Rebuild conversation supervision projection around plan views

**Files:**
- Modify: `core_matrix/app/services/conversations/update_supervision_state.rb`
- Create: `core_matrix/app/services/turn_todo_plans/build_view.rb`
- Create: `core_matrix/app/services/turn_todo_plans/build_compact_view.rb`
- Test: `core_matrix/test/services/conversations/update_supervision_state_test.rb`
- Test: `core_matrix/test/services/turn_todo_plans/build_view_test.rb`

**Step 1: Write the failing projection test**

Add a test that proves `UpdateSupervisionState`:

- reads the active owner's `TurnTodoPlan`
- projects `current_focus_summary` from the plan current item
- exposes compact primary and child plan summaries in `status_payload`

```ruby
test "projects supervision summaries from the active turn todo plan" do
  fixture = build_supervision_with_turn_todo_plan_fixture!

  state = Conversations::UpdateSupervisionState.call(
    conversation: fixture.fetch(:conversation),
    occurred_at: Time.current
  )

  assert_equal "Replace AgentTaskPlanItem with TurnTodoPlan", state.request_summary
  assert_equal "Wire plan views into supervision", state.current_focus_summary
  assert_equal "active", state.board_lane
  assert_equal "wire-supervision", state.status_payload.fetch("current_turn_plan_summary").fetch("current_item_key")
end
```

**Step 2: Run the tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/conversations/update_supervision_state_test.rb test/services/turn_todo_plans/build_view_test.rb
```

Expected: FAIL because supervision still reads the old plan path.

**Step 3: Implement the new projection**

- add `TurnTodoPlans::BuildView`
- add `TurnTodoPlans::BuildCompactView`
- update `UpdateSupervisionState` to consume current owner and child plan views
- stop reading legacy `AgentTaskPlanItem` state

**Step 4: Run the tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare test test/services/conversations/update_supervision_state_test.rb test/services/turn_todo_plans/build_view_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
git add app/services/conversations/update_supervision_state.rb app/services/turn_todo_plans/build_view.rb app/services/turn_todo_plans/build_compact_view.rb test/services/conversations/update_supervision_state_test.rb test/services/turn_todo_plans/build_view_test.rb
git commit -m "feat: project conversation supervision from turn todo plans"
```

### Task 7: Rebuild snapshot, machine status, and sidechat payloads

**Files:**
- Modify: `core_matrix/app/services/embedded_agents/conversation_supervision/build_snapshot.rb`
- Modify: `core_matrix/app/services/embedded_agents/conversation_supervision/build_machine_status.rb`
- Modify: `core_matrix/app/services/embedded_agents/conversation_supervision/build_human_sidechat.rb`
- Modify: `core_matrix/app/services/embedded_agents/conversation_supervision/build_human_summary.rb`
- Test: `core_matrix/test/services/embedded_agents/conversation_supervision/responders/builtin_test.rb`
- Test: `core_matrix/test/services/embedded_agents/conversation_supervision/append_message_test.rb`

**Step 1: Write the failing responder test**

Add a test that proves snapshot and sidechat use frozen plan views:

- current work comes from primary current item
- subagent answers come from child plan views
- recent change comes from turn feed
- old `active_plan_items` is absent

```ruby
test "supervision sidechat answers from frozen turn todo plan views" do
  fixture = prepare_conversation_supervision_context_with_turn_todo_plan!
  session = create_conversation_supervision_session!(fixture)
  snapshot = EmbeddedAgents::ConversationSupervision::BuildSnapshot.call(
    actor: fixture.fetch(:user),
    conversation_supervision_session: session
  )

  response = EmbeddedAgents::ConversationSupervision::Responders::Builtin.call(
    conversation_supervision_session: session,
    conversation_supervision_snapshot: snapshot,
    question: "What are you doing right now?"
  )

  assert_includes response.dig("human_sidechat", "content"), "Wire plan views into supervision"
  assert_nil response.fetch("machine_status")["active_plan_items"]
end
```

**Step 2: Run the tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/embedded_agents/conversation_supervision/responders/builtin_test.rb test/services/embedded_agents/conversation_supervision/append_message_test.rb
```

Expected: FAIL because snapshot and sidechat still use legacy plan payloads.

**Step 3: Implement the new payloads**

- freeze `primary_turn_todo_plan_view`
- freeze `active_subagent_turn_todo_plan_views`
- freeze `turn_feed`
- rebuild machine status to expose plan-centric payloads
- rebuild human summary builders to answer from frozen plan views and feed

**Step 4: Run the tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare test test/services/embedded_agents/conversation_supervision/responders/builtin_test.rb test/services/embedded_agents/conversation_supervision/append_message_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
git add app/services/embedded_agents/conversation_supervision/build_snapshot.rb app/services/embedded_agents/conversation_supervision/build_machine_status.rb app/services/embedded_agents/conversation_supervision/build_human_sidechat.rb app/services/embedded_agents/conversation_supervision/build_human_summary.rb test/services/embedded_agents/conversation_supervision/responders/builtin_test.rb test/services/embedded_agents/conversation_supervision/append_message_test.rb
git commit -m "feat: freeze and render supervision from turn todo plan views"
```

### Task 8: Add stable API contracts for plan views and turn feed

**Files:**
- Modify: `core_matrix/app/controllers/app_api/conversation_supervision_sessions_controller.rb`
- Modify: `core_matrix/app/controllers/app_api/conversation_supervision_messages_controller.rb`
- Create: `core_matrix/app/controllers/app_api/conversation_turn_todo_plans_controller.rb`
- Create: `core_matrix/app/controllers/app_api/conversation_turn_feeds_controller.rb`
- Modify: `core_matrix/config/routes.rb`
- Test: `core_matrix/test/requests/app_api/conversation_turn_todo_plans_controller_test.rb`
- Test: `core_matrix/test/requests/app_api/conversation_turn_feeds_controller_test.rb`

**Step 1: Write the failing request tests**

Add request tests that prove:

- current plan view can be listed for the conversation
- active child plans are included
- turn feed returns canonical new event kinds

```ruby
test "lists the current turn todo plan view for a supervised conversation" do
  fixture = build_conversation_supervision_api_fixture_with_turn_todo_plan!

  get app_api_conversation_turn_todo_plans_path(conversation_id: fixture.fetch(:conversation).public_id)

  assert_response :success
  body = JSON.parse(response.body)
  assert_equal "wire-supervision", body.fetch("primary_turn_todo_plan").fetch("current_item_key")
end
```

**Step 2: Run the tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/requests/app_api/conversation_turn_todo_plans_controller_test.rb test/requests/app_api/conversation_turn_feeds_controller_test.rb
```

Expected: FAIL because the new API endpoints do not exist.

**Step 3: Implement the controllers and routes**

- expose stable plan view JSON
- expose turn feed JSON
- keep supervision message/session controllers aligned with the new snapshot payload

**Step 4: Run the request tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare test test/requests/app_api/conversation_turn_todo_plans_controller_test.rb test/requests/app_api/conversation_turn_feeds_controller_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
git add app/controllers/app_api/conversation_supervision_sessions_controller.rb app/controllers/app_api/conversation_supervision_messages_controller.rb app/controllers/app_api/conversation_turn_todo_plans_controller.rb app/controllers/app_api/conversation_turn_feeds_controller.rb config/routes.rb test/requests/app_api/conversation_turn_todo_plans_controller_test.rb test/requests/app_api/conversation_turn_feeds_controller_test.rb
git commit -m "feat: expose turn todo plan and feed api contracts"
```

### Task 9: Delete the legacy plan path and tighten anti-regression coverage

**Files:**
- Delete: `core_matrix/app/models/agent_task_plan_item.rb`
- Delete: `core_matrix/app/services/agent_task_runs/replace_plan_items.rb`
- Modify: `core_matrix/app/services/agent_control/apply_supervision_update.rb`
- Modify: `core_matrix/app/models/agent_task_run.rb`
- Modify: `core_matrix/test/services/agent_control/handle_execution_report_test.rb`
- Create: `core_matrix/test/integration/turn_todo_plan_cleanup_contract_test.rb`

**Step 1: Write the failing cleanup contract test**

Add a test that proves:

- `supervision_update.plan_items` is rejected
- legacy `active_plan_items` payloads are absent
- canonical feed no longer emits `progress_recorded`

```ruby
test "rejects legacy plan updates and old feed semantics" do
  context = build_agent_control_context!
  scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)

  report_execution_started!(
    deployment: context.fetch(:deployment),
    mailbox_item: scenario.fetch(:mailbox_item),
    agent_task_run: scenario.fetch(:agent_task_run)
  )

  assert_raises(ArgumentError) do
    AgentControl::HandleExecutionReport.call(
      deployment: context.fetch(:deployment),
      method_id: "execution_progress",
      payload: {
        "mailbox_item_id" => scenario.fetch(:mailbox_item).public_id,
        "agent_task_run_id" => scenario.fetch(:agent_task_run).public_id,
        "logical_work_id" => scenario.fetch(:agent_task_run).logical_work_id,
        "attempt_no" => scenario.fetch(:agent_task_run).attempt_no,
        "progress_payload" => {
          "supervision_update" => {
            "plan_items" => [
              { "item_key" => "legacy", "title" => "Legacy path", "status" => "pending", "position" => 0 }
            ]
          }
        }
      },
      occurred_at: Time.current
    )
  end
end
```

**Step 2: Run the test to verify it fails**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/integration/turn_todo_plan_cleanup_contract_test.rb
```

Expected: FAIL because the legacy path is still accepted.

**Step 3: Delete the old plan path**

- remove the old model and service
- remove old associations from `AgentTaskRun`
- reject old plan payloads explicitly
- update fixtures and tests to stop referring to legacy plan items

**Step 4: Run the cleanup tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare test test/integration/turn_todo_plan_cleanup_contract_test.rb test/services/agent_control/handle_execution_report_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
git add app/services/agent_control/apply_supervision_update.rb app/models/agent_task_run.rb test/services/agent_control/handle_execution_report_test.rb test/integration/turn_todo_plan_cleanup_contract_test.rb
git rm app/models/agent_task_plan_item.rb app/services/agent_task_runs/replace_plan_items.rb
git commit -m "refactor: delete legacy supervision plan path"
```

### Task 10: Run verification and close the documentation loop

**Files:**
- Modify: `core_matrix/docs/plans/2026-04-06-turn-todo-plan-supervision-design.md`
- Modify as needed: any touched tests or docs from prior tasks

**Step 1: Run focused verification checkpoints**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/models/turn_todo_plan_test.rb test/models/turn_todo_plan_item_test.rb test/services/turn_todo_plans/apply_update_test.rb test/services/turn_todo_plans/build_feed_changeset_test.rb test/services/conversations/update_supervision_state_test.rb test/services/embedded_agents/conversation_supervision/responders/builtin_test.rb test/requests/app_api/conversation_turn_todo_plans_controller_test.rb test/requests/app_api/conversation_turn_feeds_controller_test.rb test/integration/turn_todo_plan_cleanup_contract_test.rb
```

Expected: PASS.

**Step 2: Run project verification**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails db:test:prepare test
bin/rails db:test:prepare test:system
```

Expected: PASS.

**Step 3: Refresh the design doc if implementation changed a contract**

Update the design doc only if the implementation forced a contract change.

**Step 4: Commit the verification or doc follow-up**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
git add docs/plans/2026-04-06-turn-todo-plan-supervision-design.md
git commit -m "docs: finalize turn todo plan supervision design"
```
