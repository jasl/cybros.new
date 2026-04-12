# Conversation Execution Epoch Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace implicit previous-turn runtime continuity with explicit
conversation execution epochs and a conversation-first creation API.

**Architecture:** Add `ConversationExecutionEpoch` as the durable continuity
boundary, cache current execution state on `Conversation`, and keep frozen
runtime snapshot fields on `Turn` and `ProcessRun` for cheap historical reads.
Switch the app API to conversation-first creation and update turn entry to use
the conversation current epoch instead of prior-turn runtime inference.

**Tech Stack:** Rails 8.2, PostgreSQL, Active Record, Minitest, Action Cable

---

### Task 1: Add Execution Epoch Schema

**Files:**
- Modify: `core_matrix/db/migrate/20260324090019_create_conversations.rb`
- Modify: `core_matrix/db/migrate/20260324090021_create_turns.rb`
- Modify: `core_matrix/db/migrate/20260324090034_create_process_runs.rb`
- Modify: `core_matrix/db/schema.rb`

**Step 1: Write the failing test**

Add model or migration-facing tests that assert:

- a conversation can own many execution epochs
- the first epoch sequence is unique per conversation
- turns and process runs can reference an execution epoch

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/conversation_execution_epoch_test.rb`

**Step 3: Write minimal implementation**

Rewrite the foundational migrations to:

- create `conversation_execution_epochs`
- add `current_execution_epoch_id`, `current_execution_runtime_id`,
  `execution_continuity_state` to `conversations`
- add `execution_epoch_id` to `turns` and `process_runs`
- avoid separate transition logic entirely

Then rebuild the database from scratch so `db/schema.rb` reflects the cleaned-up
base history:

```bash
bin/rails db:drop && rm db/schema.rb && bin/rails db:create && bin/rails db:migrate && bin/rails db:reset
```

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/models/conversation_execution_epoch_test.rb`

**Step 5: Commit**

```bash
git add core_matrix/db/migrate core_matrix/db/schema.rb core_matrix/test/models/conversation_execution_epoch_test.rb
git commit -m "refactor: rewrite base execution epoch schema"
```

### Task 2: Add Models And Associations

**Files:**
- Create: `core_matrix/app/models/conversation_execution_epoch.rb`
- Modify: `core_matrix/app/models/conversation.rb`
- Modify: `core_matrix/app/models/turn.rb`
- Modify: `core_matrix/app/models/process_run.rb`
- Test: `core_matrix/test/models/conversation_execution_epoch_test.rb`
- Test: `core_matrix/test/models/turn_test.rb`
- Test: `core_matrix/test/models/process_run_test.rb`

**Step 1: Write the failing test**

Add tests for:

- `Conversation#current_execution_epoch`
- epoch uniqueness by `conversation_id + sequence`
- `Turn` requiring an execution epoch
- `ProcessRun` validating epoch, turn, and runtime consistency

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/conversation_execution_epoch_test.rb test/models/turn_test.rb test/models/process_run_test.rb`

**Step 3: Write minimal implementation**

Implement:

- model enums and validations for `ConversationExecutionEpoch`
- new associations on conversation, turn, and process run
- consistency validations between epoch, conversation, and runtime snapshots

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/models/conversation_execution_epoch_test.rb test/models/turn_test.rb test/models/process_run_test.rb`

**Step 5: Commit**

```bash
git add core_matrix/app/models core_matrix/test/models
git commit -m "feat: add execution epoch model contracts"
```

### Task 3: Create Epochs When Conversations Are Created

**Files:**
- Modify: `core_matrix/app/services/conversations/creation_support.rb`
- Create: `core_matrix/app/services/conversation_execution_epochs/initialize_current.rb`
- Test: `core_matrix/test/services/conversation_execution_epochs/initialize_current_test.rb`
- Test: `core_matrix/test/services/conversations/create_root_test.rb`

**Step 1: Write the failing test**

Add tests that assert new root conversations:

- create one initial execution epoch
- cache current execution state on the conversation row
- allow nil runtime when no runtime is available

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/conversation_execution_epochs/initialize_current_test.rb test/services/conversations/create_root_test.rb`

**Step 3: Write minimal implementation**

Create a service that:

- resolves the initial runtime preference
- creates epoch sequence `1`
- updates conversation current-execution cache fields

Call it from conversation creation support.

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/conversation_execution_epochs/initialize_current_test.rb test/services/conversations/create_root_test.rb`

**Step 5: Commit**

```bash
git add core_matrix/app/services/conversations core_matrix/app/services/conversation_execution_epochs core_matrix/test/services
git commit -m "feat: initialize execution epochs for conversations"
```

### Task 4: Replace Previous-Turn Runtime Inference

**Files:**
- Modify: `core_matrix/app/services/turns/select_execution_runtime.rb`
- Modify: `core_matrix/app/services/turns/freeze_execution_identity.rb`
- Modify: `core_matrix/app/services/turns/start_user_turn.rb`
- Modify: `core_matrix/core_matrix/docs/behavior/turn-entry-and-selector-state.md`
- Test: `core_matrix/test/services/workbench/send_message_test.rb`
- Test: `core_matrix/test/services/turns/start_user_turn_test.rb`

**Step 1: Write the failing test**

Add tests that assert:

- follow-up messages use the conversation current execution epoch
- prior-turn lookup is no longer the continuity source
- turns freeze runtime snapshot fields from the current epoch target

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/workbench/send_message_test.rb test/services/turns/start_user_turn_test.rb`

**Step 3: Write minimal implementation**

Refactor turn entry to:

- read `conversation.current_execution_epoch`
- assign `turn.execution_epoch`
- resolve runtime version from the runtime referenced by the current epoch

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/workbench/send_message_test.rb test/services/turns/start_user_turn_test.rb`

**Step 5: Commit**

```bash
git add core_matrix/app/services/turns core_matrix/test/services core_matrix/docs/behavior/turn-entry-and-selector-state.md
git commit -m "feat: drive turn continuity from execution epochs"
```

### Task 5: Move App API To Conversation-First Creation

**Files:**
- Create: `core_matrix/app/controllers/app_api/conversations_controller.rb`
- Modify: `core_matrix/app/controllers/app_api/conversation_messages_controller.rb`
- Modify: `core_matrix/app/services/workbench/create_conversation_from_agent.rb`
- Modify: `core_matrix/config/routes.rb`
- Modify: `core_matrix/app/services/app_surface/presenters/conversation_presenter.rb`
- Test: `core_matrix/test/requests/app_api/conversations_test.rb`
- Modify: `core_matrix/test/requests/app_api/conversation_messages_test.rb`
- Modify: `core_matrix/test/services/workbench/create_conversation_from_agent_test.rb`

**Step 1: Write the failing test**

Add request tests for:

- `POST /app_api/conversations`
- returned `current_execution_epoch_id`
- returned `current_execution_runtime_id`
- follow-up messages continuing on the current epoch

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/requests/app_api/conversations_test.rb test/requests/app_api/conversation_messages_test.rb test/services/workbench/create_conversation_from_agent_test.rb`

**Step 3: Write minimal implementation**

Implement the new controller and route, then remove the nested create path from
the primary app surface contract. Update presenters to expose current execution
summary from conversation cache fields.

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/requests/app_api/conversations_test.rb test/requests/app_api/conversation_messages_test.rb test/services/workbench/create_conversation_from_agent_test.rb`

**Step 5: Commit**

```bash
git add core_matrix/app/controllers/app_api core_matrix/app/services/workbench core_matrix/app/services/app_surface/presenters core_matrix/config/routes.rb core_matrix/test/requests/app_api core_matrix/test/services/workbench
git commit -m "feat: add conversation-first execution epoch API"
```

### Task 6: Wire Process Runs To Execution Epochs

**Files:**
- Modify: `core_matrix/app/services/processes/provision.rb`
- Modify: `core_matrix/app/models/process_run.rb`
- Test: `core_matrix/test/services/processes/provision_test.rb`
- Test: `core_matrix/test/models/process_run_test.rb`

**Step 1: Write the failing test**

Add tests asserting new process runs:

- inherit the turn execution epoch
- validate epoch, turn, conversation, and runtime alignment

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/processes/provision_test.rb test/models/process_run_test.rb`

**Step 3: Write minimal implementation**

Update provisioning and validations to persist `execution_epoch_id` on process
runs while preserving the frozen runtime snapshot fields.

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/processes/provision_test.rb test/models/process_run_test.rb`

**Step 5: Commit**

```bash
git add core_matrix/app/services/processes/provision.rb core_matrix/app/models/process_run.rb core_matrix/test/services/processes/provision_test.rb core_matrix/test/models/process_run_test.rb
git commit -m "feat: attach process runs to execution epochs"
```

### Task 7: Update Documentation And Focused Regression Coverage

**Files:**
- Modify: `core_matrix/docs/behavior/turn-entry-and-selector-state.md`
- Modify: `docs/research-notes/2026-04-13-conversation-execution-runtime-handoff-research-note.md`
- Modify: `docs/plans/2026-04-12-ssr-first-workbench-and-onboarding-design.md`
- Modify: `docs/plans/2026-04-12-ssr-first-workbench-and-onboarding.md`
- Test: focused request and service files touched above

**Step 1: Write the failing test**

Where needed, add or update tests that still assert the old nested create route
or previous-turn inference behavior.

**Step 2: Run test to verify it fails**

Run: the focused request and service suites touched above

**Step 3: Write minimal implementation**

Update docs and behavior notes to reflect:

- conversation-first creation
- execution-epoch continuity
- turn snapshot redundancy policy

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/requests/app_api/conversations_test.rb test/requests/app_api/conversation_messages_test.rb test/services/workbench/create_conversation_from_agent_test.rb test/services/workbench/send_message_test.rb test/services/processes/provision_test.rb test/models/conversation_execution_epoch_test.rb test/models/process_run_test.rb`

**Step 5: Commit**

```bash
git add docs core_matrix/docs core_matrix/test
git commit -m "docs: update execution epoch continuity design"
```
