# Workflow Scheduler And Wait States

## Purpose

Core Matrix keeps one structured current wait state on `WorkflowRun` and now
also defines how deletion interacts with waiting and active workflow work.

## Status

This document records the current landed Phase 1 scheduler and wait-state
behavior.

Archive, delete, turn interrupt, step retry, and mailbox-close semantics are
expected to change in Phase 2. Until those tasks land, this document remains
the source of truth for the current implementation.

Planned replacement design:

- [2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md)

## Workflow Wait State Shape

- `WorkflowRun` persists:
  - `wait_state`
  - `wait_reason_kind`
  - `wait_reason_payload`
  - `waiting_since_at`
  - `blocking_resource_type`
  - `blocking_resource_id`
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
- `AgentDeployments::AutoResumeWorkflows` only resumes waiting
  `agent_unavailable` workflows while the owning conversation remains retained
- `Workflows::ManualResume` and `Workflows::ManualRetry` are explicit recovery
  boundaries for paused workflows and are rejected once deletion has been
  requested

## Archive Interaction

- archive without force is only allowed once the conversation has no unfinished
  runtime work
- `Conversations::Archive(force: true)` quiesces the conversation's own queued
  turns, active turns, active workflow runs, open human interactions, running
  processes, running subagents, and active leases before transitioning to
  `archived`
- force archival uses `conversation_archived` as the cancellation or release
  reason across turns, workflows, human-interaction payloads, process stop
  metadata, and lease release reasons
- once archived, the conversation no longer accepts new turn entry or queued
  follow-up work

## Safe Deletion Interaction

- `Conversations::RequestDeletion` cancels queued turns immediately
- open human interaction requests on the conversation are canceled
- running process runs are stopped with reason `conversation_deleted`
- running subagent runs are marked canceled
- active execution leases are force-released with reason `conversation_deleted`
- active workflow runs are marked with:
  - `cancellation_requested_at`
  - `cancellation_reason_kind = "conversation_deleted"`
- once runtime work has been quiesced, active workflow runs and turns are moved
  to `canceled`
- `Conversations::FinalizeDeletion` rejects finalization while active turns,
  active workflows, open human interactions, running processes,
  running subagents, or active leases still remain
- `Conversations::PurgeDeleted(force: true)` may quiesce corrupted deleted
  runtime work with `conversation_deleted` reasons before retrying purge, but it
  still requires final deletion to have removed the live canonical-store
  reference first

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

## Invariants

- scheduler selection remains side-effect free
- waiting workflows do not surface runnable nodes
- restart and queue policies replace older queued follow-up work with the newest
  input
- deletion uses the existing workflow wait/cancel state rather than inventing
  a second pause store

## Failure Modes

- unsupported during-generation policies are rejected
- `restart` requires a workflow run so the blocking state can be recorded
- queued follow-up work is canceled when predecessor output drift invalidates
  the expected-tail guard
- manual recovery actions are rejected for non-retained conversations
- final deletion is rejected while unfinished runtime work remains
