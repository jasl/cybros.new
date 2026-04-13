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
- Modify: `test/services/runtime_capabilities/preview_for_conversation_test.rb`
- Modify: `test/services/conversations/update_override_test.rb`
- Modify: `test/services/subagent_connections/send_message_test.rb`
- Modify: `test/services/conversation_bundle_imports/rehydrate_conversation_test.rb`

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

**Step 5: Lock the pre-execution preview/configuration boundary**

In `test/services/runtime_capabilities/preview_for_conversation_test.rb`, add
coverage that a bare conversation can be previewed without materializing
execution continuity:

- `ConversationExecutionEpoch.count` does not change
- `conversation.reload.current_execution_epoch` stays `nil`
- `conversation.reload.execution_continuity_state == "not_started"`

In `test/services/conversations/update_override_test.rb`, add the same contract
for override updates on a bare conversation:

- override persistence still succeeds
- no epoch is created
- continuity state stays `not_started`

**Step 6: Lock auxiliary first-entry write paths before implementation**

In `test/services/subagent_connections/send_message_test.rb`, add coverage
that a fresh child conversation starts in `not_started` and transitions to
`ready` on the first delivery when `SubagentConnections::SendMessage.call`
creates the first completed turn.

In `test/services/conversation_bundle_imports/rehydrate_conversation_test.rb`,
add coverage that rehydration leaves the imported conversation with:

- `current_execution_epoch` present
- `execution_continuity_state == "ready"`
- a single current epoch reused across the imported turn set

These assertions should exist before the write-path refactor so the later
service changes are guarded by tests instead of inferred from ad hoc manual
checks.

**Step 7: Run targeted tests and verify they fail for the right reasons**

Run from `/Users/jasl/Workspaces/Ruby/cybros/core_matrix`:

```bash
bin/rails test \
  test/services/conversations/create_root_test.rb \
  test/services/conversations/create_automation_root_test.rb \
  test/services/conversations/creation_support_test.rb \
  test/services/conversation_execution_epochs/initialize_current_test.rb \
  test/services/turns/freeze_execution_identity_test.rb \
  test/services/app_surface/presenters/conversation_presenter_test.rb \
  test/services/runtime_capabilities/preview_for_conversation_test.rb \
  test/services/conversations/update_override_test.rb \
  test/services/subagent_connections/send_message_test.rb \
  test/services/conversation_bundle_imports/rehydrate_conversation_test.rb \
  test/requests/app_api/conversations_test.rb
```

Expected: failures showing the eager epoch callback is still active, the state
is still `ready`, or the first-turn override path still bootstraps the wrong
runtime order. The new rehydrate assertions may already pass if they only check
final continuity state, but they should still be landed before implementation
changes so the imported-turn path remains covered throughout the refactor.

**Step 8: Commit**

```bash
git add \
  test/services/conversations/create_root_test.rb \
  test/services/conversations/create_automation_root_test.rb \
  test/services/conversations/creation_support_test.rb \
  test/services/conversation_execution_epochs/initialize_current_test.rb \
  test/services/turns/freeze_execution_identity_test.rb \
  test/services/app_surface/presenters/conversation_presenter_test.rb \
  test/services/runtime_capabilities/preview_for_conversation_test.rb \
  test/services/conversations/update_override_test.rb \
  test/services/subagent_connections/send_message_test.rb \
  test/services/conversation_bundle_imports/rehydrate_conversation_test.rb \
  test/requests/app_api/conversations_test.rb
git commit -m "test: lock lazy execution epoch bootstrap contract"
```

### Task 2: Move Conversation Bootstrap to `not_started`

**Files:**
- Modify: `app/models/conversation.rb`

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
  app/models/conversation.rb
git commit -m "refactor: make conversations start without execution epoch"
```

### Task 3: Make `Turn.execution_epoch` Explicit and Update Direct Epoch Consumers

**Files:**
- Modify: `app/models/turn.rb`
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

**Step 1: Remove the implicit turn-epoch fallback**

In `app/models/turn.rb`, delete:

```ruby
before_validation :default_execution_epoch
```

and remove:

```ruby
def default_execution_epoch
  return if execution_epoch.present?
  return unless conversation.present?

  self.execution_epoch = conversation.current_execution_epoch
end
```

Under the destructive-refactor rules for this round, `Turn` should no longer
silently copy `conversation.current_execution_epoch`. The real app write paths
already pass `execution_epoch:` explicitly. Keeping the fallback would preserve
hidden assumptions and make lazy-bootstrap regressions harder to detect.

**Step 2: Fix direct current-epoch assumptions in request and service tests**

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

**Step 3: Fix direct `Turn.create!` and fixture paths**

Several model and service tests create turns directly instead of going through
`Turns::FreezeExecutionIdentity`. With the implicit fallback removed, audit
those paths and choose one of two patterns explicitly:

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

**Step 4: Run the direct-construction regression set**

Run:

```bash
bin/rails test \
  test/models/turn_test.rb \
  test/requests/app_api/conversation_messages_test.rb \
  test/services/workbench/send_message_test.rb \
  test/services/turns/select_execution_runtime_test.rb \
  test/models/conversation_execution_epoch_test.rb \
  test/models/process_run_test.rb \
  test/services/conversations/metadata/bootstrap_title_test.rb \
  test/services/conversation_supervision/build_activity_feed_test.rb \
  test/services/conversation_supervision/prune_feed_window_test.rb
```

Expected: PASS with no lingering assumption that every bare conversation already
has a current epoch.

**Step 5: Commit**

```bash
git add \
  app/models/turn.rb \
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
git commit -m "refactor: remove implicit turn execution epoch fallback"
```

### Task 4: Separate Read-Only Execution Context Resolution From Epoch Bootstrap

**Files:**
- Create: `app/services/conversations/resolve_execution_context.rb`
- Modify: `app/services/runtime_capabilities/preview_for_conversation.rb`
- Modify: `app/services/conversations/update_override.rb`
- Create: `test/services/conversations/resolve_execution_context_test.rb`
- Modify: `test/services/runtime_capabilities/preview_for_conversation_test.rb`
- Modify: `test/services/conversations/update_override_test.rb`

**Step 1: Introduce a read-only execution context resolver**

Create `app/services/conversations/resolve_execution_context.rb` as the
pre-execution-safe companion to `Turns::FreezeExecutionIdentity`.

It should resolve:

- `agent_definition_version`
- `execution_runtime`
- `execution_runtime_version`

from:

- the active `AgentConnection` for the conversation's `agent_id`
- the conversation's configured `current_execution_runtime`, or an explicit
  `execution_runtime:` override supplied by the caller

without calling `ConversationExecutionEpochs::InitializeCurrent`.

Keep the error shape compatible with current callers:

- missing active agent connection should still add an error to the conversation
  and raise `ActiveRecord::RecordInvalid`
- callers that tolerate unavailable runtimes should still be able to receive
  `nil` runtime / runtime version without creating an epoch

Design it as the single source of truth for:

- `agent_definition_version`
- `execution_runtime`
- `execution_runtime_version`

so `Turns::FreezeExecutionIdentity` can reuse it later instead of keeping a
parallel lookup path.

**Step 2: Move preview reads onto the read-only resolver**

In `app/services/runtime_capabilities/preview_for_conversation.rb`, replace the
`Turns::FreezeExecutionIdentity` dependency with the new read-only resolver.

Preserve the existing preview semantics:

- the selected runtime is still surfaced when available
- missing runtime versions can still be tolerated for preview
- no synthetic turn is created
- no execution epoch is materialized

**Step 3: Move override schema lookup onto the read-only resolver**

In `app/services/conversations/update_override.rb`, resolve the active
`agent_definition_version` through the new read-only resolver instead of
`Turns::FreezeExecutionIdentity`.

Override validation must keep working on a bare conversation without changing:

- `current_execution_epoch_id`
- `execution_continuity_state`

**Step 4: Run the preview/configuration regression set**

Run:

```bash
bin/rails test \
  test/services/conversations/resolve_execution_context_test.rb \
  test/services/runtime_capabilities/preview_for_conversation_test.rb \
  test/services/conversations/update_override_test.rb
```

Expected: PASS with no epoch materialization on bare-conversation preview or
override updates.

**Step 5: Commit**

```bash
git add \
  app/services/conversations/resolve_execution_context.rb \
  app/services/runtime_capabilities/preview_for_conversation.rb \
  app/services/conversations/update_override.rb \
  test/services/conversations/resolve_execution_context_test.rb \
  test/services/runtime_capabilities/preview_for_conversation_test.rb \
  test/services/conversations/update_override_test.rb
git commit -m "refactor: separate read-only execution context resolution"
```

### Task 5: Make Epoch Initialization the Only Continuity Bootstrap

**Files:**
- Modify: `app/services/conversation_execution_epochs/initialize_current.rb`
- Modify: `app/services/conversation_execution_epochs/retarget_current.rb`
- Modify: `test/services/conversation_execution_epochs/initialize_current_test.rb`
- Create: `test/services/conversation_execution_epochs/retarget_current_test.rb`

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

**Step 3: Make `RetargetCurrent` retarget-only**

In `app/services/conversation_execution_epochs/retarget_current.rb`, remove the
lazy-bootstrap fallback:

```ruby
epoch = @conversation.current_execution_epoch
```

and replace it with a strict precondition:

- if `current_execution_epoch` is blank, add an error to the conversation and
  raise `ActiveRecord::RecordInvalid`
- otherwise retarget the existing epoch and keep the conversation in `ready`

This is a better fit for the destructive-refactor goal because continuity
creation stays centralized in `InitializeCurrent`. `RetargetCurrent` should no
longer hide missing-bootstrap bugs.

**Step 4: Run the epoch service tests**

Run:

```bash
bin/rails test \
  test/services/conversation_execution_epochs/initialize_current_test.rb \
  test/services/conversation_execution_epochs/retarget_current_test.rb
```

Expected: PASS with explicit `not_started -> ready` transition coverage and a
strict retarget-only contract.

**Step 5: Commit**

```bash
git add \
  app/services/conversation_execution_epochs/initialize_current.rb \
  app/services/conversation_execution_epochs/retarget_current.rb \
  test/services/conversation_execution_epochs/initialize_current_test.rb \
  test/services/conversation_execution_epochs/retarget_current_test.rb
git commit -m "refactor: lazy bootstrap conversation execution epochs"
```

### Task 6: Reorder `FreezeExecutionIdentity` Around the Resolved Runtime

**Files:**
- Modify: `app/services/turns/freeze_execution_identity.rb`
- Modify: `test/services/turns/freeze_execution_identity_test.rb`
- Modify: `test/services/turns/start_user_turn_test.rb`
- Modify: `test/requests/app_api/conversations_test.rb`

**Step 1: Split runtime choice from epoch initialization**

Refactor `resolve_execution_runtime` so it does not eagerly call
`InitializeCurrent` before deciding whether a first-turn override should apply.
After runtime choice is complete, have `Turns::FreezeExecutionIdentity` reuse
`Conversations::ResolveExecutionContext` for agent/runtime/version lookup
instead of manually repeating that logic.

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

Then, after runtime resolution, resolve the shared execution context and
initialize the epoch if needed:

```ruby
execution_context = Conversations::ResolveExecutionContext.call(
  conversation: @conversation,
  execution_runtime: resolve_execution_runtime,
  allow_unavailable_execution_runtime: @allow_unavailable_execution_runtime
)
execution_runtime = execution_context.execution_runtime
execution_epoch =
  @conversation.current_execution_epoch ||
  ConversationExecutionEpochs::InitializeCurrent.call(
    conversation: @conversation,
    execution_runtime: execution_runtime
  )
```

and build the returned identity from `execution_context` plus the materialized
`execution_epoch`, instead of directly reading `@conversation.current_execution_epoch`
and independently resolving runtime version.

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

### Task 7: Update Schema Defaults and Regenerate `db/schema.rb`

**Files:**
- Modify: `db/migrate/20260324090019_create_conversations.rb`
- Modify: `db/schema.rb`

**Step 1: Rewrite the original schema default**

In `db/migrate/20260324090019_create_conversations.rb`, change the
`execution_continuity_state` default from `"ready"` to `"not_started"`.

Do not add a new forward migration for this pre-launch change. Keep the schema
history consistent with the current optimization-round workflow.

**Step 2: Regenerate the schema from a clean database**

Run:

```bash
rails db:drop && rm db/schema.rb && rails db:create && rails db:migrate && rails db:reset
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
  db/migrate/20260324090019_create_conversations.rb \
  db/schema.rb
git commit -m "db: default conversations to not_started continuity"
```

### Task 8: Verify Broader Turn Entry, Re-Baseline Query Budgets, And Sync Behavior Docs

**Files:**
- Modify: `test/services/turns/start_user_turn_test.rb`
- Modify: `test/services/turns/start_automation_turn_test.rb`
- Modify: `test/services/turns/start_agent_turn_test.rb`
- Modify: `test/services/turns/queue_follow_up_test.rb`
- Modify: `test/services/subagent_connections/send_message_test.rb`
- Modify: `test/services/conversation_bundle_imports/rehydrate_conversation_test.rb`
- Modify: `test/services/workbench/send_message_test.rb`
- Modify: `test/requests/app_api/conversation_messages_test.rb`
- Modify: `docs/behavior/turn-entry-and-selector-state.md`
- Modify: `docs/behavior/conversation-structure-and-lineage.md`
- Modify: `docs/plans/2026-04-13-execution-epoch-lazy-bootstrap-design.md`

**Step 1: Keep regression coverage for non-user turn paths green**

Update the automation, agent, follow-up, subagent-delivery, and import
rehydration tests so they still assert the right post-bootstrap contract.

For the standard turn-entry services, keep asserting:

- created turns have `execution_epoch` present
- the owning conversation ends in `ready` after turn creation

Keep the existing user-turn assertions that `turn.execution_epoch` matches
`conversation.current_execution_epoch` after turn creation.

For `test/services/subagent_connections/send_message_test.rb`, add coverage
that the first delivery to a fresh child conversation:

- initializes `current_execution_epoch`
- transitions the child conversation from `not_started` to `ready`
- keeps later deliveries on the same epoch

For `test/services/conversation_bundle_imports/rehydrate_conversation_test.rb`,
add coverage that the first imported turn:

- bootstraps the imported conversation into `ready`
- leaves `current_execution_epoch` present at the end of rehydration
- reuses a single current epoch across the imported turn set

This protects the shared `FreezeExecutionIdentity` path across all turn-entry
surfaces.

**Step 2: Re-baseline the SQL budget tests that move with lazy bootstrap**

Do not assume the old budgets still hold.

Re-measure and update the explicit SQL ceiling tests for:

- `test/services/turns/start_user_turn_test.rb`
- `test/services/turns/start_automation_turn_test.rb`
- `test/services/turns/start_agent_turn_test.rb`
- `test/services/subagent_connections/send_message_test.rb`
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
  test/services/subagent_connections/send_message_test.rb \
  test/services/conversation_bundle_imports/rehydrate_conversation_test.rb \
  test/services/workbench/send_message_test.rb \
  test/services/conversations/resolve_execution_context_test.rb \
  test/services/runtime_capabilities/preview_for_conversation_test.rb \
  test/services/conversations/update_override_test.rb \
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
- `SubagentConnections::SendMessage`
- `Turns::StartUserTurn`

Expected:

- `Conversations::CreateRoot` query count decreases
- `Conversations::CreateAutomationRoot` query count decreases
- `Workbench::CreateConversationFromAgent` changes little or only slightly,
  because the first turn still happens in the same request
- `SubagentConnections::SendMessage` may increase on the first delivery into a
  fresh child conversation because epoch bootstrap now happens there
- `Turns::StartUserTurn` may increase slightly because epoch bootstrap now
  happens there on first entry

Capture the observed before/after counts in this design doc so the next round
of optimization work starts from measured reality.

**Step 5: Sync behavior docs to the landed contract**

Update:

- `docs/behavior/turn-entry-and-selector-state.md`
- `docs/behavior/conversation-structure-and-lineage.md`

so they explicitly describe:

- bare conversations start in `not_started`
- `current_execution_runtime_id` may exist before any epoch exists
- first-turn override initializes the first epoch directly on the resolved
  runtime instead of initializing then retargeting
- preview/configuration surfaces use read-only context resolution and must not
  materialize continuity

**Step 6: Commit**

```bash
git add \
  test/services/turns/start_user_turn_test.rb \
  test/services/turns/start_automation_turn_test.rb \
  test/services/turns/start_agent_turn_test.rb \
  test/services/turns/queue_follow_up_test.rb \
  test/services/subagent_connections/send_message_test.rb \
  test/services/conversation_bundle_imports/rehydrate_conversation_test.rb \
  test/services/workbench/send_message_test.rb \
  test/requests/app_api/conversation_messages_test.rb \
  docs/behavior/turn-entry-and-selector-state.md \
  docs/behavior/conversation-structure-and-lineage.md \
  docs/plans/2026-04-13-execution-epoch-lazy-bootstrap-design.md
git commit -m "test: verify lazy epoch bootstrap across turn entry paths"
```

### Out Of Scope For This Plan

Even under destructive-refactor rules, do not silently fold the following into
this implementation pass:

- removing `ConversationCapabilityPolicy` as a table
- deferring root `LineageStore` bootstrap
- lazily freezing `AgentTaskRun` tool bindings

Those are plausible follow-on optimization tracks, but they change different
contracts and deserve separate design and execution docs after the
execution-epoch work lands cleanly.
