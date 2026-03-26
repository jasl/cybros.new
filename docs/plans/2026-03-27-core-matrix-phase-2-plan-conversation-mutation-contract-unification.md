# Core Matrix Phase 2 Conversation Mutation Contract Unification Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace legacy retained-state helpers with one explicit mutation-contract family and migrate every current live conversation mutation and turn timeline mutation entry point onto that family.

**Architecture:** Introduce shared `retained-only`, `live-mutation`, and `timeline-mutation` validators plus lock wrappers. Delete `Conversations::RetentionGuard` and `Turns::ValidateRewriteTarget`, migrate all current callers onto the new contracts, tighten archived and close-in-progress behavior for live mutations, then prove coverage with targeted tests, neighbor regressions, and final grep audits.

**Tech Stack:** Ruby on Rails (`core_matrix`), Active Record transactions and row locks, Minitest service and integration tests, grep-based audit checks, Phase 2 behavior docs

---

## Execution Rules

- I'm using the writing-plans skill to create the implementation plan.
- Treat this as a structural hardening batch, not as a patch for one or two
  services.
- Do not keep `Conversations::RetentionGuard` or `Turns::ValidateRewriteTarget`
  as compatibility layers.
- Every migrated service must choose one explicit contract:
  - retained-only
  - live conversation mutation
  - turn timeline mutation
- Shared contracts own lifecycle legality and lock/reload discipline only.
- Service-specific business rules must stay local to the service.
- Archived or close-in-progress conversations should reject live mutation
  uniformly after this batch, even where the old behavior only blocked
  deletion.
- Final verification is not complete until grep shows no remaining references
  to the deleted helpers and no remaining in-scope mutation service outside the
  new family.
- Commit after every task with the suggested message or a tighter equivalent.

## Final Scan Scope

The pre-implementation rescan for this plan covered all current candidate
conversation-local mutation surfaces and found no remaining in-scope entry
point outside the list below.

### Retained-Only Contract Targets

- `core_matrix/app/services/conversations/archive.rb`
- `core_matrix/app/services/conversations/request_close.rb`
- `core_matrix/app/services/conversations/unarchive.rb`
- `core_matrix/app/services/publications/publish_live.rb`

### Live-Mutation Contract Targets

- `core_matrix/app/services/turns/start_user_turn.rb`
- `core_matrix/app/services/turns/queue_follow_up.rb`
- `core_matrix/app/services/turns/start_automation_turn.rb`
- `core_matrix/app/services/workflows/manual_resume.rb`
- `core_matrix/app/services/workflows/manual_retry.rb`
- `core_matrix/app/services/canonical_stores/set.rb`
- `core_matrix/app/services/canonical_stores/delete_key.rb`
- `core_matrix/app/services/variables/promote_to_workspace.rb`
- `core_matrix/app/services/human_interactions/request.rb`
- `core_matrix/app/services/human_interactions/resolve_approval.rb`
- `core_matrix/app/services/human_interactions/submit_form.rb`
- `core_matrix/app/services/human_interactions/complete_task.rb`
- `core_matrix/app/services/conversations/create_branch.rb`
- `core_matrix/app/services/conversations/create_thread.rb`
- `core_matrix/app/services/conversations/create_checkpoint.rb`
- `core_matrix/app/services/conversations/add_import.rb`
- `core_matrix/app/services/conversations/update_override.rb`
- `core_matrix/app/services/conversation_summaries/create_segment.rb`
- `core_matrix/app/services/messages/update_visibility.rb`

### Timeline-Mutation Contract Targets

- `core_matrix/app/services/turns/steer_current_input.rb`
- `core_matrix/app/services/turns/edit_tail_input.rb`
- `core_matrix/app/services/turns/select_output_variant.rb`
- `core_matrix/app/services/turns/retry_output.rb`
- `core_matrix/app/services/turns/rerun_output.rb`
- `core_matrix/app/services/conversations/rollback_to_turn.rb`

### Out Of Scope For The Shared Mutation Family

These are lifecycle roots or system-owned projection/infrastructure writers and
should stay outside this contract family:

- `core_matrix/app/services/conversations/request_deletion.rb`
- `core_matrix/app/services/conversations/request_turn_interrupt.rb`
- `core_matrix/app/services/conversations/finalize_deletion.rb`
- `core_matrix/app/services/conversations/reconcile_close_operation.rb`
- `core_matrix/app/services/conversations/switch_agent_deployment.rb`
- `core_matrix/app/services/conversations/refresh_runtime_contract.rb`
- `core_matrix/app/services/conversations/create_root.rb`
- `core_matrix/app/services/conversations/create_automation_root.rb`
- `core_matrix/app/services/canonical_stores/bootstrap_for_conversation.rb`
- `core_matrix/app/services/canonical_stores/compact_snapshot.rb`
- `core_matrix/app/services/conversation_events/project.rb`

### Task 1: Add The Shared Conversation-State Contracts And Delete The Legacy Helper

**Files:**
- Create: `core_matrix/app/services/conversations/validate_retained_state.rb`
- Create: `core_matrix/app/services/conversations/with_retained_state_lock.rb`
- Create: `core_matrix/app/services/conversations/validate_mutable_state.rb`
- Create: `core_matrix/app/services/conversations/with_mutable_state_lock.rb`
- Delete: `core_matrix/app/services/conversations/retention_guard.rb`
- Modify: `core_matrix/app/services/conversations/archive.rb`
- Modify: `core_matrix/app/services/conversations/request_close.rb`
- Modify: `core_matrix/app/services/conversations/unarchive.rb`
- Modify: `core_matrix/app/services/publications/publish_live.rb`
- Test: `core_matrix/test/services/conversations/archive_test.rb`
- Test: `core_matrix/test/services/conversations/unarchive_test.rb`
- Test: `core_matrix/test/services/publications/publish_live_test.rb`

**Step 1: Write the failing tests**

Add or extend tests so they prove:

- retained-only callers still reject `pending_delete`
- retained-only callers re-check from fresh locked state instead of trusting a
  stale object snapshot
- no migrated retained-only service still includes or references
  `Conversations::RetentionGuard`

Example expectation:

```ruby
test "publish live rechecks retained state under the shared retained-state contract" do
  conversation = Conversations::CreateRoot.call(...)
  request_deletion_during_lock!(conversation)

  error = assert_raises(ActiveRecord::RecordInvalid) do
    Publications::PublishLive.call(
      conversation: conversation,
      actor: user,
      visibility_mode: "internal_public"
    )
  end

  assert_includes error.record.errors[:deletion_state], "must be retained before publishing"
end
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/conversations/archive_test.rb \
  test/services/conversations/unarchive_test.rb \
  test/services/publications/publish_live_test.rb
```

Expected: FAIL because the new retained-state contract classes do not exist yet.

**Step 3: Write the minimal implementation**

Implement:

- `ValidateRetainedState`
  - reload the conversation when needed
  - reject non-retained conversations
  - attach errors to the target record and raise `RecordInvalid`
- `WithRetainedStateLock`
  - lock the conversation row
  - run `ValidateRetainedState`
  - yield the fresh locked conversation

Then:

- delete `RetentionGuard`
- migrate `Archive`, `RequestClose`, `Unarchive`, and `PublishLive` to the new
  retained-only contract

**Step 4: Run tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/conversations/validate_retained_state.rb \
  core_matrix/app/services/conversations/with_retained_state_lock.rb \
  core_matrix/app/services/conversations/archive.rb \
  core_matrix/app/services/conversations/request_close.rb \
  core_matrix/app/services/conversations/unarchive.rb \
  core_matrix/app/services/publications/publish_live.rb \
  core_matrix/test/services/conversations/archive_test.rb \
  core_matrix/test/services/conversations/unarchive_test.rb \
  core_matrix/test/services/publications/publish_live_test.rb
git rm core_matrix/app/services/conversations/retention_guard.rb
git commit -m "refactor: replace legacy retained state guard"
```

### Task 2: Migrate Live Conversation Mutation Roots Onto The Shared Mutable-State Contract

**Files:**
- Modify: `core_matrix/app/services/conversations/validate_mutable_state.rb`
- Modify: `core_matrix/app/services/conversations/with_mutable_state_lock.rb`
- Modify: `core_matrix/app/services/turns/start_user_turn.rb`
- Modify: `core_matrix/app/services/turns/queue_follow_up.rb`
- Modify: `core_matrix/app/services/turns/start_automation_turn.rb`
- Modify: `core_matrix/app/services/workflows/manual_resume.rb`
- Modify: `core_matrix/app/services/workflows/manual_retry.rb`
- Modify: `core_matrix/app/services/canonical_stores/set.rb`
- Modify: `core_matrix/app/services/canonical_stores/delete_key.rb`
- Modify: `core_matrix/app/services/variables/promote_to_workspace.rb`
- Test: `core_matrix/test/services/turns/start_user_turn_test.rb`
- Test: `core_matrix/test/services/turns/queue_follow_up_test.rb`
- Test: `core_matrix/test/services/turns/start_automation_turn_test.rb`
- Test: `core_matrix/test/services/workflows/manual_resume_test.rb`
- Test: `core_matrix/test/services/workflows/manual_retry_test.rb`
- Test: `core_matrix/test/services/canonical_stores/set_test.rb`
- Test: `core_matrix/test/services/canonical_stores/delete_key_test.rb`
- Test: `core_matrix/test/services/variables/promote_to_workspace_test.rb`

**Step 1: Write the failing tests**

Add negative tests proving all these live mutation paths reject:

- `pending_delete`
- archived conversations
- active conversations with an unfinished close operation

At minimum cover one representative from each subfamily:

- turn entry
- manual recovery
- canonical-store write/delete
- variable promotion

Example expectation:

```ruby
test "manual retry rejects archived conversations" do
  context = build_paused_recovery_context!
  context[:conversation].update!(lifecycle_state: "archived")

  error = assert_raises(ActiveRecord::RecordInvalid) do
    Workflows::ManualRetry.call(
      workflow_run: context[:workflow_run],
      deployment: context[:agent_deployment],
      actor: actor
    )
  end

  assert_includes error.record.errors[:lifecycle_state], "must be active for live conversation mutation"
end
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/turns/start_user_turn_test.rb \
  test/services/turns/queue_follow_up_test.rb \
  test/services/turns/start_automation_turn_test.rb \
  test/services/workflows/manual_resume_test.rb \
  test/services/workflows/manual_retry_test.rb \
  test/services/canonical_stores/set_test.rb \
  test/services/canonical_stores/delete_key_test.rb \
  test/services/variables/promote_to_workspace_test.rb
```

Expected: FAIL because the current callers do not uniformly reject archived or
close-in-progress conversations.

**Step 3: Write the minimal implementation**

Implement:

- `ValidateMutableState`
  - reload the conversation when needed
  - enforce `retained + active + not_closing`
  - expose a consistent error contract
- `WithMutableStateLock`
  - lock the conversation row
  - run `ValidateMutableState`
  - yield the fresh locked conversation

Then migrate the services listed above to the new mutable-state contract and
delete any leftover local retained-state checks that the contract now owns.

**Step 4: Run tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/conversations/validate_mutable_state.rb \
  core_matrix/app/services/conversations/with_mutable_state_lock.rb \
  core_matrix/app/services/turns/start_user_turn.rb \
  core_matrix/app/services/turns/queue_follow_up.rb \
  core_matrix/app/services/turns/start_automation_turn.rb \
  core_matrix/app/services/workflows/manual_resume.rb \
  core_matrix/app/services/workflows/manual_retry.rb \
  core_matrix/app/services/canonical_stores/set.rb \
  core_matrix/app/services/canonical_stores/delete_key.rb \
  core_matrix/app/services/variables/promote_to_workspace.rb \
  core_matrix/test/services/turns/start_user_turn_test.rb \
  core_matrix/test/services/turns/queue_follow_up_test.rb \
  core_matrix/test/services/turns/start_automation_turn_test.rb \
  core_matrix/test/services/workflows/manual_resume_test.rb \
  core_matrix/test/services/workflows/manual_retry_test.rb \
  core_matrix/test/services/canonical_stores/set_test.rb \
  core_matrix/test/services/canonical_stores/delete_key_test.rb \
  core_matrix/test/services/variables/promote_to_workspace_test.rb
git commit -m "refactor: share live conversation mutation guards"
```

### Task 3: Migrate Human Interaction, Lineage, Projection, And Override Writers Onto The Mutable-State Contract

**Files:**
- Modify: `core_matrix/app/services/human_interactions/request.rb`
- Modify: `core_matrix/app/services/human_interactions/resolve_approval.rb`
- Modify: `core_matrix/app/services/human_interactions/submit_form.rb`
- Modify: `core_matrix/app/services/human_interactions/complete_task.rb`
- Modify: `core_matrix/app/services/conversations/create_branch.rb`
- Modify: `core_matrix/app/services/conversations/create_thread.rb`
- Modify: `core_matrix/app/services/conversations/create_checkpoint.rb`
- Modify: `core_matrix/app/services/conversations/add_import.rb`
- Modify: `core_matrix/app/services/conversations/update_override.rb`
- Modify: `core_matrix/app/services/conversation_summaries/create_segment.rb`
- Modify: `core_matrix/app/services/messages/update_visibility.rb`
- Test: `core_matrix/test/services/human_interactions/request_test.rb`
- Test: `core_matrix/test/services/human_interactions/resolve_approval_test.rb`
- Test: `core_matrix/test/services/human_interactions/submit_form_test.rb`
- Test: `core_matrix/test/services/human_interactions/complete_task_test.rb`
- Test: `core_matrix/test/services/conversations/create_branch_test.rb`
- Test: `core_matrix/test/services/conversations/create_thread_test.rb`
- Test: `core_matrix/test/services/conversations/create_checkpoint_test.rb`
- Test: `core_matrix/test/services/conversations/add_import_test.rb`
- Test: `core_matrix/test/services/conversations/update_override_test.rb`
- Test: `core_matrix/test/services/conversation_summaries/create_segment_test.rb`
- Test: `core_matrix/test/services/messages/update_visibility_test.rb`
- Test: `core_matrix/test/integration/conversation_safe_deletion_flow_test.rb`

**Step 1: Write the failing tests**

Add negative tests proving these services reject:

- archived conversations
- close-in-progress conversations
- `pending_delete` where not already covered

Make sure the suite covers at least:

- one human-interaction resolution path
- one lineage creation path
- one transcript-support write path
- `UpdateOverride`

Example expectation:

```ruby
test "update override rejects conversations while close is in progress" do
  conversation = Conversations::CreateRoot.call(...)
  Conversations::RequestClose.call(conversation: conversation, intent_kind: "archive")

  error = assert_raises(ActiveRecord::RecordInvalid) do
    Conversations::UpdateOverride.call(
      conversation: conversation,
      payload: {},
      schema_fingerprint: "schema-v1",
      selector_mode: "auto"
    )
  end

  assert_includes error.record.errors[:base], "must not mutate conversation state while close is in progress"
end
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/human_interactions/request_test.rb \
  test/services/human_interactions/resolve_approval_test.rb \
  test/services/human_interactions/submit_form_test.rb \
  test/services/human_interactions/complete_task_test.rb \
  test/services/conversations/create_branch_test.rb \
  test/services/conversations/create_thread_test.rb \
  test/services/conversations/create_checkpoint_test.rb \
  test/services/conversations/add_import_test.rb \
  test/services/conversations/update_override_test.rb \
  test/services/conversation_summaries/create_segment_test.rb \
  test/services/messages/update_visibility_test.rb \
  test/integration/conversation_safe_deletion_flow_test.rb
```

Expected: FAIL because several of these services still bypass the mutable-state
contract.

**Step 3: Write the minimal implementation**

Migrate the listed services to `WithMutableStateLock` or
`ValidateMutableState`, depending on whether they already own a larger locked
context.

Rules:

- use the lock wrapper where the service is the natural locking root
- use the validator directly when the service already holds the correct
  conversation lock through another context helper
- keep all business-specific checks local

**Step 4: Run tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/human_interactions/request.rb \
  core_matrix/app/services/human_interactions/resolve_approval.rb \
  core_matrix/app/services/human_interactions/submit_form.rb \
  core_matrix/app/services/human_interactions/complete_task.rb \
  core_matrix/app/services/conversations/create_branch.rb \
  core_matrix/app/services/conversations/create_thread.rb \
  core_matrix/app/services/conversations/create_checkpoint.rb \
  core_matrix/app/services/conversations/add_import.rb \
  core_matrix/app/services/conversations/update_override.rb \
  core_matrix/app/services/conversation_summaries/create_segment.rb \
  core_matrix/app/services/messages/update_visibility.rb \
  core_matrix/test/services/human_interactions/request_test.rb \
  core_matrix/test/services/human_interactions/resolve_approval_test.rb \
  core_matrix/test/services/human_interactions/submit_form_test.rb \
  core_matrix/test/services/human_interactions/complete_task_test.rb \
  core_matrix/test/services/conversations/create_branch_test.rb \
  core_matrix/test/services/conversations/create_thread_test.rb \
  core_matrix/test/services/conversations/create_checkpoint_test.rb \
  core_matrix/test/services/conversations/add_import_test.rb \
  core_matrix/test/services/conversations/update_override_test.rb \
  core_matrix/test/services/conversation_summaries/create_segment_test.rb \
  core_matrix/test/services/messages/update_visibility_test.rb \
  core_matrix/test/integration/conversation_safe_deletion_flow_test.rb
git commit -m "refactor: unify live conversation mutation entry points"
```

### Task 4: Replace The Rewrite Guard With The Shared Timeline-Mutation Contract

**Files:**
- Create: `core_matrix/app/services/turns/validate_timeline_mutation_target.rb`
- Create: `core_matrix/app/services/turns/with_timeline_mutation_lock.rb`
- Delete: `core_matrix/app/services/turns/validate_rewrite_target.rb`
- Modify: `core_matrix/app/services/turns/steer_current_input.rb`
- Modify: `core_matrix/app/services/turns/edit_tail_input.rb`
- Modify: `core_matrix/app/services/turns/select_output_variant.rb`
- Modify: `core_matrix/app/services/turns/retry_output.rb`
- Modify: `core_matrix/app/services/turns/rerun_output.rb`
- Modify: `core_matrix/app/services/conversations/rollback_to_turn.rb`
- Test: `core_matrix/test/services/turns/steer_current_input_test.rb`
- Test: `core_matrix/test/services/turns/edit_tail_input_test.rb`
- Test: `core_matrix/test/services/turns/select_output_variant_test.rb`
- Test: `core_matrix/test/services/turns/retry_output_test.rb`
- Test: `core_matrix/test/services/turns/rerun_output_test.rb`
- Test: `core_matrix/test/services/conversations/rollback_to_turn_test.rb`
- Test: `core_matrix/test/services/turns/validate_timeline_mutation_target_test.rb`
- Test: `core_matrix/test/integration/turn_history_rewrite_flow_test.rb`

**Step 1: Write the failing tests**

Add negative tests proving all timeline mutations reject:

- archived conversations
- close-in-progress conversations
- `pending_delete`
- `turn_interrupted`

At minimum cover:

- direct current-turn steering
- tail input edit
- output-variant selection
- output retry or rerun
- rollback

Example expectation:

```ruby
test "steer current input rejects a turn fenced by turn interrupt" do
  turn = prepare_active_turn!
  turn.update!(
    cancellation_requested_at: Time.current,
    cancellation_reason_kind: "turn_interrupted"
  )

  error = assert_raises(ActiveRecord::RecordInvalid) do
    Turns::SteerCurrentInput.call(turn: turn, content: "Revised input")
  end

  assert_includes error.record.errors[:base], "must not mutate timeline after turn interruption"
end
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/turns/steer_current_input_test.rb \
  test/services/turns/edit_tail_input_test.rb \
  test/services/turns/select_output_variant_test.rb \
  test/services/turns/retry_output_test.rb \
  test/services/turns/rerun_output_test.rb \
  test/services/conversations/rollback_to_turn_test.rb \
  test/integration/turn_history_rewrite_flow_test.rb
```

Expected: FAIL because the timeline contract classes do not exist yet and the
current services still use bespoke logic.

**Step 3: Write the minimal implementation**

Implement:

- `ValidateTimelineMutationTarget`
  - reload the turn and owning conversation
  - enforce the live-mutation conversation contract
  - reject `turn_interrupted`
- `WithTimelineMutationLock`
  - lock conversation first
  - lock turn second
  - run the validator
  - yield fresh locked records

Then:

- migrate all listed timeline services to the new contract
- delete `ValidateRewriteTarget`

**Step 4: Run tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/turns/validate_timeline_mutation_target.rb \
  core_matrix/app/services/turns/with_timeline_mutation_lock.rb \
  core_matrix/app/services/turns/steer_current_input.rb \
  core_matrix/app/services/turns/edit_tail_input.rb \
  core_matrix/app/services/turns/select_output_variant.rb \
  core_matrix/app/services/turns/retry_output.rb \
  core_matrix/app/services/turns/rerun_output.rb \
  core_matrix/app/services/conversations/rollback_to_turn.rb \
  core_matrix/test/services/turns/steer_current_input_test.rb \
  core_matrix/test/services/turns/edit_tail_input_test.rb \
  core_matrix/test/services/turns/select_output_variant_test.rb \
  core_matrix/test/services/turns/retry_output_test.rb \
  core_matrix/test/services/turns/rerun_output_test.rb \
  core_matrix/test/services/conversations/rollback_to_turn_test.rb \
  core_matrix/test/services/turns/validate_timeline_mutation_target_test.rb \
  core_matrix/test/integration/turn_history_rewrite_flow_test.rb
git rm core_matrix/app/services/turns/validate_rewrite_target.rb
git commit -m "refactor: unify turn timeline mutation guards"
```

### Task 5: Update Behavior Docs And The Audit Artifact To Match The New Contract Family

**Files:**
- Modify: `core_matrix/docs/behavior/turn-entry-and-selector-state.md`
- Modify: `core_matrix/docs/behavior/turn-rewrite-and-variant-operations.md`
- Modify: `core_matrix/docs/behavior/transcript-visibility-and-attachments.md`
- Modify: `core_matrix/docs/behavior/transcript-imports-and-summary-segments.md`
- Modify: `core_matrix/docs/behavior/agent-runtime-resource-apis.md`
- Modify: `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
- Modify: `core_matrix/docs/plans/2026-03-26-core-matrix-review-audit-findings.md`

**Step 1: Write the doc changes**

Document these landed rules:

- `RetentionGuard` is gone
- conversation-local live mutation uses one shared
  `retained + active + not_closing` contract
- timeline mutation uses one shared turn contract layered on top of that
- archived and close-in-progress conversations now reject the migrated live
  mutation surfaces
- `UpdateOverride` is part of the same live mutation family
- runtime resource API docs now describe archived and closing rejection for
  variable writes, deletes, and promotion
- manual recovery docs now describe archived and closing rejection

**Step 2: Verify docs render coherently**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
sed -n '1,220p' core_matrix/docs/behavior/turn-entry-and-selector-state.md
sed -n '1,220p' core_matrix/docs/behavior/turn-rewrite-and-variant-operations.md
sed -n '1,220p' core_matrix/docs/behavior/agent-runtime-resource-apis.md
sed -n '1,260p' core_matrix/docs/plans/2026-03-26-core-matrix-review-audit-findings.md
```

Expected: the new shared-contract family is explicit and no doc still describes
the old partial guard behavior.

**Step 3: Commit**

```bash
git add core_matrix/docs/behavior/turn-entry-and-selector-state.md \
  core_matrix/docs/behavior/turn-rewrite-and-variant-operations.md \
  core_matrix/docs/behavior/transcript-visibility-and-attachments.md \
  core_matrix/docs/behavior/transcript-imports-and-summary-segments.md \
  core_matrix/docs/behavior/agent-runtime-resource-apis.md \
  core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md \
  core_matrix/docs/plans/2026-03-26-core-matrix-review-audit-findings.md
git commit -m "docs: describe shared conversation mutation contracts"
```

### Task 6: Run Targeted, Neighbor, And Grep Verification Until The Scan Stays Clean

**Files:**
- Verify only

**Step 1: Run the targeted regression suites**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/turns/start_user_turn_test.rb \
  test/services/turns/queue_follow_up_test.rb \
  test/services/turns/start_automation_turn_test.rb \
  test/services/workflows/manual_resume_test.rb \
  test/services/workflows/manual_retry_test.rb \
  test/services/canonical_stores/set_test.rb \
  test/services/canonical_stores/delete_key_test.rb \
  test/services/variables/promote_to_workspace_test.rb \
  test/services/human_interactions/request_test.rb \
  test/services/human_interactions/resolve_approval_test.rb \
  test/services/human_interactions/submit_form_test.rb \
  test/services/human_interactions/complete_task_test.rb \
  test/services/conversations/create_branch_test.rb \
  test/services/conversations/create_thread_test.rb \
  test/services/conversations/create_checkpoint_test.rb \
  test/services/conversations/add_import_test.rb \
  test/services/conversations/update_override_test.rb \
  test/services/conversation_summaries/create_segment_test.rb \
  test/services/messages/update_visibility_test.rb \
  test/services/turns/steer_current_input_test.rb \
  test/services/turns/edit_tail_input_test.rb \
  test/services/turns/select_output_variant_test.rb \
  test/services/turns/retry_output_test.rb \
  test/services/turns/rerun_output_test.rb \
  test/services/conversations/rollback_to_turn_test.rb \
  test/services/turns/validate_timeline_mutation_target_test.rb
```

Expected: PASS.

**Step 2: Run neighbor regressions**

Run:

```bash
cd core_matrix
bin/rails test \
  test/integration/turn_entry_flow_test.rb \
  test/integration/turn_history_rewrite_flow_test.rb \
  test/integration/conversation_safe_deletion_flow_test.rb \
  test/integration/human_interaction_flow_test.rb \
  test/integration/agent_recovery_flow_test.rb \
  test/services/conversations/archive_test.rb \
  test/services/conversations/request_deletion_test.rb \
  test/services/conversations/finalize_deletion_test.rb \
  test/services/conversations/reconcile_close_operation_test.rb \
  test/services/conversations/request_turn_interrupt_test.rb \
  test/services/workflows/execute_run_test.rb \
  test/requests/agent_api/execution_delivery_test.rb \
  test/e2e/protocol/turn_interrupt_e2e_test.rb \
  test/e2e/protocol/conversation_close_e2e_test.rb
```

Expected: PASS.

**Step 3: Run the final grep audits**

Run:

```bash
cd core_matrix
rg -n "RetentionGuard|ValidateRewriteTarget" app/services test
rg -n "WithMutableStateLock|ValidateMutableState|WithRetainedStateLock|ValidateRetainedState|WithTimelineMutationLock|ValidateTimelineMutationTarget" app/services
rg -n "selected_input_message|selected_output_message|override_payload|ConversationImport.create!|ConversationSummarySegment.create!|ConversationMessageVisibility.find_or_initialize_by" app/services
```

Expected:

- the first command returns no matches
- the second command covers all intended family members
- the third command shows only in-scope writers and all of them are now inside
  the shared contract family

**Step 4: Re-run the scan if grep surfaces a missed sibling**

If any new in-scope mutation service appears, do not finish. Add it to the
same contract family, extend tests, and re-run Step 3 until the scan stays
clean.

**Step 5: Commit**

```bash
git add -A
git commit -m "test: verify conversation mutation contract unification"
```
