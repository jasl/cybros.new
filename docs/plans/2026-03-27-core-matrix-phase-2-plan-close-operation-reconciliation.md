# Close Operation Reconciliation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refactor Phase 2 close progression so `ConversationCloseOperation` is reconciled by one conversation-scoped service, every close-summary-affecting path explicitly routes through that service, and archive or delete no longer require a second request to advance state after blockers clear.

**Architecture:** Introduce `Conversations::ReconcileCloseOperation` as the single application-layer writer for close lifecycle state and archive-side conversation transition. Then migrate `RequestClose`, `FinalizeDeletion`, `RequestTurnInterrupt`, and `AgentControl::Report` to call it explicitly, extend regression coverage for local and mailbox-driven blocker removal, and finish with grep-based exhaustiveness checks so no duplicate close writers remain.

**Tech Stack:** Ruby on Rails (`core_matrix`), Active Record transactions and row locks, mailbox control plane, Minitest service/integration/E2E coverage, Phase 2 planning docs

---

## Execution Rules

- Treat this as a structural repair, not a compatibility exercise.
- Do not keep duplicated close-state writers alive behind temporary shims.
- Do not solve the `SubagentRun` bug with a one-off special case in
  `AgentControl::Report`.
- Keep reconciliation explicit in application services; do not add model
  callbacks for close progression.
- Preserve the existing archive-versus-delete product distinction.
- Extend the existing Milestone C tests and protocol E2E harness instead of
  creating a second close stack.
- After each migration step, re-run grep-based checks to confirm no stale
  lifecycle writers remain.
- Commit after every task with the suggested message or a tighter equivalent.

## Current Implementations That Must Be Adjusted

These are the current code paths that should change during implementation:

- `core_matrix/app/services/conversations/request_close.rb`
  Reason: computes close summary and lifecycle inline; should delegate to the
  reconciler.
- `core_matrix/app/services/conversations/finalize_deletion.rb`
  Reason: computes delete-side close lifecycle inline; should delegate to the
  reconciler after `deleted` is durable.
- `core_matrix/app/services/conversations/request_turn_interrupt.rb`
  Reason: can clear mainline blockers and finalize turn/workflow cancellation
  without refreshing an unfinished close operation.
- `core_matrix/app/services/agent_control/report.rb`
  Reason: mailbox terminal close reporting currently resolves close progression
  only for resources that directly expose `conversation`.
- `core_matrix/app/queries/conversations/close_summary_query.rb`
  Reason: remains the summary source of truth and may need small clarifying
  changes or comments once the reconciler becomes the only lifecycle writer.
- `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
  Reason: must state the new single-writer reconciliation contract explicitly.
- `core_matrix/docs/behavior/agent-runtime-resource-apis.md`
  Reason: must state that terminal close reports trigger conversation close
  reconciliation when a close operation is active.

Before finishing, explicitly re-check that no other path writes
`ConversationCloseOperation.lifecycle_state`, `summary_payload`, or
`completed_at` directly.

## Post-Implementation Hardening Notes

A later audit found two follow-up race windows that belong to the same close
fence contract and should stay documented with this plan:

- `Conversations::RequestTurnInterrupt` must cancel superseded retry mailbox
  items in both `queued` and `leased` state, clear any existing lease
  attribution, and rely on `AgentControl::Poll` to deliver
  `execution_assignment` only while the backing `AgentTaskRun` remains `queued`
- `ProviderExecution::ExecuteTurnStep` must perform a second freshness check
  under lock before persisting success or failure so a late local provider
  result cannot overwrite `turn_interrupted` state or create post-fence
  transcript, usage, or profiling side effects

### Task 1: Introduce The Reconciler And Lock Its Decision Contract Down With Tests

**Files:**
- Create: `core_matrix/app/services/conversations/reconcile_close_operation.rb`
- Create: `core_matrix/test/services/conversations/reconcile_close_operation_test.rb`
- Modify: `core_matrix/app/models/conversation.rb`
- Modify: `core_matrix/test/models/conversation_close_operation_test.rb`

**Step 1: Write the failing tests**

Add focused service-level tests that prove the reconciler is the single
decision point. Cover at least:

- archive close stays `quiescing` while mainline blockers remain
- archive close moves to `disposing` and archives the conversation when the
  mainline is clear but detached background tail remains
- archive close moves to `completed` when both mainline and tail are clear
- delete close remains `quiescing` until the conversation is already `deleted`
- delete close moves to `disposing`, `degraded`, or `completed` only after
  final deletion has happened

Example expectation:

```ruby
test "archive reconcile archives the conversation once mainline blockers clear" do
  conversation, close_operation = build_archive_close_scenario_with_mainline_clear!

  Conversations::ReconcileCloseOperation.call(conversation: conversation)

  assert_equal "archived", conversation.reload.lifecycle_state
  assert_equal "disposing", close_operation.reload.lifecycle_state
end
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/conversations/reconcile_close_operation_test.rb \
  test/models/conversation_close_operation_test.rb
```

Expected: FAIL because the reconciler service does not yet exist and the
single-writer contract is not implemented.

**Step 3: Write the minimal implementation**

Implement `Conversations::ReconcileCloseOperation` with these constraints:

- lock the conversation row before mutating close state
- load the unfinished close operation, or no-op if none exists
- compute summary through `Conversations::CloseSummaryQuery`
- derive lifecycle state from summary plus current conversation state
- write `summary_payload`, `lifecycle_state`, and `completed_at`
- for archive intent only, set `conversation.lifecycle_state = "archived"`
  inside the reconciler once the mainline stop barrier is clear
- keep delete-side product transition out of this service; delete still becomes
  `deleted` only through `FinalizeDeletion`

**Step 4: Run tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/conversations/reconcile_close_operation.rb \
  core_matrix/app/models/conversation.rb \
  core_matrix/test/services/conversations/reconcile_close_operation_test.rb \
  core_matrix/test/models/conversation_close_operation_test.rb
git commit -m "refactor: add close operation reconciler"
```

### Task 2: Migrate Close Initiation And Final Deletion To The Reconciler

**Files:**
- Modify: `core_matrix/app/services/conversations/request_close.rb`
- Modify: `core_matrix/app/services/conversations/finalize_deletion.rb`
- Modify: `core_matrix/test/services/conversations/archive_test.rb`
- Modify: `core_matrix/test/services/conversations/request_deletion_test.rb`
- Modify: `core_matrix/test/services/conversations/finalize_deletion_test.rb`

**Step 1: Write the failing regression tests**

Add tests that exercise initiation and finalization through the new single
writer:

- force archive should create or reuse the close operation and immediately
  persist a reconciled summary instead of bespoke inline lifecycle logic
- `FinalizeDeletion` should update `deletion_state = deleted` and then rely on
  the reconciler for close-operation lifecycle
- delete should not require a later manual refresh call to move from
  `quiescing` once final deletion is complete

Example expectation:

```ruby
test "finalize deletion reconciles the unfinished close operation after marking deleted" do
  finalized = Conversations::FinalizeDeletion.call(conversation: conversation.reload)

  assert finalized.deleted?
  assert_includes %w[disposing degraded completed],
    finalized.unfinished_close_operation&.lifecycle_state || finalized.conversation_close_operations.last.lifecycle_state
end
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/conversations/archive_test.rb \
  test/services/conversations/request_deletion_test.rb \
  test/services/conversations/finalize_deletion_test.rb
```

Expected: FAIL because `RequestClose` and `FinalizeDeletion` still compute close
progression themselves.

**Step 3: Write the minimal implementation**

Refactor both services so they keep only their real responsibilities:

- `RequestClose`
  - create or reuse the close operation
  - request interrupts and background close work
  - invoke `Conversations::ReconcileCloseOperation`
  - remove `refresh_close_operation!`, `close_operation_lifecycle_state`, and
    related inline lifecycle helpers
- `FinalizeDeletion`
  - validate final deletion preconditions
  - remove the canonical store reference
  - set `deletion_state = "deleted"`
  - invoke `Conversations::ReconcileCloseOperation`
  - remove its duplicate close-state decision block

**Step 4: Run tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/conversations/request_close.rb \
  core_matrix/app/services/conversations/finalize_deletion.rb \
  core_matrix/test/services/conversations/archive_test.rb \
  core_matrix/test/services/conversations/request_deletion_test.rb \
  core_matrix/test/services/conversations/finalize_deletion_test.rb
git commit -m "refactor: route close initiation and deletion finalization through reconciler"
```

### Task 3: Reconcile After Local Mainline-Barrier State Changes

**Files:**
- Modify: `core_matrix/app/services/conversations/request_turn_interrupt.rb`
- Modify: `core_matrix/test/services/conversations/request_turn_interrupt_test.rb`
- Modify: `core_matrix/test/e2e/protocol/turn_interrupt_e2e_test.rb`

**Step 1: Write the failing regression tests**

Add tests proving local blocker removal also refreshes close progression:

- if `RequestTurnInterrupt` cancels the last local blocker while a close
  operation is active, the close operation is reconciled immediately
- local cancellation of blocking human interactions or queued retry work does
  not wait for a later archive/delete call to update summary

Example expectation:

```ruby
test "turn interrupt reconciles close progress after clearing local blockers" do
  Conversations::Archive.call(conversation: context[:conversation], force: true, occurred_at: freeze_time)

  assert_equal "quiescing", context[:conversation].conversation_close_operations.last.reload.lifecycle_state

  Conversations::RequestTurnInterrupt.call(turn: context[:turn], occurred_at: freeze_time + 1.second)

  assert_includes %w[disposing completed degraded],
    context[:conversation].conversation_close_operations.last.reload.lifecycle_state
end
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/conversations/request_turn_interrupt_test.rb \
  test/e2e/protocol/turn_interrupt_e2e_test.rb
```

Expected: FAIL because `RequestTurnInterrupt` currently finishes local state
changes without re-entering close reconciliation.

**Step 3: Write the minimal implementation**

Refactor `RequestTurnInterrupt` so it:

- preserves its existing turn and workflow fence semantics
- explicitly checks whether the conversation is closing
- invokes `Conversations::ReconcileCloseOperation` after local blocker changes
  or after turn/workflow finalization
- avoids duplicate inline close-lifecycle reasoning

Keep the service explicit; do not add callbacks on `Turn`, `WorkflowRun`, or
`HumanInteractionRequest`.

**Step 4: Run tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/conversations/request_turn_interrupt.rb \
  core_matrix/test/services/conversations/request_turn_interrupt_test.rb \
  core_matrix/test/e2e/protocol/turn_interrupt_e2e_test.rb
git commit -m "refactor: reconcile close progress after local turn interrupts"
```

### Task 4: Reconcile Mailbox Terminal Close Paths For Every Runtime Resource

**Files:**
- Modify: `core_matrix/app/services/agent_control/report.rb`
- Modify: `core_matrix/test/services/agent_control/report_test.rb`
- Modify: `core_matrix/test/e2e/protocol/conversation_close_e2e_test.rb`
- Modify: `core_matrix/test/e2e/protocol/process_close_escalation_e2e_test.rb`
- Modify: `core_matrix/test/services/conversations/archive_test.rb`

**Step 1: Write the failing regression tests**

Add explicit regressions for mailbox-driven progression:

- force archive with a `SubagentRun` as the last mainline blocker archives the
  conversation after the `resource_closed` report without needing a second
  archive call
- force delete with a `SubagentRun` as the last mainline blocker reconciles the
  close operation immediately after the terminal close report
- process close reporting still reconciles correctly for `ProcessRun`
- `AgentTaskRun` close reporting still reconciles correctly for task-owned
  blocker removal

Example expectation:

```ruby
test "subagent terminal close report archives the conversation when it clears the last mainline blocker" do
  close_request = start_force_archive_with_running_subagent!

  report_resource_closed!(mailbox_item: close_request, close_outcome_kind: "graceful")

  assert context[:conversation].reload.archived?
  assert_includes %w[disposing completed degraded],
    context[:conversation].conversation_close_operations.last.reload.lifecycle_state
end
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/agent_control/report_test.rb \
  test/e2e/protocol/conversation_close_e2e_test.rb \
  test/e2e/protocol/process_close_escalation_e2e_test.rb \
  test/services/conversations/archive_test.rb
```

Expected: FAIL because mailbox terminal close handling still resolves close
progression only for resources that directly expose `conversation`.

**Step 3: Write the minimal implementation**

Refactor `AgentControl::Report` so terminal close handling:

- keeps ownership over mailbox idempotency and resource terminalization
- stops writing close progression itself
- resolves conversation generically from:
  - `resource.conversation`
  - or `resource.turn.conversation`
  - or `resource.workflow_run.conversation`
- invokes `Conversations::ReconcileCloseOperation` after
  `reconcile_turn_interrupt!`
- removes the old resource-specific close refresh helper

Do not leave a one-off `SubagentRun` branch behind; keep the resource-to-
conversation rule generic for future Phase 2 runtime resources.

**Step 4: Run tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/agent_control/report.rb \
  core_matrix/test/services/agent_control/report_test.rb \
  core_matrix/test/e2e/protocol/conversation_close_e2e_test.rb \
  core_matrix/test/e2e/protocol/process_close_escalation_e2e_test.rb \
  core_matrix/test/services/conversations/archive_test.rb
git commit -m "refactor: reconcile close progress from mailbox terminal reports"
```

### Task 5: Remove Leftover Duplicate Writers, Update Docs, And Run Exhaustiveness Checks

**Files:**
- Modify: `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
- Modify: `core_matrix/docs/behavior/agent-runtime-resource-apis.md`
- Modify: `docs/plans/README.md`
- Modify: `docs/plans/2026-03-26-core-matrix-phase-2-plan-agent-loop-execution.md`
- Modify: `docs/plans/2026-03-26-core-matrix-phase-2-milestone-c-runtime-pairing-and-control.md`
- Modify: `docs/plans/2026-03-26-core-matrix-phase-2-task-turn-interrupt-and-conversation-close-semantics.md`

**Step 1: Run grep-based exhaustiveness checks before editing docs**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
rg -n "ConversationCloseOperation.*update!|close_operation.update!|lifecycle_state: .*quiescing|lifecycle_state: .*disposing|lifecycle_state: .*completed|lifecycle_state: .*degraded" app
rg -n "CloseSummaryQuery.call" app
```

Expected:

- only `Conversations::ReconcileCloseOperation` should remain as the
  application-layer writer for close lifecycle state
- `CloseSummaryQuery.call` should appear only in the reconciler and in tests or
  read-only documentation helpers

If another writer remains, stop and fold it into the reconciler before editing
docs.

**Step 2: Update docs to match the landed architecture**

Document these rules explicitly:

- `ConversationCloseOperation` progression is single-writer and explicit
- every close-summary-affecting mutation path must re-enter the reconciler
- mailbox terminal close reports participate in the same close progression as
  local blocker removal
- `SubagentRun` is a first-class mainline blocker and close-progress trigger

Also link the new follow-up plan into the Phase 2 plan chain so execution does
not depend on chat context.

**Step 3: Run targeted verification**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test \
  test/services/conversations/reconcile_close_operation_test.rb \
  test/services/conversations/archive_test.rb \
  test/services/conversations/request_deletion_test.rb \
  test/services/conversations/finalize_deletion_test.rb \
  test/services/conversations/request_turn_interrupt_test.rb \
  test/services/agent_control/report_test.rb \
  test/e2e/protocol/turn_interrupt_e2e_test.rb \
  test/e2e/protocol/conversation_close_e2e_test.rb \
  test/e2e/protocol/process_close_escalation_e2e_test.rb
```

Expected: PASS

**Step 4: Re-run the exhaustiveness checks**

Run the same `rg` commands again and confirm the single-writer invariant still
holds after documentation cleanup and any last code edits.

**Step 5: Commit**

```bash
git add core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md \
  core_matrix/docs/behavior/agent-runtime-resource-apis.md \
  docs/plans/README.md \
  docs/plans/2026-03-26-core-matrix-phase-2-plan-agent-loop-execution.md \
  docs/plans/2026-03-26-core-matrix-phase-2-milestone-c-runtime-pairing-and-control.md \
  docs/plans/2026-03-26-core-matrix-phase-2-task-turn-interrupt-and-conversation-close-semantics.md
git commit -m "docs: document unified close operation reconciliation"
```

## Completeness Check

This plan is not complete unless all of the following are still true after
re-reading it end to end:

- the goal is explicit
- the architecture is explicit
- every current implementation that must change is named directly
- the new single-writer invariant is explicit
- regression coverage includes local and mailbox-driven blocker removal
- `SubagentRun` regression coverage is explicit
- the docs update task includes grep-based exhaustiveness checks
- the task relationship is linear and dependency-safe
- no task depends on unwritten assumptions from chat-only context
