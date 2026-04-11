# Core Matrix Conversation Close And Mailbox Control Protocol Design

## Status

Approved focused design note for the Phase 2 control plane.

This document replaces the earlier claim-first execution-delivery direction for
the parts covered here. Use it as the source of truth for:

- mailbox-shaped agent control semantics
- `turn_interrupt` as a kernel primitive
- conversation close semantics for archive and delete
- resource close lifecycle and retry taxonomy

## Purpose

Phase 2 needs one coherent model that covers:

- how `Core Matrix` delivers work to agents
- how agents report progress and terminal state
- how `Stop`, archive, and delete interact with active work
- how retries behave without reviving superseded work

The design target is not "HTTP" or "WebSocket". The canonical target is a
durable mailbox model with leases, deadlines, and idempotent handlers.

## Decision Summary

- Canonical control semantics are `mailbox / MQ + lease + deadlines`.
- `poll` and `WebSocket` are delivery transports for the same mailbox items.
- `Core Matrix` must never require a reverse callback into an agent.
- `turn_interrupt` is a first-class kernel primitive and is orthogonal to
  archive and delete.
- archive and delete both reuse `turn_interrupt`, then add disposal behavior
  and state transitions.
- `step_retry` inside the current turn and workflow is a distinct recovery
  mode from `workflow_retry`.
- `close` always outranks `retry`.
- archive may complete with residual background-disposal failures, but only
  after the active turn and workflow mainline have been stopped.

## Transport Split

### Resource Plane

Use short HTTP requests for resource-style APIs:

- registration and enrollment
- transcript reads
- conversation and workspace variable APIs
- human interaction open or resolve paths
- artifact upload or download when needed

These APIs stay stateless and are not the main control loop.

### Control Plane

Use a mailbox-shaped control plane for:

- execution delivery
- execution progress and terminal reporting
- close requests
- capability refresh requests
- recovery or operator notices
- deployment health reporting

Delivery rules:

- `WebSocket` is the preferred low-latency delivery path
- `agent_poll` is always available as the durable fallback path
- agent-to-kernel responses may piggyback pending mailbox items when useful
- both transports use the same mailbox item envelope

The protocol remains framework-agnostic even if Rails uses ActionCable,
SolidCable, or AnyCable underneath.

## Presence And Health

Do not collapse link state and deployment health into one boolean.

Persist two separate facts:

- `realtime_link_state`
  - `connected`
  - `disconnected`
- `control_activity_state`
  - `active`
  - `stale`
  - `offline`

Recommended rules:

- `WebSocket` connect sets `realtime_link_state = connected`
- `WebSocket` disconnect sets `realtime_link_state = disconnected`
- any valid control-plane activity refreshes `control_activity_state`
  - `agent_poll`
  - `deployment_health_report`
  - execution reports
  - close acknowledgements
  - `WebSocket` messages
- lack of control activity moves the deployment from `active` to `stale`, then
  to `offline`

Implication:

- `WebSocket` disconnect alone is a warning, not a hard failure
- `Polling only` is an acceptable steady state

## Mailbox Item Model

The kernel should model one targeted control mailbox rather than a generic
message bus.

Each mailbox item should carry at least:

- `item_id`
- `item_type`
- `target_kind`
- `target_ref`
- `logical_work_id`
- `attempt_no`
- `delivery_no`
- `message_id`
- `causation_id`
- `priority`
- `status`
- `available_at`
- `dispatch_deadline_at`
- optional `lease_timeout_seconds`
- optional `execution_hard_deadline_at`
- `payload`

Recommended Phase 2 `item_type` values:

- `execution_assignment`
- `resource_close_request`
- `capabilities_refresh_request`
- `recovery_notice`

Recommended status values:

- `queued`
- `leased`
- `acked`
- `completed`
- `failed`
- `expired`
- `canceled`

This is sufficient for Phase 2. It is intentionally not a general-purpose
broker product.

### Targeting Rules

Mailbox items must be explicitly targetable.

Recommended rules:

- `execution_assignment` should target an eligible deployment scope for one
  `AgentInstallation` until one runtime accepts it with `execution_started`
- once an execution is started, later progress and terminal reports are
  attributable to the accepted holder and lease
- `resource_close_request` should target the current holder when one is known,
  rather than broadcasting across all deployments for an installation
- deployment rotation may move future assignments to a new deployment, but it
  must not make close requests ambiguous for work already in flight

## Ordering And Priority

The protocol does not need global FIFO.

Rules:

- preserve causality within one resource or logical work item
- do not require cross-resource total ordering
- close requests outrank all normal execution work

Recommended priority classes:

- `P0`: `resource_close_request`
- `P1`: `execution_assignment`
- `P2`: `execution_attempt_retry`
- `P3`: `capabilities_refresh_request`
- `P4`: `recovery_notice`

Close outranks retry:

- once a close request exists for a resource or turn fence, queued retries must
  be canceled or ignored
- no new ordinary retry attempt may be opened for fenced work

## Execution Delivery

### Canonical Flow

The durable execution flow should be:

1. kernel creates `execution_assignment`
2. agent receives it by `WebSocket`, `agent_poll`, or piggyback delivery
3. agent replies with `execution_started`
4. agent emits zero or more `execution_progress`
5. agent emits one terminal message:
   - `execution_complete`
   - `execution_fail`
   - `execution_interrupted`

This replaces the earlier `execution_claim` model for Phase 2.

`execution_started` is the durable acceptance point for the assignment:

- it acknowledges one delivery
- it establishes the active holder or lease for the attempt
- it turns an offered mailbox item into running execution

### `AgentTaskRun`

`AgentTaskRun` remains the recommended workflow-owned runtime resource for
agent-controlled execution.

Recommended task kinds:

- `turn_step`
- `agent_tool_call`
- `subagent_step`

`AgentTaskRun` should persist:

- workflow and node ownership
- useful redundant conversation and turn ownership
- logical execution identity
- attempt lineage
- close lifecycle fields
- progress or terminal summaries

### Deadlines

The execution path should use explicit deadlines:

- `dispatch_deadline`
- `lease_timeout`
- `execution_hard_deadline`

An agent may report:

- `expected_duration_seconds`
- or `expected_finish_at`

The kernel may accept, cap, or reject that expectation according to policy.

## Retry Taxonomy

The protocol must separate different retry classes.

### 1. Message Retry

One protocol message is resent because the sender is unsure the receiver
accepted it.

Rules:

- same `message_id`
- no new attempt
- pure idempotent replay

### 2. Delivery Retry

One mailbox item was not consumed or its lease went stale.

Rules:

- same `logical_work_id`
- same `attempt_no`
- `delivery_no` increases
- does not mean the business operation restarted

### 3. Step Retry

This is the product-facing "Retry" for a failed step inside the current turn.

Rules:

- same turn
- same workflow
- same workflow node or logical execution scope
- completed predecessor work stays intact
- a new attempt is created
- this is not `workflow_retry`

Use this for retryable tool-call or step failures where the user expects to
continue from the current turn state.

### 4. Workflow Resume

Resume the current workflow after a recoverable wait such as deployment
unavailability.

This maps to the existing `ManualResume` semantics.

### 5. Workflow Retry

Abandon the paused workflow history and start a fresh workflow from the last
stable input.

This maps to the existing `ManualRetry` semantics.

### 6. Close Escalation

Retry or escalate a close operation:

- graceful close
- forced close
- residual or degraded terminal state

This is not an execution retry.

## Retryable Failure Gate

When a step fails in a way the product should allow retrying in place, the turn
should not be treated as fully finished.

Recommended behavior:

- the turn remains part of active conversation work
- the workflow moves into a kernel-owned retry gate
- the failing resource is recorded as the blocker
- the user may choose:
  - `Retry Step`
  - `Stop`
  - future actions such as edited recovery inputs

Recommended `WorkflowRun.wait_reason_kind` addition:

- `retryable_failure`

Recommended payload fields:

- `failure_kind`
- `retryable`
- `retry_scope = "step"`
- `logical_work_id`
- `attempt_no`
- `last_error_summary`

## Turn Interrupt

### Product Meaning

User-facing `Stop` maps to protocol-level `turn_interrupt`.

The kernel result is:

- current active turn work is interrupted
- the turn eventually moves to `canceled`
- no new ordinary retry work may continue under the same interrupted turn

### Scope

`turn_interrupt` must clear the `mainline stop barrier`:

- active turn
- active workflow mainline
- active `AgentTaskRun`
- blocking `HumanInteractionRequest`
- turn-scoped tool call
- user shell command
- `ProcessRun(kind = turn_command)`
- turn-bound `SubagentConnection`

It does not, by itself, guarantee termination of detached background resources.

### Fence Rule

Once `turn_interrupt` is requested:

- create a close fence for the turn
- reject or ignore later stale completions that would mutate the current turn
- disallow ordinary `step_retry` for that fenced turn
- treat late results only as duplicate, stale, or superseded reports

This fence rule is the main safeguard against "Stop" being silently undone by a
later retry or stale completion.

## Resource Close Protocol

Execution reporting alone is not sufficient for archive, delete, and detached
resource cleanup.

Phase 2 should add a generic resource close protocol with these public method
ids:

- `resource_close_request`
- `resource_close_acknowledged`
- `resource_closed`
- `resource_close_failed`

Recommended request payload:

- `close_request_id`
- `resource_type`
- `resource_id`
- `target_kind`
- `target_ref`
- `request_kind`
- `reason_kind`
- `grace_deadline_at`
- `force_deadline_at`
- `strictness`

Recommended `request_kind` values:

- `turn_interrupt`
- `workflow_cancel`
- `archive_force_quiesce`
- `deletion_force_quiesce`
- `resource_terminate`

Recommended terminal outcome values:

- `graceful`
- `forced`
- `timed_out_forced`
- `residual_abandoned`

### Resource-Specific Disposal Expectations

Phase 2 should keep one generic close protocol, but still pin down the expected
resource-specific behavior:

- `ProcessRun(kind = turn_command)`:
  - graceful close should request interrupt semantics equivalent to `SIGINT`
  - forced close should request termination semantics equivalent to `SIGKILL`
  - if forced close still fails, persist `close_outcome_kind =
    residual_abandoned`
- `ProcessRun(kind = background_service)`:
  - normal `turn_interrupt` does not target it
  - archive and delete close flows do target it through the generic
    resource-close protocol
- agent-owned tool processes:
  - if they are modeled as `ProcessRun`, they inherit the same `SIGINT /
    SIGKILL / residual_abandoned` behavior
  - this matches the current Phase 2 validation shape where `Fenix` tools are
    process-oriented
- `MCP` or long-lived network calls:
  - graceful close should request local stream or request cancellation
  - forced close should abort the connection or client session
  - kernel still requires a terminal close outcome rather than assuming that a
    dropped connection implies successful cleanup

### Durable Resource Fields

Add durable close fields to closable runtime resources:

- `AgentTaskRun`
- `ProcessRun`
- `SubagentConnection`

Recommended fields:

- `close_state`
- `close_reason_kind`
- `close_requested_at`
- `close_grace_deadline_at`
- `close_force_deadline_at`
- `close_acknowledged_at`
- `close_outcome_kind`
- `close_outcome_payload`

These fields are necessary so archive, delete, operator tooling, and proof
artifacts do not have to infer close history solely from event streams.

## Archive And Delete

Both archive and delete should reuse the same close machinery, but they do not
share the same final business semantics.

### Conversation Close Operation

Introduce a dedicated durable object:

- `ConversationCloseOperation`

Recommended fields:

- `intent_kind`
  - `archive`
  - `delete`
- `lifecycle_state`
  - `requested`
  - `quiescing`
  - `disposing`
  - `completed`
  - `degraded`
- `summary_payload`
- `requested_at`
- `completed_at`

`Conversation` keeps final product state such as:

- `lifecycle_state`
- `deletion_state`

The close operation records how the conversation is being or was closed.

### Archive

`Archive(force: true)` should mean:

1. create `ConversationCloseOperation(intent_kind = archive)`
2. close the conversation to new turn entry
3. request `turn_interrupt`
4. request disposal of detached background resources
5. once the mainline stop barrier is clear, transition the conversation to
   `archived`
6. if disposal tails still have residual failures, mark the close operation as
   `degraded`

Archive therefore requires the active turn and workflow mainline to stop, but
it does not require every detached background residue to disappear before
`archived` is reached.

### Delete

Delete should mean:

1. set `deletion_state = pending_delete`
2. create `ConversationCloseOperation(intent_kind = delete)`
3. remove the conversation from normal product surfaces
4. request `turn_interrupt`
5. request disposal of detached background resources
6. allow `FinalizeDeletion` once the mainline stop barrier is clear
7. allow `PurgeDeleted` only when lineage and provenance blockers are gone

Delete does not imply recursive child deletion.

## Parent And Child Conversations

Recommended Phase 2 rules:

- parent archive does not archive retained children
- parent delete does not delete retained children
- child conversations may continue running
- ancestor purge remains blocked by descendant lineage or provenance
- subtree delete, if added later, should be a separate explicit product action

This preserves the existing lineage shell model while keeping purge safe.

## Mainline Stop Barrier Versus Disposal Tail

The close model depends on a strict distinction.

### Mainline Stop Barrier

Must be stopped before archive or final deletion proceeds:

- current turn
- current workflow mainline
- current `AgentTaskRun`
- blocking human interaction
- turn-scoped shell or tool process
- running subagent work that is part of the current turn path

### Disposal Tail

Best-effort cleanup after the mainline has stopped:

- detached background service
- detached tool process
- MCP connection
- long-lived network stream
- other external residue no longer required for turn correctness

Archive and delete may reach terminal conversation state while disposal tail
cleanup is degraded, as long as the degradation is recorded durably.

## UI And Operator Summary

Add a close-summary query for UI confirmation and operator inspection rather
than exposing only narrow helper predicates.

Recommended query object:

- `Conversations::CloseSummaryQuery`

Recommended result shape:

- `mainline.active_turn_count`
- `mainline.active_workflow_count`
- `mainline.active_agent_task_count`
- `mainline.open_blocking_interaction_count`
- `mainline.running_turn_command_count`
- `mainline.running_subagent_count`
- `tail.running_background_process_count`
- `tail.detached_tool_process_count`
- `dependencies.descendant_lineage_blockers`
- `dependencies.root_store_blocker`
- `dependencies.variable_provenance_blocker`
- `dependencies.import_provenance_blocker`

Keep small helper predicates such as
`Conversation#active_turn_exists?(include_descendants: false)` for hot paths,
but do not make them the primary UI contract.

## Differences From The Current Phase 1 Behavior

The current implementation still uses direct local mutation through
`Conversations::QuiesceActiveWork` and `Processes::Stop`.

Phase 2 should replace that model with:

- durable mailbox delivery
- close requests and acknowledgements
- resource-level close lifecycle fields
- `ConversationCloseOperation`
- interrupt fences and retry taxonomy

This is an intentional breaking redesign, not an additive compatibility layer.

## Superseded Design Direction

This document supersedes the earlier Phase 2 direction that treated:

- short HTTP execution claim as the canonical control path
- heartbeat as the only availability truth
- execution delivery and close behavior as one mostly execution-centric model

Use this document instead when Phase 2 plans or tasks mention:

- execution transport
- mailbox delivery
- stop or interrupt semantics
- archive or delete close behavior
- retry taxonomy
