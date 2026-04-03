# Conversation Diagnostics And Usage Review

## Goal

Add a conversation-local diagnostics surface inside `core_matrix` so internal
review can evaluate agent work quality and usage cost without exporting raw
runtime tables. The first implementation should favor correctness and durable
readability over aggressive live optimization.

This work must also verify that the existing token accounting is correct at the
conversation, turn, and attributed-user levels.

## Non-Goals

- no cost tuning or prompt optimization
- no compatibility layer for alternate diagnostics payloads
- no bigint ids at external or agent-facing boundaries
- no automatic agent-written review report in this pass

## Principles

- `UsageEvent` remains the authoritative detailed usage source
- `UsageRollup` remains provider-window reporting, not conversation diagnostics
- diagnostics should be `turn-first`, then rolled up to conversation
- the first pass may use on-demand canonical recompute for one conversation and
  persist the derived snapshots
- agent analysis should consume deterministic diagnostics snapshots instead of
  raw runtime tables

## Deliverables

1. Durable read models

- `TurnDiagnosticsSnapshot`
- `ConversationDiagnosticsSnapshot`

2. Canonical recompute services

- recompute one turn snapshot from durable runtime facts
- recompute one conversation snapshot by refreshing its turn snapshots and then
  rolling them up

3. Agent-facing read APIs

- `conversation_diagnostics_show`
- `conversation_diagnostics_turns`

4. Token-accounting verification

- explicit tests that provider-backed usage is attributed to the workspace
  owner user
- explicit tests that diagnostics totals match authoritative `UsageEvent` facts
- explicit tests that attributed-user totals are exposed separately from raw
  conversation totals

5. One fresh 2048 acceptance rerun and a follow-up evaluation of whether the
   collected diagnostics are sufficient for internal analysis

## Snapshot Scope

### Turn Snapshot

Store the durable diagnostics row keyed by `turn_id`.

Typed top-level fields:

- `installation_id`
- `conversation_id`
- `turn_id`
- `lifecycle_state`
- `usage_event_count`
- `input_tokens_total`
- `output_tokens_total`
- `estimated_cost_total`
- `attributed_user_usage_event_count`
- `attributed_user_input_tokens_total`
- `attributed_user_output_tokens_total`
- `attributed_user_estimated_cost_total`
- `provider_round_count`
- `tool_call_count`
- `tool_failure_count`
- `command_run_count`
- `command_failure_count`
- `process_run_count`
- `process_failure_count`
- `subagent_session_count`
- `input_variant_count`
- `output_variant_count`
- `resume_attempt_count`
- `retry_attempt_count`

Derived JSON metadata:

- `provider_usage_breakdown`
- `workflow_node_type_counts`
- `tool_breakdown`
- `command_classification_counts`
- `subagent_status_counts`
- `latency_summary`
- `pause_state`
- `evidence_refs`

### Conversation Snapshot

Store the durable diagnostics row keyed by `conversation_id`.

Typed top-level fields:

- `installation_id`
- `conversation_id`
- `lifecycle_state`
- `turn_count`
- `active_turn_count`
- `completed_turn_count`
- `failed_turn_count`
- `canceled_turn_count`
- `usage_event_count`
- `input_tokens_total`
- `output_tokens_total`
- `estimated_cost_total`
- `attributed_user_usage_event_count`
- `attributed_user_input_tokens_total`
- `attributed_user_output_tokens_total`
- `attributed_user_estimated_cost_total`
- `provider_round_count`
- `tool_call_count`
- `tool_failure_count`
- `command_run_count`
- `command_failure_count`
- `process_run_count`
- `process_failure_count`
- `subagent_session_count`
- `input_variant_count`
- `output_variant_count`
- `resume_attempt_count`
- `retry_attempt_count`
- `most_expensive_turn_id`
- `most_rounds_turn_id`

Derived JSON metadata:

- aggregated provider breakdown
- aggregated workflow node type counts
- aggregated tool breakdown
- aggregated command classification counts
- aggregated subagent status counts
- outlier refs

## Source Mapping

### Usage and Cost

Use `UsageEvent` as truth.

- totals: all events for the turn or conversation
- attributed-user totals: only events whose `user_id` equals the owning
  workspace user
- provider rounds: `UsageEvent` count for `operation_kind = text_generation`
- latency summary: derive from `UsageEvent.latency_ms`

### Workflow and Agent Activity

- node counts and node-type breakdown: `WorkflowNode`
- tool counts and breakdown: `ToolInvocation` joined with `ToolDefinition`
- command counts and classification: `CommandRun`
- process counts: `ProcessRun`
- subagent counts and status breakdown: `SubagentSession`
- steer proxy: extra input variants on the same turn
- output retry proxy: extra output variants on the same turn
- resume attempts: `AgentTaskRun.task_payload.delivery_kind = turn_resume`
- retry attempts: `AgentTaskRun.task_payload.delivery_kind in (step_retry,
  paused_retry)`
- pause state: current `WorkflowRun` wait-state snapshot, not inferred history

## API Shape

### `conversation_diagnostics_show`

Input:

- `conversation_id`

Response:

- `method_id`
- `conversation_id`
- `snapshot`

### `conversation_diagnostics_turns`

Input:

- `conversation_id`

Response:

- `method_id`
- `conversation_id`
- `items`

All ids in responses must be public ids.

## Implementation Strategy

### Stage 1

- add snapshot tables and models
- add missing `usage_events` indexes for `conversation_id` and `turn_id`
- implement canonical recompute services
- add request endpoints that refresh and then return snapshots

### Stage 2

- use the new diagnostics endpoints in agent-side analysis workflows
- rerun the 2048 acceptance flow
- assess whether the collected diagnostics are sufficient without additional
  heuristic fields

## Testing Strategy

Write tests first.

1. model tests for new snapshot invariants
2. service tests for turn recompute
3. service tests for conversation rollup
4. request tests for both diagnostics endpoints
5. integration test proving provider-backed usage is attributed to the
   workspace owner and exposed through diagnostics

## Acceptance Criteria

- one conversation request returns durable diagnostics without exposing bigint
  ids
- turn diagnostics let a reviewer identify the most expensive and most
  round-heavy turns without exporting raw tables
- attributed-user token totals are visible and match authoritative usage rows
- a fresh 2048 run produces enough diagnostics to support a qualitative review
  of cost and execution quality
