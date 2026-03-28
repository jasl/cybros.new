# Workflow Scheduler And Wait States

## Purpose

Core Matrix keeps one structured current wait state on `WorkflowRun` and now
also defines how interrupt, retry, archive, and delete interact with active
workflow work.

## Status

This document reflects the landed Phase 2 scheduler and close-fence behavior.

## Workflow Wait State Shape

- `WorkflowRun` persists:
  - `wait_state`
  - `wait_reason_kind`
  - `wait_reason_payload`
  - `waiting_since_at`
  - `blocking_resource_type`
  - `blocking_resource_id`
- `blocking_resource_id` stores durable external-style identifiers only:
  - `AgentDeployment.public_id` for `agent_unavailable`
  - blocker `public_id` values for `human_interaction`, `retryable_failure`,
    and `policy_gate`
- `WorkflowRun` also persists workflow-yield continuation hints through:
  - `resume_policy`
  - `resume_metadata`
- supported wait states:
  - `ready`
  - `waiting`
- supported wait reasons:
  - `human_interaction`
  - `agent_unavailable`
  - `manual_recovery_required`
  - `policy_gate`
  - `retryable_failure`
- `waiting` requires a reason kind and `waiting_since_at`
- `ready` must not retain stale wait fields or blocking-resource references

## Scheduler Behavior

- `Workflows::Scheduler.call` returns runnable workflow nodes and does not
  mutate workflow state
- workflows in `waiting` state expose no runnable nodes
- workflow ordering for scheduler and later proof export continues to use the
  frozen node `ordinal`, while yielded intent nodes may also carry
  `stage_index` and `stage_position` for stage-local inspection
- `Workflows::Scheduler.apply_during_generation_policy` supports:
  - `reject`
  - `restart`
  - `queue`
- queued follow-up turns record public-id based origin metadata:
  - `expected_tail_message_id` uses the predecessor output message `public_id`
  - `queued_from_turn_id` uses the predecessor turn `public_id`
- queued follow-up turns are guarded by predecessor-tail drift checks before
  execution

## Workflow Yield And Resume Substrate

- `Workflows::IntentBatchMaterialization` records workflow-first yield facts on
  the yielding node instead of mutating kernel state in place
- accepted intents become durable workflow nodes
- rejected intents remain audit-only node events
- barrier summaries are stored as workflow artifacts on the yielding node
- current Phase 2 resume policy is `re_enter_agent`; later continuation work
  should create a successor agent step from `resume_metadata` rather than
  continuing an old batch tail under a stale snapshot

## Recovery Behavior

- `AgentDeployments::MarkUnavailable` moves active workflows into a waiting
  state when the pinned deployment becomes unavailable
- `agent_unavailable` stores:
  - `blocking_resource_type = "AgentDeployment"`
  - `blocking_resource_id = <deployment public_id>`
- if a workflow was already waiting on another blocker, outage pause snapshots
  that original blocker and restores it after recovery instead of erasing it
- `WorkflowWaitSnapshot` is the explicit parser and restore contract for those
  nested pause payloads
- `AgentDeployments::AutoResumeWorkflows` only resumes waiting
  `agent_unavailable` workflows while the owning conversation remains retained
- compatible rotated replacements may auto resume only when they preserve the
  conversation-bound execution environment and capability contract
- auto-resume rebinding now updates both `conversation.agent_deployment` and
  `turn.agent_deployment` through the same shared deployment-target contract
  used by manual recovery
- `Workflows::ManualResume` and `Workflows::ManualRetry` are explicit recovery
  boundaries for paused workflows and are rejected unless the owning
  conversation is still:
  - `retained`
  - `active`
  - free of unfinished close operations
- retryable in-place step failures now move the workflow into:
  - `wait_state = "waiting"`
  - `wait_reason_kind = "retryable_failure"`
  - `blocking_resource_type = "AgentTaskRun"`
  - `blocking_resource_id = <failed agent task public_id>`
- the retry gate stores `logical_work_id`, `attempt_no`, `retry_scope`, and
  the last error summary in `wait_reason_payload`
- `Workflows::StepRetry` creates a new `AgentTaskRun` inside the same turn and
  workflow and delivers it through the mailbox as a priority-2 retry attempt
- step retry is rejected once the turn has been fenced by
  `turn_interrupt`

## Turn Interrupt

- user-facing `Stop` maps to `Conversations::RequestTurnInterrupt`
- turn interrupt writes a durable close fence by marking both the turn and its
  workflow with:
  - `cancellation_requested_at`
  - `cancellation_reason_kind = "turn_interrupted"`
- the fence cancels queued retry attempts, revokes already leased retry
  `execution_assignment` mailbox items, and clears workflow wait fields
- `AgentControl::Poll` must not redeliver an `execution_assignment` once the
  backing `AgentTaskRun` has left `queued`
- late mailbox `execution_progress` or terminal execution reports for the
  superseded attempt are rejected as stale
- local provider completions and failures must re-lock the turn, workflow, and
  workflow node before persistence; if the interrupt fence or another terminal
  state has landed first, that provider result is dropped without transcript,
  usage, or profiling side effects
- close-summary projection and live/timeline mutation enforcement now both read
  from `ConversationBlockerSnapshot`
- turn timeline mutation helpers now use one shared blocker contract and lock
  order:
  - `conversation.with_lock`
  - `turn.with_lock`
  - re-check `ConversationBlockerSnapshot` plus `not turn_interrupted`
- steering current input, editing tail input, selecting output variants,
  retrying or rerunning output, and rollback all fail closed once that
  interrupt fence or a close fence has landed
- turn interrupt targets only mainline blockers:
  - running `AgentTaskRun`
  - blocking `HumanInteractionRequest`
  - running `ProcessRun(kind = "turn_command")`
  - running turn-bound `SubagentRun`
- turn interrupt does not target detached
  `ProcessRun(kind = "background_service")`
- the turn and workflow move to `canceled` only after those mainline blockers
  have reached durable terminal close state

## Archive Interaction

- archive without force is only allowed once the conversation has no unfinished
  runtime work
- `Conversations::Archive(force: true)` now creates a durable
  `ConversationCloseOperation(intent_kind = "archive")`
- the archive close operation immediately blocks new turn entry even while the
  conversation row is still `active`
- active mainline work is stopped through `turn_interrupt`
- detached background processes are closed through mailbox
  `resource_close_request(request_kind = "archive_force_quiesce")`
- close-request delivery for both archive and interrupt now follows the durable
  mailbox routing contract:
  - `runtime_plane`
  - `target_ref`
  - optional `target_execution_environment_id`
  rather than payload-based runtime inference
- `Conversations::ReconcileCloseOperation` is the single writer for archive
  close lifecycle state, `summary_payload`, and archive-side
  `conversation.lifecycle_state = archived`
- the conversation transitions to `archived` once the mainline stop barrier is
  clear
- any local blocker cancellation or mailbox terminal close report that changes
  close summary must re-enter that reconciler before the flow returns
- the close operation remains:
  - `quiescing` while mainline blockers remain
  - `disposing` while only background disposal tails remain
  - `degraded` when disposal tails end in residual or failed close outcomes
  - `completed` when both mainline and disposal tail cleanup finish cleanly
- once archived, the conversation no longer accepts new turn entry or queued
  follow-up work

## Safe Deletion Interaction

- `Conversations::RequestDeletion` moves the conversation to
  `pending_delete` immediately and stamps `deleted_at`
- queued turns are canceled immediately with
  `cancellation_reason_kind = "conversation_deleted"`
- the active turn is fenced through `turn_interrupt`
- detached background processes are closed through mailbox
  `resource_close_request(request_kind = "deletion_force_quiesce")`
- environment-plane close terminal reports are accepted only from deployments
  attached to the owning execution environment, and they re-enter close
  reconciliation through the dedicated close-report handler family
- delete also records a durable
  `ConversationCloseOperation(intent_kind = "delete")`
- `Conversations::ReconcileCloseOperation` is the single writer for delete
  close lifecycle state and `summary_payload`; it does not set
  `deletion_state = deleted`
- `Conversations::FinalizeDeletion` now requires only the mainline stop
  barrier to be clear; background disposal tails may still be `disposing` or
  `degraded`
- `Conversations::PurgeDeleted` still requires:
  - final deletion to have removed the live canonical-store reference
  - no active runtime residue
  - no lineage or provenance blockers
- once those guards pass, purge removes mailbox residue and teardown-backed
  runtime rows through an explicit ownership graph instead of relying on model
  cascades
- purge-owned mailbox cleanup includes phase-two `agent_task_runs`,
  `agent_control_mailbox_items`, and `agent_control_report_receipts`
- attachment-backed runtime rows such as `MessageAttachment` and
  `WorkflowArtifact` are destroyed so their Active Storage attachment joins are
  also removed
- if the purge graph still reports owned rows after cleanup, purge fails closed
  and keeps the deleted conversation shell in place
- `PurgeDeleted(force: true)` does not locally stop mailbox-owned runtime
  resources; it issues the same delete close contract and expects purge to be
  retried after terminal close reports land
- retained child conversations are not deleted or interrupted when a parent is
  put into `pending_delete`

## Human Interaction Interaction

- blocking human interaction requests still move workflows to
  `wait_state = "waiting"`
- human-interaction conversation-event payloads use the request `public_id`
  rather than the internal row id
- normal resolution paths resume the workflow to `ready`
- open-for-user inbox queries return only requests that still belong to
  `retained + active` conversations
- open and resolve paths re-check conversation lifecycle state under lock
  before mutating the request or workflow wait state
- once a conversation is no longer retained or no longer active:
  - opening a new human interaction is rejected
  - late completion, form submission, and approval resolution are rejected
  - deletion-driven cancellation projects `human_interaction.canceled`
    conversation events
- once a conversation is closing, the same open and late-resolution writes are
  rejected even if the row still reads `lifecycle_state = active`
- once a turn has been fenced by `turn_interrupt`, opening a new human
  interaction from that workflow is also rejected

## Invariants

- scheduler selection remains side-effect free
- waiting workflows do not surface runnable nodes
- restart and queue policies replace older queued follow-up work with the newest
  input
- close fences reuse the same workflow row rather than inventing a second pause
  store

## Failure Modes

- unsupported during-generation policies are rejected
- `restart` requires a workflow run so the blocking state can be recorded
- queued follow-up work is canceled when predecessor output drift invalidates
  the expected-tail guard
- manual recovery actions are rejected for non-retained conversations
- step retry is rejected after `turn_interrupt`
- final deletion is rejected while unfinished mainline work remains
