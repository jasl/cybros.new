# Execution Epoch Lazy Bootstrap Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Keep `ConversationExecutionEpoch` as the execution continuity model, but stop creating it during conversation bootstrap so a conversation can exist in `not_started` state until the first real execution entry.

**Architecture:** `Conversation` continues to own the selected `current_execution_runtime_id`, while `ConversationExecutionEpoch` becomes lazily materialized state created by `Turns::FreezeExecutionIdentity` on first execution entry. `execution_continuity_state` becomes explicit: `not_started` means no current epoch exists yet, `ready` means the current epoch has been initialized and matches the cached runtime.

**Tech Stack:** Ruby on Rails, Active Record, PostgreSQL, Minitest, request tests under `test/requests`, service tests under `test/services`, schema migration under `db/migrate`, docs under `docs/plans`.

---

### Task 1: Lock Down the New Continuity Contract With Failing Tests

**Files:**
- Modify: `test/services/conversations/create_root_test.rb`
- Modify: `test/services/conversations/create_automation_root_test.rb`
- Modify: `test/services/conversations/creation_support_test.rb`
- Modify: `test/services/conversation_execution_epochs/initialize_current_test.rb`
- Create: `test/services/turns/freeze_execution_identity_test.rb`
- Modify: `test/requests/app_api/conversations_test.rb`
- Modify: `test/services/app_surface/presenters/conversation_presenter_test.rb`

**Step 1: Update bare conversation creation expectations**

In `test/services/conversations/create_root_test.rb`, change the interactive
root creation assertions so they expect:

- `conversation.current_execution_runtime` is still populated
- `conversation.current_execution_epoch` is `nil`
- `conversation.execution_epochs.count == 0`
- `conversation.execution_continuity_state == "not_started"`

The old assertions to remove are the ones that require a current epoch to exist
immediately after `Conversations::CreateRoot.call`.

In `test/services/conversations/create_automation_root_test.rb`, add the same
contract for automation roots:

- runtime may already be selected
- current epoch is absent
- continuity state is `not_started`

In `test/services/conversations/creation_support_test.rb`, add assertions that
fresh child conversation instances built from a parent:

- copy `current_execution_runtime`
- do not carry a current epoch
- default to `execution_continuity_state = "not_started"`

**Step 2: Add initialization transition assertions**

In `test/services/conversation_execution_epochs/initialize_current_test.rb`,
assert that:

- a conversation without an epoch starts in `not_started`
- `InitializeCurrent.call` creates sequence `1`
- the conversation reloads with `current_execution_epoch` set
- the conversation transitions to `execution_continuity_state == "ready"`

**Step 3: Add a first-turn override regression test**

Create `test/services/turns/freeze_execution_identity_test.rb` and make the
first-turn override test fail if
`ConversationExecutionEpochs::RetargetCurrent.call` is used during bootstrap.

Use the existing `with_redefined_singleton_method` pattern already present in
`test/lib/acceptance/manual_support_test.rb`, but do not assume the helper is
globally available. Either extract that helper into shared test support first
or define a small local equivalent in this new test file so the test locks the
intended control flow, not just the final state.

For example:

```ruby
require "test_helper"

class Turns::FreezeExecutionIdentityTest < ActiveSupport::TestCase
  test "initializes the first epoch directly on the requested runtime" do
    context = create_workspace_context!
    override_runtime = create_execution_runtime!(installation: context[:installation])
    create_execution_runtime_connection!(
      installation: context[:installation],
      execution_runtime: override_runtime
    )
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

    with_redefined_singleton_method(
      ConversationExecutionEpochs::RetargetCurrent,
      :call,
      ->(*) { raise "RetargetCurrent should not be called for first-turn override bootstrap" }
    ) do
      identity = Turns::FreezeExecutionIdentity.call(
        conversation: conversation,
        execution_runtime: override_runtime
      )

      assert_equal override_runtime, identity.execution_runtime
      assert_equal override_runtime, identity.execution_epoch.execution_runtime
      assert_equal 1, conversation.reload.execution_epochs.count
    end
  end
end
```

This test protects the reorder inside `FreezeExecutionIdentity`.

**Step 4: Preserve request and presenter contracts where the first turn exists**

In `test/requests/app_api/conversations_test.rb`, keep the conversation-first
endpoint assertions that the returned payload ends in:

- `execution_continuity_state == "ready"`
- `current_execution_epoch_id.present?`

In `test/services/app_surface/presenters/conversation_presenter_test.rb`, add a
bare-conversation assertion that the presenter emits:

- `current_execution_runtime_id` present
- `current_execution_epoch_id` absent
- `execution_continuity_state == "not_started"`

**Step 5: Run targeted tests and verify they fail for the right reasons**

Run from `/Users/jasl/Workspaces/Ruby/cybros/core_matrix`:

```bash
bin/rails test \
  test/services/conversations/create_root_test.rb \
  test/services/conversations/create_automation_root_test.rb \
  test/services/conversations/creation_support_test.rb \
  test/services/conversation_execution_epochs/initialize_current_test.rb \
  test/services/turns/freeze_execution_identity_test.rb \
  test/services/app_surface/presenters/conversation_presenter_test.rb \
  test/requests/app_api/conversations_test.rb
```

Expected: failures showing the eager epoch callback is still active, the state
is still `ready`, or the first-turn override path still bootstraps the wrong
runtime order.

**Step 6: Commit**

```bash
git add \
  test/services/conversations/create_root_test.rb \
  test/services/conversations/create_automation_root_test.rb \
  test/services/conversations/creation_support_test.rb \
  test/services/conversation_execution_epochs/initialize_current_test.rb \
  test/services/turns/freeze_execution_identity_test.rb \
  test/services/app_surface/presenters/conversation_presenter_test.rb \
  test/requests/app_api/conversations_test.rb
git commit -m "test: lock lazy execution epoch bootstrap contract"
```

### Task 2: Move Conversation Bootstrap to `not_started`

**Files:**
- Modify: `app/models/conversation.rb`
- Modify: `app/services/conversations/creation_support.rb`

**Step 1: Expand the continuity enum**

In `app/models/conversation.rb`, update:

```ruby
enum :execution_continuity_state,
  {
    not_started: "not_started",
    ready: "ready",
    handoff_pending: "handoff_pending",
    handoff_blocked: "handoff_blocked",
  },
  validate: true
```

**Step 2: Remove eager epoch creation**

Delete the callback and helper:

```ruby
after_create :ensure_initial_execution_epoch!
```

and remove:

```ruby
def ensure_initial_execution_epoch!
  ConversationExecutionEpochs::InitializeCurrent.call(conversation: self)
end
```

**Step 3: Change the default continuity state**

Update:

```ruby
def default_execution_continuity_state
  self.execution_continuity_state ||= "not_started"
end
```

Do not change `default_current_execution_runtime`; the runtime should still be
selected at container creation time.

**Step 4: Keep conversation creation lean**

In `app/services/conversations/creation_support.rb`, do not add any new epoch
logic. The desired end state after `Conversation.create!` remains:

- `current_execution_runtime` chosen
- `current_execution_epoch_id == nil`
- `execution_continuity_state == "not_started"`

**Step 5: Run the focused test set**

Run:

```bash
bin/rails test \
  test/services/conversations/create_root_test.rb \
  test/services/conversations/create_automation_root_test.rb \
  test/services/conversations/creation_support_test.rb \
  test/services/app_surface/presenters/conversation_presenter_test.rb
```

Expected: PASS for `not_started` semantics and nil current epoch on bare
conversation creation.

**Step 6: Commit**

```bash
git add \
  app/models/conversation.rb \
  app/services/conversations/creation_support.rb
git commit -m "refactor: make conversations start without execution epoch"
```

### Task 3: Update Direct Epoch Consumers and Test Support Before Touching Write Paths

**Files:**
- Modify: `test/requests/app_api/conversation_messages_test.rb`
- Modify: `test/services/workbench/send_message_test.rb`
- Modify: `test/services/turns/select_execution_runtime_test.rb`
- Modify: `test/models/conversation_execution_epoch_test.rb`
- Modify: `test/models/turn_test.rb`
- Modify: `test/models/process_run_test.rb`
- Modify: `test/services/conversations/metadata/bootstrap_title_test.rb`
- Modify: `test/services/conversation_supervision/build_activity_feed_test.rb`
- Modify: `test/services/conversation_supervision/prune_feed_window_test.rb`
- Modify: `test/test_helper.rb`

**Step 1: Fix direct current-epoch assumptions in request and service tests**

Update tests that currently do work like:

- `conversation.current_execution_epoch.update!(...)`
- `source_execution_epoch: conversation.current_execution_epoch`
- assertions that a bare `CreateRoot` always exposes a current epoch

The affected files already include:

- `test/requests/app_api/conversation_messages_test.rb`
- `test/services/workbench/send_message_test.rb`
- `test/services/turns/select_execution_runtime_test.rb`
- `test/models/conversation_execution_epoch_test.rb`

In these tests, initialize a current epoch explicitly with:

```ruby
ConversationExecutionEpochs::InitializeCurrent.call(conversation: conversation)
```

before reading or mutating `conversation.current_execution_epoch`.

**Step 2: Fix direct `Turn.create!` and fixture paths**

Several model and service tests create turns directly instead of going through
`Turns::FreezeExecutionIdentity`. Audit those paths and choose one of two
patterns explicitly:

- call `ConversationExecutionEpochs::InitializeCurrent.call(conversation:)`
  before constructing the turn, or
- pass `execution_epoch:` explicitly when creating the turn

The known affected files already include:

- `test/models/turn_test.rb`
- `test/models/process_run_test.rb`
- `test/services/conversations/metadata/bootstrap_title_test.rb`
- `test/services/conversation_supervision/build_activity_feed_test.rb`
- `test/services/conversation_supervision/prune_feed_window_test.rb`

If the same setup pattern repeats in several files, add a small test helper in
`test/test_helper.rb` instead of open-coding the initialization everywhere.

**Step 3: Run the direct-construction regression set**

Run:

```bash
bin/rails test \
  test/requests/app_api/conversation_messages_test.rb \
  test/services/workbench/send_message_test.rb \
  test/services/turns/select_execution_runtime_test.rb \
  test/models/conversation_execution_epoch_test.rb \
  test/models/turn_test.rb \
  test/models/process_run_test.rb \
  test/services/conversations/metadata/bootstrap_title_test.rb \
  test/services/conversation_supervision/build_activity_feed_test.rb \
  test/services/conversation_supervision/prune_feed_window_test.rb
```

Expected: PASS with no lingering assumption that every bare conversation already
has a current epoch.

**Step 4: Commit**

```bash
git add \
  test/requests/app_api/conversation_messages_test.rb \
  test/services/workbench/send_message_test.rb \
  test/services/turns/select_execution_runtime_test.rb \
  test/models/conversation_execution_epoch_test.rb \
  test/models/turn_test.rb \
  test/models/process_run_test.rb \
  test/services/conversations/metadata/bootstrap_title_test.rb \
  test/services/conversation_supervision/build_activity_feed_test.rb \
  test/services/conversation_supervision/prune_feed_window_test.rb \
  test/test_helper.rb
git commit -m "test: remove implicit current epoch assumptions"
```

### Task 4: Make Epoch Initialization the Only Continuity Bootstrap

**Files:**
- Modify: `app/services/conversation_execution_epochs/initialize_current.rb`
- Modify: `app/services/conversation_execution_epochs/retarget_current.rb`
- Modify: `test/services/conversation_execution_epochs/initialize_current_test.rb`

**Step 1: Preserve idempotent initialization**

Keep the early return:

```ruby
return @conversation.current_execution_epoch if @conversation.current_execution_epoch.present?
```

That guarantees repeated first-entry lookups do not create extra epochs.

**Step 2: Keep `InitializeCurrent` responsible for the state transition**

Ensure the service still writes:

```ruby
@conversation.update_columns(
  current_execution_epoch_id: epoch.id,
  current_execution_runtime_id: runtime&.id,
  execution_continuity_state: "ready"
)
```

This is the only point where a `not_started` conversation becomes `ready`.

**Step 3: Keep `RetargetCurrent` compatible with lazy bootstrap**

In `app/services/conversation_execution_epochs/retarget_current.rb`, preserve
the existing behavior that initializes an epoch when one is absent:

```ruby
epoch = @conversation.current_execution_epoch ||
  ConversationExecutionEpochs::InitializeCurrent.call(
    conversation: @conversation,
    execution_runtime: @execution_runtime
  )
```

This protects any direct caller that still reaches `RetargetCurrent` before an
epoch exists.

**Step 4: Run the epoch service tests**

Run:

```bash
bin/rails test test/services/conversation_execution_epochs/initialize_current_test.rb
```

Expected: PASS with explicit `not_started -> ready` transition coverage.

**Step 5: Commit**

```bash
git add \
  app/services/conversation_execution_epochs/initialize_current.rb \
  app/services/conversation_execution_epochs/retarget_current.rb \
  test/services/conversation_execution_epochs/initialize_current_test.rb
git commit -m "refactor: lazy bootstrap conversation execution epochs"
```

### Task 5: Reorder `FreezeExecutionIdentity` Around the Resolved Runtime

**Files:**
- Modify: `app/services/turns/freeze_execution_identity.rb`
- Modify: `test/services/turns/freeze_execution_identity_test.rb`
- Modify: `test/services/turns/start_user_turn_test.rb`
- Modify: `test/requests/app_api/conversations_test.rb`

**Step 1: Split runtime choice from epoch initialization**

Refactor `resolve_execution_runtime` so it does not eagerly call
`InitializeCurrent` before deciding whether a first-turn override should apply.

One safe shape is:

```ruby
def resolve_execution_runtime
  if @requested_execution_runtime.present?
    return @requested_execution_runtime if @conversation.current_execution_epoch.blank?
    return @requested_execution_runtime if @requested_execution_runtime == @conversation.current_execution_runtime

    if @conversation.turns.exists?
      @conversation.errors.add(:base, "conversation runtime handoff is not implemented yet")
      raise ActiveRecord::RecordInvalid, @conversation unless @allow_unavailable_execution_runtime
      return @requested_execution_runtime
    end

    ConversationExecutionEpochs::RetargetCurrent.call(
      conversation: @conversation,
      execution_runtime: @requested_execution_runtime
    )
    return @requested_execution_runtime
  end

  Turns::SelectExecutionRuntime.call(conversation: @conversation)
rescue ActiveRecord::RecordInvalid
  raise unless @allow_unavailable_execution_runtime
  nil
end
```

Then, after runtime resolution, initialize the epoch if needed:

```ruby
execution_runtime = resolve_execution_runtime
execution_epoch =
  @conversation.current_execution_epoch ||
  ConversationExecutionEpochs::InitializeCurrent.call(
    conversation: @conversation,
    execution_runtime: execution_runtime
  )
```

and return `execution_epoch:` from that variable instead of directly reading
`@conversation.current_execution_epoch`.

**Step 2: Keep unsupported handoff behavior unchanged**

Do not change the branch that rejects runtime switches after turns already
exist. This plan is about lazy bootstrap, not handoff semantics.

**Step 3: Run targeted first-turn tests**

Run:

```bash
bin/rails test \
  test/services/turns/freeze_execution_identity_test.rb \
  test/services/turns/start_user_turn_test.rb \
  test/requests/app_api/conversations_test.rb
```

Expected: PASS with the first epoch created directly on the requested runtime
and no regression in conversation-first request behavior.

**Step 4: Commit**

```bash
git add \
  app/services/turns/freeze_execution_identity.rb \
  test/services/turns/freeze_execution_identity_test.rb \
  test/services/turns/start_user_turn_test.rb \
  test/requests/app_api/conversations_test.rb
git commit -m "refactor: initialize first execution epoch on resolved runtime"
```

### Task 6: Update Database Defaults and Backfill Existing Rows

**Files:**
- Create: `db/migrate/20260413113000_change_conversation_execution_continuity_default.rb`
- Modify: `db/schema.rb`
- Modify: `test/services/conversations/create_root_test.rb`
- Modify: `test/services/conversations/create_automation_root_test.rb`
- Modify: `test/services/conversations/creation_support_test.rb`
- Modify: `test/services/app_surface/presenters/conversation_presenter_test.rb`

**Step 1: Add a forward migration**

Create `db/migrate/20260413113000_change_conversation_execution_continuity_default.rb`:

```ruby
class ChangeConversationExecutionContinuityDefault < ActiveRecord::Migration[8.2]
  def up
    change_column_default :conversations, :execution_continuity_state, from: "ready", to: "not_started"

    execute <<~SQL.squish
      UPDATE conversations
      SET execution_continuity_state = 'not_started'
      WHERE current_execution_epoch_id IS NULL
        AND execution_continuity_state = 'ready'
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE conversations
      SET execution_continuity_state = 'ready'
      WHERE execution_continuity_state = 'not_started'
    SQL

    change_column_default :conversations, :execution_continuity_state, from: "not_started", to: "ready"
  end
end
```

If the app's migration version differs, match the repo's current migration base
class version.

**Step 2: Run migrations and inspect the schema diff**

Run:

```bash
bin/rails db:migrate
git diff -- db/schema.rb
```

Expected: `db/schema.rb` shows the conversations table default changed to
`"not_started"`.

**Step 3: Re-run the targeted request/service tests**

Run:

```bash
bin/rails test \
  test/services/conversations/create_root_test.rb \
  test/services/conversations/create_automation_root_test.rb \
  test/services/conversations/creation_support_test.rb \
  test/services/app_surface/presenters/conversation_presenter_test.rb \
  test/requests/app_api/conversations_test.rb
```

Expected: PASS with database-backed defaults aligned to the model behavior.

**Step 4: Commit**

```bash
git add \
  db/migrate/20260413113000_change_conversation_execution_continuity_default.rb \
  db/schema.rb \
  test/services/conversations/create_root_test.rb \
  test/services/conversations/create_automation_root_test.rb \
  test/services/conversations/creation_support_test.rb \
  test/services/app_surface/presenters/conversation_presenter_test.rb \
  test/requests/app_api/conversations_test.rb
git commit -m "db: default conversations to not_started continuity"
```

### Task 7: Verify Broader Turn Entry and Re-Baseline Query Budgets

**Files:**
- Modify: `test/services/turns/start_user_turn_test.rb`
- Modify: `test/services/turns/start_automation_turn_test.rb`
- Modify: `test/services/turns/start_agent_turn_test.rb`
- Modify: `test/services/turns/queue_follow_up_test.rb`
- Modify: `test/services/workbench/send_message_test.rb`
- Modify: `test/requests/app_api/conversation_messages_test.rb`
- Modify: `docs/plans/2026-04-13-execution-epoch-lazy-bootstrap-design.md`

**Step 1: Add regression coverage for non-user turn paths**

Update the automation, agent, and follow-up turn tests so they still assert:

- created turns have `execution_epoch` present
- the owning conversation ends in `ready` after turn creation

Keep the existing user-turn assertions that `turn.execution_epoch` matches
`conversation.current_execution_epoch` after turn creation.

This protects the shared `FreezeExecutionIdentity` path across all turn-entry
surfaces.

**Step 2: Re-baseline the SQL budget tests that move with lazy bootstrap**

Do not assume the old budgets still hold.

Re-measure and update the explicit SQL ceiling tests for:

- `test/services/turns/start_user_turn_test.rb`
- `test/services/turns/start_automation_turn_test.rb`
- `test/services/turns/start_agent_turn_test.rb`
- `test/services/workbench/send_message_test.rb`
- `test/requests/app_api/conversation_messages_test.rb`

`test/services/turns/queue_follow_up_test.rb` should still be run, but it may
or may not need a budget change because the queued follow-up path already
starts from a conversation that has entered execution.

**Step 3: Run the wider targeted suite**

Run:

```bash
bin/rails test \
  test/services/turns/start_user_turn_test.rb \
  test/services/turns/start_automation_turn_test.rb \
  test/services/turns/start_agent_turn_test.rb \
  test/services/turns/queue_follow_up_test.rb \
  test/services/workbench/send_message_test.rb \
  test/requests/app_api/conversation_messages_test.rb \
  test/requests/app_api/conversations_test.rb
```

Expected: PASS with no turn-entry regression.

**Step 4: Re-measure the narrow SQL probes**

From `/Users/jasl/Workspaces/Ruby/cybros/core_matrix`, rerun the same probe used
during analysis for:

- `Conversations::CreateRoot`
- `Conversations::CreateAutomationRoot`
- `Workbench::CreateConversationFromAgent`
- `Turns::StartUserTurn`

Expected:

- `Conversations::CreateRoot` query count decreases
- `Conversations::CreateAutomationRoot` query count decreases
- `Workbench::CreateConversationFromAgent` changes little or only slightly,
  because the first turn still happens in the same request
- `Turns::StartUserTurn` may increase slightly because epoch bootstrap now
  happens there on first entry

Capture the observed before/after counts in this design doc so the next round
of optimization work starts from measured reality.

**Step 5: Commit**

```bash
git add \
  test/services/turns/start_user_turn_test.rb \
  test/services/turns/start_automation_turn_test.rb \
  test/services/turns/start_agent_turn_test.rb \
  test/services/turns/queue_follow_up_test.rb \
  test/services/workbench/send_message_test.rb \
  test/requests/app_api/conversation_messages_test.rb \
  docs/plans/2026-04-13-execution-epoch-lazy-bootstrap-design.md
git commit -m "test: verify lazy epoch bootstrap across turn entry paths"
```
