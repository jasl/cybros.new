# Workflow Scheduler And Wait States

## Purpose

Core Matrix keeps one structured current wait state on `WorkflowRun` and now
also defines how interrupt, retry, archive, and delete interact with active
workflow work.

## Status

This document reflects the landed scheduler and close-fence behavior.

Within the lifecycle model, workflow runs and workflow nodes remain
`owner_bound`. Their wait-state fields are canonical runtime state, not
ephemeral diagnostics.

This document describes lifecycle and cleanup boundaries, not an active cleanup
job. No automatic retention policy is implemented here yet.

## Workflow Wait State Shape

- `WorkflowRun` persists:
  - `wait_state`
  - `wait_reason_kind`
  - `wait_reason_payload`
  - `waiting_since_at`
  - `blocking_resource_type`
  - `blocking_resource_id`
- `blocking_resource_id` stores durable external-style identifiers only:
  - `AgentProgramVersion.public_id` for `agent_unavailable`
  - barrier artifact keys for `subagent_barrier`
  - blocker `public_id` values for `human_interaction`, `retryable_failure`,
    `external_dependency_blocked`, and `policy_gate`
- `WorkflowRun` also persists workflow-yield continuation hints through:
  - `resume_policy`
  - `resume_metadata`
- supported wait states:
  - `ready`
  - `waiting`
- supported wait reasons:
  - `human_interaction`
  - `subagent_barrier`
  - `agent_unavailable`
  - `manual_recovery_required`
  - `policy_gate`
  - `retryable_failure`
  - `external_dependency_blocked`
- `waiting` requires a reason kind and `waiting_since_at`
- `ready` must not retain stale wait fields or blocking-resource references
- because these fields are canonical runtime state, future cleanup work must
  not delete them independently from the owning workflow run

## Scheduler Behavior

- `Workflows::Scheduler.call` returns runnable workflow nodes and does not
  mutate workflow state
- workflows in `waiting` state expose no runnable nodes
- scheduler input is the persisted workflow graph plus durable
  `WorkflowNode.lifecycle_state`
- only `pending` nodes are runnable
- a node with no predecessors is runnable immediately
- a node with predecessors is runnable only when:
  - at least one predecessor is durably `completed`
  - every incoming `required` edge comes from a durably `completed`
    predecessor
- because a node leaves `pending` as soon as it is queued, late completion of
  an `optional` predecessor cannot retrigger an already consumed merge node
- workflow ordering for scheduler and later proof export continues to use the
  frozen node `ordinal`, while yielded intent nodes may also carry
  `stage_index` and `stage_position` for stage-local inspection
- `Workflows::DispatchRunnableNodes` is the dispatch boundary:
  - it locks the workflow run
  - moves each selected runnable node from `pending` to `queued`
  - enqueues one `Workflows::ExecuteNodeJob` per node
- `WorkflowRun` is not the async execution unit. The current implementation dispatches one job per
  runnable `WorkflowNode`.
- `Workflows::ExecuteRun` is the turn-step enqueue boundary; it
  resolves a runnable `turn_step` node and hands it to node dispatch instead of
  executing provider work inline.
- `Workflows::ExecuteNodeJob` and `Workflows::ExecuteNode` are the node-local
  execution boundary for kernel-owned execution. Local provider-backed
  `turn_step` work now runs there, not in the caller's request path.
- `Workflows::Scheduler.apply_during_generation_policy` supports:
  - `reject`
  - `restart`
  - `queue`
- during-generation policy resolution reads the frozen turn feature-policy
  snapshot once a transcript side-effect boundary exists
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
- current resume policy is `re_enter_agent`; later continuation work
  should create a successor agent step from `resume_metadata` rather than
  continuing an old batch tail under a stale snapshot
- `WorkflowRun.feature_policy_snapshot` freezes the turn-owned feature policy
  onto active workflow work
- `AgentTaskRun.feature_policy_snapshot` freezes the same policy again at the
  queued or running task boundary

## Wait Transition Handoff

- `AgentControl::HandleExecutionReport` is the terminal-report boundary that
  consumes `terminal_payload["wait_transition_requested"]`
- `Workflows::HandleWaitTransitionRequest` materializes the yielded batch before
  it changes wait state:
  - accepted `human_interaction_request` intents become durable
    `HumanInteractionRequest` rows
  - accepted `subagent_spawn` intents become durable `SubagentSession`, child
    conversation, child turn, child workflow, and child `AgentTaskRun` records
  - those owner-managed yielded nodes are marked `completed` immediately when
    their durable runtime resources are created
  - `wait_all` stages pause the parent workflow with a durable
    `subagent_barrier`
  - stages with no blocking resource immediately continue through
    `Workflows::ReEnterAgent`
- `Workflows::ResumeAfterWaitResolution` is the only ready-transition owner for
  workflow waits created by yielded human interaction or `subagent_barrier`
  materialization
- `Workflows::ReEnterAgent` is the only successor-step owner for
  `resume_policy = re_enter_agent`:
  - it rebuilds the turn execution snapshot before queueing successor work
  - it creates the successor node when needed
  - it enqueues the fresh successor `AgentTaskRun` through the normal mailbox
    assignment path
- wait handoff therefore relies only on durable workflow rows, artifacts, and
  runtime resources; no runtime-private continuation cursor is required
- mailbox-owned agent execution also keeps the durable node state aligned:
  - assignment creation moves the node to `queued`
  - `execution_started` moves the node to `running`
  - terminal execution reports move the node to `completed`, `failed`, or
    `canceled`
  - successful terminal reports re-run workflow lifecycle refresh and node
    dispatch so DAG successors can continue

## Recovery Behavior

- `AgentProgramVersions::MarkUnavailable` moves active workflows into a waiting
  state when the pinned deployment becomes unavailable
- `agent_unavailable` stores:
  - `blocking_resource_type = "AgentProgramVersion"`
  - `blocking_resource_id = <deployment public_id>`
- if a workflow was already waiting on another blocker, outage pause snapshots
  that original blocker and restores it after recovery instead of erasing it
- `WorkflowWaitSnapshot` is the explicit parser and restore contract for those
  nested pause payloads
- wait snapshots are runtime-owned state, not disposable observability rows
- `AgentProgramVersions::AutoResumeWorkflows` only resumes waiting
  `agent_unavailable` workflows while the owning conversation remains retained
- compatible rotated replacements may auto resume only when they preserve the
  paused turn's frozen execution-runtime choice and capability contract
- `AgentProgramVersions::ResolveRecoveryTarget` is the one paused-work
  target-resolution contract used by:
  - `AgentProgramVersions::BuildRecoveryPlan`
  - `Workflows::ManualResume`
  - `Workflows::ManualRetry`
- `AgentProgramVersions::RebindTurn` is the one paused-turn rebinding mutation
  owner used by both auto-resume recovery-plan application and manual resume
- `Conversations::ValidateAgentProgramVersionTarget` stays generic to live
  conversation deployment switching and only enforces the installation and
  execution-environment boundary
- `Workflows::ManualResume` and `Workflows::ManualRetry` are explicit recovery
  boundaries for paused workflows and are rejected unless the owning
  conversation is still:
  - `retained`
  - `active`
  - free of unfinished close operations
- retryable in-place step failures move the workflow into:
  - `wait_state = "waiting"`
  - `wait_reason_kind = "retryable_failure"`
  - `blocking_resource_type = "AgentTaskRun"` for mailbox-owned agent work, or
    `blocking_resource_type = "WorkflowNode"` for provider/tool-step contract
    failures
- external dependency failures move the workflow into:
  - `wait_state = "waiting"`
  - `wait_reason_kind = "external_dependency_blocked"`
  - `blocking_resource_type = "WorkflowNode"`
  - `blocking_resource_id = <blocked workflow node public_id>`
- blocked step waits store:
  - `failure_category`
  - `failure_kind`
  - `retry_scope`
  - `resume_mode`
  - `retry_strategy`
  - `attempt_no`
  - `max_auto_retries`
  - `next_retry_at`
  - `last_error_summary`
  in `wait_reason_payload`
- `Workflows::StepRetry` remains the explicit same-step retry boundary:
  - for `AgentTaskRun` blockers it creates a new `AgentTaskRun` inside the
    same turn and workflow and delivers it through the mailbox as a priority-2
    retry attempt
  - for `WorkflowNode` blockers it resumes the blocked node in place through
    `Workflows::ResumeBlockedStep`
- automatic step retries are explicit workflow waits, not hidden queue
  retries:
  - `Workflows::BlockNodeForFailure` stores the waiting contract on the run,
    turn, and workflow node
  - `Workflows::ResumeBlockedStepJob` is scheduled only for automatic retry
    cases and later re-enters the same blocked node
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
- mailbox delivery remains the only product execution path for external or
  bundled runtimes; the scheduler does not depend on a runtime callback
  endpoint to start work
- late mailbox `execution_progress` or terminal execution reports for the
  superseded attempt are rejected as stale
- local provider completions and failures must re-lock the turn, workflow, and
  workflow node before persistence; if the interrupt fence or another terminal
  state has landed first, that provider result is dropped without transcript,
  usage, or profiling side effects
- the same freshness check also rejects late provider results when the
  frozen execution snapshot no longer matches:
  - the selected input message `public_id`
  - the resolved provider/model pair
- stale result rejection therefore relies on durable execution-snapshot state,
  not process-local memory
- close-summary projection and live/timeline mutation enforcement now both read
  from `ConversationBlockerSnapshot`
- turn timeline mutation helpers now use one shared blocker contract and lock
  order:
  - `conversation.with_lock`
  - `turn.with_lock`
  - re-check `ConversationBlockerSnapshot` plus `not turn_interrupted`
- the canonical mutation guard family is:
  - `Conversations::WithConversationEntryLock` for new turn entry
  - `Turns::WithTimelineMutationLock` for tail rewrites and rollback
  - `Conversations::ValidateQuiescence` for archive/delete quiescence checks
- steering current input, editing tail input, selecting output variants,
  retrying or rerunning output, and rollback all fail closed once that
  interrupt fence or a close fence has landed
- turn interrupt targets only mainline blockers:
  - running `AgentTaskRun`
  - blocking `HumanInteractionRequest`
  - running turn-bound `SubagentSession`
- short-lived command execution is no longer a standalone mainline runtime
  resource; it rides under the owning `AgentTaskRun` as tool-invocation
  sub-execution
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
- owned open subagent sessions also receive mailbox-driven close requests
- detached background processes are closed through mailbox
  `resource_close_request(request_kind = "archive_force_quiesce")`
- close-request delivery for both archive and interrupt now follows the durable
  mailbox routing contract:
  - `runtime_plane`
  - `target_ref`
  - optional `target_execution_runtime_id`
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
- execution-plane close terminal reports are accepted only from the active
  execution session for the owning `ExecutionRuntime`, and they re-enter close
  reconciliation through the dedicated close-report handler family
- delete also records a durable
  `ConversationCloseOperation(intent_kind = "delete")`
- `Conversations::ReconcileCloseOperation` is the single writer for delete
  close lifecycle state and `summary_payload`; it does not set
  `deletion_state = deleted`
- `Conversations::FinalizeDeletion` now requires only the mainline stop
  barrier to be clear; background disposal tails may still be `disposing` or
  `degraded`
- archive, finalize deletion, and purge now invoke
  `Conversations::ValidateQuiescence` directly with the appropriate
  `mainline_only` contract instead of including a helper module
- `Conversations::PurgeDeleted` still requires:
  - final deletion to have removed the live lineage store reference
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
- the yielded `human_interaction` workflow node itself is owner-managed and is
  marked `completed` as soon as the durable request row is created
- the open request, not the workflow node row, is the durable blocker that
  keeps the workflow waiting
- non-blocking human interaction requests do not leave the workflow stalled;
  after request creation the workflow immediately refreshes lifecycle and
  dispatches any newly runnable successors
- human-interaction conversation-event payloads use the request `public_id`
  rather than the internal row id
- yielded human-interaction intents are materialized by
  `Workflows::HandleWaitTransitionRequest`, not by direct transcript mutation
- normal resolution paths clear the active blocker and then re-enter the same
  workflow through `Workflows::ReEnterAgent` when successor metadata is present
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
- conversations can still change their live feature policy while work is
  active, but the scheduler continues to honor the frozen turn/workflow/task
  snapshots for already-created work
- close fences reuse the same workflow row rather than inventing a second pause
  store
- yielded waits and resumes do not rely on runtime-private continuation state;
  the durable workflow graph and wait snapshot remain the only source of truth

## Failure Modes

- unsupported during-generation policies are rejected
- live policy drift cannot override an active turn's frozen
  during-generation-input policy
- `restart` requires a workflow run so the blocking state can be recorded
- queued follow-up work is canceled when predecessor output drift invalidates
  the expected-tail guard
- provider success or failure persistence is rejected as stale when selected
  input or selector drift breaks the frozen execution snapshot
- `subagent_barrier` waits do not resolve until every referenced session
  `public_id` belongs to the owner conversation and has reached terminal
  wait-for-parent status
- manual recovery actions are rejected for non-retained conversations
- step retry is rejected after `turn_interrupt`
- final deletion is rejected while unfinished mainline work remains
