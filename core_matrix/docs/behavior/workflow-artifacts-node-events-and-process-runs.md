# Workflow Artifacts, Node Events, And Process Runs

## Purpose

Task 10.1 added the first workflow-owned runtime resource layer beyond the DAG
shape itself, and the later mailbox-control batch extends that layer with mailbox-owned
execution resources and durable close metadata.

The current runtime substrate still keeps workflow-local durable resources as
the source of truth and leaves user-visible projection to later layers. The
runtime resources that later tasks now build on are:

- `WorkflowArtifact`
- `WorkflowNodeEvent`
- `AgentTaskRun`
- `ProcessRun`
- `SubagentSession`

## Workflow Artifacts

- `WorkflowArtifact` belongs to exactly one installation, workflow run, and
  workflow node.
- Artifacts redundantly persist:
  - `workspace_id`
  - `conversation_id`
  - `turn_id`
  - `workflow_node_key`
  - `workflow_node_ordinal`
  - `presentation_policy`
- Artifacts use explicit storage modes rather than ad hoc payload shapes:
  - `inline_json`
  - `attached_file`
- `inline_json` persists structured payload in `payload` and does not attach a
  file.
- `attached_file` persists canonical metadata in `payload` and requires a
  `has_one_attached :file` attachment.
- Artifact ownership stays workflow-scoped: a node may emit an artifact, but
  the artifact remains queryable through the owning workflow run.
- Current yield materialization uses:
  - `intent_batch_manifest`
  - `intent_batch_barrier`
  as inline-json workflow artifacts on the yielding node.

## Workflow Node Events

- `WorkflowNode.lifecycle_state` is the durable scheduler truth for node
  execution.
- `WorkflowNodeEvent` is the append-only workflow-local execution stream.
- Every event belongs to one installation, workflow run, and workflow node.
- Events redundantly persist:
  - `workspace_id`
  - `conversation_id`
  - `turn_id`
  - `workflow_node_key`
  - `workflow_node_ordinal`
  - `presentation_policy`
- Events are ordered by a node-local `ordinal` that is unique per workflow
  node.
- Node-event ordinal allocation is serialized at the workflow-node boundary so
  concurrent runtime writers keep append-only event order without duplicate
  ordinal races.
- `event_kind` remains open-ended. The currently landed runtime paths use:
  - `status` events for node-local execution trace
  - `yield_requested`
  - `intent_rejected`
- `WorkflowNodeEvent` remains the kernel trace surface; later tasks may project
  selected runtime state into `ConversationEvent` only when that state is
  intentionally user-visible.
- The current implementation also exposes a separate temporary runtime stream for live consumers:
  - `ConversationRuntime::Broadcast` publishes ephemeral Action Cable payloads
  - these payloads may mirror node lifecycle changes or assistant-output deltas
  - they are transport only and must not be treated as scheduler truth,
    transcript history, or proof material
- scheduler selection reads the persisted graph plus
  `WorkflowNode.lifecycle_state`; node events are trace, not the runnable-node
  cursor.
- current `status` events are appended by:
  - `Workflows::ExecuteNode` when a coordination node such as `turn_root` or
    `barrier_join` completes
  - `ProviderExecution::ExecuteTurnStep` and its terminal persistence services
    for provider-backed `turn_step` nodes
  - `HumanInteractions::Request` when a yielded `human_interaction` node is
    consumed into a durable request resource
  - `Workflows::HandleWaitTransitionRequest` when a yielded `subagent_spawn`
    node is consumed into a durable subagent session
  - `Processes::Provision`, `Processes::Activate`, and `Processes::Exit` for
    environment-owned process resources
- Current yield materialization records:
  - `yield_requested`
  - `intent_rejected`
  as yielding-node-local audit events.
- Rejected intents remain visible through node-local events and proof output,
  but they do not create false durable mutation nodes.

## Process Runs

- `ProcessRun` is now a first-class runtime resource instead of an opaque tool
  side effect.
- `ProcessRun` is `ExecutionRuntime`-owned, not `AgentProgramVersion`-owned.
- Every process run belongs to:
  - one installation
  - one workflow node
  - one execution runtime
  - one conversation
  - one turn
  - optionally one originating transcript-bearing `Message`
- Task 10.1 intentionally does not add a second persisted `workflow_run_id` on
  `ProcessRun`; workflow-run ownership is derived through the owning node, while
  `conversation_id` and `turn_id` are redundantly persisted for operational
  filtering exactly as required by the design.
- `ProcessRun` now models detached background services only:
  - `background_service`
- v1 lifecycle states are explicit and validated:
  - `starting`
  - `running`
  - `stopped`
  - `failed`
  - `lost`
- detached background services are kernel-first:
  - `POST /execution_api/process_runs` provisions the durable `ProcessRun`
  - the execution runtime then reports `process_started` when the local handle
    is live
  - if the process exits without a close request, the runtime reports
    `process_exited`
- every process run now has a `public_id` so agent-facing close payloads and
  diagnostics never expose raw bigint ids
- process runs also persist close lifecycle fields:
  - `close_state`
  - `close_reason_kind`
  - `close_requested_at`
  - `close_grace_deadline_at`
  - `close_force_deadline_at`
  - `close_acknowledged_at`
  - `close_outcome_kind`
  - `close_outcome_payload`
- mailbox close for `ProcessRun` now rides the `execution` runtime plane:
  - mailbox `target_ref` is the owning `ExecutionRuntime.public_id`
  - delivery goes to the currently active `ExecutionSession` for that runtime
  - deployment rotation does not change process ownership

## Agent Task Runs

- `AgentTaskRun` is the workflow-owned execution resource for mailbox-driven
  agent work
- every agent task run belongs to:
  - one installation
  - one agent program
  - one workflow run
  - one workflow node
  - one conversation
  - one turn
  - optionally one accepted holder deployment
- task kinds are explicit and validated:
  - `turn_step`
  - `agent_tool_call`
  - `subagent_step`
- lifecycle states are explicit and validated:
  - `queued`
  - `running`
  - `completed`
  - `failed`
  - `interrupted`
  - `canceled`
- `logical_work_id` plus `attempt_no` separate business-attempt identity from
  mailbox-delivery retries
- `execution_started` is the durable acceptance point that:
  - moves the task to `running`
  - records the accepted holder deployment
  - acquires an `ExecutionLease`
- mailbox execution also keeps the backing `WorkflowNode` aligned:
  - assignment creation moves the node to `queued`
  - `execution_started` moves the node to `running`
  - terminal reports move the node to `completed`, `failed`, or `canceled`
- `AgentTaskRun` and `WorkflowNode` therefore have related but different state
  machines:
  - `AgentTaskRun` models mailbox-owned runtime execution, including
    `interrupted`
  - `WorkflowNode` models scheduler-visible DAG progress and does not use
    `interrupted`
- progress and terminal summaries are persisted directly on the task run
- mailbox-driven execution may also emit temporary runtime-stream events such
  as:
  - `runtime.agent_task.*`
  - `runtime.tool_invocation.*`
  for frontend progress display without mutating transcript or workflow truth
- short-lived command execution such as `exec_command` now rides this path:
  - durable result and audit land in `ToolInvocation`
  - kernel allocation creates one `CommandRun` in `starting`
  - runtime flips that `CommandRun` to `running` only after the local command
    handle is live
  - stdout/stderr chunks are streamed as
    `runtime.tool_invocation.output`
  - the durable terminal payload keeps summary fields such as exit status and
    byte counts, not raw stdout/stderr bodies
  - command subprocess lifecycle remains subordinate to the owning
    `AgentTaskRun`
  - runtime execution of that task is delivered through mailbox control, not a
    runtime-specific HTTP execution callback
- agent task runs persist the same durable close fields as other closable
  runtime resources so later interrupt and close orchestration can target one
  stable execution aggregate

## Subagent Sessions

- delegated subagent work now owns a child conversation plus a
  `SubagentSession`
- the durable execution instance remains
  `AgentTaskRun(kind = "subagent_step")`
- yielded `subagent_spawn` workflow nodes are owner-managed and are marked
  `completed` as soon as the child session and initial child work are created
- later parent waiting comes from the barrier/session state, not from leaving a
  `subagent_spawn` node in `pending`
- session close requests use the same mailbox-driven close machinery as other
  closable runtime resources
- when a session close request has no active lease holder, delivery falls back
  to the owner conversation's logical `agent_program`

## Timeout And Ownership Rules

- `background_service` must not carry a bounded timeout.
- `conversation_id` must match the owning workflow run conversation.
- `turn_id` must match the owning workflow run turn.
- `origin_message_id`, when present, must belong to the same conversation and
  turn as the process run.
- `AgentTaskRun.agent_program_id` must match the turn program version logical
  agent program.
- `ExecutionLease.holder_key` is only a routing and heartbeat hint for the
  current runtime endpoint; it does not redefine the owner of a process run.
- `started_at` is defaulted during validation for new records so model-level
  validation and service-created rows share the same timestamp baseline.
- non-running process states require `ended_at`; running process states must not
  carry `ended_at`.
- queued `AgentTaskRun` rows must not carry `started_at` or `finished_at`
- terminal `AgentTaskRun` rows must persist both `started_at` and `finished_at`

## Process Lifecycle Services

- `Processes::Provision` is the kernel-first application-service boundary for
  opening a detached workflow process resource.
- Provision currently:
  - materializes one `ProcessRun` in `starting`
  - derives `conversation` and `turn` from the owning workflow run
  - appends one `WorkflowNodeEvent` with `event_kind=status` and
    `payload.state=starting`
  - acquires the delivery lease used by later `process_started`,
    `process_output`, and `process_exited` reports
- `Processes::Activate` is the runtime-confirmed activation boundary.
- Activate currently:
  - transitions the process from `starting` to `running`
  - appends the `running` status event
  - broadcasts one temporary `runtime.process_run.started` event for live UI
    consumers
  - records an `AuditLog` row when the process is actually live
- `Processes::Exit` is the runtime-side terminalization boundary for detached
  processes that stop without an explicit close request.
- Exit currently:
  - accepts `starting` or `running` process runs
  - transitions them to `stopped` or `failed`
  - releases the execution lease
  - appends the matching terminal status event
  - broadcasts the matching `runtime.process_run.*` event
  - stamps `ended_at`
  - records `stop_reason` in process metadata
  - appends one `WorkflowNodeEvent` with `event_kind=status` and
    `payload.state=stopped`
  - broadcasts one temporary `runtime.process_run.stopped` event for live UI
    consumers
- terminal close handling may also broadcast:
  - `runtime.process_run.output` for stdout/stderr chunks supplied by the
    reporting runtime
  - `runtime.process_run.stopped`
  - `runtime.process_run.lost`
- those runtime-stream payloads are not persisted on `ProcessRun`; the durable
  row only keeps lifecycle, close, and metadata facts

## Failure Modes

- attached-file artifacts reject missing attachments
- node events reject duplicate ordinals within the same workflow node
- artifacts and node events reject projection metadata that disagrees with the
  owning workflow node
- process runs reject workflow-turn or workflow-conversation mismatches
- process runs reject bounded timeouts on background services
- stop requests reject non-running process runs instead of silently mutating
  terminal rows
- agent task runs reject turn, conversation, workflow, or agent-program
  projection drift
- closable runtime resources reject incomplete close lifecycle pairings

## Rails And Reference Findings

- Local Rails association guides were used here to keep ownership explicit
  through `belongs_to` foreign-key relationships and model-level consistency
  checks instead of inferring cross-record identity from loose IDs alone.
- Local Rails validation guides were used again for the
  `errors.add` plus `ActiveRecord::RecordInvalid` service-boundary pattern used
  in `Processes::Activate` and `Processes::Exit`.
- Local Active Storage guides confirmed the `has_one_attached` model pattern is
  the right durable boundary for file-backed workflow artifacts in this task.
- No `references/` implementation was treated as authoritative for Task 10.1;
  the landed behavior is derived from the local design and plan documents.

## Yield Materialization Notes

- `Workflows::IntentBatchMaterialization` is the current workflow-first
  materialization path for accepted and rejected intent batches.
- Accepted intents append durable `WorkflowNode` rows and workflow edges from
  the yielding node.
- The yielding `WorkflowRun` stores the active `resume_policy` and successor
  summary in `resume_metadata` so later wait-state and proof work can resume
  from stable kernel-owned facts.
