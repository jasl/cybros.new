# Lineage Provenance And Supersession Hardening Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Repair Milestone C lineage and supersession drift so rollback, output-variant history, and child-conversation anchors all use explicit durable provenance contracts.

**Architecture:** Add one shared validator for historical anchors, one shared validator for suffix supersession, and one shared output-variant writer backed by durable `source_input_message` provenance. Tighten `Conversation`, `Message`, and `Turn` model invariants, remove silent anchor fallback, and finish with targeted, neighboring, and grep-based verification so future mutation paths reuse the same contracts.

**Tech Stack:** Ruby on Rails (`core_matrix`), Active Record migrations and validations, Minitest service/integration coverage, Phase 2 planning docs

---

## Execution Rules

- Treat this as a structural Milestone C follow-up, not as three unrelated bug
  patches.
- Keep supersession orchestration separate from interrupt and close
  orchestration. Rollback should reject live suffix runtime, not invent a second
  quiesce flow.
- Do not preserve compatibility for invalid historical anchors or output lineage
  rows through silent fallback.
- Every output-producing path must go through one shared writer once the new
  contract exists.
- Every child-conversation creation path must go through one shared anchor
  validator once the new contract exists.
- Re-run sibling-path grep checks after each task so this follow-up closes the
  family, not just the originally reported sites.
- Commit after every task with the suggested message or a tighter equivalent.

## Current Implementations That Must Be Adjusted

- `core_matrix/app/services/conversations/rollback_to_turn.rb`
  Reason: cancels later turns without proving their owned runtime is quiescent.
- `core_matrix/app/models/workflow_run.rb`
  Reason: exposes live runtime ownership that rollback must treat as blockers.
- `core_matrix/app/models/message.rb`
  Reason: lacks durable output-to-input provenance.
- `core_matrix/app/models/turn.rb`
  Reason: allows selected input/output pointers to drift across lineages.
- `core_matrix/app/services/provider_execution/execute_turn_step.rb`
  Reason: writes output variants inline without provenance.
- `core_matrix/app/services/turns/retry_output.rb`
  Reason: writes retried output variants inline without provenance.
- `core_matrix/app/services/turns/rerun_output.rb`
  Reason: branches replay from the current selected input instead of the target
  output's original input lineage.
- `core_matrix/app/services/turns/select_output_variant.rb`
  Reason: selects an output variant without restoring its matching input lineage.
- `core_matrix/app/models/conversation.rb`
  Reason: validates anchor presence only and silently truncates inherited
  transcript when the anchor is invalid.
- `core_matrix/app/services/conversations/create_branch.rb`
  Reason: accepts arbitrary anchor ids and does permissive anchor lookup.
- `core_matrix/app/services/conversations/create_checkpoint.rb`
  Reason: accepts arbitrary anchor ids and validates too little.
- `core_matrix/app/services/conversations/create_thread.rb`
  Reason: accepts arbitrary optional anchor ids and validates too little.
- `core_matrix/docs/behavior/conversation-structure-and-lineage.md`
  Reason: must document strict historical-anchor rules.
- `core_matrix/docs/behavior/turn-entry-and-selector-state.md`
  Reason: must document output-lineage selection behavior.
- `core_matrix/docs/plans/2026-03-26-core-matrix-review-audit-findings.md`
  Reason: should reflect the final implementation status once complete.

Before finishing, explicitly re-check that:

- all output writers use the shared output-variant creator
- all child-conversation creators use the shared anchor validator
- rollback rejects live suffix runtime through the shared supersession validator
- no read path silently converts invalid historical anchors into empty inherited
  transcript

### Task 1: Introduce Strict Historical Anchor Validation

**Files:**
- Create: `core_matrix/app/services/conversations/validate_historical_anchor.rb`
- Modify: `core_matrix/app/models/conversation.rb`
- Modify: `core_matrix/app/services/conversations/create_branch.rb`
- Modify: `core_matrix/app/services/conversations/create_checkpoint.rb`
- Modify: `core_matrix/app/services/conversations/create_thread.rb`
- Modify: `core_matrix/test/models/conversation_test.rb`
- Modify: `core_matrix/test/services/conversations/create_branch_test.rb`
- Modify: `core_matrix/test/services/conversations/create_checkpoint_test.rb`
- Modify: `core_matrix/test/services/conversations/create_thread_test.rb`
- Modify: `core_matrix/test/integration/conversation_structure_flow_test.rb`

**Step 1: Write the failing tests**

Add regressions that prove:

- branch rejects an anchor outside the parent conversation history
- checkpoint rejects an anchor outside the parent conversation history
- thread rejects an invalid optional anchor
- valid anchors still create durable child conversations
- inherited transcript projection no longer silently falls back to `[]` for an
  invalid persisted anchor

Example expectation:

```ruby
test "create branch rejects an anchor outside the parent conversation history" do
  error = assert_raises(ActiveRecord::RecordInvalid) do
    Conversations::CreateBranch.call(parent: root, historical_anchor_message_id: invalid_message.id)
  end

  assert_includes error.record.errors[:historical_anchor_message_id], "must belong to the parent conversation history"
end
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/models/conversation_test.rb \
  test/services/conversations/create_branch_test.rb \
  test/services/conversations/create_checkpoint_test.rb \
  test/services/conversations/create_thread_test.rb \
  test/integration/conversation_structure_flow_test.rb
```

Expected: FAIL because anchors are still accepted permissively.

**Step 3: Write the minimal implementation**

Implement `Conversations::ValidateHistoricalAnchor` so it:

- accepts `parent:`, `kind:`, `historical_anchor_message_id:`, and `record:`
- resolves and returns the anchor `Message` row when valid
- enforces branch/checkpoint required anchors and thread optional anchors
- validates membership against the parent conversation history
- allows durable output anchors only when replay can recover matching
  `source_input_message` provenance

Then:

- wire `CreateBranch`, `CreateCheckpoint`, and `CreateThread` through it
- make `CreateBranch` build `branch_prefix` imports from the resolved anchor
- add model-level anchor-membership validation to `Conversation`
- remove silent `[]` fallback from inherited transcript projection

**Step 4: Run tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/conversations/validate_historical_anchor.rb \
  core_matrix/app/models/conversation.rb \
  core_matrix/app/services/conversations/create_branch.rb \
  core_matrix/app/services/conversations/create_checkpoint.rb \
  core_matrix/app/services/conversations/create_thread.rb \
  core_matrix/test/models/conversation_test.rb \
  core_matrix/test/services/conversations/create_branch_test.rb \
  core_matrix/test/services/conversations/create_checkpoint_test.rb \
  core_matrix/test/services/conversations/create_thread_test.rb \
  core_matrix/test/integration/conversation_structure_flow_test.rb
git commit -m "fix: validate historical anchors against parent transcript"
```

### Task 2: Add Durable Output Provenance And Shared Output Creation

**Files:**
- Create: `core_matrix/app/services/turns/create_output_variant.rb`
- Modify: `core_matrix/app/models/message.rb`
- Modify: `core_matrix/app/models/turn.rb`
- Modify: `core_matrix/app/services/provider_execution/execute_turn_step.rb`
- Modify: `core_matrix/app/services/turns/retry_output.rb`
- Modify: `core_matrix/app/services/turns/rerun_output.rb`
- Modify: `core_matrix/app/services/turns/select_output_variant.rb`
- Modify: `core_matrix/db/migrate/*_add_source_input_message_to_messages.rb`
- Modify: `core_matrix/db/schema.rb`
- Modify: `core_matrix/test/models/message_test.rb`
- Modify: `core_matrix/test/models/turn_test.rb`
- Modify: `core_matrix/test/services/turns/retry_output_test.rb`
- Modify: `core_matrix/test/services/turns/rerun_output_test.rb`
- Modify: `core_matrix/test/services/turns/select_output_variant_test.rb`
- Modify: `core_matrix/test/services/workflows/execute_run_test.rb`
- Modify: `core_matrix/test/integration/turn_history_rewrite_flow_test.rb`
- Modify: `core_matrix/test/integration/provider_backed_turn_execution_test.rb`

**Step 1: Write the failing tests**

Add regressions that prove:

- output messages must persist `source_input_message`
- selected output lineage must match selected input lineage
- selecting an older output variant restores the matching input variant
- branch rerun uses the target output's original input, not the current selected
  input
- provider-backed execution persists output provenance

Example expectation:

```ruby
test "select output variant restores the matching input lineage" do
  selected = Turns::SelectOutputVariant.call(message: older_output)

  assert_equal older_output, selected.selected_output_message
  assert_equal older_output.source_input_message, selected.selected_input_message
end
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/models/message_test.rb \
  test/models/turn_test.rb \
  test/services/turns/retry_output_test.rb \
  test/services/turns/rerun_output_test.rb \
  test/services/turns/select_output_variant_test.rb \
  test/services/workflows/execute_run_test.rb \
  test/integration/turn_history_rewrite_flow_test.rb \
  test/integration/provider_backed_turn_execution_test.rb
```

Expected: FAIL because outputs do not yet carry source-input provenance.

**Step 3: Write the minimal implementation**

Add `messages.source_input_message_id` and implement:

- `Message` association and provenance validations
- `Turn` backstop validation for selected lineage consistency
- `Turns::CreateOutputVariant` to allocate output variants and attach source input
- refactors in provider execution, retry output, rerun output, and select output
  variant to use the new contract

Use the target output's `source_input_message` for branch rerun.

**Step 4: Run tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/turns/create_output_variant.rb \
  core_matrix/app/models/message.rb \
  core_matrix/app/models/turn.rb \
  core_matrix/app/services/provider_execution/execute_turn_step.rb \
  core_matrix/app/services/turns/retry_output.rb \
  core_matrix/app/services/turns/rerun_output.rb \
  core_matrix/app/services/turns/select_output_variant.rb \
  core_matrix/db/migrate \
  core_matrix/db/schema.rb \
  core_matrix/test/models/message_test.rb \
  core_matrix/test/models/turn_test.rb \
  core_matrix/test/services/turns/retry_output_test.rb \
  core_matrix/test/services/turns/rerun_output_test.rb \
  core_matrix/test/services/turns/select_output_variant_test.rb \
  core_matrix/test/services/workflows/execute_run_test.rb \
  core_matrix/test/integration/turn_history_rewrite_flow_test.rb \
  core_matrix/test/integration/provider_backed_turn_execution_test.rb
git commit -m "fix: persist transcript output provenance"
```

### Task 3: Introduce Shared Suffix Supersession Validation For Rollback

**Files:**
- Create: `core_matrix/app/queries/conversations/work_barrier_query.rb`
- Create: `core_matrix/app/services/conversations/validate_timeline_suffix_supersession.rb`
- Modify: `core_matrix/app/services/conversations/rollback_to_turn.rb`
- Modify: `core_matrix/app/services/conversations/work_quiescence_guard.rb`
- Modify: `core_matrix/test/services/conversations/rollback_to_turn_test.rb`
- Create: `core_matrix/test/services/conversations/validate_timeline_suffix_supersession_test.rb`
- Modify: `core_matrix/test/integration/turn_history_rewrite_flow_test.rb`

**Step 1: Write the failing tests**

Add regressions that prove rollback rejects:

- later queued turns
- later active turns
- later turns with active workflow runs
- later turns with queued or running agent tasks
- later turns with open human interaction requests
- later turns with running turn-command or subagent work
- later turns with active execution leases

Also keep one success path proving rollback still works after the suffix is
already quiescent.

Example expectation:

```ruby
test "rollback rejects when a later turn still owns an active workflow run" do
  error = assert_raises(ActiveRecord::RecordInvalid) do
    Conversations::RollbackToTurn.call(conversation: conversation, turn: earlier_turn)
  end

  assert_includes error.record.errors[:base], "must not roll back the timeline while later workflow runs remain active"
end
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/conversations/rollback_to_turn_test.rb \
  test/integration/turn_history_rewrite_flow_test.rb
```

Expected: FAIL because rollback still cancels later turns unconditionally and no
shared suffix-supersession validator exists yet.

**Step 3: Write the minimal implementation**

Implement `Conversations::ValidateTimelineSuffixSupersession` so it:

- uses a shared scoped runtime-barrier query for conversation or suffix checks
- gathers queued work and live runtime blockers on later turns
- raises `RecordInvalid` on the caller-facing record when blockers exist

Then:

- call it from `RollbackToTurn` before canceling later turns
- refactor `WorkQuiescenceGuard` to reuse the same shared query
- keep summary/import pruning behavior after the suffix is proven quiescent
- do not add auto-interrupt side effects to rollback

**Step 4: Run tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/conversations/validate_timeline_suffix_supersession.rb \
  core_matrix/app/services/conversations/rollback_to_turn.rb \
  core_matrix/test/services/conversations/rollback_to_turn_test.rb \
  core_matrix/test/integration/turn_history_rewrite_flow_test.rb
git commit -m "fix: require quiescent suffixes before rollback"
```

### Task 4: Update Behavior Docs, Audit Notes, And Run Full Verification

**Files:**
- Modify: `core_matrix/docs/behavior/conversation-structure-and-lineage.md`
- Modify: `core_matrix/docs/behavior/turn-entry-and-selector-state.md`
- Modify: `core_matrix/docs/behavior/workflow-context-assembly-and-execution-snapshot.md`
- Modify: `core_matrix/docs/plans/2026-03-26-core-matrix-review-audit-findings.md`

**Step 1: Update the docs**

Document:

- strict historical-anchor validation rules
- output variant provenance and selection behavior
- rollback suffix supersession expectations
- the fact that invalid persisted lineage now fails loudly instead of truncating
  silently

**Step 2: Run targeted verification**

Run:

```bash
cd core_matrix
bin/rails test \
  test/models/conversation_test.rb \
  test/models/message_test.rb \
  test/models/turn_test.rb \
  test/services/conversations/create_branch_test.rb \
  test/services/conversations/create_checkpoint_test.rb \
  test/services/conversations/create_thread_test.rb \
  test/services/conversations/rollback_to_turn_test.rb \
  test/services/turns/retry_output_test.rb \
  test/services/turns/rerun_output_test.rb \
  test/services/turns/select_output_variant_test.rb \
  test/services/workflows/execute_run_test.rb \
  test/integration/conversation_structure_flow_test.rb \
  test/integration/turn_history_rewrite_flow_test.rb \
  test/integration/provider_backed_turn_execution_test.rb
```

Expected: PASS.

**Step 3: Run wider neighboring regression**

Run:

```bash
cd core_matrix
bin/rails test \
  test/integration/transcript_import_summary_flow_test.rb \
  test/integration/transcript_visibility_attachment_flow_test.rb \
  test/integration/workflow_context_flow_test.rb \
  test/services/conversations/request_turn_interrupt_test.rb \
  test/services/conversations/reconcile_close_operation_test.rb \
  test/services/workflows/manual_retry_test.rb \
  test/services/workflows/manual_resume_test.rb \
  test/requests/agent_api/execution_delivery_test.rb \
  test/e2e/protocol/turn_interrupt_e2e_test.rb \
  test/e2e/protocol/conversation_close_e2e_test.rb
```

Expected: PASS.

**Step 4: Run static audit checks**

Run:

```bash
cd core_matrix
rg -n "slot: \"output\"" app/services
rg -n "CreateBranch.call|CreateCheckpoint.call|CreateThread.call" app/services
rg -n "historical_anchor_message_id" app/models app/services
rg -n "RollbackToTurn|sequence > .*turn.sequence" app/services
```

Confirm:

- output writers flow through `Turns::CreateOutputVariant`
- child-conversation creation flows route through `ValidateHistoricalAnchor`
- anchor handling no longer allows permissive raw-id writes
- no rollback-like suffix mutation path bypasses the supersession validator

**Step 5: Commit**

```bash
git add core_matrix/docs/behavior/conversation-structure-and-lineage.md \
  core_matrix/docs/behavior/turn-entry-and-selector-state.md \
  core_matrix/docs/behavior/workflow-context-assembly-and-execution-snapshot.md \
  core_matrix/docs/plans/2026-03-26-core-matrix-review-audit-findings.md
git commit -m "docs: describe lineage provenance hardening"
```
