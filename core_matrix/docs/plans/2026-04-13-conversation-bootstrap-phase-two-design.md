# Conversation Bootstrap Phase Two Design

> Supersedes:
> - `docs/plans/2026-04-13-conversation-bootstrap-slimming-design.md`
> - `docs/plans/2026-04-13-turn-lazy-bootstrap-design.md`

## Goal

Define the next `Conversation`-domain slimming pass as one coherent iteration:

1. remove synchronous root-conversation bootstrap work that is not required for a
   bare container to exist
2. then slim app-facing manual user turn entry so accepted work is recorded
   synchronously but workflow substrate is materialized later

This branch allows destructive refactors, in-place migration rewrites, and full
database rebuilds. Compatibility with unfinished pre-launch schema is not a
constraint.

## Why These Two Plans Belong Together

The previously drafted plans were individually sound in direction, but they are
not independent:

- `ConversationCapabilityPolicy` collapse and lazy lineage bootstrap remove
  container-level preallocation from `Conversations::CreateRoot`
- lazy user-turn bootstrap removes workflow substrate allocation from
  `Workbench::CreateConversationFromAgent` and `Workbench::SendMessage`

Those are two halves of the same request-path problem. If they are planned in
isolation, the second plan keeps inheriting noise from the first one and the
measured weight reduction is harder to reason about.

The cleaner next iteration is therefore:

- **Phase A:** slim the conversation container bootstrap
- **Phase B:** slim the app-facing manual user turn acceptance boundary

Each phase records real before/after query counts and row deltas before moving
on.

## Scope

This iteration has two ordered phases.

### Phase A: Conversation Container Bootstrap Slimming

1. Collapse `ConversationCapabilityPolicy` into `Conversation`
2. Make lineage substrate lazy and conversation-owned instead of eagerly rooted
   at every root conversation

### Phase B: App-Facing Manual User Turn Lazy Bootstrap

1. Restrict deferred workflow materialization to:
   - `Workbench::CreateConversationFromAgent`
   - `Workbench::SendMessage`
2. Record accepted-turn truth synchronously on `Turn`
3. Materialize `WorkflowRun` / `WorkflowNode` / initial task substrate later in a
   dedicated bootstrap boundary
4. Project honest queued or bootstrap-failed UI state without fabricating
   workflow-backed runtime state

## Non-Goals

This iteration does not:

- redesign `ConversationExecutionEpoch`
- redesign `ConversationCapabilityGrant`
- redesign `ConversationSupervisionState` as a top-level resource
- redesign provider execution, wait-state, or retry semantics after workflow
  substrate exists
- redesign transcript branching or checkpoint product rules
- generalize lazy workflow bootstrap to every turn origin in this pass

The following turn-entry paths explicitly stay on their current semantics unless
they need small adaptation for shared helpers:

- `Turns::StartAutomationTurn`
- `Turns::StartAgentTurn`
- `Turns::QueueFollowUp`
- `Workflows::ManualRetry`
- `Turns::RerunOutput`
- `SubagentConnections::SendMessage`

## Phase A Baseline

The earlier conversation-bootstrap draft already measured the current container
cost and remains the correct starting baseline:

- `Conversations::CreateRoot.call(workspace: ...)`
  - `16` SQL
  - `+1` `conversations`
  - `+1` `conversation_closures`
  - `+1` `conversation_capability_policies`
  - `+1` `lineage_stores`
  - `+1` `lineage_store_snapshots`
  - `+1` `lineage_store_references`
- `create_capability_policy_for!`
  - `3` SQL
  - `+1` `conversation_capability_policies`
- `LineageStores::BootstrapForConversation.call`
  - `5` SQL
  - `+1` `lineage_stores`
  - `+1` `lineage_store_snapshots`
  - `+1` `lineage_store_references`
- child lineage attach
  - `4` SQL
  - `+1` `lineage_store_references`

Phase A keeps those exact baselines and should continue to target:

- root bootstrap without capability row: `<= 13` SQL
- bare root bootstrap after lazy lineage: `<= 8` SQL

## Phase B Baseline

The current turn-entry path still synchronously performs:

- selector resolution
- execution snapshot construction
- `WorkflowRun` creation
- root `WorkflowNode` creation
- optional initial `AgentTaskRun` and assignment creation
- workflow anchor refresh
- dispatch enqueue

Existing tests already show that the path is still heavy:

- `Workbench::SendMessage` is currently budgeted at `<= 75` SQL
- `POST /app_api/conversations/:id/messages` is currently budgeted at `<= 84`
  SQL
- `Workbench::CreateConversationFromAgent` must be remeasured after Phase A,
  because its current weight still includes root bootstrap work that Phase A
  removes first

This iteration therefore requires:

1. refresh the real measured before-values after Phase A lands
2. only then freeze the exact Phase B after-budgets in tests and in this design
   doc

## Phase A End State

### Capability authority becomes row-local to `Conversation`

`ConversationCapabilityPolicy` should be removed entirely.

`Conversation` directly owns:

- `supervision_enabled`
- `detailed_progress_enabled`
- `side_chat_enabled`
- `control_enabled`

Those booleans remain a frozen projection from workspace policy at conversation
creation time. The product rule does not change:

- workspace policy edits affect future conversations
- existing conversations keep the authority projected when they were created

### Lineage substrate becomes lazy and conversation-owned

Root creation stops preallocating:

- `LineageStore`
- `LineageStoreSnapshot`
- `LineageStoreReference`

Empty lineage is represented as absence of a reference.

The ownership concept should also be cleaned up under the destructive-refactor
rule:

- rename `root_conversation_id` to `owner_conversation_id`
- rename root-specific helpers to owner-specific helpers

That keeps the model honest once a child conversation may be the first owner to
materialize lineage state.

## Phase B Problem Statement

Even after Phase A, app-facing manual user entry still lies about what has
happened:

- the API acknowledges only after workflow substrate already exists
- request latency still depends on `CreateForTurn`
- UI queued state currently depends on workflow-backed reconstruction

The system needs a cleaner split between:

- **accepted-turn truth**
- **workflow substrate truth**

Those are related, but they are not the same boundary.

## Phase B Recommended Direction

### Scope the lazy bootstrap contract to app-facing manual user entry only

This phase should not pretend every turn origin shares one lifecycle yet.

Only turns created through:

- `Workbench::CreateConversationFromAgent`
- `Workbench::SendMessage`

enter the new deferred workflow-bootstrap contract.

Everything else stays on its current substrate lifecycle unless Phase B needs a
small no-op compatibility value on `Turn`.

### Use explicit workflow-bootstrap columns on `Turn`

To avoid colliding with unrelated bootstrap state elsewhere in the app, the
turn-owned contract should use explicit workflow-specific names:

- `workflow_bootstrap_state`
- `workflow_bootstrap_payload`
- `workflow_bootstrap_failure_payload`
- `workflow_bootstrap_requested_at`
- `workflow_bootstrap_started_at`
- `workflow_bootstrap_finished_at`

Recommended states:

- `not_requested`
  - default
  - this turn is not using the deferred workflow-bootstrap contract in this
    iteration
- `pending`
  - accepted by the API
  - workflow substrate not materialized yet
- `materializing`
  - background bootstrap is currently allocating workflow substrate
- `ready`
  - workflow substrate exists and handoff into the existing dispatch chain
    succeeded
- `failed`
  - bootstrap failed before the normal workflow lifecycle began

This avoids the current false assumption that every legacy turn can safely
default to `ready`.

### The synchronous acceptance boundary must be one durable transaction

The accepted-turn truth for app-facing manual user entry must commit atomically:

- `Conversation` exists when first-turn entry is creating one
- `Turn` exists
- selected input `Message` exists
- execution identity is frozen
- `workflow_bootstrap_state = "pending"`
- `workflow_bootstrap_payload` is present
- latest turn/message anchors are refreshed
- minimal queued supervision state is projected

Only enqueue-style async kickoffs may happen after commit, and correctness must
not depend on any one enqueue succeeding.

The plan must not split accepted-turn truth across multiple later writes after
the turn row is already committed.

### Pending must be a durable backlog, not just a hopeful enqueue

`pending` must mean more than “the request returned before the job was queued.”

For long-term correctness, the durable source of truth is the `Turn` row itself:

- `workflow_bootstrap_state = "pending"` means bootstrap work is outstanding
- `workflow_bootstrap_requested_at` is the durable acceptance timestamp
- `workflow_bootstrap_payload` is the durable bootstrap request body

The immediate post-commit enqueue should be treated only as an acceleration
path. Correctness must not depend on that single enqueue succeeding.

This phase should therefore also define a small recovery boundary:

- pending turns with no `workflow_bootstrap_started_at` are claimable backlog
- `materializing` turns older than a small timeout are stale and must be
  re-driven through the same locked reconcile path
- a short-cadence maintenance recovery job may re-enqueue or directly process
  those turns, but it must not invent a second source of truth outside `Turn`

That keeps the system honest if the process crashes after commit, the queue
adapter drops the enqueue, or a worker dies mid-bootstrap.

### Use a dedicated turn-bootstrap projector

Do not make queued and failed bootstrap UI state depend on the heavy runtime
projector.

Use one small projector, for example
`Conversations::ProjectTurnBootstrapState`, whose contract is explicit:

- it writes only fields already known synchronously
- it does not query workflow/task/subagent state
- it publishes the normal supervision update notification

When the bootstrap state is `pending` or `materializing`, it should project:

- `overall_state = "queued"`
- `board_lane = "queued"`
- `current_owner_kind = "turn"`
- `current_owner_public_id = turn.public_id`
- `request_summary`
- `last_progress_at = accepted_at`

When the bootstrap state is `failed`, it should project:

- `overall_state = "failed"`
- `board_lane = "failed"`
- `current_owner_kind = "turn"`
- `current_owner_public_id = turn.public_id`
- `request_summary`
- a compact failure summary derived from `workflow_bootstrap_failure_payload`
- `last_progress_at = workflow_bootstrap_finished_at`

### Read-side projector must preserve turn-bootstrap truth

`Conversations::UpdateSupervisionState` cannot only special-case
`pending/materializing`.

It must also avoid regressing a bootstrap-failed turn back to `idle` before any
workflow row exists.

The read-side should therefore recognize:

- pending/materializing bootstrap turns with no richer runtime owner
  - reuse the same queued semantics as `ProjectTurnBootstrapState`
- bootstrap-failed turns with no richer runtime owner
  - reuse the same failed semantics as `ProjectTurnBootstrapState`

That closes the state hole where the system accepted a turn but startup failed
before workflow substrate existed.

### Async bootstrap remains idempotent and reusable

The background bootstrap boundary should:

1. find the turn by public id
2. lock the turn
3. no-op if:
   - the turn no longer exists
   - the turn is canceled/terminal
   - a workflow run already exists for the turn and bootstrap already completed
4. move `workflow_bootstrap_state: pending -> materializing`
5. resolve selector
6. build execution snapshot
7. create `WorkflowRun`
8. create root `WorkflowNode`
9. create initial `AgentTaskRun` and assignment when required
10. refresh latest workflow anchor
11. move `workflow_bootstrap_state -> ready`
12. hand off to the existing dispatch path

When materialization fails:

- persist `workflow_bootstrap_state = failed`
- persist `workflow_bootstrap_failure_payload`
- project failed turn-bootstrap UI state and publish the normal update
- keep the accepted turn readable and retryable

If a retry starts after a crash left the turn in `materializing` with partially
created substrate, the retry path must reconcile that substrate under the turn
lock and drive the state to either `ready` or `failed`. The system must not
leave durable turns indefinitely stranded in an ambiguous mid-bootstrap shape.

### Fix the internal bootstrap-state shape, not just the labels

For long-term correctness, the `workflow_bootstrap_*` fields need a strict shape
contract, not just named enum values.

Treat `workflow_bootstrap_state != "not_requested"` as “this turn is governed by
the deferred workflow-bootstrap contract.”

Recommended durable shape:

- `not_requested`
  - `workflow_bootstrap_payload = {}`
  - `workflow_bootstrap_failure_payload = {}`
  - `workflow_bootstrap_requested_at = nil`
  - `workflow_bootstrap_started_at = nil`
  - `workflow_bootstrap_finished_at = nil`
- `pending`
  - payload present and non-empty
  - payload has the exact top-level contract shape
  - failure payload empty
  - requested_at present
  - started_at/finished_at nil
- `materializing`
  - same payload contract as `pending`
  - failure payload empty
  - requested_at and started_at present
  - finished_at nil
- `ready`
  - same payload contract as `pending`
  - failure payload empty
  - requested_at, started_at, and finished_at present
  - workflow substrate exists
- `failed`
  - same payload contract as `pending`
  - failure payload present with a fixed error shape
  - requested_at, started_at, and finished_at present
  - workflow substrate may be absent or only partially reconciled, but the next
    retry must resolve the ambiguity under lock

Required payload keys for contract-active states should be fixed up front:

- `selector_source`
- `selector`
- `root_node_key`
- `root_node_type`
- `decision_source`
- `metadata`

No extra top-level keys should be allowed in the durable payload for this phase.
If future product work needs more shape, the branch can destructively rewrite
the contract instead of letting ad-hoc payload drift accumulate.

Required failure payload keys should also be fixed:

- `error_class`
- `error_message`
- `retryable`

No extra top-level failure keys should be allowed either. Nested detail may live
inside a dedicated sub-key if a later phase truly needs it, but the top-level
shape should stay exact.

`accepted_at` in the API should simply be a presentation of
`workflow_bootstrap_requested_at`; it should not become a second source of truth.

### Fix the allowed state transitions

To avoid suspended states, only these transitions should be legal:

- `not_requested -> pending`
- `pending -> materializing`
- `materializing -> ready`
- `materializing -> failed`
- `failed -> materializing` for explicit or automatic retry

Additionally, stale `materializing` is not a separate state. It is still
`materializing`, but the recovery boundary must be allowed to reclaim it after a
timeout and drive it forward under lock.

Do not allow arbitrary direct updates such as:

- `pending -> ready`
- `pending -> failed`
- `ready -> pending`
- `ready -> failed`
- `not_requested -> ready`

### Give the bootstrap state a single write boundary

For long-term maintainability, the system should centralize writes:

- `Turns::AcceptPendingUserTurn`
  - owns `not_requested -> pending`
  - owns the initial payload and requested timestamp
  - owns queued bootstrap projection
- `Turns::MaterializeWorkflowBootstrap`
  - owns `pending/failed -> materializing`
  - owns `materializing -> ready`
  - owns `materializing -> failed`
  - owns failure payload writes and failure projection
- `Turns::RecoverWorkflowBootstrapBacklog`
  - owns scanning claimable `pending` turns and stale `materializing` turns
  - owns re-enqueueing or directly re-driving them through the materializer
  - does not mutate payload shape; it only restores progress on stranded work

No other service should directly mutate `workflow_bootstrap_state`,
`workflow_bootstrap_payload`, `workflow_bootstrap_failure_payload`, or the
bootstrap timestamps.

## Why This Merged Plan Is Better Than Keeping Two Independent Follow-Ups

Keeping the earlier two plans separate creates three problems:

1. root-conversation bootstrap noise masks the real before/after of first-turn
   API slimming
2. turn lazy bootstrap keeps redefining conversation-side read surfaces without
   explicitly owning the capability/lineage cleanup that precedes it
3. behavior docs drift because the first plan rewrites container semantics and
   the second rewrites turn-entry semantics on the same product surface

The merged iteration fixes that by making the dependency explicit:

- Phase A first
- remeasure
- Phase B second

## Behavior Docs That Must Change

This merged pass must update at least:

- `docs/behavior/turn-entry-and-selector-state.md`
- `docs/behavior/conversation-supervision-and-control.md`
- `docs/behavior/workflow-context-assembly-and-execution-snapshot.md`
- `docs/behavior/workflow-graph-foundations.md`
- `docs/behavior/workflow-model-selector-resolution.md`
- `docs/behavior/workflow-scheduler-and-wait-states.md`
- `docs/behavior/conversation-structure-and-lineage.md`
- any API behavior doc that still implies workflow substrate exists before a
  turn is merely accepted

## Recommended End State

After this iteration:

- bare `Conversation` bootstrap no longer allocates a capability row or lineage
  substrate
- `Conversation` owns its hot supervision/control authority directly
- lineage absence is represented honestly as “no reference yet”
- app-facing manual user turn entry records accepted-turn truth synchronously
- workflow substrate is created later and exactly once for those turns
- queued and bootstrap-failed states remain visible even before workflow rows
  exist
- bootstrap-state rows have a fixed internal shape and a narrow transition graph
  instead of ad-hoc partial updates
- all weight reductions are recorded with real before/after SQL and row deltas
