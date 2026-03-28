# Core Matrix Phase 2 Task: Turn Interrupt And Conversation Close Semantics

Part of `Core Matrix Phase 2: Agent Loop Execution`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md`
3. `docs/design/2026-03-26-core-matrix-phase-2-test-strategy-design.md`
4. `docs/plans/2026-03-26-core-matrix-phase-2-plan-agent-loop-execution.md`
5. `docs/plans/2026-03-26-core-matrix-phase-2-milestone-c-runtime-pairing-and-control.md`
6. `docs/plans/2026-03-26-core-matrix-phase-2-task-mailbox-control-and-resource-close-contract.md`
7. `docs/plans/2026-03-27-core-matrix-phase-2-close-operation-reconciliation-design.md`
8. `docs/plans/2026-03-27-core-matrix-phase-2-plan-close-operation-reconciliation.md`

## Purpose

Land the kernel-side close semantics that make `Stop`, archive, and delete
behave consistently.

This task should establish:

- `turn_interrupt` as a first-class kernel primitive
- close fences that prevent stale retries or completions from reviving stopped
  turn work
- `ConversationCloseOperation`
- archive and delete orchestration over the mailbox control plane
- `step_retry` versus `workflow_retry` semantics
- close-summary queries for UI and operator confirmation

This task's landed implementation now has an approved follow-up design for
unifying close progression under one conversation-scoped reconciler rather than
keeping lifecycle writes distributed across initiation, finalization, and
mailbox handlers.

## Scope

### In Scope

- `turn_interrupt`
- mainline stop barrier rules
- disposal-tail rules
- `step_retry`
- `retryable_failure` workflow wait state
- `ConversationCloseOperation`
- archive force-quiesce semantics
- delete force-quiesce semantics
- finalize and purge preconditions
- parent and child close behavior
- close-summary query shape

### Out Of Scope

- provider execution internals
- MCP breadth
- generalized trigger or automation closure
- Web UI implementation

## Files

- Create: `core_matrix/app/models/conversation_close_operation.rb`
- Likely create: `core_matrix/app/services/conversations/request_turn_interrupt.rb`
- Likely create: `core_matrix/app/services/conversations/request_close.rb`
- Likely create: `core_matrix/app/queries/conversations/close_summary_query.rb`
- Likely create: `core_matrix/test/e2e/protocol/turn_interrupt_e2e_test.rb`
- Likely create: `core_matrix/test/e2e/protocol/conversation_close_e2e_test.rb`
- Likely create: `core_matrix/test/e2e/protocol/process_close_escalation_e2e_test.rb`
- Modify: `core_matrix/app/services/conversations/archive.rb`
- Modify: `core_matrix/app/services/conversations/request_deletion.rb`
- Modify: `core_matrix/app/services/conversations/finalize_deletion.rb`
- Modify: `core_matrix/app/services/conversations/purge_deleted.rb`
- Modify: `core_matrix/app/services/conversations/quiesce_active_work.rb`
- Modify: `core_matrix/app/models/conversation.rb`
- Modify: `core_matrix/app/models/turn.rb`
- Modify: `core_matrix/app/models/workflow_run.rb`
- Create: `core_matrix/test/models/conversation_close_operation_test.rb`
- Create: `core_matrix/test/services/conversations/request_turn_interrupt_test.rb`
- Modify: `core_matrix/test/services/conversations/archive_test.rb`
- Modify: `core_matrix/test/services/conversations/request_deletion_test.rb`
- Modify: `core_matrix/test/services/conversations/finalize_deletion_test.rb`
- Modify: `core_matrix/test/services/conversations/purge_deleted_test.rb`
- Modify: `core_matrix/test/integration/conversation_safe_deletion_flow_test.rb`
- Modify: `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
- Modify: `core_matrix/docs/behavior/conversation-structure-and-lineage.md`

## Required Behavior

### Turn Interrupt

- user-facing `Stop` maps to `turn_interrupt`
- `turn_interrupt` clears the mainline stop barrier only
- `turn_interrupt` fences stale or superseded work
- ordinary `step_retry` is no longer allowed once a turn has been interrupted

### Retry Semantics

- `step_retry` continues from the current turn and workflow state
- `step_retry` is distinct from `workflow_retry`
- retryable in-place step failures should move the workflow into
  `wait_reason_kind = retryable_failure`

### Archive

- archive may complete once the mainline stop barrier is clear
- detached background disposal may continue in degraded form
- archive does not archive retained children

### Delete

- delete moves the conversation into `pending_delete` immediately
- delete does not recursively delete retained children
- finalize requires the mainline stop barrier to be clear
- purge remains blocked by descendant lineage or provenance dependencies

### Disposal Expectations

- `ProcessRun(kind = turn_command)` should attempt graceful interrupt first,
  then forced termination, and persist `residual_abandoned` if forced
  termination still fails
- detached `background_service` processes should be targeted only by archive
  and delete close flows, not by plain `turn_interrupt`
- process-oriented agent-program tool runs should inherit the same close
  semantics when they are modeled as `ProcessRun`
- `MCP` or long-lived network calls should close by cancellation or connection
  abort, but still record a terminal close outcome in durable state

## Verification

Cover at least:

- stopping an active turn fences stale reports and stale retries
- retryable failure produces a step-retry gate rather than a full workflow
  restart
- archive completes only after active mainline work has stopped
- delete hides the conversation immediately while child conversations remain
  retained
- ancestor purge remains blocked by descendant lineage
- close-summary query reports mainline blockers, tail blockers, and dependency
  blockers distinctly
- protocol-E2E coverage for `turn_interrupt`, close fences, and stale late
  reports
- protocol-E2E coverage for archive and delete close flows with degraded or
  residual disposal outcomes
- protocol-E2E coverage for graceful then forced `ProcessRun` termination

This task should extend the Milestone C protocol-E2E harness created by the
mailbox-control task rather than creating a second end-to-end path.

## Stop Point

Stop after `turn_interrupt`, close orchestration, close-summary queries, and
archive or delete semantics are implemented and tested.
