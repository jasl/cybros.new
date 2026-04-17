# Agent And Execution Runtime Resource APIs

## Purpose

Core Matrix exposes two machine-facing runtime resource planes for:

- canonical transcript listing
- conversation-local lineage store reads and writes
- workspace-scoped canonical variable reads and writes
- conversation-scoped supervision status refresh and bounded control dispatch
- workflow-owned human interaction request creation
- workflow-owned `ToolInvocation` creation on the agent plane
- workflow-owned `CommandRun` and `ProcessRun` creation on the
  execution-runtime plane
- mailbox-driven execution delivery and close control

The resource plane stays a thin HTTP boundary over authenticated lookups,
query objects, and kernel-owned services. The control plane uses the same
connection-credential authentication model but carries durable mailbox items
through `poll`, `WebSocket`, and response piggyback delivery.

Runtime pairing manifests remain registration metadata only. Product execution
and close control do not use a separate runtime callback endpoint such as
`/runtime/executions`; they ride the mailbox-first control plane described
here.

Conversation supervision side chat does not talk to these runtime endpoints
directly. It creates `ConversationControlRequest` rows, and the control plane
then reuses the same mailbox substrate for the subset of verbs that require
agent-runtime delivery.

## Status

This document describes the current landed runtime resource plane and the
current mailbox control surface. Transcript, variable, and human-interaction
APIs remain short HTTP resource-style boundaries. Mailbox delivery and
resource-close reporting now use dedicated control endpoints plus the optional
realtime stream described here. Broader turn-interrupt and conversation-close
orchestration are still defined in:

- [2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md)

## Authentication And Lookup Scope

- agent-plane endpoints authenticate `AgentConnection`
- execution-runtime-plane endpoints authenticate `ExecutionRuntimeConnection`
- lookups are scoped to the authenticated connection owner's installation
- lookups resolve resources by `public_id`, never raw internal `bigint` ids
- conversations are resolved only while `deletion_state = retained`
- deleted or pending-delete conversations are therefore hidden from
  agent-facing transcript and variable endpoints
- control-plane resources such as `AgentTaskRun`, `ProcessRun`, and
  `SubagentConnection` also resolve by `public_id`
- those runtime resources also redundantly persist `user_id`, `workspace_id`,
  `agent_id`, `conversation_id`, and `turn_id` wherever the resource type has
  that context, so control-plane filters do not need to reconstruct ownership
  from nested joins
- capability refresh also exposes governed tool metadata by `public_id`; the
  agent-facing boundary does not expose internal numeric ids for
  `ToolDefinition` or `ToolImplementation`

## Control Plane

### Delivery Paths

- `POST /agent_api/control/poll` is the durable fallback transport for pending
  agent-plane mailbox items
- `POST /agent_api/control/report` carries agent-plane reports back into the
  kernel
- `POST /execution_runtime_api/control/report` carries execution-runtime-plane
  reports for execution-runtime-owned resources such as `ProcessRun`
- the agent control plane uses one mailbox with multiple request kinds,
  including prompt and loop preparation, supervision verbs, and agent-owned
  tool calls
- execution-runtime-plane mailbox items are only for runtime-owned work such
  as tool execution, detached runtime resources, and close control
- conversation-scoped status refresh and guidance requests are serialized into
  the same mailbox envelope after `ConversationControl::DispatchRequest`
- `/cable` may stream the same mailbox-item envelope over `ControlPlaneChannel`
- poll responses, realtime broadcasts, and report-response piggyback all use
  the same mailbox item envelope:
  - `item_id`
  - `item_type`
  - `control_plane`
  - `target_kind`
  - `target_ref`
  - `logical_work_id`
  - `attempt_no`
  - `delivery_no`
  - `protocol_message_id`
  - `causation_id`
  - `priority`
  - `status`
  - `available_at`
  - `dispatch_deadline_at`
  - `lease_timeout_seconds`
  - optional `execution_hard_deadline_at`
  - `payload`
- `control_plane` is explicit:
  - `agent` for agent-loop work and agent-owned close control
  - `execution_runtime` for `ExecutionRuntime`-owned resources such as
    `ProcessRun`
- turns may legitimately have no execution-runtime-plane work at all when the
  conversation is running without a selected execution runtime
- mailbox rows persist routing semantics as durable columns:
  - `control_plane`
  - `target_kind`
  - `target_ref`
  - optional `target_execution_runtime_id` for execution-runtime-plane work
- `payload` now carries only family-specific request data; routing identity is
  not reconstructed from payload shape
- for `agent` plane close work, the durable owner fallback is resolved from
  the resource type rather than the current delivery lease:
  - `AgentTaskRun` falls back to its own `agent`
  - `SubagentConnection` falls back to the logical `agent`
    associated with its owner conversation, or its origin turn when that turn
    exists
- for `execution_runtime` plane work:
  - `target_ref` is the owning `ExecutionRuntime.public_id`
  - `target_execution_runtime_id` stores the owning
    `ExecutionRuntime` foreign key on the mailbox row
  - if no active execution-runtime connection currently holds the resource
    lease, the
    mailbox row still records the owning turn agent definition version's logical
    `agent` as the durable installation target
  - the live delivery endpoint is resolved separately through the shared
    `ResolveTargetRuntime` contract instead of SQL payload routing

### Control Reports

- `agent_poll` leases queued mailbox items to the authenticated agent
  connection
- `execution_assignment` delivery remains valid only while the backing
  `AgentTaskRun` is still `queued`; interrupt-canceled leased assignments are
  marked `canceled` and have their lease cleared before later polls
- `ResolveTargetRuntime`, `Poll`, and `PublishPending` now share the same
  durable mailbox routing contract for both agent-plane and
  execution-runtime-plane delivery
- `AgentControl::Report` is a thin ingress shell for:
  - agent-connection activity touch
  - duplicate detection
  - receipt creation
  - stale-to-HTTP translation
  - piggyback poll assembly
  - explicit `payload:` envelope ingestion; report body fields are no longer
    accepted as top-level Ruby keywords
- `execution_started` is the durable acceptance point for
  `execution_assignment`
- `execution_progress`, `execution_complete`, `execution_fail`, and
  `execution_interrupted` are attributed to the accepted holder agent connection,
  its frozen `AgentDefinitionVersion`, and the active `AgentTaskRun` lease
- execution report lifecycle handling now lives in
  `HandleExecutionReport` and freshness checks live in
  `ValidateExecutionReportFreshness`
- `process_output` is the live output report for running detached
  `ProcessRun(kind = "background_service")` resources:
  - it is accepted only for `ProcessRun`
  - the reporting execution-runtime connection must belong to the owning
    `ExecutionRuntime`
  - when a process lease is active, the report also heartbeats that lease
  - payload carries `output_chunks`, each with transport-only stdout/stderr
    text
  - the chunks are broadcast on the temporary conversation runtime stream and
    are not persisted on the `ProcessRun` row
- `process_started` is the runtime-side activation report for a provisioned
  detached `ProcessRun`:
  - the kernel creates the durable resource first through
    `POST /execution_runtime_api/process_runs`
  - the runtime reports `process_started` only after the local process handle
    is live
  - the report transitions the `ProcessRun` from `starting` to `running`
- `process_exited` is the runtime-side terminal report for a detached
  `ProcessRun` that stops without a mailbox close request:
  - it is accepted only while the process is still `starting` or `running`
  - payload carries terminal `lifecycle_state`, optional `exit_status`, and
    summary metadata such as `reason`
  - the report terminalizes the durable `ProcessRun` and emits the matching
    `runtime.process_run.*` stream event without creating a `ToolInvocation`
- short-lived command output does not use `process_output`; it is reported
  through execution progress as `runtime.tool_invocation.output`
- short-lived command resources are created in two steps before local spawn:
  - `POST /agent_api/tool_invocations`
  - `POST /execution_runtime_api/command_runs`
- those create APIs are valid only while the backing parent execution is still
  live:
  - `tool_invocations` require `AgentTaskRun.lifecycle_state = running` and no
    in-flight close request
  - `command_runs` require a running `ToolInvocation` whose backing
    `AgentTaskRun` is still live
  - `command_run_activate` also rejects activation once the parent execution is
    closing or terminal
- detached long-lived process resources are created before local spawn through:
  - `POST /execution_runtime_api/process_runs`
- that create payload includes `tool_name = "process_exec"` so the kernel can
  resolve the frozen governed `ToolBinding` before it allocates the durable
  `ProcessRun`
- `process_runs` creation likewise requires the backing `AgentTaskRun` to still
  be running and free of a close request
- detached long-lived process tools such as `process_exec` then activate that
  durable resource through `process_started`; they do not create `ToolInvocation`
  rows or `CommandRun` rows
- the terminal `ToolInvocation.response_payload` for short-lived commands should
  keep structured summary data only, such as exit status and streamed byte
  counts, rather than raw stdout/stderr bodies
- `resource_close_acknowledged`, `resource_closed`, and
  `resource_close_failed` update the durable close fields on closable runtime
  resources
- close report lifecycle handling now lives in `HandleCloseReport` and
  freshness checks live in `ValidateCloseReportFreshness`
- close reports are attributed to the connection and frozen
  `leased_to_agent_definition_version` recorded for that mailbox item; once one
  connection has accepted the close request, sibling connections for the same
  logical agent must be treated as stale reporters for that request
- terminal close reports for `AgentTaskRun`, `ProcessRun`, and
  `SubagentConnection` must also re-enter
  `Conversations::ReconcileCloseOperation` through the resource's owning
  conversation. `SubagentConnection` close reports also refresh the child
  conversation because the connection row itself owns that transcript
  container.
- terminal process close reports may also carry `output_chunks`; those chunks
  are broadcast before the terminal `runtime.process_run.*` event and are not
  persisted durably
- execution-runtime-owned close reports are only accepted from the active
  `ExecutionRuntimeConnection` attached to the owning `ExecutionRuntime`
- `agent_health_report` now routes through `HandleHealthReport` and
  refreshes connection health plus `control_activity_state`
- duplicate control reports are idempotent by `protocol_message_id`
- stale or superseded reports return `409 conflict` and do not mutate durable
  execution state

### Connection Activity Facts

- `AgentConnection.realtime_link_state` records whether the active agent
  connection currently has a realtime control link
- `AgentConnection.control_activity_state` records durable control-plane
  freshness separately from realtime connectivity
- valid poll, report, and realtime-open events refresh
  `control_activity_state = "active"`
- realtime disconnect alone only moves `realtime_link_state` to
  `disconnected`; it does not mark the agent unavailable by itself

## Transcript Listing

- transcript listing publishes the stable method ID
  `conversation_transcript_list`
- transcript reads return only the canonical visible transcript projection
- hidden transcript rows do not leak through this endpoint
- cursor pagination uses visible message `public_id`

## Conversation Variable APIs

### Read Operations

- `conversation_variables_get` returns one visible conversation-local value
- `conversation_variables_mget` returns visible conversation-local values keyed
  by requested names
- `conversation_variables_exists` returns whether a visible conversation-local
  key exists
- `conversation_variables_list_keys` returns paginated key metadata only
- `conversation_variables_resolve` returns the effective merged view with
  conversation-local values overriding workspace-scoped canonical variables

### Mutation Operations

- `conversation_variables_set` writes one conversation-local value through
  `LineageStores::Set`
- `conversation_variables_delete` writes one conversation-local tombstone
  through `LineageStores::DeleteKey`
- `conversation_variables_promote` reads the current conversation-local value
  and writes a new workspace canonical-variable history row through
  `Variables::PromoteToWorkspace`

### Contract Rules

- conversation-local runtime state is backed by the lineage store, not by
  `CanonicalVariable`
- `conversation_variables_get`, `mget`, `exists`, and `list_keys` do not fall
  back to workspace values
- `list_keys` returns metadata only:
  - key
  - scope
  - value type
  - value byte size
- `conversation_variables_list` and `conversation_variables_write` were removed
  in the same rollout; no compatibility aliases remain
- conversation-variable payloads do not expose lineage-store row ids or
  canonical-variable row ids
- writes, deletes, and promotion are rejected unless the owning conversation is
  still:
  - `retained`
  - `active`
  - free of unfinished close operations

## Workspace Variable APIs

- `workspace_variables_get` returns the current workspace value for one key
- `workspace_variables_mget` returns current workspace values keyed by
  requested names
- `workspace_variables_list` returns current workspace values in key order
- `workspace_variables_write` creates a new workspace-scoped
  `CanonicalVariable` history row through `Variables::Write`

## Human Interaction Requests

- `human_interactions_request` creates a workflow-owned
  `HumanInteractionRequest` through `HumanInteractions::Request`
- blocking requests still move the workflow run into `wait_state = "waiting"`
- request creation still projects `human_interaction.opened`
  `ConversationEvent` rows
- opening a human interaction is rejected unless the owning conversation is
  both retained and active
- opening a human interaction is also rejected while a conversation close is in
  progress or after the owning turn has been fenced by `turn_interrupt`
- late human resolution paths are also rejected once the conversation is no
  longer retained, no longer active, or already closing
- both checks are enforced from fresh locked conversation and workflow/request
  state through the shared `ConversationBlockerSnapshot`-backed mutation guard
  rather than trusting a stale caller-side object snapshot

## Public Contract Rules

- runtime method IDs stay stable `snake_case` protocol identifiers
- route names stay resource-oriented and do not redefine the method IDs
- payload fields such as `workspace_id`, `conversation_id`, `turn_id`,
  `workflow_run_id`, `workflow_node_id`, `agent_task_run_id`, and
  `resource_id` carry `public_id` values
- machine-facing runtime resource creation also uses `public_id` only:
  - `agent_task_run_id`
  - `tool_invocation_id`
  - `command_run_id`
  - `process_run_id`
- workflow wait blockers also use durable identifiers:
  - `WorkflowRun.blocking_resource_id` stores `public_id` values, including
    `AgentDefinitionVersion.public_id` for `agent_unavailable`
- raw internal bigint ids are never accepted as fallback resource lookups
- capability snapshots still expose `protocol_methods` separately from
  `tool_catalog`
- capability endpoints also expose:
  - `agent_plane`
  - `execution_runtime_plane`
  - `effective_tool_catalog`
  - `governed_effective_tool_catalog`
- those capability sections and the conversation-facing runtime capability
  payload now come from the shared `RuntimeCapabilityContract`
- `effective_tool_catalog` applies ordinary tool precedence in
  `ExecutionRuntime -> Agent -> Core Matrix` order and keeps reserved
  `core_matrix__*` tools outside that collision domain
- `governed_effective_tool_catalog` adds the durable governance identifiers and
  `governance_mode` for the effective tool winner without exposing internal ids
- `target_ref` is the durable owner reference, not a promise that the same
  agent definition version will remain the delivery endpoint across rotation

## Governed Tool Execution Audit

- `AgentTaskRun` now freezes its visible governed tool set when the task row is
  created
- that freeze produces one `ToolBinding` row per visible logical tool for the
  task attempt
- later tool use is expected to record `ToolInvocation` rows against those
  bindings instead of bypassing the task boundary with source-specific audit
  paths
- later delivery is routed from the frozen `ToolBinding` winner, not by
  re-inferring ownership from the logical tool name at execution time
- runtime-owned tool execution now requests kernel-owned `ToolInvocation`
  resources through `POST /agent_api/tool_invocations` before local side
  effects begin
- command tools that need an attached process handle additionally request one
  `CommandRun` through `POST /execution_runtime_api/command_runs`
- `CommandRun` creation is an allocation step, not proof that the local
  command already exists:
  - create returns `lifecycle_state = "starting"`
  - runtime must follow with `POST /execution_runtime_api/command_runs/:id/activate`
    after the local subprocess or PTY session is actually live
- detached long-lived environment processes request one `ProcessRun` through
  `POST /execution_runtime_api/process_runs` before local spawn
- `POST /execution_runtime_api/process_runs` still resolves the frozen `process_exec`
  `ToolBinding` for the owning `AgentTaskRun`; long-lived process creation does
  not bypass governed tool visibility just because it materializes a
  `ProcessRun` instead of a `ToolInvocation`
- capability refresh exposes the winning governed tool definition and
  implementation ids as `public_id` values inside
  `governed_effective_tool_catalog`
- MCP-backed governed tools keep transport state on
  `ToolBinding.binding_payload["mcp"]`, including:
  - `transport_kind`
  - `server_url`
  - `tool_name`
  - `session_id`
  - `session_state`
  - `last_sse_event`
  - `initialize_result`
- failed governed MCP attempts record one shared source-neutral error shape on
  `ToolInvocation.error_payload`, including:
  - `classification`
  - `code`
  - `message`
  - `retryable`
  - `details`

## Failure Modes

- unknown public ids fail lookup before any read or mutation runs
- raw bigint identifiers fail as missing resources at these boundaries
- transcript cursors that are not present in the visible projection are invalid
- oversized or illegal lineage-store writes fail through the underlying
  lineage-store validations
- conversation-local writes, deletes, promotions, and human interaction opens
  are rejected for `pending_delete` or `deleted` conversations
- conversation-local writes, deletes, promotions, and human interaction opens
  are also rejected for archived or close-in-progress conversations
- late human-interaction resolution is rejected for archived or
  close-in-progress conversations
- control reports for stale attempts, stale delivery leases, or superseded
  close requests fail safe with `409 conflict`
- governed MCP invocation failures remain durable audit rows; transport loss is
  not a silent retry-only path
