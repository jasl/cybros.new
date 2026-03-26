# Anchor Lineage And Provenance Regression Hardening Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Repair the latest lineage regressions so effective-history anchors, output-anchor fork-point protection, and output rewrite provenance all obey one explicit contract.

**Architecture:** Tighten the existing lineage contract rather than adding a new layer. Make `ValidateHistoricalAnchor` align with transcript replay, widen `Message#fork_point?` to cover output-anchor source inputs, remove provenance fallbacks from output rewrites, then re-run targeted suites, full `core_matrix` verification, and a fresh audit pass.

**Tech Stack:** Ruby on Rails (`core_matrix`), Active Record validations and services, Minitest service/integration coverage, Phase 2 planning docs

---

## Execution Rules

- Treat this as a regression-hardening follow-up to Task C8, not as a fresh
  architecture branch.
- Do not add compatibility fallbacks for malformed provenance rows.
- Do not introduce new local anchor or fork-point logic in callers when a
  shared helper can carry the rule.
- Keep the write-side and read-side historical-anchor contracts identical.
- After implementation, run full `core_matrix` verification because this batch
  is explicitly a regression fix.
- After the full suite is green, immediately run the audit plan again and
  continue only until either:
  - no new concrete defect appears, or
  - the next issue requires architectural discussion
- Commit after the documentation baseline and after each implementation task.

## Current Implementations That Must Be Adjusted

- `core_matrix/app/services/conversations/validate_historical_anchor.rb`
  Reason: only accepts parent-owned rows, not inherited transcript history.
- `core_matrix/app/models/conversation.rb`
  Reason: transcript replay still supports inherited anchors and must align with
  the validator.
- `core_matrix/app/models/message.rb`
  Reason: fork-point protection ignores source inputs of output-anchored
  descendants.
- `core_matrix/app/services/messages/update_visibility.rb`
  Reason: should inherit stricter fork-point protection from the shared helper.
- `core_matrix/app/services/turns/edit_tail_input.rb`
  Reason: should inherit stricter fork-point protection from the shared helper.
- `core_matrix/app/services/turns/rerun_output.rb`
  Reason: still falls back to the turn's current selected input for malformed
  provenance during in-place rerun.
- `core_matrix/app/services/turns/retry_output.rb`
  Reason: still falls back to the turn's current selected input for malformed
  provenance during retry.
- `core_matrix/test/services/messages/update_visibility_test.rb`
  Reason: needs inherited-anchor and output-anchor-source-input regressions.
- `core_matrix/test/integration/transcript_visibility_attachment_flow_test.rb`
  Reason: currently exposes the inherited-anchor regression and should also
  cover output-anchor-source-input protection.
- `core_matrix/test/services/turns/edit_tail_input_test.rb`
  Reason: needs output-anchor-source-input fork-point coverage.
- `core_matrix/test/services/turns/rerun_output_test.rb`
  Reason: needs fail-closed malformed provenance coverage.
- `core_matrix/test/services/turns/retry_output_test.rb`
  Reason: needs fail-closed malformed provenance coverage.
- `core_matrix/test/models/conversation_test.rb`
  Reason: needs effective-history anchor validation coverage.
- `core_matrix/test/services/conversations/create_branch_test.rb`
  Reason: needs inherited-anchor success coverage and invalid-foreign-anchor
  rejection preserved.
- `core_matrix/test/services/conversations/create_checkpoint_test.rb`
  Reason: needs inherited-anchor success coverage and invalid-foreign-anchor
  rejection preserved.
- `core_matrix/test/services/conversations/create_thread_test.rb`
  Reason: needs inherited-anchor success coverage for optional anchors.
- `core_matrix/docs/behavior/conversation-structure-and-lineage.md`
  Reason: must document effective-history anchor rules.
- `core_matrix/docs/behavior/turn-rewrite-and-variant-operations.md`
  Reason: must document output-anchor source-input fork-point protection and
  fail-closed rewrite behavior.
- `core_matrix/docs/plans/2026-03-26-core-matrix-review-audit-findings.md`
  Reason: should record the fix state after implementation and the next audit
  pass.

Before finishing, explicitly re-check that:

- all child-conversation creators still use the shared historical-anchor
  validator
- no caller now duplicates output-anchor source-input checks outside
  `Message#fork_point?`
- no output rewrite path still contains `source_input_message || selected_input`
  fallback logic

### Task 1: Align Historical Anchor Validation With Effective Transcript History

**Files:**
- Modify: `core_matrix/app/services/conversations/validate_historical_anchor.rb`
- Modify: `core_matrix/app/models/conversation.rb`
- Modify: `core_matrix/test/models/conversation_test.rb`
- Modify: `core_matrix/test/services/conversations/create_branch_test.rb`
- Modify: `core_matrix/test/services/conversations/create_checkpoint_test.rb`
- Modify: `core_matrix/test/services/conversations/create_thread_test.rb`
- Modify: `core_matrix/test/integration/transcript_visibility_attachment_flow_test.rb`

**Step 1: Write the failing tests**

Add regressions that prove:

- a branch can anchor to a message inherited into the parent's effective
  transcript
- a checkpoint can anchor to an inherited message visible in the parent
- a thread with an optional anchor can anchor to an inherited message visible in
  the parent
- foreign messages outside the effective parent transcript still fail

Example expectation:

```ruby
test "create checkpoint accepts an inherited parent-transcript anchor" do
  checkpoint = Conversations::CreateCheckpoint.call(
    parent: branch,
    historical_anchor_message_id: root_turn.selected_input_message_id
  )

  assert_equal root_turn.selected_input_message_id, checkpoint.historical_anchor_message_id
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
  test/integration/transcript_visibility_attachment_flow_test.rb
```

Expected: FAIL because the validator still rejects inherited anchors.

**Step 3: Write the minimal implementation**

Implement the shared fix so:

- `ValidateHistoricalAnchor` resolves the row and validates membership against
  the parent's effective transcript history
- `Conversation#inherited_transcript_projection_messages` accepts inherited
  anchors while still failing loudly for invalid persisted anchors
- output anchors still require replayable `source_input_message` provenance

**Step 4: Run tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/conversations/validate_historical_anchor.rb \
  core_matrix/app/models/conversation.rb \
  core_matrix/test/models/conversation_test.rb \
  core_matrix/test/services/conversations/create_branch_test.rb \
  core_matrix/test/services/conversations/create_checkpoint_test.rb \
  core_matrix/test/services/conversations/create_thread_test.rb \
  core_matrix/test/integration/transcript_visibility_attachment_flow_test.rb
git commit -m "fix: align anchors with effective transcript history"
```

### Task 2: Protect Output-Anchor Source Inputs As Fork Points

**Files:**
- Modify: `core_matrix/app/models/message.rb`
- Modify: `core_matrix/test/services/messages/update_visibility_test.rb`
- Modify: `core_matrix/test/services/turns/edit_tail_input_test.rb`
- Modify: `core_matrix/test/integration/transcript_visibility_attachment_flow_test.rb`

**Step 1: Write the failing tests**

Add regressions that prove:

- hiding a source input referenced by an output-anchored child is rejected
- excluding that source input from context is rejected
- editing that source input as the selected tail input is rejected
- direct-anchor protection still works as before

Example expectation:

```ruby
assert_includes error.record.errors[:base], "fork-point messages cannot be hidden or excluded from context"
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/messages/update_visibility_test.rb \
  test/services/turns/edit_tail_input_test.rb \
  test/integration/transcript_visibility_attachment_flow_test.rb
```

Expected: FAIL because source inputs of output-anchored descendants are not yet
treated as fork points.

**Step 3: Write the minimal implementation**

Expand the shared helper so:

- `Message#fork_point?` returns true for direct anchors and source inputs of
  anchored output messages
- visibility and tail-edit services continue using `fork_point?` without adding
  private duplicate logic

**Step 4: Run tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/models/message.rb \
  core_matrix/test/services/messages/update_visibility_test.rb \
  core_matrix/test/services/turns/edit_tail_input_test.rb \
  core_matrix/test/integration/transcript_visibility_attachment_flow_test.rb
git commit -m "fix: protect output anchor source inputs"
```

### Task 3: Fail Closed On Missing Output Provenance

**Files:**
- Modify: `core_matrix/app/services/turns/rerun_output.rb`
- Modify: `core_matrix/app/services/turns/retry_output.rb`
- Modify: `core_matrix/test/services/turns/rerun_output_test.rb`
- Modify: `core_matrix/test/services/turns/retry_output_test.rb`
- Modify: `core_matrix/test/integration/turn_history_rewrite_flow_test.rb`

**Step 1: Write the failing tests**

Add regressions that prove:

- in-place rerun rejects a target output with missing `source_input_message`
- retry rejects a target output with missing `source_input_message`
- branch rerun still rejects the same malformed provenance
- well-formed provenance still succeeds

Example expectation:

```ruby
assert_includes error.record.errors[:selected_output_message], "must carry source input provenance"
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/turns/rerun_output_test.rb \
  test/services/turns/retry_output_test.rb \
  test/integration/turn_history_rewrite_flow_test.rb
```

Expected: FAIL because in-place rerun and retry still fall back to the selected
input.

**Step 3: Write the minimal implementation**

Remove provenance fallback so:

- `RetryOutput` rejects malformed provenance
- in-place `RerunOutput` rejects malformed provenance
- branch rerun keeps the same strict rule

**Step 4: Run tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/turns/rerun_output.rb \
  core_matrix/app/services/turns/retry_output.rb \
  core_matrix/test/services/turns/rerun_output_test.rb \
  core_matrix/test/services/turns/retry_output_test.rb \
  core_matrix/test/integration/turn_history_rewrite_flow_test.rb
git commit -m "fix: fail closed on malformed output provenance"
```

### Task 4: Update Docs, Run Full Verification, And Audit Again

**Files:**
- Modify: `core_matrix/docs/behavior/conversation-structure-and-lineage.md`
- Modify: `core_matrix/docs/behavior/turn-rewrite-and-variant-operations.md`
- Modify: `core_matrix/docs/plans/2026-03-26-core-matrix-review-audit-findings.md`

**Step 1: Update behavior docs**

Document:

- effective-history anchors
- output-anchor source-input fork-point protection
- fail-closed provenance rewrite behavior

**Step 2: Run targeted regression suites**

Run:

```bash
cd core_matrix
bin/rails test \
  test/models/conversation_test.rb \
  test/services/conversations/create_branch_test.rb \
  test/services/conversations/create_checkpoint_test.rb \
  test/services/conversations/create_thread_test.rb \
  test/services/messages/update_visibility_test.rb \
  test/services/turns/edit_tail_input_test.rb \
  test/services/turns/rerun_output_test.rb \
  test/services/turns/retry_output_test.rb \
  test/integration/transcript_visibility_attachment_flow_test.rb \
  test/integration/turn_history_rewrite_flow_test.rb
```

Expected: PASS.

**Step 3: Run full `core_matrix` verification**

Run:

```bash
cd core_matrix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails db:test:prepare test
bin/rails db:test:prepare test:system
```

Expected: all commands succeed.

**Step 4: Re-run the audit plan**

Run the review workflow from:

```bash
core_matrix/docs/plans/2026-03-26-core-matrix-review-audit.md
```

Stop only when:

- no new concrete defect is found, or
- the next issue is architectural enough to require user discussion

Record the result in
`core_matrix/docs/plans/2026-03-26-core-matrix-review-audit-findings.md`.

**Step 5: Commit**

```bash
git add core_matrix/docs/behavior/conversation-structure-and-lineage.md \
  core_matrix/docs/behavior/turn-rewrite-and-variant-operations.md \
  core_matrix/docs/plans/2026-03-26-core-matrix-review-audit-findings.md
git commit -m "docs: record anchor lineage regression hardening"
```
