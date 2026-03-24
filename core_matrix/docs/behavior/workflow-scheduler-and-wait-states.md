# Workflow Scheduler And Wait States

## Purpose

Task 09.2 adds the first deterministic scheduler layer on top of the durable
workflow graph from Task 09.1.

This task does not execute node side effects. It only decides:

- which workflow nodes are runnable
- whether a workflow is currently blocked
- how new human input is handled after the first transcript side-effect boundary
- whether queued follow-up work is still valid against the predecessor turn tail

## Workflow Run Wait State

- `WorkflowRun` now persists a structured current wait state with:
  - `wait_state`
  - `wait_reason_kind`
  - `wait_reason_payload`
  - `waiting_since_at`
  - `blocking_resource_type`
  - `blocking_resource_id`
- Supported v1 wait states are:
  - `ready`
  - `waiting`
- Supported v1 wait reasons are:
  - `human_interaction`
  - `agent_unavailable`
  - `manual_recovery_required`
  - `policy_gate`
- `waiting` requires a reason kind and `waiting_since_at`.
- `ready` must not retain stale wait reason, wait timestamp, blocking resource,
  or reason payload fields.
- `wait_reason_payload` is a structured hash describing the current blocking
  condition only. It is not a historical pause ledger.

## Runnable Node Selection

- `Workflows::Scheduler.call` returns the workflow nodes that are currently
  runnable and does not mutate workflow, node, or transcript state.
- A workflow in `waiting` state produces no runnable nodes.
- A node with no predecessors is runnable unless it is already listed as
  satisfied.
- A node with predecessors becomes runnable only when every predecessor node
  key is present in the caller-supplied `satisfied_node_keys` set.
- Fan-out therefore produces multiple runnable children once their common
  predecessor is satisfied.
- Barrier-style fan-in joins remain blocked until all required predecessor
  branches are satisfied.

## During-Generation Input Policy

- `Workflows::Scheduler.apply_during_generation_policy` enforces the supported
  v1 policies:
  - `reject`
  - `restart`
  - `queue`
- `reject` raises `ActiveRecord::RecordInvalid` and leaves transcript state
  unchanged.
- `queue` cancels older queued follow-up turns in the same conversation, then
  creates a fresh queued follow-up turn that carries:
  - `during_generation_policy`
  - `expected_tail_message_id`
  - `queued_from_turn_id`
- `restart` also replaces older queued follow-up work, but additionally moves
  the current workflow run into `waiting` with `wait_reason_kind=policy_gate`
  and a blocking-resource reference to the queued replacement turn.

## Expected-Tail Guard

- Queued follow-up turns are guarded against predecessor-tail drift before
  execution.
- The guard compares the queued turn's `expected_tail_message_id` against the
  selected output of the immediately preceding turn in sequence order.
- If that predecessor output no longer matches, the queued turn is canceled
  instead of silently running against stale transcript state.
- The guard therefore keys off the predecessor turn output, not the
  conversation's last transcript row, because the queued turn's own selected
  input message already extends the visible tail.

## Steer Current Input

- `Turns::SteerCurrentInput` still rewrites the current selected input in place
  before the first transcript side-effect boundary.
- After the boundary, it delegates to workflow scheduler policy handling rather
  than mutating already-sent work in place.
- Side-effect boundary detection now reads the current workflow-node scope from
  the database instead of trusting a possibly cached `workflow_run.workflow_nodes`
  association.
- The boundary may therefore be detected either by:
  - an already selected output message
  - a persisted workflow node metadata marker such as
    `transcript_side_effect_committed`

## Invariants

- scheduler selection remains side-effect free
- blocked workflows do not surface runnable nodes
- queue and restart replace older queued follow-up work with the newest input
- restart records current blocking state on the active workflow instead of
  inventing a second pause store
- queued work fails safe when predecessor tail state drifts

## Failure Modes

- unsupported during-generation policy values are rejected
- `reject` policy refuses new input without mutating transcript state
- `restart` policy requires a workflow run so the blocking state can be
  recorded
- queued follow-up work is canceled when predecessor output drift invalidates
  the expected-tail guard
- stale workflow-node association caches must not hide freshly persisted
  side-effect boundary markers

## Rails And Reference Findings

- Local Rails enum source confirmed that `validate: { allow_nil: true }` is the
  correct way to keep `wait_reason_kind` optional while the workflow is `ready`
  but still validated when present.
- Local Rails migration guides confirmed the additive `add_column` pattern used
  to extend `workflow_runs` after Task 09.1 rather than rewriting the earlier
  migration.
- A narrow Dify sanity check showed Dify models pauses as dedicated pause
  entities plus runtime-state snapshots. Core Matrix intentionally keeps a
  single structured current wait state on `WorkflowRun` and leaves historical
  pause transitions to later event-stream tasks, matching the local design.
