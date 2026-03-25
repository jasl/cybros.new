# Core Matrix Phase 1 Review Follow-Ups Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Correct the Phase 1 review regressions in `core_matrix` and finish the follow-up hardening work for attachments, projection performance, and append-only concurrency safety.

**Architecture:** Keep the existing append-only conversation and workflow model intact. Batch 1 fixes the finished-plan drift in place by tightening fork-point visibility invariants, stabilizing test assertions, and revising the historical records. Batch 2 hardens the current implementation without adding a global DAG or sequence subsystem: attachment reuse should stream from storage, transcript visibility should batch local overlay lookups, and append-only counters should be allocated under aggregate-root locks.

**Tech Stack:** Ruby on Rails, Active Record, Active Storage, PostgreSQL, Minitest, Bun, Brakeman, Bundler Audit, RuboCop

---

### Task 1: Enforce Descendant Fork-Point Visibility Protection

**Files:**
- Modify: `core_matrix/app/services/messages/update_visibility.rb`
- Modify: `core_matrix/test/services/messages/update_visibility_test.rb`
- Modify: `core_matrix/test/integration/transcript_visibility_attachment_flow_test.rb`
- Modify: `core_matrix/test/integration/transcript_import_summary_flow_test.rb`

**Step 1: Write the failing descendant-protection tests**

Add a service regression that tries to hide and exclude a fork-point anchor from a descendant branch or checkpoint projection:

```ruby
error = assert_raises(ActiveRecord::RecordInvalid) do
  Messages::UpdateVisibility.call(
    conversation: branch,
    message: anchor_message,
    excluded_from_context: true
  )
end

assert_includes error.record.errors[:base], "fork-point messages cannot be hidden or excluded from context"
```

Update the transcript integration tests so descendant projections keep the anchored message and its attachment support visible instead of accepting the overlay.

**Step 2: Run the targeted tests to verify failure**

Run:

```bash
cd core_matrix
bin/rails test test/services/messages/update_visibility_test.rb test/integration/transcript_visibility_attachment_flow_test.rb test/integration/transcript_import_summary_flow_test.rb
```

Expected:

- the new descendant overlay assertions fail because the current service only blocks native-conversation fork-point overlays

**Step 3: Implement the minimal protection change**

Tighten the guard so any attempt to hide or exclude a `fork_point?` message fails once the message has already been validated as part of the target conversation projection:

```ruby
if @message.fork_point? && (overlay.hidden? || overlay.excluded_from_context?)
  raise_invalid!(@message, :base, "fork-point messages cannot be hidden or excluded from context")
end
```

Do not weaken the existing projection-membership validation. The target rule is simple: if a message is a fork-point anchor anywhere, no projection that depends on it may hide or exclude it.

**Step 4: Run the targeted tests to verify they pass**

Run:

```bash
cd core_matrix
bin/rails test test/services/messages/update_visibility_test.rb test/integration/transcript_visibility_attachment_flow_test.rb test/integration/transcript_import_summary_flow_test.rb
```

Expected:

- all targeted descendant fork-point tests pass

**Step 5: Commit**

```bash
git -C .. add core_matrix/app/services/messages/update_visibility.rb core_matrix/test/services/messages/update_visibility_test.rb core_matrix/test/integration/transcript_visibility_attachment_flow_test.rb core_matrix/test/integration/transcript_import_summary_flow_test.rb
git -C .. commit -m "fix: protect fork-point visibility across descendants"
```

### Task 2: Stabilize Workflow Context Assertions And Revise Batch 1 Records

**Files:**
- Modify: `core_matrix/test/services/workflows/context_assembler_test.rb`
- Modify: `core_matrix/test/integration/workflow_context_flow_test.rb`
- Modify: `core_matrix/docs/behavior/transcript-visibility-and-attachments.md`
- Modify: `core_matrix/docs/behavior/transcript-imports-and-summary-segments.md`
- Modify: `core_matrix/docs/behavior/workflow-context-assembly-and-execution-snapshot.md`
- Modify: `docs/finished-plans/2026-03-24-core-matrix-phase-1-task-08-1-visibility-and-attachments.md`
- Modify: `docs/finished-plans/2026-03-24-core-matrix-phase-1-task-08-2-imports-and-summary-segments.md`
- Modify: `docs/finished-plans/2026-03-24-core-matrix-phase-1-task-09-4-context-assembly-and-execution-snapshot.md`

**Step 1: Replace order-sensitive assertions with set comparisons**

Change the flaky attachment-id expectations so both sides express the same semantics:

```ruby
expected_ids = [unsupported_audio.id.to_s, supported_file.id.to_s]
actual_ids = snapshot.dig("execution_context", "attachment_manifest").map { |item| item.fetch("attachment_id") }

assert_equal expected_ids.sort, actual_ids.sort
```

Use the same pattern in `workflow_context_flow_test.rb` anywhere order is not the behavior under test.

**Step 2: Run the workflow context tests under multiple seeds**

Run:

```bash
cd core_matrix
bin/rails test test/services/workflows/context_assembler_test.rb test/integration/workflow_context_flow_test.rb --seed 1234
bin/rails test test/services/workflows/context_assembler_test.rb test/integration/workflow_context_flow_test.rb --seed 5678
```

Expected:

- both seeded runs pass without order-related failures

**Step 3: Revise the behavior docs and finished records**

Update the behavior docs so they explicitly say fork-point transcript rows stay immutable across descendant projections. Update the three finished-plan records so their completion notes describe the review correction clearly instead of leaving the broken invariant implicit.

Use compact review language such as:

```markdown
- review correction:
  - descendant visibility overlays now reject fork-point anchors in all dependent projections
```

**Step 4: Re-run the Batch 1 targeted test suite**

Run:

```bash
cd core_matrix
bin/rails test test/services/messages/update_visibility_test.rb test/integration/transcript_visibility_attachment_flow_test.rb test/integration/transcript_import_summary_flow_test.rb test/services/workflows/context_assembler_test.rb test/integration/workflow_context_flow_test.rb
```

Expected:

- all Batch 1 transcript and workflow regressions pass together

**Step 5: Commit**

```bash
git -C .. add core_matrix/test/services/workflows/context_assembler_test.rb core_matrix/test/integration/workflow_context_flow_test.rb core_matrix/docs/behavior/transcript-visibility-and-attachments.md core_matrix/docs/behavior/transcript-imports-and-summary-segments.md core_matrix/docs/behavior/workflow-context-assembly-and-execution-snapshot.md docs/finished-plans/2026-03-24-core-matrix-phase-1-task-08-1-visibility-and-attachments.md docs/finished-plans/2026-03-24-core-matrix-phase-1-task-08-2-imports-and-summary-segments.md docs/finished-plans/2026-03-24-core-matrix-phase-1-task-09-4-context-assembly-and-execution-snapshot.md
git -C .. commit -m "docs: align phase 1 review corrections"
```

### Task 3: Stream Attachment Materialization Instead Of Buffering Blobs

**Files:**
- Modify: `core_matrix/app/services/attachments/materialize_refs.rb`
- Modify: `core_matrix/test/services/attachments/materialize_refs_test.rb`

**Step 1: Write the failing no-download regression**

Add a test that proves materialization no longer depends on `download`:

```ruby
blob = source_attachment.file.blob

blob.stub(:download, -> { raise "download should not be called" }) do
  materialized = Attachments::MaterializeRefs.call(message: target_message, refs: [source_attachment])
  assert_equal "source.txt", materialized.first.file.filename.to_s
end
```

Keep the existing ancestry assertions so the test still covers `origin_attachment`, `origin_message`, and copied bytes.

**Step 2: Run the attachment tests to verify failure**

Run:

```bash
cd core_matrix
bin/rails test test/services/attachments/materialize_refs_test.rb test/integration/transcript_visibility_attachment_flow_test.rb
```

Expected:

- the new test fails because `MaterializeRefs` currently calls `ref.file.download`

**Step 3: Implement streaming attachment reuse**

Open the source attachment through Active Storage and attach the yielded IO directly:

```ruby
ref.file.open do |source_io|
  attachment.file.attach(
    io: source_io,
    filename: ref.file.filename.to_s,
    content_type: ref.file.content_type
  )
end
```

Remove the eager `StringIO` path and any now-unused requires.

**Step 4: Run the attachment tests to verify they pass**

Run:

```bash
cd core_matrix
bin/rails test test/services/attachments/materialize_refs_test.rb test/integration/transcript_visibility_attachment_flow_test.rb
```

Expected:

- attachment reuse passes without calling `download`

**Step 5: Commit**

```bash
git -C .. add core_matrix/app/services/attachments/materialize_refs.rb core_matrix/test/services/attachments/materialize_refs_test.rb
git -C .. commit -m "fix: stream materialized attachments"
```

### Task 4: Batch Transcript Visibility Lookups For Context Projection

**Files:**
- Modify: `core_matrix/app/models/conversation.rb`
- Modify: `core_matrix/test/models/conversation_test.rb`
- Modify: `core_matrix/test/services/workflows/context_assembler_test.rb`
- Modify: `core_matrix/test/integration/workflow_context_flow_test.rb`

**Step 1: Write a failing visibility-query regression**

Add a model test that builds a branch with multiple inherited messages and descendant overlays, then counts only `conversation_message_visibilities` SQL statements while resolving `context_projection_messages`:

```ruby
queries = capture_visibility_queries { branch.context_projection_messages.map(&:id) }

assert_operator queries.size, :<=, 2
```

Implement `capture_visibility_queries` in the test using `ActiveSupport::Notifications.subscribed` and filter SQL text to the `conversation_message_visibilities` table. The current implementation should exceed the limit because it calls `exists?` for each message and each lineage hop.

**Step 2: Run the projection tests to verify failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/conversation_test.rb test/services/workflows/context_assembler_test.rb test/integration/workflow_context_flow_test.rb
```

Expected:

- the new query-shape regression fails before any behavioral assertion changes

**Step 3: Implement a batched projection visibility cache**

Keep the current lineage semantics, but preload the relevant overlay rows once per projection:

```ruby
lineage_ids = projection_conversation_chain_ids
message_ids = base_messages.map(&:id)
rows = ConversationMessageVisibility.where(conversation_id: lineage_ids, message_id: message_ids)
```

Build a lookup keyed by `message_id` and `conversation_id`, then have `hidden_in_projection?` and `excluded_from_context_in_projection?` consult the in-memory lookup instead of issuing `exists?` queries per message.

Do not change the public projection semantics. Root, thread, branch, and checkpoint results must remain identical.

**Step 4: Run the projection tests to verify they pass**

Run:

```bash
cd core_matrix
bin/rails test test/models/conversation_test.rb test/services/workflows/context_assembler_test.rb test/integration/workflow_context_flow_test.rb
```

Expected:

- the query-shape regression passes
- existing context-assembly behavior remains unchanged

**Step 5: Commit**

```bash
git -C .. add core_matrix/app/models/conversation.rb core_matrix/test/models/conversation_test.rb core_matrix/test/services/workflows/context_assembler_test.rb core_matrix/test/integration/workflow_context_flow_test.rb
git -C .. commit -m "perf: batch transcript visibility lookups"
```

### Task 5: Lock Conversation, Turn, And Deployment Allocators

**Files:**
- Create: `core_matrix/test/support/concurrent_allocation_helpers.rb`
- Modify: `core_matrix/test/test_helper.rb`
- Modify: `core_matrix/app/services/turns/start_user_turn.rb`
- Modify: `core_matrix/app/services/turns/start_automation_turn.rb`
- Modify: `core_matrix/app/services/turns/queue_follow_up.rb`
- Modify: `core_matrix/app/services/turns/steer_current_input.rb`
- Modify: `core_matrix/app/services/turns/edit_tail_input.rb`
- Modify: `core_matrix/app/services/turns/retry_output.rb`
- Modify: `core_matrix/app/services/turns/rerun_output.rb`
- Modify: `core_matrix/app/services/conversation_events/project.rb`
- Modify: `core_matrix/app/services/agent_deployments/handshake.rb`
- Modify: `core_matrix/app/services/installations/register_bundled_agent_runtime.rb`
- Create: `core_matrix/test/services/append_only/conversation_and_turn_allocation_test.rb`
- Test: `core_matrix/test/services/turns/start_user_turn_test.rb`
- Test: `core_matrix/test/services/turns/start_automation_turn_test.rb`
- Test: `core_matrix/test/services/turns/queue_follow_up_test.rb`
- Test: `core_matrix/test/services/turns/steer_current_input_test.rb`
- Test: `core_matrix/test/services/turns/edit_tail_input_test.rb`
- Test: `core_matrix/test/services/turns/retry_output_test.rb`
- Test: `core_matrix/test/services/turns/rerun_output_test.rb`
- Test: `core_matrix/test/services/conversation_events/project_test.rb`
- Test: `core_matrix/test/services/agent_deployments/handshake_test.rb`
- Test: `core_matrix/test/services/installations/register_bundled_agent_runtime_test.rb`

**Step 1: Write the failing concurrent-allocation regressions**

Create a dedicated concurrency test class with `self.use_transactional_tests = false` and helper methods that run two service calls against the same aggregate on separate connections.

Because `core_matrix/test/test_helper.rb` globally enables parallel workers, keep these new concurrency files and their commands explicitly serial. Use `PARALLEL_WORKERS=1` for the Task 5 and Task 6 concurrency commands so framework-level parallelism does not interfere with the business-level race being tested.

Cover at least:

- two concurrent `Turns::StartUserTurn.call` invocations on the same conversation
- two concurrent `ConversationEvents::Project.call` invocations on the same conversation and `stream_key`
- two concurrent tail-variant writers on the same turn
- two concurrent capability-snapshot creators on the same deployment

Example shape:

```ruby
results = run_in_parallel(2) do
  Turns::StartUserTurn.call(...)
end

assert_equal [1, 2], results.map(&:sequence).sort
```

**Step 2: Run the allocator tests to verify failure**

Run:

```bash
cd core_matrix
PARALLEL_WORKERS=1 bin/rails test test/services/append_only/conversation_and_turn_allocation_test.rb test/services/agent_deployments/handshake_test.rb test/services/installations/register_bundled_agent_runtime_test.rb
```

Expected:

- at least one concurrent path fails with duplicate-key or `RecordNotUnique` behavior before the lock-based fix lands

**Step 3: Add aggregate-root locks around each allocator**

Wrap each append-only allocation in the owning record lock and keep the create inside the same transaction:

```ruby
@conversation.with_lock do
  sequence = @conversation.turns.maximum(:sequence).to_i + 1
  Turn.create!(..., sequence: sequence)
end
```

Use the same pattern with:

- `@turn.with_lock` for `variant_index`
- `@conversation.with_lock` for `projection_sequence` and `stream_revision`
- `@deployment.with_lock` for capability `version`

Do not introduce a global counter table. The parent aggregate already defines the ordering boundary.

**Step 4: Run the allocator tests to verify they pass**

Run:

```bash
cd core_matrix
PARALLEL_WORKERS=1 bin/rails test test/services/append_only/conversation_and_turn_allocation_test.rb test/services/agent_deployments/handshake_test.rb test/services/installations/register_bundled_agent_runtime_test.rb test/services/turns/start_user_turn_test.rb test/services/turns/start_automation_turn_test.rb test/services/turns/queue_follow_up_test.rb test/services/turns/steer_current_input_test.rb test/services/turns/edit_tail_input_test.rb test/services/turns/retry_output_test.rb test/services/turns/rerun_output_test.rb test/services/conversation_events/project_test.rb
```

Expected:

- concurrent allocators succeed with unique monotonic values
- existing single-threaded turn and event tests still pass

**Step 5: Commit**

```bash
git -C .. add core_matrix/test/support/concurrent_allocation_helpers.rb core_matrix/test/test_helper.rb core_matrix/app/services/turns/start_user_turn.rb core_matrix/app/services/turns/start_automation_turn.rb core_matrix/app/services/turns/queue_follow_up.rb core_matrix/app/services/turns/steer_current_input.rb core_matrix/app/services/turns/edit_tail_input.rb core_matrix/app/services/turns/retry_output.rb core_matrix/app/services/turns/rerun_output.rb core_matrix/app/services/conversation_events/project.rb core_matrix/app/services/agent_deployments/handshake.rb core_matrix/app/services/installations/register_bundled_agent_runtime.rb core_matrix/test/services/append_only/conversation_and_turn_allocation_test.rb core_matrix/test/services/agent_deployments/handshake_test.rb core_matrix/test/services/installations/register_bundled_agent_runtime_test.rb
git -C .. commit -m "fix: lock conversation and deployment append allocators"
```

### Task 6: Lock Workflow And Process Ordinal Allocation

**Files:**
- Modify: `core_matrix/app/services/workflows/mutate.rb`
- Modify: `core_matrix/app/services/processes/start.rb`
- Modify: `core_matrix/app/services/processes/stop.rb`
- Create: `core_matrix/test/services/append_only/workflow_and_process_allocation_test.rb`
- Modify: `core_matrix/test/services/workflows/mutate_test.rb`
- Modify: `core_matrix/test/services/processes/start_test.rb`
- Modify: `core_matrix/test/services/processes/stop_test.rb`
- Modify: `core_matrix/test/integration/runtime_process_flow_test.rb`
- Modify: `core_matrix/test/integration/workflow_graph_flow_test.rb`

**Step 1: Write the failing workflow/process concurrency regressions**

Use the same separate-connection helper to cover:

- two concurrent `Workflows::Mutate.call` operations that append nodes and edges to the same `workflow_run`
- concurrent status-event writers on the same `workflow_node` through `Processes::Start.call` and `Processes::Stop.call`

Keep these commands serial for the same reason as Task 5: the concurrency signal must come from the application code under test, not from Rails test-worker fan-out.

Regression shape:

```ruby
results = run_in_parallel(
  -> { Workflows::Mutate.call(workflow_run: workflow_run, nodes: [...], edges: [...]) },
  -> { Workflows::Mutate.call(workflow_run: workflow_run, nodes: [...], edges: [...]) }
)

assert_equal expected_ordinals, workflow_run.reload.workflow_nodes.order(:ordinal).pluck(:ordinal)
```

**Step 2: Run the workflow/process tests to verify failure**

Run:

```bash
cd core_matrix
PARALLEL_WORKERS=1 bin/rails test test/services/append_only/workflow_and_process_allocation_test.rb test/services/workflows/mutate_test.rb test/services/processes/start_test.rb test/services/processes/stop_test.rb
```

Expected:

- concurrent workflow or process event allocation fails or produces duplicate-ordinal errors before the locking change

**Step 3: Lock the workflow and node allocation boundaries**

Keep the current append-only model, but lock the owning aggregate before computing ordinals:

```ruby
@workflow_run.with_lock do
  next_ordinal = workflow_nodes_scope.maximum(:ordinal).to_i + 1
  append_nodes!(...)
  append_edges!(...)
end
```

Use:

- `@workflow_run.with_lock` for workflow node and edge ordinals
- `@workflow_node.with_lock` or `@process_run.workflow_node.with_lock` for `WorkflowNodeEvent.ordinal`

The lock scope should be only the local aggregate; do not serialize unrelated workflow runs or nodes.

**Step 4: Run the workflow/process tests to verify they pass**

Run:

```bash
cd core_matrix
PARALLEL_WORKERS=1 bin/rails test test/services/append_only/workflow_and_process_allocation_test.rb test/services/workflows/mutate_test.rb test/services/processes/start_test.rb test/services/processes/stop_test.rb test/integration/runtime_process_flow_test.rb test/integration/workflow_graph_flow_test.rb
```

Expected:

- concurrent workflow mutations and process events produce unique ordinals
- existing workflow graph and runtime process flows still pass

**Step 5: Commit**

```bash
git -C .. add core_matrix/app/services/workflows/mutate.rb core_matrix/app/services/processes/start.rb core_matrix/app/services/processes/stop.rb core_matrix/test/services/append_only/workflow_and_process_allocation_test.rb core_matrix/test/services/workflows/mutate_test.rb core_matrix/test/services/processes/start_test.rb core_matrix/test/services/processes/stop_test.rb core_matrix/test/integration/runtime_process_flow_test.rb core_matrix/test/integration/workflow_graph_flow_test.rb
git -C .. commit -m "fix: lock workflow and process ordinals"
```

### Task 7: Run Full Verification And Close The Active Plan

**Files:**
- Modify: `docs/finished-plans/2026-03-25-core-matrix-phase-1-review-follow-ups-design.md`
- Modify: `docs/finished-plans/2026-03-25-core-matrix-phase-1-review-follow-ups.md`
- Modify: `docs/plans/README.md`
- Modify: `docs/finished-plans/README.md`

**Step 1: Run the full `core_matrix` verification suite serially**

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

Expected:

- all commands pass
- `test` and `test:system` are run serially because they prepare the same test database

**Step 2: Update the plan with completion evidence**

Add a completion record summarizing:

- Batch 1 direct fixes shipped
- Batch 2 hardening shipped
- final verification command output
- any retained follow-up notes that remain intentionally deferred

Mirror the closeout state in the approved design doc if it is being archived alongside the execution plan.

**Step 3: Update the plan indexes**

Move both the completed execution plan and its approved design companion into `docs/finished-plans`, then update both index files so the active-plans directory no longer claims either record is open.

**Step 4: Verify the documentation move**

Run:

```bash
git status --short
```

Expected:

- only the expected plan-index move and completion-record edits remain staged before commit

**Step 5: Commit**

```bash
git -C .. add docs/plans/README.md docs/finished-plans/2026-03-25-core-matrix-phase-1-review-follow-ups-design.md docs/finished-plans/2026-03-25-core-matrix-phase-1-review-follow-ups.md docs/finished-plans/README.md
git -C .. commit -m "docs: archive phase 1 review follow-up plan"
```
