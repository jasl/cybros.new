# Turn Todo Plan Supervision Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace summary-derived supervision progress reporting with an explicit turn-scoped todo plan domain that powers UI checklist rendering, turn feed entries, and supervision conversation answers.

**Architecture:** Introduce `TurnTodoPlan` and `TurnTodoPlanItem` as the only plan truth for active `AgentTaskRun` work, including child-agent work. Persist the plan head with an explicit `agent_task_run_id` foreign key, route execution-time plan updates through a dedicated `turn_todo_plan_update` payload, rebuild conversation supervision to consume plan views, then switch feed generation to canonical plan-diff events and delete the old `AgentTaskPlanItem` and `supervision_update.plan_items` pathways. Do not introduce a second structured execution-item domain; any future Codex-style inline "worked for" or "explored files" affordances must render from existing workflow/runtime projections instead.

**Tech Stack:** Rails 8.2, Active Record/Postgres, JSONB/public-id boundaries, Minitest, app API request tests, supervision services under `app/services`

---

## Execution Notes

- Use an explicit `agent_task_run_id` foreign key for `TurnTodoPlan`; do not
  use a polymorphic owner column.
- Add database-level cascading cleanup from `agent_task_runs` to
  `turn_todo_plans` and from `turn_todo_plans` to `turn_todo_plan_items`.
- This repo's Rails commands do not accept combined forms like
  `bin/rails db:test:prepare test ...`; run `db:test:prepare` and `test`
  as separate commands.
- When a task adds or edits migrations, run `bin/rails db:migrate` before the
  focused test command so pending development migrations do not block test
  boot.
- This is a multi-database Rails app. If you need to replay an already-applied
  migration while iterating locally, use the namespaced task such as
  `bin/rails db:migrate:redo:primary VERSION=...`.
- Stage `core_matrix/db/schema.rb` in the same commit as any migration change.
- Do not switch canonical feed kinds until supervision projection, snapshot,
  machine status, and summary responders have all stopped reading
  `active_plan_items`.
- Legacy cleanup must include code, tests, purge/lifecycle paths, and behavior
  docs. The implementation is not complete while
  `AgentTaskPlanItem`-centric docs remain.
- The `2048` full acceptance bundle is a hard gate. Internal tests passing is
  insufficient if exported supervision artifacts still look generic or fail to
  reflect the actual work that happened during the turn.
- Acceptance artifact rendering is part of this implementation scope. Do not
  defer the acceptance contract itself until the end.
- Create a feature branch before Task 1. Do not start this implementation on
  `main`.
- Execute a small Batch 0 before Task 1:
  - pull forward Task 10 Step 1 and Step 2
  - add explicit failing `2048` bundle-quality assertions
  - run the acceptance scenario once to capture the expected failing baseline
- Treat the `2048` hard gate as "wired in from the start and required to pass
  at the end," not as "already passing before Task 1 begins."

### Task 1: Add the `TurnTodoPlan` schema and model contract

**Files:**
- Create: `core_matrix/db/migrate/20260406110000_create_turn_todo_plans.rb`
- Create: `core_matrix/app/models/turn_todo_plan.rb`
- Modify: `core_matrix/app/models/agent_task_run.rb`
- Test: `core_matrix/test/models/turn_todo_plan_test.rb`

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
    agent_task_run: agent_task_run,
    conversation: agent_task_run.conversation,
    turn: agent_task_run.turn,
    status: "active",
    goal_summary: "Rebuild supervision around turn todo plans",
    current_item_key: "define-domain",
    counts_payload: {}
  )

  duplicate = TurnTodoPlan.new(
    installation: agent_task_run.installation,
    agent_task_run: agent_task_run,
    conversation: agent_task_run.conversation,
    turn: agent_task_run.turn,
    status: "active",
    goal_summary: "Second active plan",
    current_item_key: "duplicate",
    counts_payload: {}
  )

  assert_not duplicate.valid?
  assert_includes duplicate.errors[:agent_task_run], "already has an active turn todo plan"
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
- `agent_task_run_id`
- `conversation_id`
- `turn_id`
- `status`
- `goal_summary`
- `current_item_key`
- `counts_payload`
- `closed_at`
- timestamps

Model rules:

- `belongs_to :agent_task_run`
- unique active plan per owner
- counts payload must be a hash
- database foreign key should cascade on task deletion

Add the corresponding `has_one :turn_todo_plan, dependent: :delete` to
`AgentTaskRun`, while keeping the database foreign key cascade as the source of
truth for owner cleanup.

**Step 4: Run the model test to verify it passes**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:migrate
bin/rails db:test:prepare
bin/rails test test/models/turn_todo_plan_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
git add db/migrate/20260406110000_create_turn_todo_plans.rb db/schema.rb app/models/turn_todo_plan.rb app/models/agent_task_run.rb test/models/turn_todo_plan_test.rb
git commit -m "feat: add turn todo plan model"
```

**Guardrail:** Do not create companion execution-item tables or models while
adding the plan domain. This task is only about the explicit turn todo plan.

### Task 2: Add the `TurnTodoPlanItem` schema and item contract

**Files:**
- Modify: `core_matrix/db/migrate/20260406110000_create_turn_todo_plans.rb`
- Modify: `core_matrix/app/models/turn_todo_plan.rb`
- Create: `core_matrix/app/models/turn_todo_plan_item.rb`
- Test: `core_matrix/test/models/turn_todo_plan_item_test.rb`

**Step 1: Write the failing item test**

Add a test that proves:

- item statuses are limited to `pending in_progress completed blocked canceled failed`
- `item_key` is unique per plan
- delegated subagent connections must belong to the plan conversation
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
- `delegated_subagent_connection_id`
- `depends_on_item_keys`
- `last_status_changed_at`

Implement the validations from the test and add:

- `belongs_to :turn_todo_plan`
- `belongs_to :delegated_subagent_connection, optional: true`
- installation and conversation alignment checks
- database foreign key should cascade on plan deletion

**Step 4: Run the model test to verify it passes**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:migrate:redo:primary VERSION=20260406110000
bin/rails db:test:prepare
bin/rails test test/models/turn_todo_plan_item_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
git add db/migrate/20260406110000_create_turn_todo_plans.rb db/schema.rb app/models/turn_todo_plan.rb app/models/turn_todo_plan_item.rb test/models/turn_todo_plan_item_test.rb
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

**Guardrail:** Keep this service scoped to `TurnTodoPlan` and
`TurnTodoPlanItem`. Do not extend it into a generic structured execution-item
pipeline.

**Step 3: Write the service**

Implement `TurnTodoPlans::ApplyUpdate` to:

- load or create the current plan head for the target `AgentTaskRun`
- validate the incoming payload
- replace all current plan items
- compute counts via `TurnTodoPlans::BuildCounts`
- update the plan head atomically

Do not generate feed yet in this task.

**Step 4: Run the service test to verify it passes**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
bin/rails test test/services/turn_todo_plans/apply_update_test.rb
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
    agent snapshot: context.fetch(:agent snapshot),
    mailbox_item: scenario.fetch(:mailbox_item),
    agent_task_run: scenario.fetch(:agent_task_run)
  )

  AgentControl::HandleExecutionReport.call(
    agent snapshot: context.fetch(:agent snapshot),
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
bin/rails db:test:prepare
bin/rails test test/services/agent_control/handle_execution_report_turn_todo_plan_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
git add app/services/agent_control/handle_execution_report.rb test/services/agent_control/handle_execution_report_turn_todo_plan_test.rb
git commit -m "feat: route execution reports through turn todo plan updates"
```

### Task 5: Rebuild conversation supervision projection around plan views

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
bin/rails db:test:prepare
bin/rails test test/services/conversations/update_supervision_state_test.rb test/services/turn_todo_plans/build_view_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
git add app/services/conversations/update_supervision_state.rb app/services/turn_todo_plans/build_view.rb app/services/turn_todo_plans/build_compact_view.rb test/services/conversations/update_supervision_state_test.rb test/services/turn_todo_plans/build_view_test.rb
git commit -m "feat: project conversation supervision from turn todo plans"
```

### Task 6: Rebuild snapshot, machine status, and responder payloads

**Files:**
- Modify: `core_matrix/app/services/embedded_agents/conversation_supervision/build_snapshot.rb`
- Modify: `core_matrix/app/services/embedded_agents/conversation_supervision/build_machine_status.rb`
- Modify: `core_matrix/app/services/embedded_agents/conversation_supervision/build_human_sidechat.rb`
- Modify: `core_matrix/app/services/embedded_agents/conversation_supervision/build_human_summary.rb`
- Modify: `core_matrix/app/services/embedded_agents/conversation_supervision/responders/summary_model.rb`
- Test: `core_matrix/test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb`
- Test: `core_matrix/test/services/embedded_agents/conversation_supervision/responders/builtin_test.rb`
- Test: `core_matrix/test/services/embedded_agents/conversation_supervision/append_message_test.rb`

**Step 1: Write the failing responder test**

Add tests that prove snapshot and responders use frozen plan views:

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
bin/rails test test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb test/services/embedded_agents/conversation_supervision/responders/builtin_test.rb test/services/embedded_agents/conversation_supervision/append_message_test.rb
```

Expected: FAIL because snapshot and responders still use legacy plan payloads.

**Step 3: Implement the new payloads**

- freeze `primary_turn_todo_plan_view`
- freeze `active_subagent_turn_todo_plan_views`
- freeze `turn_feed`
- rebuild machine status to expose plan-centric payloads
- rebuild human summary builders to answer from frozen plan views and feed
- update `Responders::SummaryModel` so modeled replies consume plan-centric
  machine status instead of `active_plan_items`

**Step 4: Run the tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
bin/rails test test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb test/services/embedded_agents/conversation_supervision/responders/builtin_test.rb test/services/embedded_agents/conversation_supervision/append_message_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
git add app/services/embedded_agents/conversation_supervision/build_snapshot.rb app/services/embedded_agents/conversation_supervision/build_machine_status.rb app/services/embedded_agents/conversation_supervision/build_human_sidechat.rb app/services/embedded_agents/conversation_supervision/build_human_summary.rb app/services/embedded_agents/conversation_supervision/responders/summary_model.rb test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb test/services/embedded_agents/conversation_supervision/responders/builtin_test.rb test/services/embedded_agents/conversation_supervision/append_message_test.rb
git commit -m "feat: freeze and render supervision from turn todo plan views"
```

### Task 7: Rebuild canonical feed generation and remove old emitters

**Files:**
- Modify: `core_matrix/app/models/conversation_supervision_feed_entry.rb`
- Modify: `core_matrix/app/services/conversation_supervision/append_feed_entries.rb`
- Modify: `core_matrix/app/services/agent_control/apply_supervision_update.rb`
- Modify: `core_matrix/app/services/conversations/update_supervision_state.rb`
- Create: `core_matrix/app/services/turn_todo_plans/build_feed_changeset.rb`
- Test: `core_matrix/test/models/conversation_supervision_feed_entry_test.rb`
- Test: `core_matrix/test/services/turn_todo_plans/build_feed_changeset_test.rb`
- Test: `core_matrix/test/services/conversation_supervision/append_feed_entries_test.rb`
- Test: `core_matrix/test/services/conversation_supervision/build_activity_feed_test.rb`
- Test: `core_matrix/test/services/conversation_supervision/publish_update_test.rb`

**Step 1: Write the failing feed diff tests**

Add tests that prove:

- old/new plan heads produce canonical event kinds
- `progress_recorded`, `subagent_started`, and `subagent_completed` are no
  longer accepted feed kinds
- old emitters do not survive in `ApplySupervisionUpdate` or
  `UpdateSupervisionState`

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
bin/rails test test/models/conversation_supervision_feed_entry_test.rb test/services/turn_todo_plans/build_feed_changeset_test.rb test/services/conversation_supervision/append_feed_entries_test.rb test/services/conversation_supervision/build_activity_feed_test.rb test/services/conversation_supervision/publish_update_test.rb
```

Expected: FAIL because the canonical feed diff path does not exist and the old
feed kinds are still wired in.

**Step 3: Implement the canonical feed cutover**

- narrow `ConversationSupervisionFeedEntry::EVENT_KINDS` to the new canonical
  set
- make `AppendFeedEntries` accept only canonical changesets
- implement `TurnTodoPlans::BuildFeedChangeset`
- invoke it from `TurnTodoPlans::ApplyUpdate`
- remove `progress_recorded` feed emission from `ApplySupervisionUpdate`
- remove old semantic feed generation from `UpdateSupervisionState`

Do not keep `progress_recorded`, `subagent_started`, or `subagent_completed`
in the main path after this task.

**Step 4: Run the tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
bin/rails test test/models/conversation_supervision_feed_entry_test.rb test/services/turn_todo_plans/build_feed_changeset_test.rb test/services/conversation_supervision/append_feed_entries_test.rb test/services/conversation_supervision/build_activity_feed_test.rb test/services/conversation_supervision/publish_update_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
git add app/models/conversation_supervision_feed_entry.rb app/services/conversation_supervision/append_feed_entries.rb app/services/agent_control/apply_supervision_update.rb app/services/conversations/update_supervision_state.rb app/services/turn_todo_plans/build_feed_changeset.rb test/models/conversation_supervision_feed_entry_test.rb test/services/turn_todo_plans/build_feed_changeset_test.rb test/services/conversation_supervision/append_feed_entries_test.rb test/services/conversation_supervision/build_activity_feed_test.rb test/services/conversation_supervision/publish_update_test.rb
git commit -m "feat: generate canonical supervision feed entries from plan diffs"
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
- return only `public_id` values at API boundaries

**Step 4: Run the request tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
bin/rails test test/requests/app_api/conversation_turn_todo_plans_controller_test.rb test/requests/app_api/conversation_turn_feeds_controller_test.rb
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
- Create: `core_matrix/db/migrate/20260406120000_drop_agent_task_plan_items.rb`
- Delete: `core_matrix/app/models/agent_task_plan_item.rb`
- Delete: `core_matrix/app/services/agent_task_runs/replace_plan_items.rb`
- Modify: `core_matrix/app/services/agent_control/apply_supervision_update.rb`
- Modify: `core_matrix/app/models/agent_task_run.rb`
- Modify: `core_matrix/app/models/subagent_connection.rb`
- Modify: `core_matrix/app/services/conversations/purge_plan.rb`
- Modify: `core_matrix/docs/behavior/agent-progress-and-plan-items.md`
- Modify: `core_matrix/test/services/agent_control/handle_execution_report_test.rb`
- Modify: `core_matrix/test/support/conversation_supervision_fixture_builder.rb`
- Modify: `core_matrix/test/services/conversation_supervision/publish_update_test.rb`
- Create: `core_matrix/test/integration/turn_todo_plan_cleanup_contract_test.rb`

**Step 1: Write the failing cleanup contract test**

Add a test that proves:

- `supervision_update.plan_items` is rejected
- legacy `active_plan_items` payloads are absent
- canonical feed no longer emits `progress_recorded`
- lifecycle cleanup no longer depends on `AgentTaskPlanItem`

```ruby
test "rejects legacy plan updates and old feed semantics" do
  context = build_agent_control_context!
  scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)

  report_execution_started!(
    agent snapshot: context.fetch(:agent snapshot),
    mailbox_item: scenario.fetch(:mailbox_item),
    agent_task_run: scenario.fetch(:agent_task_run)
  )

  assert_raises(ArgumentError) do
    AgentControl::HandleExecutionReport.call(
      agent snapshot: context.fetch(:agent snapshot),
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

- add a migration that drops `agent_task_plan_items`
- remove the old model and service
- remove old associations from `AgentTaskRun`
- remove old delegated item associations from `SubagentConnection`
- reject old plan payloads explicitly
- update `Conversations::PurgePlan` to account for `TurnTodoPlan` ownership and
  cleanup
- update behavior docs to present `TurnTodoPlan` as the active product
  contract
- update fixtures and tests to stop referring to legacy plan items

**Step 4: Run the cleanup tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
bin/rails test test/integration/turn_todo_plan_cleanup_contract_test.rb test/services/agent_control/handle_execution_report_test.rb test/services/conversation_supervision/publish_update_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
git add db/migrate/20260406120000_drop_agent_task_plan_items.rb db/schema.rb app/services/agent_control/apply_supervision_update.rb app/models/agent_task_run.rb app/models/subagent_connection.rb app/services/conversations/purge_plan.rb docs/behavior/agent-progress-and-plan-items.md test/services/agent_control/handle_execution_report_test.rb test/support/conversation_supervision_fixture_builder.rb test/services/conversation_supervision/publish_update_test.rb test/integration/turn_todo_plan_cleanup_contract_test.rb
git rm app/models/agent_task_plan_item.rb app/services/agent_task_runs/replace_plan_items.rb
git commit -m "refactor: delete legacy supervision plan path"
```

### Task 10: Rebuild acceptance artifact rendering and add the `2048` hard gate

**Files:**
- Modify: `acceptance/lib/conversation_artifacts.rb`
- Modify: `acceptance/lib/turn_runtime_transcript.rb`
- Modify: `acceptance/lib/artifact_bundle.rb`
- Modify: `acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb`
- Modify as needed: `acceptance/README.md`

**Step 1: Write failing bundle-quality assertions**

Batching note:

- execute this step in Batch 0 before Task 1
- the goal is to establish the acceptance quality contract immediately, not to
  finish the acceptance rendering before core implementation starts

Update the `2048` acceptance scenario so it fails when the exported bundle:

- renders `Current focus: none` / `Recent progress: none` / `Active plan items: 0`
  as the dominant supervision story
- renders only generic lifecycle feed events instead of canonical plan-driven
  events
- fails to correlate supervision-facing markdown with underlying exported
  JSON/JSONL logs

Prefer explicit assertions in the scenario or a shared acceptance helper over
manual post-run inspection.

**Step 2: Run the acceptance scenario to verify it fails**

Batching note:

- execute this step in Batch 0 immediately after Step 1
- this is the expected red baseline that proves the hard gate is active before
  the main implementation work begins

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh
```

Expected: FAIL because the exported bundle still reflects the legacy
supervision contract and low-value content.

**Step 3: Rebuild the acceptance bundle around the new supervision contract**

Batching note:

- leave this step in its current place after the core `TurnTodoPlan`,
  supervision, feed, API, and cleanup work
- only the failing assertion baseline moves forward; the acceptance rendering
  rebuild stays here

- update `ConversationArtifacts` to read plan-centric machine status and
  canonical turn feed data instead of `active_plan_items`
- update the supervision markdown renderers so status, feed, and child work
  sections describe the current `TurnTodoPlan` truth
- keep `turn_runtime_transcript` runtime-first, but make its supervision
  sections line up with the same plan/focus/feed facts as the bundle review
  markdown
- update the bundle index/README wiring if the rendered artifacts or their
  descriptions need to change
- keep the export evidence grounded in raw JSON/JSONL logs rather than in
  regenerated prose

**Step 4: Run the acceptance scenario to verify it passes**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh
```

Expected: PASS, producing a fresh `2048` full bundle whose supervision status,
feed, and runtime transcript contain meaningful plan-driven evidence of the
actual turn work.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add acceptance/lib/conversation_artifacts.rb acceptance/lib/turn_runtime_transcript.rb acceptance/lib/artifact_bundle.rb acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb acceptance/README.md
git commit -m "feat: harden acceptance bundle supervision evidence"
```

### Task 11: Run verification and close the documentation loop

**Files:**
- Modify: `core_matrix/docs/plans/2026-04-06-turn-todo-plan-supervision-design.md`
- Modify as needed: any touched tests or docs from prior tasks

**Step 1: Run focused verification checkpoints**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/models/turn_todo_plan_test.rb test/models/turn_todo_plan_item_test.rb test/models/conversation_supervision_feed_entry_test.rb test/services/turn_todo_plans/apply_update_test.rb test/services/turn_todo_plans/build_view_test.rb test/services/turn_todo_plans/build_feed_changeset_test.rb test/services/agent_control/handle_execution_report_turn_todo_plan_test.rb test/services/conversations/update_supervision_state_test.rb test/services/conversation_supervision/append_feed_entries_test.rb test/services/conversation_supervision/build_activity_feed_test.rb test/services/conversation_supervision/publish_update_test.rb test/services/embedded_agents/conversation_supervision/build_snapshot_test.rb test/services/embedded_agents/conversation_supervision/responders/builtin_test.rb test/requests/app_api/conversation_turn_todo_plans_controller_test.rb test/requests/app_api/conversation_turn_feeds_controller_test.rb test/integration/turn_todo_plan_cleanup_contract_test.rb
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
bin/rails db:test:prepare
bin/rails test
bin/rails test:system
```

Expected: PASS.

**Step 3: Re-run the `2048` acceptance hard gate**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh
```

Expected: PASS, and the newly generated bundle must show:

- supervision status with meaningful current focus and plan progress
- supervision feed with canonical plan-driven events
- runtime transcript entries that line up with the supervision story
- raw exported logs that back the rendered markdown

If the command passes but the bundle remains low-information, the plan is not
complete and execution must continue.

**Step 4: Refresh the design doc if implementation changed a contract**

Update the design doc only if the implementation forced a contract change.

**Step 5: Commit the verification or doc follow-up**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/docs/plans/2026-04-06-turn-todo-plan-supervision-design.md acceptance/README.md
git commit -m "docs: finalize turn todo plan supervision design"
```
