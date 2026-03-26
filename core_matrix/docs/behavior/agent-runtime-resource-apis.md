# Agent Runtime Resource APIs

## Purpose

Core Matrix exposes machine-facing runtime resource APIs for:

- canonical transcript listing
- conversation-local canonical store reads and writes
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
  `SubagentRun` also resolve by `public_id`

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
  - `message_id`
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
- for `environment` plane work:
  - `target_ref` is the owning `ExecutionEnvironment.public_id`
  - `payload.execution_environment_id` carries the same durable owner identity
  - the live delivery endpoint is resolved separately from the active
    deployment attached to that environment

### Control Reports

- `agent_poll` leases queued mailbox items to the authenticated deployment
- `execution_started` is the durable acceptance point for
  `execution_assignment`
- `execution_progress`, `execution_complete`, `execution_fail`, and
  `execution_interrupted` are attributed to the accepted holder deployment and
  the active `AgentTaskRun` lease
- `resource_close_acknowledged`, `resource_closed`, and
  `resource_close_failed` update the durable close fields on closable runtime
  resources
- environment-owned close reports are only accepted from deployments attached
  to the owning execution environment
- `deployment_health_report` refreshes deployment health plus
  `control_activity_state`
- duplicate control reports are idempotent by `message_id`
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
  `CanonicalStores::Set`
- `conversation_variables_delete` writes one conversation-local tombstone
  through `CanonicalStores::DeleteKey`
- `conversation_variables_promote` reads the current conversation-local value
  and writes a new workspace canonical-variable history row through
  `Variables::PromoteToWorkspace`

### Contract Rules

- conversation-local runtime state is backed by the canonical store, not by
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
- conversation-variable payloads do not expose canonical-store row ids or
  canonical-variable row ids
- writes, deletes, and promotion are rejected once a conversation is no longer
  retained

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
  longer retained or no longer active
- both checks are enforced from fresh locked conversation and workflow/request
  state rather than trusting a stale caller-side object snapshot

## Public Contract Rules

- runtime method IDs stay stable `snake_case` protocol identifiers
- route names stay resource-oriented and do not redefine the method IDs
- payload fields such as `workspace_id`, `conversation_id`, `turn_id`,
  `workflow_run_id`, `workflow_node_id`, `agent_task_run_id`, and
  `resource_id` carry `public_id` values
- raw internal bigint ids are never accepted as fallback resource lookups
- capability snapshots still expose `protocol_methods` separately from
  `tool_catalog`
- capability endpoints also expose:
  - `agent_plane`
  - `environment_plane`
  - `effective_tool_catalog`
- `effective_tool_catalog` applies environment-first tool precedence for
  ordinary tool names and keeps reserved `core_matrix__*` tools outside that
  collision domain
- `target_ref` is the durable owner reference, not a promise that the same
  deployment will remain the delivery endpoint across rotation

## Failure Modes

- unknown public ids fail lookup before any read or mutation runs
- raw bigint identifiers fail as missing resources at these boundaries
- transcript cursors that are not present in the visible projection are invalid
- oversized or illegal canonical-store writes fail through the underlying
  canonical-store validations
- conversation-local writes, deletes, promotions, and human interaction opens
  are rejected for `pending_delete` or `deleted` conversations
- human interaction opens and late human-interaction resolution are rejected for
  archived conversations
- control reports for stale attempts, stale delivery leases, or superseded
  close requests fail safe with `409 conflict`
