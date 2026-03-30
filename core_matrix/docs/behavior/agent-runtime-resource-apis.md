# Agent Runtime Resource APIs

## Purpose

Core Matrix exposes machine-facing runtime resource APIs for:

- canonical transcript listing
- conversation-local lineage store reads and writes
- workspace-scoped canonical variable reads and writes
- workflow-owned human interaction request creation
- mailbox-driven execution delivery and close control

The resource plane stays a thin HTTP boundary over authenticated lookups,
query objects, and kernel-owned services. The control plane uses the same
machine credential authentication but carries durable mailbox items through
`poll`, `WebSocket`, and response piggyback delivery.

## Status

This document describes the current landed runtime resource plane and the first
Phase 2 mailbox control surface. Transcript, variable, and human-interaction
APIs remain short HTTP resource-style boundaries. Mailbox delivery and
resource-close reporting now use dedicated control endpoints plus the optional
realtime stream described here. Broader turn-interrupt and conversation-close
orchestration are still defined in:

- [2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-26-core-matrix-conversation-close-and-mailbox-control-protocol-design.md)

## Authentication And Lookup Scope

- all runtime-resource endpoints require machine credential authentication
- lookups are scoped to the deployment installation
- lookups resolve resources by `public_id`, never raw internal `bigint` ids
- conversations are resolved only while `deletion_state = retained`
- deleted or pending-delete conversations are therefore hidden from
  agent-facing transcript and variable endpoints
- control-plane resources such as `AgentTaskRun`, `ProcessRun`, and
  `SubagentSession` also resolve by `public_id`
- capability refresh also exposes governed tool metadata by `public_id`; the
  agent-facing boundary does not expose internal numeric ids for
  `ToolDefinition` or `ToolImplementation`

## Control Plane

### Delivery Paths

- `POST /agent_api/control/poll` is the durable fallback transport for pending
  mailbox items
- `POST /agent_api/control/report` carries control-plane reports back into the
  kernel
- `/cable` may stream the same mailbox-item envelope over `AgentControlChannel`
- poll responses, realtime broadcasts, and report-response piggyback all use
  the same mailbox item envelope:
  - `item_id`
  - `item_type`
  - `runtime_plane`
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
- `runtime_plane` is explicit:
  - `agent` for agent-loop work and agent-owned close control
  - `environment` for `ExecutionEnvironment`-owned resources such as
    `ProcessRun`
- mailbox rows persist routing semantics as durable columns:
  - `runtime_plane`
  - `target_kind`
  - `target_ref`
  - optional `target_execution_environment_id` for environment-plane work
- `payload` now carries only family-specific request data; routing identity is
  not reconstructed from payload shape
- for `agent` plane close work, the durable owner fallback is resolved from the
  resource type rather than the current delivery lease:
  - `AgentTaskRun` falls back to its own `agent_installation`
  - `SubagentSession` falls back to the logical `agent_installation`
    associated with its owner conversation, or its origin turn when that turn
    exists
- for `environment` plane work:
  - `target_ref` is the owning `ExecutionEnvironment.public_id`
  - `target_execution_environment_id` stores the owning
    `ExecutionEnvironment` foreign key on the mailbox row
  - if no active deployment currently holds the resource lease, the mailbox row
    still records the owning turn deployment's logical `agent_installation` as
    the durable installation target
  - the live delivery endpoint is resolved separately through the shared
    `ResolveTargetRuntime` contract instead of SQL payload routing

### Control Reports

- `agent_poll` leases queued mailbox items to the authenticated deployment
- `execution_assignment` delivery remains valid only while the backing
  `AgentTaskRun` is still `queued`; interrupt-canceled leased assignments are
  marked `canceled` and have their lease cleared before later polls
- `ResolveTargetRuntime`, `Poll`, and `PublishPending` now share the same
  durable mailbox routing contract for both agent-plane and environment-plane
  delivery
- `AgentControl::Report` is a thin ingress shell for:
  - deployment activity touch
  - duplicate detection
  - receipt creation
  - stale-to-HTTP translation
  - piggyback poll assembly
- `execution_started` is the durable acceptance point for
  `execution_assignment`
- `execution_progress`, `execution_complete`, `execution_fail`, and
  `execution_interrupted` are attributed to the accepted holder deployment and
  the active `AgentTaskRun` lease
- execution report lifecycle handling now lives in
  `HandleExecutionReport` and freshness checks live in
  `ValidateExecutionReportFreshness`
- `process_output` is the live output report for running detached
  `ProcessRun(kind = "background_service")` resources:
  - it is accepted only for `ProcessRun`
  - the reporting deployment must belong to the owning execution environment
  - when a process lease is active, the report also heartbeats that lease
  - payload carries `output_chunks`, each with transport-only stdout/stderr
    text
  - the chunks are broadcast on the temporary conversation runtime stream and
    are not persisted on the `ProcessRun` row
- short-lived command output does not use `process_output`; it is reported
  through execution progress as `runtime.tool_invocation.output`
- the terminal `ToolInvocation.response_payload` for short-lived commands should
  keep structured summary data only, such as exit status and streamed byte
  counts, rather than raw stdout/stderr bodies
- `resource_close_acknowledged`, `resource_closed`, and
  `resource_close_failed` update the durable close fields on closable runtime
  resources
- close report lifecycle handling now lives in `HandleCloseReport` and
  freshness checks live in `ValidateCloseReportFreshness`
- close reports are attributed to the deployment recorded in
  `leased_to_agent_deployment` for that mailbox item; once one deployment has
  accepted the close request, sibling deployments in the same installation must
  be treated as stale reporters for that request
- terminal close reports for `AgentTaskRun`, `ProcessRun`, and
  `SubagentSession` must also re-enter
  `Conversations::ReconcileCloseOperation` through the resource's owning
  conversation. `SubagentSession` close reports also refresh the child
  conversation because the session itself owns that transcript container.
- terminal process close reports may also carry `output_chunks`; those chunks
  are broadcast before the terminal `runtime.process_run.*` event and are not
  persisted durably
- environment-owned close reports are only accepted from deployments attached
  to the owning execution environment
- `deployment_health_report` now routes through `HandleHealthReport` and
  refreshes deployment health plus `control_activity_state`
- duplicate control reports are idempotent by `protocol_message_id`
- stale or superseded reports return `409 conflict` and do not mutate durable
  execution state

### Deployment Activity Facts

- `AgentDeployment.realtime_link_state` records whether the deployment
  currently has a realtime control link
- `AgentDeployment.control_activity_state` records durable control-plane
  freshness separately from realtime connectivity
- valid poll, report, and realtime-open events refresh
  `control_activity_state = "active"`
- realtime disconnect alone only moves `realtime_link_state` to
  `disconnected`; it does not mark the deployment unavailable by itself

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
- workflow wait blockers also use durable identifiers:
  - `WorkflowRun.blocking_resource_id` stores `public_id` values, including
    `AgentDeployment.public_id` for `agent_unavailable`
- raw internal bigint ids are never accepted as fallback resource lookups
- capability snapshots still expose `protocol_methods` separately from
  `tool_catalog`
- capability endpoints also expose:
  - `agent_plane`
  - `environment_plane`
  - `effective_tool_catalog`
  - `governed_effective_tool_catalog`
- those capability sections and the conversation-facing runtime capability
  payload now come from the shared `RuntimeCapabilityContract`
- `effective_tool_catalog` applies environment-first tool precedence for
  ordinary tool names and keeps reserved `core_matrix__*` tools outside that
  collision domain
- `governed_effective_tool_catalog` adds the durable governance identifiers and
  `governance_mode` for the effective tool winner without exposing internal ids
- `target_ref` is the durable owner reference, not a promise that the same
  deployment will remain the delivery endpoint across rotation

## Governed Tool Execution Audit

- `AgentTaskRun` now freezes its visible governed tool set when the task row is
  created
- that freeze produces one `ToolBinding` row per visible logical tool for the
  task attempt
- later tool use is expected to record `ToolInvocation` rows against those
  bindings instead of bypassing the task boundary with source-specific audit
  paths
- the durable binding and invocation rows remain kernel-owned audit state; they
  are not currently separate HTTP resource endpoints
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
