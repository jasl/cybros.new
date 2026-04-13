# Supervision Feed Todo Projection-First Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the app-facing supervision feed and todo-plan endpoints
projection-first by removing synchronous supervision refresh and runtime-derived
fallbacks from those request paths.

**Architecture:** The feed and todo-plan controllers will stop calling
`Conversations::UpdateSupervisionState`. Feed selection will rely only on
persisted conversation anchors and feed entries. Todo-plan selection will read
the persisted `ConversationSupervisionState` owner and only materialize a
persisted `TurnTodoPlan` when that owner is an `agent_task_run`.

**Tech Stack:** Ruby on Rails, Active Record, Minitest,
`ConversationSupervisionState`, `ConversationSupervisionFeedEntry`,
`TurnTodoPlan`.

---

### Task 1: Lock Projection-First Request Contracts In Feed And Todo Tests

**Files:**
- Modify: `core_matrix/test/requests/app_api/conversation_turn_feeds_controller_test.rb`
- Modify: `core_matrix/test/requests/app_api/conversation_turn_todo_plans_controller_test.rb`

**Step 1: Write failing feed request tests**

Extend `conversation_turn_feeds_controller_test.rb` so it expects:

- the endpoint still returns persisted feed entries when they already exist
- the endpoint preserves queued pending-turn supervision without forcing a fresh
  `ConversationSupervisionState` recompute
- missing anchors return `items = []`

Add a contract test that would fail if the request still depended on
`Conversations::UpdateSupervisionState` to populate the response.

**Step 2: Write failing todo-plan request tests**

Extend `conversation_turn_todo_plans_controller_test.rb` so it expects:

- the endpoint still returns the persisted plan when supervision state points at
  an `agent_task_run`
- queued pending-turn supervision still returns no primary todo plan
- missing supervision state returns no primary todo plan instead of synthesizing
  one from runtime scans

**Step 3: Run request tests to verify red**

Run:

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/requests/app_api/conversation_turn_feeds_controller_test.rb \
  test/requests/app_api/conversation_turn_todo_plans_controller_test.rb
```

Expected: failures showing the old request path still relies on synchronous
supervision refresh and runtime-derived fallback.

### Task 2: Lock Projection Readers Against Runtime Fallback

**Files:**
- Modify: `core_matrix/test/services/conversation_supervision/build_activity_feed_test.rb`
- Modify: `core_matrix/test/services/conversation_supervision/build_current_turn_todo_test.rb`

**Step 1: Write failing feed reader tests**

Add coverage to `build_activity_feed_test.rb` for:

- returning `[]` when both `latest_active_turn_id` and `latest_turn_id` are nil
- not scanning `turns` as a fallback in that case

**Step 2: Write failing todo reader tests**

Add coverage to `build_current_turn_todo_test.rb` for:

- returning the persisted plan when `conversation_supervision_state` points to
  an `agent_task_run`
- returning an empty projection when the state is missing
- returning an empty projection when `current_owner_kind` is not
  `agent_task_run`

**Step 3: Run service tests to verify red**

Run:

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/services/conversation_supervision/build_activity_feed_test.rb \
  test/services/conversation_supervision/build_current_turn_todo_test.rb
```

Expected: failures showing `BuildActivityFeed` still falls back to `turns`
scans and `BuildCurrentTurnTodo` still queries runtime task state directly.

### Task 3: Remove Synchronous Refresh From Feed And Todo Controllers

**Files:**
- Modify: `core_matrix/app/controllers/app_api/conversations/feeds_controller.rb`
- Modify: `core_matrix/app/controllers/app_api/conversations/todo_plans_controller.rb`
- Modify: `core_matrix/test/requests/app_api/conversation_turn_feeds_controller_test.rb`
- Modify: `core_matrix/test/requests/app_api/conversation_turn_todo_plans_controller_test.rb`

**Step 1: Remove request-time supervision refresh**

Delete the `Conversations::UpdateSupervisionState.call(...)` invocation from:

- `FeedsController#show`
- `TodoPlansController#show`

Keep the response payload shape unchanged.

**Step 2: Run request tests and confirm the controllers are green**

Run:

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/requests/app_api/conversation_turn_feeds_controller_test.rb \
  test/requests/app_api/conversation_turn_todo_plans_controller_test.rb
```

Expected: request tests still fail only where projection readers still rely on
runtime fallback.

### Task 4: Make `BuildActivityFeed` Anchor-Only

**Files:**
- Modify: `core_matrix/app/services/conversation_supervision/build_activity_feed.rb`
- Modify: `core_matrix/test/services/conversation_supervision/build_activity_feed_test.rb`
- Modify: `core_matrix/test/requests/app_api/conversation_turn_feeds_controller_test.rb`

**Step 1: Remove turn-table fallback scanning**

Change `BuildActivityFeed#feed_turn_id` so it only uses:

- `conversation.latest_active_turn_id`
- else `conversation.latest_turn_id`
- else `nil`

Do not query `conversation.turns` inside this service anymore.

**Step 2: Keep serialization behavior stable**

Do not change the feed entry payload shape when entries exist.

Only change the empty case:

- missing anchors now mean `[]`

**Step 3: Run feed tests and verify green**

Run:

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/services/conversation_supervision/build_activity_feed_test.rb \
  test/requests/app_api/conversation_turn_feeds_controller_test.rb
```

Expected: feed reads are now projection-first and no longer scan turns.

### Task 5: Make `BuildCurrentTurnTodo` State-First For App-Facing Reads

**Files:**
- Modify: `core_matrix/app/services/conversation_supervision/build_current_turn_todo.rb`
- Modify: `core_matrix/test/services/conversation_supervision/build_current_turn_todo_test.rb`
- Modify: `core_matrix/test/requests/app_api/conversation_turn_todo_plans_controller_test.rb`

**Step 1: Resolve the current task from persisted supervision state**

Update `BuildCurrentTurnTodo` so it:

- first checks `conversation.conversation_supervision_state`
- only loads a task run if:
  - the state exists
  - `current_owner_kind == "agent_task_run"`
  - `current_owner_public_id` is present
- finds the task by `public_id`
- returns the persisted `turn_todo_plan` for that task when present

If any of those conditions fail, return the existing empty projection.

**Step 2: Remove runtime active-task fallback from the app-facing path**

Do not query “latest active task run” as an implicit fallback inside
`BuildCurrentTurnTodo`.

The service should become state-first for this read path.

**Step 3: Run todo-plan tests and verify green**

Run:

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/services/conversation_supervision/build_current_turn_todo_test.rb \
  test/requests/app_api/conversation_turn_todo_plans_controller_test.rb
```

Expected: todo-plan reads now follow persisted supervision state and accept
empty results when projection is absent or stale.

### Task 6: Verify Query Budgets And Wider Supervision Regression Coverage

**Files:**
- Modify as needed: `core_matrix/test/requests/app_api/conversation_turn_feeds_controller_test.rb`
- Modify as needed: `core_matrix/test/requests/app_api/conversation_turn_todo_plans_controller_test.rb`
- Modify as needed: `core_matrix/test/services/conversations/update_supervision_state_test.rb`
- Modify as needed: `core_matrix/test/services/conversation_supervision/build_board_card_test.rb`
- Modify as needed: `core_matrix/test/services/conversation_supervision/list_board_cards_test.rb`

**Step 1: Rebaseline request query budgets if they move**

Measure and update the SQL budgets for:

- `GET /feed`
- `GET /todo_plan`

Only after the behavior is correct.

**Step 2: Run focused supervision regression suite**

Run:

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/requests/app_api/conversation_turn_feeds_controller_test.rb \
  test/requests/app_api/conversation_turn_todo_plans_controller_test.rb \
  test/services/conversation_supervision/build_activity_feed_test.rb \
  test/services/conversation_supervision/build_current_turn_todo_test.rb \
  test/services/conversations/update_supervision_state_test.rb \
  test/services/conversation_supervision/build_board_card_test.rb \
  test/services/conversation_supervision/list_board_cards_test.rb
```

Expected: all focused supervision/feed/todo coverage is green.

**Step 3: Run full verification**

Run:

```bash
bin/rails test
```

Expected: full suite passes with no regression in supervision projections.
