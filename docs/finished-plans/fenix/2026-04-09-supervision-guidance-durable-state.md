# Supervision Guidance Durable State

## Problem

`supervision_guidance` and `supervision_status_refresh` now have complete
delivery/report contracts, but completed guidance does not yet influence the
next `prepare_round`.

Current gap:

- `ConversationControlRequest` is durable and auditable
- `Fenix` acknowledges `supervision_guidance`
- `core_matrix` persists the terminal mailbox outcome
- `ProviderExecution::BuildWorkContextView` does not project delivered guidance
  into the next round
- subagent guidance is created from the owner conversation, but the next
  `prepare_round` happens on the child conversation

## Goals

- Completed supervision guidance becomes durable input to the next relevant
  `prepare_round`
- Conversation guidance applies to the target conversation
- Subagent guidance applies to the child conversation that owns the targeted
  `SubagentConnection`
- Guidance projection is read-only and derived from audit records
- The prompt surface in `Fenix` makes the newest guidance salient

## Non-Goals

- Mutating the transcript to inject supervisor messages
- Adding a new runtime-only state store in `Fenix`
- Marking guidance requests as "consumed" after a round
- Changing status-refresh semantics beyond their existing acknowledgment flow
- Projecting `request_status_refresh` into durable guidance state

## Durable Source Of Truth

Delivered guidance remains sourced from `ConversationControlRequest` rows with:

- `request_kind` in:
  - `send_guidance_to_active_agent`
  - `send_guidance_to_subagent`
- `lifecycle_state = completed`
- `result_payload.response_payload.control_outcome.outcome_kind =
  guidance_acknowledged`

No extra table is introduced in v1. The read model is projected from these
auditable records.

## Projection Semantics

Add a read-model service:

- `ConversationControl::BuildGuidanceProjection`

Inputs:

- `conversation`

Outputs:

- `nil` when no delivered guidance applies
- otherwise a hash under `work_context_view["supervisor_guidance"]`

Returned shape:

```json
{
  "guidance_scope": "conversation",
  "latest_guidance": {
    "conversation_control_request_id": "ccr_123",
    "request_kind": "send_guidance_to_active_agent",
    "target_kind": "conversation",
    "target_public_id": "conv_123",
    "content": "Stop and summarize your current status.",
    "source_conversation_id": "conv_123",
    "delivered_at": "2026-04-09T12:00:00Z"
  },
  "recent_guidance": [
    {
      "conversation_control_request_id": "ccr_122",
      "request_kind": "send_guidance_to_active_agent",
      "target_kind": "conversation",
      "target_public_id": "conv_123",
      "content": "Work only on the benchmark failure.",
      "source_conversation_id": "conv_123",
      "delivered_at": "2026-04-09T11:58:00Z"
    },
    {
      "conversation_control_request_id": "ccr_123",
      "request_kind": "send_guidance_to_active_agent",
      "target_kind": "conversation",
      "target_public_id": "conv_123",
      "content": "Stop and summarize your current status.",
      "source_conversation_id": "conv_123",
      "delivered_at": "2026-04-09T12:00:00Z"
    }
  ]
}
```

Rules:

- `latest_guidance` is the newest delivered guidance for this runtime target
- `recent_guidance` is the last 5 delivered guidance items for this runtime
  target, ordered oldest to newest
- the newest item is authoritative; older items are short audit context only
- no `consumed` flag is stored or mutated

## Target Routing

### Conversation Guidance

For a normal conversation runtime:

- select completed `send_guidance_to_active_agent` requests where
  `target_kind = conversation`
- select completed `send_guidance_to_active_agent` requests where
  `target_conversation_id = conversation.id`

### Subagent Guidance

For a child conversation runtime:

- if `conversation.subagent_connection` is present, treat the child as a subagent
  runtime target
- select completed `send_guidance_to_subagent` requests where
  `target_kind = subagent_connection`
- select completed `send_guidance_to_subagent` requests where
  `target_public_id = conversation.subagent_connection.public_id`
- set `guidance_scope = subagent`
- set `source_conversation_id = conversation.subagent_connection.owner_conversation.public_id`

This keeps the durable source in the owner conversation audit trail while
projecting the guidance into the child conversation's next round.

## Injection Seam

- `ConversationControl::BuildGuidanceProjection` feeds
  `ProviderExecution::BuildWorkContextView`
- `BuildWorkContextView` adds `supervisor_guidance` only when present
- `ProviderExecution::PrepareAgentRound` continues passing the full
  `work_context_view`
- `Fenix::Prompts::Assembler` gets a dedicated `Supervisor Guidance` section
  derived from `work_context_view["supervisor_guidance"]`

## Prompt Semantics In Fenix

The prompt should not rely on the operator noticing raw JSON inside durable
state.

Add a dedicated section:

- `## Supervisor Guidance`

Rendering rules:

- when empty: `No active supervisor guidance.`
- when present:
  - show the latest guidance first
  - include whether it targets the conversation or a subagent
  - include the recent guidance list as short bullet-like lines

The existing `CoreMatrix Durable State` JSON block stays intact for auditability.

## Query Shape And Indexes

The projection will query by completed guidance request state. Add indexes to
support that shape:

- `conversation_control_requests` on
  `(installation_id, request_kind, lifecycle_state, target_conversation_id, completed_at)`
- `conversation_control_requests` on
  `(installation_id, request_kind, lifecycle_state, target_public_id, completed_at)`

Descending time is not required for correctness; application code can still
apply `order(completed_at: :desc, id: :desc).limit(5)`.

## Tests

CoreMatrix:

- `ConversationControl::BuildGuidanceProjectionTest`
  - returns latest + recent conversation guidance
  - routes subagent guidance from owner conversation to child conversation
  - ignores failed or non-guidance control requests
- `ProviderExecution::BuildWorkContextViewTest`
  - includes `supervisor_guidance` when guidance exists
- `ProviderExecution::PrepareAgentRoundTest`
  - carries projected guidance through `round_context.work_context_view`

Fenix:

- `Fenix::Prompts::AssemblerTest`
  - renders a dedicated `Supervisor Guidance` section
  - keeps durable JSON intact
- `Fenix::Application::BuildRoundInstructionsTest`
  - includes the rendered guidance section without inferring it from transcript

## Rollout Notes

- This is a contract completion, not a compatibility layer
- No fallback path is added for missing guidance projection
- If a later product decision needs stronger guidance lifecycle semantics, it
  should introduce a dedicated domain object instead of mutating audit rows
