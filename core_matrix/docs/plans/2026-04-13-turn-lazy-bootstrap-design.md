# Turn Lazy Bootstrap Design

## Goal

Slim down the synchronous API turn-entry path so `conversations#create` and
`conversation_messages#create` only persist boundary truth that must exist
immediately, while workflow substrate and execution setup are materialized
later, right before the turn actually begins background execution.

This plan is a follow-up to:

- `docs/plans/2026-04-13-conversation-bootstrap-slimming-design.md`
- `docs/plans/2026-04-13-conversation-bootstrap-slimming-implementation.md`

That earlier phase slims `Conversation` container bootstrap. This phase builds
on that work and moves the heavier turn-entry workflow substrate out of the
API request path.

This design assumes:

- destructive refactors are allowed on the current branch
- compatibility with the current unfinished schema is not required
- original migrations may be rewritten in place
- local and test databases may be rebuilt from scratch
- API contracts may change to expose a clearer `pending` execution state

The target is not to make turns “eventually consistent everywhere.” The target
is a cleaner boundary where:

- `Turn` owns the durable truth of “this execution request was accepted”
- synchronous API work stops creating workflow substrate just to acknowledge
  receipt
- the first background execution boundary materializes workflow rows exactly
  once
- the API and UI can truthfully represent `pending` without pretending
  execution has already started

## Scope

This pass focuses on four connected refactors:

1. Move workflow substrate creation out of the synchronous API entry path
2. Make `Turn` own execution-bootstrap intent and bootstrap status
3. Change API contracts so accepted turns can be explicitly `pending`
4. Add a minimal pending projection path for UI-visible queued state without
   creating workflow substrate

## Non-Goals

This pass does not:

- redesign `ConversationExecutionEpoch`
- redesign `ConversationCapabilityGrant`
- redesign `ConversationSupervisionState` as a resource
- remove `WorkflowRun` / `WorkflowNode` from the product model
- redesign provider execution, wait-state, or retry semantics after workflow
  materialization
- change branching, checkpoint, lineage, or supervision product rules

Those remain follow-on work.

## Current Baseline

The current synchronous API chain is still:

- `Workbench::CreateConversationFromAgent`
  - `UserAgentBindings::Enable`
  - `Conversations::CreateRoot`
  - `Turns::StartUserTurn`
  - `Workflows::CreateForTurn`
  - `Workflows::ExecuteRun`
- `Workbench::SendMessage`
  - `Turns::StartUserTurn`
  - `Workflows::CreateForTurn`
  - `Workflows::ExecuteRun`

That means request completion currently depends on all of the following being
done synchronously:

- model selector resolution
- execution snapshot creation
- `WorkflowRun` creation
- `WorkflowNode` creation
- initial `AgentTaskRun` / execution assignment creation when applicable
- workflow anchor refresh
- enqueue of `Workflows::ExecuteNodeJob`

Even after the earlier execution-epoch and conversation-bootstrap slimming
work, this remains the dominant request-path cost because `CreateForTurn`
still owns the heavy setup.

## Problem 1: `Turn` Does Not Yet Own “Accepted For Execution” Truth

Today `Turn` already owns:

- execution identity
- selector result snapshots
- frozen config snapshots
- turn origin and source refs

But it does **not** own the durable truth that:

- the turn was accepted for later execution
- execution setup has not been materialized yet
- execution setup is currently being materialized
- setup failed before workflow substrate existed

That missing truth is why the code currently has to build workflow substrate
inside the request before the API can honestly claim anything happened.

## Recommended Direction For Turn-Owned Bootstrap Truth

### Make `Turn` the acceptance boundary

Once a request is accepted, the synchronous truth should be:

- the `Turn` exists
- the selected input `Message` exists
- the execution identity is frozen
- the turn has a durable bootstrap status
- the turn has a durable bootstrap intent describing how execution should
  begin later

The API should not need a `WorkflowRun` row to acknowledge receipt.

### Add explicit bootstrap state to `Turn`

`Turn` should gain a small execution-bootstrap state machine:

- `pending`
  - request accepted
  - workflow substrate not yet materialized
- `materializing`
  - background job is building the workflow substrate
- `ready`
  - workflow substrate exists and handoff to the current dispatch chain
    succeeded
- `failed`
  - the bootstrap attempt failed before normal workflow execution could begin

These states are distinct from `Turn.lifecycle_state`.

`Turn.lifecycle_state` continues to answer whether the turn itself is queued,
active, waiting, completed, failed, or canceled in the product model.
Bootstrap state answers a different question: “has the execution substrate for
this turn been created yet?”

### Store bootstrap intent directly on `Turn`

`Turn` should also own a compact `bootstrap_payload` that freezes the minimum
input needed to create workflow substrate later.

That payload should contain only boundary truth, for example:

- selector source
- selector payload
- root node key
- root node type
- decision source
- metadata
- initial task kind and payload when needed
- origin-turn or subagent-connection refs when needed

This is intentionally not an execution snapshot. It is the input required to
build one later.

### Record bootstrap failures without terminalizing the turn

If workflow materialization fails, `Turn` should record:

- `bootstrap_state = failed`
- `bootstrap_failure_payload`

Do **not** immediately terminalize `Turn.lifecycle_state` just because the
first bootstrap attempt failed. That would collapse “execution setup failed”
and “the turn itself definitively failed” into the same state too early.

The product can still expose this as a user-visible execution-start failure.

## Problem 2: Pending API Responses Currently Imply More Than They Mean

Today the request returns only after the workflow substrate already exists and
the execution job has been enqueued from `WorkflowNode`.

That contract makes “accepted” and “workflow already materialized” look like
the same state.

It also means a pending turn cannot be represented honestly. The system either
pretends execution has already started or falls back to `idle`.

## Recommended Direction For API Contracts

### Return an explicit pending execution state

`conversations#create` and `conversation_messages#create` should continue to
return `201`, but their business meaning should become:

- request accepted
- turn recorded
- execution pending

The response should include only the fields that are synchronously true.

Recommended response additions:

- `execution_status: "pending"`
- `accepted_at`
- `request_summary`

Allowed pending-phase omissions or `null`s:

- `workflow_run_id`
- `workflow_node_id`
- detailed progress summaries
- wait-state and blocker summaries
- any workflow-backed runtime evidence

This makes the API more honest and removes the pressure to materialize
workflow rows only for acknowledgment.

## Problem 3: UI Read Surfaces Need Queued State Before Workflow Exists

Mutation responses alone are not enough if:

- the page refreshes immediately
- another surface reads the conversation list
- supervision / board views load before bootstrap finishes

Without a lightweight projection, those surfaces can temporarily show `idle`
even though the new turn has already been accepted and is waiting to execute.

## Recommended Direction For Pending UI Projection

### Add a dedicated pending-turn projector

Do **not** reuse `Conversations::UpdateSupervisionState` for the synchronous
pending path.

`UpdateSupervisionState` is a rich projector that reads:

- `WorkflowRun`
- `AgentTaskRun`
- subagent state
- runtime evidence
- feed state

That is the wrong shape for the synchronous boundary because it mixes read-time
runtime reconstruction with the write-time acknowledgment path.

Instead, add a tiny service such as `Conversations::ProjectPendingTurn` that:

- upserts a minimal `ConversationSupervisionState`
- performs no workflow/task/subagent reconstruction
- writes only fields that are already synchronously known
- publishes the normal supervision update notification so live subscribers
  immediately see the queued state

Recommended pending projection fields:

- `overall_state = "queued"`
- `board_lane = "queued"`
- `current_owner_kind = "turn"`
- `current_owner_public_id = turn.public_id`
- `request_summary`
- `last_progress_at = accepted_at`

Everything else can remain blank until richer runtime state exists.

### Keep the rich projector pending-aware on read paths

Even with a dedicated pending projector, read paths can still invoke
`Conversations::UpdateSupervisionState` before workflow substrate exists, for
example through supervision snapshot refreshes or feed endpoints.

If `UpdateSupervisionState` stays unaware of pending bootstrap turns, those
reads will overwrite the queued projection back to `idle`.

So the correct split is:

- synchronous API path uses `Conversations::ProjectPendingTurn`
- rich read-side projection keeps using `Conversations::UpdateSupervisionState`
- `UpdateSupervisionState` gains a read-side pending-preservation branch that
  returns the same minimal queued projection when:
  - a pending/materializing bootstrap turn exists
  - no richer workflow/task/subagent owner exists yet

That branch exists to preserve correctness on read paths, not to become the
new synchronous API entry point.

### Why a small service is still better than using only a fast path inside `UpdateSupervisionState`

A pending fast path inside `UpdateSupervisionState` is still needed for
read-side correctness, but it is not sufficient as the primary synchronous
boundary because it has two problems:

1. it weakens the separation between a lightweight boundary write and a heavy
   runtime projector
2. it makes state-priority mistakes more likely because the projector already
   carries rich precedence rules for waiting, blocked, active workflow, active
   task, and subagent work

A dedicated pending projector avoids both problems on the synchronous boundary
without adding a new entity or table, while the read-side pending branch keeps
later projector refreshes from regressing queued turns back to `idle`.

## Recommended End-State Architecture

### Synchronous API boundary

For `Workbench::CreateConversationFromAgent`:

1. enable binding / resolve workspace
2. create root conversation
3. create user turn and input message
4. persist turn bootstrap state and bootstrap payload
5. refresh turn/message anchors
6. project minimal queued supervision state
7. enqueue a turn-bootstrap job by `turn.public_id`
8. return `201 created` with `execution_status = pending`

For `Workbench::SendMessage`:

1. create user turn and input message
2. persist turn bootstrap state and bootstrap payload
3. refresh turn/message anchors
4. project minimal queued supervision state
5. enqueue a turn-bootstrap job by `turn.public_id`
6. return `201 created` with `execution_status = pending`

### Background bootstrap boundary

Introduce a new job such as `Turns::MaterializeAndDispatchJob`.

That job should:

1. load the turn by public id
2. lock the turn for idempotent bootstrap
3. return immediately if:
   - the turn is canceled or terminal
   - workflow substrate already exists and has already moved past bootstrap
4. create workflow substrate only when absent:
   - resolve selector
   - build execution snapshot
   - create `WorkflowRun`
   - create the root `WorkflowNode`
   - create the initial `AgentTaskRun` / assignment when required
   - refresh latest workflow anchor
5. transition `bootstrap_state` to `ready`
6. hand off to the existing workflow dispatch path

This keeps workflow creation lazy but still durable.

## Idempotency And Reliability

### Turn lock is the primary bootstrap guard

`workflow_runs.turn_id` is already unique, so the database already prevents
duplicate workflow rows for one turn.

The primary logic should still be:

- `turn.with_lock`
- check `turn.workflow_run`
- only materialize when absent

The unique constraint is the last-resort safeguard, not the main branch.

### Repeated enqueue and retry must be safe

Repeated delivery of the bootstrap job must not:

- create a second `WorkflowRun`
- create extra root nodes
- create a second initial `AgentTaskRun`
- double-dispatch already materialized work

If a job is retried after workflow creation but before dispatch completion, it
should detect the existing substrate and continue safely.

### Bootstrap failure should be durable and retryable

When materialization fails:

- record `bootstrap_state = failed`
- record `bootstrap_failure_payload`
- keep the turn readable and retryable

Do not force the user to lose the accepted turn just because the first
bootstrap attempt failed.

## Why This Is Better Than Simpler Alternatives

### Option A: Keep creating a minimal `WorkflowRun` synchronously

Rejected because:

- it keeps workflow substrate on the request path
- it still pays substrate-allocation and anchor-maintenance costs during API
  acknowledgment
- it makes the API contract look lighter without actually removing the heavy
  creation boundary

### Option B: Put a pending fast path inside `UpdateSupervisionState`

Rejected because:

- it mixes a lightweight acknowledgment write with a heavy runtime projector
- it makes priority mistakes easier when real workflow/task/subagent state
  coexists with a pending turn
- it gives no structural guarantee that the synchronous boundary stays light

### Option C: Add a new `turn_bootstraps` table

Rejected because:

- the bootstrap lifecycle is strictly one-to-one with `Turn`
- it adds a new resource and purge surface without a separate product meaning
- `Turn` already owns the surrounding execution identity truth

## Recommended End State

After this refactor:

- `Turn` is the durable synchronous truth that an execution request was
  accepted
- API turn-entry no longer creates workflow substrate synchronously
- API responses explicitly return `pending`
- workflow-backed fields may be absent during pending
- a dedicated pending projector writes the minimum queued UI state
- rich read-side supervision refreshes preserve that queued state until
  workflow substrate exists
- a turn-bootstrap job materializes workflow substrate exactly once
- existing provider execution, wait-state, and retry flows continue after
  materialization

## Behavior Docs That Must Change

This refactor must update at least:

- `docs/behavior/turn-entry-and-selector-state.md`
- `docs/behavior/conversation-supervision-and-control.md`
- `docs/behavior/workflow-context-assembly-and-execution-snapshot.md`
- `docs/behavior/workflow-scheduler-and-wait-states.md`
- any API behavior doc that still implies workflow substrate exists before the
  turn is merely accepted

## Follow-On Work

If this pass lands cleanly, the next nearby optimizations become easier:

- moving more request-path projection refreshes behind queued projectors
- revisiting whether `QueueFollowUp` should share the same bootstrap contract
- shrinking `StartUserTurn` further now that execution substrate no longer
  depends on synchronous selector resolution
