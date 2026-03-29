# Core Matrix Test Suite Audit Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Audit the current `core_matrix` test suite for correctness protection, remove low-value tests, and raise meaningful coverage in the backend-critical paths.

**Architecture:** Work batch-by-batch through the current product core, starting with workflow, turn, conversation, lineage, and provider-execution domains. In each batch, classify existing tests by value, delete or rewrite weak cases, then add missing failure-path and invariant coverage before moving to the next domain.

**Tech Stack:** Ruby on Rails, Minitest, SimpleCov, PostgreSQL

---

### Task 1: Record The Batch 1 Audit Ledger

**Files:**
- Create: `docs/plans/2026-03-29-core-matrix-test-suite-audit-findings.md`
- Modify: `test/services/workflows/build_execution_snapshot_test.rb`
- Modify: `test/services/workflows/intent_batch_materialization_test.rb`
- Modify: `test/services/turns/start_user_turn_test.rb`
- Modify: `test/services/conversations/request_close_test.rb`
- Modify: `test/services/lineage_stores/compact_snapshot_test.rb`
- Modify: `test/services/provider_execution/persist_turn_step_success_test.rb`

**Step 1: Write the failing test**

For each target file, add or tighten one assertion that encodes a real
invariant currently under-protected. Examples:

```ruby
assert_equal expected_attachment_ids.sort,
  workflow_run.model_input_attachments.map { |item| item.fetch("attachment_id") }.sort
assert_includes error.record.errors[:base], "must remain acyclic after mutation"
refute request_body.key?("sandbox")
```

**Step 2: Run test to verify it fails**

Run one focused file at a time and confirm the new or tightened assertion fails
for the intended reason.

Run:

```bash
bin/rails test test/services/workflows/build_execution_snapshot_test.rb
bin/rails test test/services/provider_execution/persist_turn_step_success_test.rb
```

Expected: at least one assertion fails because the current test does not yet
protect the missing behavior strongly enough.

**Step 3: Write minimal implementation**

Do not change product behavior yet. Update the test code and the findings
ledger so each file is explicitly classified as:

- keep_and_strengthen
- rewrite_or_lower
- delete

Capture the behavior being protected and the missing branch or invariant.

**Step 4: Run test to verify it passes**

Re-run the same focused files after the test rewrite and confirm the
classification doc and assertions are stable.

**Step 5: Commit**

```bash
git add docs/plans/2026-03-29-core-matrix-test-suite-audit-findings.md \
  test/services/workflows/build_execution_snapshot_test.rb \
  test/services/workflows/intent_batch_materialization_test.rb \
  test/services/turns/start_user_turn_test.rb \
  test/services/conversations/request_close_test.rb \
  test/services/lineage_stores/compact_snapshot_test.rb \
  test/services/provider_execution/persist_turn_step_success_test.rb
git commit -m "test: classify and strengthen batch 1 audit targets"
```

### Task 2: Harden Workflow Snapshot And Turn Entry Coverage

**Files:**
- Modify: `app/services/workflows/build_execution_snapshot.rb`
- Modify: `app/services/workflows/intent_batch_materialization.rb`
- Modify: `app/services/turns/start_user_turn.rb`
- Modify: `test/services/workflows/build_execution_snapshot_test.rb`
- Modify: `test/services/workflows/intent_batch_materialization_test.rb`
- Modify: `test/services/turns/start_user_turn_test.rb`
- Modify: `test/integration/workflow_context_flow_test.rb`
- Test: `test/services/workflows/build_execution_snapshot_test.rb`
- Test: `test/services/workflows/intent_batch_materialization_test.rb`
- Test: `test/services/turns/start_user_turn_test.rb`
- Test: `test/integration/workflow_context_flow_test.rb`

**Step 1: Write the failing test**

Add focused failures for missing behavior such as:

- imported-context ordering
- attachment eligibility across root/branch boundaries
- snapshot persistence when optional config keys are absent
- turn-start invariants around selected input/output state

Example:

```ruby
assert_equal %w[branch_prefix quoted_context],
  branch_turn.execution_snapshot.context_imports.map { |item| item.fetch("kind") }.sort
```

**Step 2: Run test to verify it fails**

Run:

```bash
bin/rails test test/services/workflows/build_execution_snapshot_test.rb
bin/rails test test/services/workflows/intent_batch_materialization_test.rb
bin/rails test test/services/turns/start_user_turn_test.rb
bin/rails test test/integration/workflow_context_flow_test.rb
```

Expected: failures should point to the specific uncovered branch or incorrect
assumption.

**Step 3: Write minimal implementation**

Only if needed, adjust service code so the newly specified behavior is correct.
Prefer the smallest change that preserves existing contracts.

**Step 4: Run test to verify it passes**

Re-run the same files until the new assertions pass.

**Step 5: Commit**

```bash
git add app/services/workflows/build_execution_snapshot.rb \
  app/services/workflows/intent_batch_materialization.rb \
  app/services/turns/start_user_turn.rb \
  test/services/workflows/build_execution_snapshot_test.rb \
  test/services/workflows/intent_batch_materialization_test.rb \
  test/services/turns/start_user_turn_test.rb \
  test/integration/workflow_context_flow_test.rb
git commit -m "test: harden workflow snapshot and turn entry coverage"
```

### Task 3: Harden Conversation Lifecycle And Lineage Guarantees

**Files:**
- Modify: `app/services/conversations/request_close.rb`
- Modify: `app/services/conversations/rollback_to_turn.rb`
- Modify: `app/services/conversations/create_branch.rb`
- Modify: `app/services/lineage_stores/compact_snapshot.rb`
- Modify: `test/services/conversations/request_close_test.rb`
- Modify: `test/services/conversations/rollback_to_turn_test.rb`
- Modify: `test/services/conversations/create_branch_test.rb`
- Modify: `test/services/lineage_stores/compact_snapshot_test.rb`
- Modify: `test/integration/conversation_lineage_store_branch_flow_test.rb`
- Test: `test/services/conversations/request_close_test.rb`
- Test: `test/services/conversations/rollback_to_turn_test.rb`
- Test: `test/services/conversations/create_branch_test.rb`
- Test: `test/services/lineage_stores/compact_snapshot_test.rb`
- Test: `test/integration/conversation_lineage_store_branch_flow_test.rb`

**Step 1: Write the failing test**

Target missing guarantees such as:

- only valid mutable states allow close or rollback
- branch creation preserves lineage constraints
- compacted snapshots keep visible keys and remove superseded history only when
  allowed

Example:

```ruby
assert_includes error.record.errors[:base], "conversation must be quiescent"
assert_equal expected_keys.sort, snapshot.entries.map(&:key).sort
```

**Step 2: Run test to verify it fails**

Run:

```bash
bin/rails test test/services/conversations/request_close_test.rb
bin/rails test test/services/conversations/rollback_to_turn_test.rb
bin/rails test test/services/conversations/create_branch_test.rb
bin/rails test test/services/lineage_stores/compact_snapshot_test.rb
bin/rails test test/integration/conversation_lineage_store_branch_flow_test.rb
```

Expected: failures should expose a missing guard, missing assertion, or weakly
specified lineage expectation.

**Step 3: Write minimal implementation**

Delete weak tests when they only repeat lower-level behavior. Where the service
code truly lacks a guard or invariant, implement only the required fix.

**Step 4: Run test to verify it passes**

Re-run the same files until lifecycle and lineage expectations pass.

**Step 5: Commit**

```bash
git add app/services/conversations/request_close.rb \
  app/services/conversations/rollback_to_turn.rb \
  app/services/conversations/create_branch.rb \
  app/services/lineage_stores/compact_snapshot.rb \
  test/services/conversations/request_close_test.rb \
  test/services/conversations/rollback_to_turn_test.rb \
  test/services/conversations/create_branch_test.rb \
  test/services/lineage_stores/compact_snapshot_test.rb \
  test/integration/conversation_lineage_store_branch_flow_test.rb
git commit -m "test: strengthen conversation lifecycle and lineage coverage"
```

### Task 4: Harden Provider Execution Success And Failure Persistence

**Files:**
- Modify: `app/services/provider_execution/execute_turn_step.rb`
- Modify: `app/services/provider_execution/persist_turn_step_success.rb`
- Modify: `app/services/provider_execution/persist_turn_step_failure.rb`
- Modify: `test/services/provider_execution/execute_turn_step_test.rb`
- Modify: `test/services/provider_execution/persist_turn_step_success_test.rb`
- Modify: `test/services/provider_execution/persist_turn_step_failure_test.rb`
- Modify: `test/integration/provider_backed_turn_execution_test.rb`
- Test: `test/services/provider_execution/execute_turn_step_test.rb`
- Test: `test/services/provider_execution/persist_turn_step_success_test.rb`
- Test: `test/services/provider_execution/persist_turn_step_failure_test.rb`
- Test: `test/integration/provider_backed_turn_execution_test.rb`

**Step 1: Write the failing test**

Add or tighten assertions around:

- sanitized request-body contracts
- selected output persistence
- token usage persistence
- failure state propagation and retry-ready metadata

Example:

```ruby
assert_equal "Direct provider result",
  workflow_run.turn.reload.selected_output_message.content
assert_equal 20, usage_event.reload.total_tokens
```

**Step 2: Run test to verify it fails**

Run:

```bash
bin/rails test test/services/provider_execution/execute_turn_step_test.rb
bin/rails test test/services/provider_execution/persist_turn_step_success_test.rb
bin/rails test test/services/provider_execution/persist_turn_step_failure_test.rb
bin/rails test test/integration/provider_backed_turn_execution_test.rb
```

Expected: failures should demonstrate missing contract protection or a real
incorrect persistence path.

**Step 3: Write minimal implementation**

Tighten tests first. If the service code fails the stronger contract, fix the
smallest persistence or request-building seam necessary.

**Step 4: Run test to verify it passes**

Re-run the same files until request and persistence behavior matches the new
specification.

**Step 5: Commit**

```bash
git add app/services/provider_execution/execute_turn_step.rb \
  app/services/provider_execution/persist_turn_step_success.rb \
  app/services/provider_execution/persist_turn_step_failure.rb \
  test/services/provider_execution/execute_turn_step_test.rb \
  test/services/provider_execution/persist_turn_step_success_test.rb \
  test/services/provider_execution/persist_turn_step_failure_test.rb \
  test/integration/provider_backed_turn_execution_test.rb
git commit -m "test: strengthen provider execution persistence coverage"
```

### Task 5: Sweep Batch 1 For Low-Value Tests

**Files:**
- Modify: the specific Batch 1 test files classified as `delete` or `rewrite_or_lower` in `docs/plans/2026-03-29-core-matrix-test-suite-audit-findings.md`
- Test: the focused directories under `test/services/workflows`, `test/services/turns`, `test/services/conversations`, `test/services/lineage_stores`, and `test/services/provider_execution`

**Step 1: Write the failing test**

Where a file is marked `rewrite_or_lower`, first add the stronger assertion at
the correct layer before deleting the weaker one. Do not delete coverage before
replacement exists.

**Step 2: Run test to verify it fails**

Run only the replacement file(s) first and confirm they fail for the intended
behavior.

**Step 3: Write minimal implementation**

Delete duplicate or low-signal tests, merge overlapping examples, and keep the
replacement behavior-focused cases.

**Step 4: Run test to verify it passes**

Run:

```bash
bin/rails test test/services/workflows \
  test/services/turns \
  test/services/conversations \
  test/services/lineage_stores \
  test/services/provider_execution
```

Expected: focused Batch 1 directories pass without the removed weak cases.

**Step 5: Commit**

```bash
git add docs/plans/2026-03-29-core-matrix-test-suite-audit-findings.md test/services
git commit -m "test: remove low-value batch 1 coverage"
```

### Task 6: Verify Batch 1 And Re-read Coverage

**Files:**
- Test: `test/services/workflows`
- Test: `test/services/turns`
- Test: `test/services/conversations`
- Test: `test/services/lineage_stores`
- Test: `test/services/provider_execution`
- Test: `test/integration/workflow_context_flow_test.rb`
- Test: `test/integration/conversation_lineage_store_branch_flow_test.rb`
- Test: `test/integration/provider_backed_turn_execution_test.rb`

**Step 1: Run focused verification**

Run:

```bash
bin/rails test test/services/workflows
bin/rails test test/services/turns
bin/rails test test/services/conversations
bin/rails test test/services/lineage_stores
bin/rails test test/services/provider_execution
bin/rails test test/integration/workflow_context_flow_test.rb
bin/rails test test/integration/conversation_lineage_store_branch_flow_test.rb
bin/rails test test/integration/provider_backed_turn_execution_test.rb
```

Expected: all touched Batch 1 suites pass.

**Step 2: Run coverage-aware verification**

Run:

```bash
bin/rails test test/services/workflows \
  test/services/turns \
  test/services/conversations \
  test/services/lineage_stores \
  test/services/provider_execution \
  test/integration/workflow_context_flow_test.rb \
  test/integration/conversation_lineage_store_branch_flow_test.rb \
  test/integration/provider_backed_turn_execution_test.rb
```

Expected: `coverage/.resultset.json` updates and the touched critical-path files
show improved or more defensible coverage.

**Step 3: Review residual gaps**

Search the coverage output and findings ledger for the next Batch 1 hotspots.
Only then start Batch 2.
