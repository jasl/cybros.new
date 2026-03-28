# Runtime Binding And Rewrite Safety Hardening Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Repair Milestone C runtime binding drift so deployment rebinding, new turn entry, turn-history rewrite, and wait-state blocker identifiers all use one coherent safety contract.

**Architecture:** Introduce shared service-level validators for deployment rebinding and rewrite-target safety, make new turn-entry inherit the conversation-bound deployment, add a `Turn` backstop invariant for execution-environment consistency, and normalize `blocking_resource_id` to durable external-style identifiers. Finish with targeted, neighboring, and grep-based verification so the repaired rules apply to current and future entry points.

**Tech Stack:** Ruby on Rails (`core_matrix`), Active Record transactions and validations, Minitest service/integration coverage, Phase 2 planning docs

---

## Execution Rules

- Treat this as a structural hardening follow-up for `Milestone C`.
- Do not solve `ManualRetry` with a one-off environment check while leaving the
  other rebinding paths unsynchronized.
- Keep the shared safety rules explicit in application services; do not hide
  them behind callbacks.
- New turn-entry helpers must inherit the conversation binding instead of
  trusting arbitrary external deployment input.
- Keep the `Turn` model invariant as a backstop only; do not move the whole
  orchestration layer into the model.
- Normalize `blocking_resource_id` semantics rather than documenting the mixed
  bigint versus `public_id` behavior.
- Extend the existing tests and docs instead of creating alternate recovery or
  rewrite stacks.
- After each migration task, re-run grep checks so future paths cannot quietly
  bypass the shared rules.
- Commit after every task with the suggested message or a tighter equivalent.

## Current Implementations That Must Be Adjusted

- `core_matrix/app/services/conversations/switch_agent_deployment.rb`
  Reason: validates target deployment inline instead of through a shared
  deployment-target contract.
- `core_matrix/app/services/workflows/manual_resume.rb`
  Reason: partially duplicates deployment-target validation and should reuse the
  shared contract for common checks.
- `core_matrix/app/services/workflows/manual_retry.rb`
  Reason: can rebind paused work to a deployment outside the conversation's
  bound execution environment.
- `core_matrix/app/services/agent_deployments/auto_resume_workflows.rb`
  Reason: rotated auto-resume rebinding must use the same deployment-target
  contract and must not drift across execution environments.
- `core_matrix/app/services/turns/start_user_turn.rb`
  Reason: currently trusts a caller-supplied deployment for new turn entry.
- `core_matrix/app/services/turns/queue_follow_up.rb`
  Reason: currently trusts a caller-supplied deployment for queued turn entry.
- `core_matrix/app/services/turns/start_automation_turn.rb`
  Reason: currently trusts a caller-supplied deployment for automation turn
  entry.
- `core_matrix/app/models/turn.rb`
  Reason: lacks a backstop invariant for deployment/environment consistency.
- `core_matrix/app/services/turns/retry_output.rb`
  Reason: reactivates a turn without a shared retention/close-fence guard.
- `core_matrix/app/services/turns/rerun_output.rb`
  Reason: reactivates or branches replay work without a shared
  retention/close-fence guard.
- `core_matrix/app/services/agent_deployments/unavailable_pause_state.rb`
  Reason: still writes internal deployment ids into `blocking_resource_id`.
- `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
  Reason: must state the normalized blocker identifier contract and the shared
  safety rules explicitly.
- `docs/plans/2026-03-26-core-matrix-phase-2-review-audit-findings.md`
  Reason: should be refreshable against the landed result once implementation is
  complete.

Before finishing, explicitly re-check that:

- deployment rebinding paths all use the shared validator
- new turn-entry paths do not trust arbitrary external deployment input
- rewrite helpers all use the shared rewrite-target validator
- `blocking_resource_id` writers all follow one identifier semantic

### Task 1: Introduce The Shared Deployment Target Validator

**Files:**
- Create: `core_matrix/app/services/conversations/validate_agent_deployment_target.rb`
- Modify: `core_matrix/app/services/conversations/switch_agent_deployment.rb`
- Modify: `core_matrix/test/services/conversations/switch_agent_deployment_test.rb`
- Modify: `core_matrix/test/services/workflows/manual_resume_test.rb`

**Step 1: Write the failing tests**

Add focused tests proving the shared validator contract:

- `SwitchAgentDeployment` still rejects deployments from another execution
  environment
- `ManualResume` still rejects mismatched logical agents
- `ManualResume` still rejects incompatible capability contracts
- both services rely on the same common installation/environment validation path

Example expectation:

```ruby
test "switch agent deployment rejects a deployment outside the bound environment" do
  error = assert_raises(ActiveRecord::RecordInvalid) do
    Conversations::SwitchAgentDeployment.call(
      conversation: conversation,
      agent_deployment: replacement
    )
  end

  assert_includes error.record.errors[:agent_deployment], "must belong to the bound execution environment"
end
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/conversations/switch_agent_deployment_test.rb \
  test/services/workflows/manual_resume_test.rb
```

Expected: FAIL because the shared validator does not yet exist.

**Step 3: Write the minimal implementation**

Implement `Conversations::ValidateAgentDeploymentTarget` with these
constraints:

- accept `conversation:`, `agent_deployment:`, and explicit options for extra
  continuity requirements
- own common same-installation and same-environment checks
- optionally enforce same logical agent installation
- optionally enforce paused capability-contract preservation
- attach errors to the caller-facing record and raise `RecordInvalid`
- refactor `SwitchAgentDeployment` and `ManualResume` to call it

**Step 4: Run tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/conversations/validate_agent_deployment_target.rb \
  core_matrix/app/services/conversations/switch_agent_deployment.rb \
  core_matrix/test/services/conversations/switch_agent_deployment_test.rb \
  core_matrix/test/services/workflows/manual_resume_test.rb
git commit -m "refactor: share conversation deployment target validation"
```

### Task 2: Route Manual Retry Through Explicit Conversation Rebinding

**Files:**
- Modify: `core_matrix/app/services/workflows/manual_retry.rb`
- Modify: `core_matrix/test/services/workflows/manual_retry_test.rb`
- Modify: `core_matrix/test/integration/agent_recovery_flow_test.rb`

**Step 1: Write the failing tests**

Add regressions that prove retry cannot drift runtime binding:

- manual retry rejects a deployment outside the bound execution environment
- the successful retry path explicitly rebinds the conversation before creating
  the new turn
- the successful retry path leaves conversation binding, turn deployment, and
  serialized execution identity coherent

Example expectation:

```ruby
test "manual retry rejects a deployment outside the bound execution environment" do
  error = assert_raises(ActiveRecord::RecordInvalid) do
    Workflows::ManualRetry.call(
      workflow_run: paused_workflow_run,
      deployment: other_environment_deployment,
      actor: actor
    )
  end

  assert_includes error.record.errors[:agent_deployment], "must belong to the bound execution environment"
end
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/workflows/manual_retry_test.rb \
  test/integration/agent_recovery_flow_test.rb
```

Expected: FAIL because `ManualRetry` currently allows cross-environment retry
targets.

**Step 3: Write the minimal implementation**

Refactor `ManualRetry` so it:

- validates the candidate deployment through the shared validator
- explicitly rebinds the conversation through `Conversations::SwitchAgentDeployment`
  before creating the new turn
- creates the retried turn from the conversation-bound deployment rather than
  trusting arbitrary external deployment input
- keeps existing paused-state and input-presence validation
- keep rotated auto-resume rebinding aligned with the same contract so the new
  `Turn` invariant does not expose a sibling drift path

**Step 4: Run tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/workflows/manual_retry.rb \
  core_matrix/test/services/workflows/manual_retry_test.rb \
  core_matrix/test/integration/agent_recovery_flow_test.rb
git commit -m "fix: rebind conversations explicitly before manual retry"
```

### Task 3: Collapse Turn Entry Onto Conversation-Bound Deployment And Add A Backstop Invariant

**Files:**
- Modify: `core_matrix/app/services/turns/start_user_turn.rb`
- Modify: `core_matrix/app/services/turns/queue_follow_up.rb`
- Modify: `core_matrix/app/services/turns/start_automation_turn.rb`
- Modify: `core_matrix/app/models/turn.rb`
- Modify: `core_matrix/test/services/turns/start_user_turn_test.rb`
- Modify: `core_matrix/test/services/turns/queue_follow_up_test.rb`
- Modify: `core_matrix/test/services/turns/start_automation_turn_test.rb`
- Modify: `core_matrix/test/models/turn_test.rb`

**Step 1: Write the failing tests**

Add tests proving new turn-entry no longer trusts arbitrary deployment input:

- `StartUserTurn` uses the conversation-bound deployment for persisted turns
- `QueueFollowUp` uses the conversation-bound deployment for persisted turns
- `StartAutomationTurn` uses the conversation-bound deployment for persisted
  turns
- `Turn` rejects a deployment from another execution environment even if a
  caller bypasses the service layer
- archived, pending-delete, and closing guards still behave exactly as before

Example expectation:

```ruby
test "turn rejects a deployment outside the conversation environment" do
  turn = Turn.new(
    installation: installation,
    conversation: conversation,
    agent_deployment: other_environment_deployment,
    ...
  )

  assert turn.invalid?
  assert_includes turn.errors[:agent_deployment], "must belong to the conversation execution environment"
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
  test/models/turn_test.rb
```

Expected: FAIL because the current services still trust caller-supplied
deployments and `Turn` lacks the backstop invariant.

**Step 3: Write the minimal implementation**

Refactor turn-entry so it:

- derives the effective deployment from `conversation.agent_deployment`
- stops using arbitrary external deployment input as the durable source of truth
- keeps the existing conversation lifecycle and retention guards
- adds a `Turn` validation enforcing same conversation execution environment

**Step 4: Run tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/turns/start_user_turn.rb \
  core_matrix/app/services/turns/queue_follow_up.rb \
  core_matrix/app/models/turn.rb \
  core_matrix/test/services/turns/start_user_turn_test.rb \
  core_matrix/test/services/turns/queue_follow_up_test.rb \
  core_matrix/test/models/turn_test.rb
git commit -m "fix: bind new turn entry to the conversation deployment"
```

### Task 4: Introduce The Shared Rewrite Target Validator

**Files:**
- Create: `core_matrix/app/services/turns/validate_rewrite_target.rb`
- Modify: `core_matrix/app/services/turns/retry_output.rb`
- Modify: `core_matrix/app/services/turns/rerun_output.rb`
- Modify: `core_matrix/test/services/turns/retry_output_test.rb`
- Modify: `core_matrix/test/services/turns/rerun_output_test.rb`
- Modify: `core_matrix/test/integration/turn_history_rewrite_flow_test.rb`

**Step 1: Write the failing tests**

Add shared negative-path regressions for rewrite safety:

- `RetryOutput` rejects archived conversations
- `RetryOutput` rejects pending-delete conversations
- `RetryOutput` rejects turns fenced by `turn_interrupted`
- `RerunOutput` rejects conversations with an unfinished close operation
- existing happy-path rewrite behavior still works when all guards pass

Example expectation:

```ruby
test "retry output rejects an interrupted turn" do
  turn.update!(
    lifecycle_state: "canceled",
    cancellation_requested_at: Time.current,
    cancellation_reason_kind: "turn_interrupted"
  )

  error = assert_raises(ActiveRecord::RecordInvalid) do
    Turns::RetryOutput.call(message: output, content: "retry")
  end

  assert_includes error.record.errors[:turn], "must not be fenced by turn interrupt"
end
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/turns/retry_output_test.rb \
  test/services/turns/rerun_output_test.rb \
  test/integration/turn_history_rewrite_flow_test.rb
```

Expected: FAIL because the shared rewrite-target validator does not yet exist.

**Step 3: Write the minimal implementation**

Implement `Turns::ValidateRewriteTarget` so it:

- validates conversation retention and active lifecycle state
- rejects unfinished close operations
- rejects turns fenced by `turn_interrupted`
- can attach errors to the turn or conversation and raise `RecordInvalid`
- is called explicitly by `RetryOutput` and `RerunOutput` before they append new
  transcript artifacts

**Step 4: Run tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/turns/validate_rewrite_target.rb \
  core_matrix/app/services/turns/retry_output.rb \
  core_matrix/app/services/turns/rerun_output.rb \
  core_matrix/test/services/turns/retry_output_test.rb \
  core_matrix/test/services/turns/rerun_output_test.rb \
  core_matrix/test/integration/turn_history_rewrite_flow_test.rb
git commit -m "fix: share turn rewrite safety guards"
```

### Task 5: Normalize Wait-State Blocker Identifiers, Update Docs, And Run Exhaustiveness Checks

**Files:**
- Modify: `core_matrix/app/services/agent_deployments/unavailable_pause_state.rb`
- Modify: `core_matrix/test/services/agent_deployments/mark_unavailable_test.rb`
- Modify: `core_matrix/test/services/agent_deployments/auto_resume_workflows_test.rb`
- Modify: `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
- Modify: `docs/plans/2026-03-26-core-matrix-phase-2-review-audit-findings.md`
- Modify: `docs/plans/README.md`
- Modify: `docs/plans/2026-03-26-core-matrix-phase-2-plan-agent-loop-execution.md`
- Modify: `docs/plans/2026-03-26-core-matrix-phase-2-milestone-c-runtime-pairing-and-control.md`

**Step 1: Write the failing tests**

Add or update tests proving the normalized blocker identifier contract:

- `MarkUnavailable` stores `AgentDeployment.public_id`
- paused snapshot and restore behavior still works for human interaction and
  other blocker kinds
- auto-resume leaves wait-state restoration coherent after the identifier
  normalization

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/agent_deployments/mark_unavailable_test.rb \
  test/services/agent_deployments/auto_resume_workflows_test.rb
```

Expected: FAIL because agent-unavailable still stores `deployment.id.to_s`.

**Step 3: Write the minimal implementation**

Refactor `UnavailablePauseState` so it:

- stores `deployment.public_id` in `blocking_resource_id`
- preserves snapshot/resume semantics for existing blocker kinds
- leaves wait-state restoration behavior unchanged apart from identifier shape

Then update docs so they state:

- this batch is a `Task C6 Follow-Up` under Milestone C
- deployment rebinding, turn-entry, and rewrite helpers must use the shared
  validators
- `blocking_resource_id` uses durable external-style identifiers only

**Step 4: Run targeted and neighboring verification**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/conversations/switch_agent_deployment_test.rb \
  test/services/workflows/manual_resume_test.rb \
  test/services/workflows/manual_retry_test.rb \
  test/integration/agent_recovery_flow_test.rb \
  test/services/turns/start_user_turn_test.rb \
  test/services/turns/queue_follow_up_test.rb \
  test/services/turns/retry_output_test.rb \
  test/services/turns/rerun_output_test.rb \
  test/integration/turn_history_rewrite_flow_test.rb \
  test/services/agent_deployments/mark_unavailable_test.rb \
  test/services/agent_deployments/auto_resume_workflows_test.rb
```

Expected: PASS.

**Step 5: Run wider state-machine regression**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/conversations/request_turn_interrupt_test.rb \
  test/services/workflows/execute_run_test.rb \
  test/services/agent_control/poll_test.rb \
  test/requests/agent_api/execution_delivery_test.rb \
  test/e2e/protocol/turn_interrupt_e2e_test.rb \
  test/services/conversations/archive_test.rb \
  test/services/conversations/request_deletion_test.rb \
  test/services/conversations/finalize_deletion_test.rb \
  test/services/conversations/reconcile_close_operation_test.rb \
  test/e2e/protocol/conversation_close_e2e_test.rb
```

Expected: PASS, confirming this batch does not regress the earlier close-fence
repairs.

**Step 6: Run grep-based exhaustiveness checks**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
rg -n "SwitchAgentDeployment.call|ValidateAgentDeploymentTarget.call" app
rg -n "Turns::StartUserTurn.call|Turns::QueueFollowUp.call" app
rg -n "ValidateRewriteTarget.call" app
rg -n "blocking_resource_id:" app/services
```

Expected:

- every deployment-rebinding path routes through the shared validator
- new turn-entry helpers no longer trust arbitrary deployment input as the
  durable source of truth
- rewrite helpers route through the shared rewrite validator
- `blocking_resource_id` writers all use one identifier semantic

**Step 7: Commit**

```bash
git add core_matrix/app/services/agent_deployments/unavailable_pause_state.rb \
  core_matrix/test/services/agent_deployments/mark_unavailable_test.rb \
  core_matrix/test/services/agent_deployments/auto_resume_workflows_test.rb \
  core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md \
  docs/plans/2026-03-26-core-matrix-phase-2-review-audit-findings.md \
  docs/plans/README.md \
  docs/plans/2026-03-26-core-matrix-phase-2-plan-agent-loop-execution.md \
  docs/plans/2026-03-26-core-matrix-phase-2-milestone-c-runtime-pairing-and-control.md
git commit -m "docs: record milestone c runtime binding hardening follow-up"
```

## Completion Gate

Do not call this work complete until:

- the shared deployment validator exists and all rebinding paths use it
- turn-entry services inherit conversation-bound deployment
- `Turn` rejects cross-environment persistence
- rewrite helpers use the shared rewrite validator
- `blocking_resource_id` is normalized to `public_id`
- targeted tests pass
- neighboring regression tests pass
- wider close-fence regression tests pass
- grep checks confirm no bypass path remains
