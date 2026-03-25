# Turn Entry And Selector State

## Purpose

Task 07.2 adds the first turn and transcript-bearing message foundation for
Core Matrix. It also persists conversation-level override and interactive
selector state without implementing selector resolution or fallback yet.

## Conversation Selector And Override Behavior

- `Conversation` persists interactive selector state in two user-visible modes:
  - `auto`
  - `explicit_candidate`
- `auto` means the conversation stores no explicit provider or model pin.
- `explicit_candidate` stores one exact `provider_handle/model_ref` pair and
  validates that pair against the provider catalog.
- `Conversation` also persists:
  - `override_payload`
  - `override_last_schema_fingerprint`
  - `override_reconciliation_report`
  - `override_updated_at`
- Override persistence is execution state, not unsent draft state.
- `Conversations::UpdateOverride` updates override state and interactive
  selector state together.

## Turn Behavior

- `Turn` belongs to a conversation, installation, and pinned agent deployment.
- Turn state is explicit and supports:
  - `queued`
  - `active`
  - terminal states such as `completed`, `failed`, and `canceled`
- Turn origin is structured and persisted through:
  - `origin_kind`
  - `origin_payload`
  - `source_ref_type`
  - `source_ref_id`
  - `idempotency_key`
  - `external_event_key`
- Supported v1 origin kinds are:
  - `manual_user`
  - `automation_schedule`
  - `automation_webhook`
  - `system_internal`
- Turn rows freeze:
  - pinned deployment fingerprint
  - resolved config snapshot
  - resolved model-selection snapshot
- Turn sequence is unique within one conversation.
- Turn-sequence allocation is serialized at the conversation boundary so
  concurrent turn writers keep a monotonic append-only order without leaking
  duplicate-key races to callers.

## Message Behavior

- `Message` is reserved for transcript-bearing records only.
- v1 uses STI with two allowed persisted subclasses:
  - `UserMessage`
  - `AgentMessage`
- `UserMessage` is constrained to `role = user` and `slot = input`.
- `AgentMessage` is constrained to `role = agent` and `slot = output`.
- Message variants are append-only within a turn and slot, keyed by
  `variant_index`.
- Variant-index allocation is serialized at the turn boundary so concurrent
  input or output rewrites keep unique append-only ordering within the slot.
- Turn rows store explicit selected input and output pointers rather than
  inferring the active transcript path from the newest message row.

## Entry And Steering Behavior

- `Turns::StartUserTurn` creates an active manual-user turn plus an initial
  selected `UserMessage`.
- manual-user turns persist `source_ref_type = "User"` with the owning user's
  `public_id` in `source_ref_id`
- Ordinary user-turn entry rejects automation-purpose conversations.
- `Turns::StartAutomationTurn` creates an active automation-origin turn without
  requiring a transcript-bearing `UserMessage`.
- deployment bootstrap reuses `Turns::StartAutomationTurn` with
  `origin_kind = "system_internal"` so system-owned recovery and bootstrap work
  still uses the same durable turn substrate as other automation flows.
- deployment bootstrap persists `source_ref_type = "AgentDeployment"` with the
  deployment `public_id` in `source_ref_id`
- `Turns::QueueFollowUp` creates a queued manual-user turn only when the
  conversation already has active or queued work.
- `Turns::SteerCurrentInput` creates a new selected input variant on the same
  active turn and moves the turn's selected-input pointer.
- Steering is limited to pre-output state in this task; if an output pointer is
  already selected, the in-place steering path is rejected.

## Invariants

- conversation selector persistence remains separate from selector resolution
  and entitlement fallback
- override payload persistence remains separate from unsent client draft state
- automation-origin turns may exist without a transcript-bearing `UserMessage`
- queued follow-up only exists when there is already active work to follow
- selected transcript pointers remain explicit turn-owned state

## Failure Modes

- duplicate turn sequences inside one conversation are rejected
- invalid selector modes or explicit candidates outside the provider catalog are
  rejected
- base `Message` rows that are not transcript-bearing subclasses are rejected
- invalid role or slot combinations on `UserMessage` and `AgentMessage` are
  rejected
- ordinary user-turn entry into automation conversations is rejected
- follow-up queueing without active work is rejected

## Reference Sanity Check

The retained conclusion from the local design and model-role-resolution docs is
narrow: user-visible selector persistence must stay simple and explicit while
resolved model snapshots freeze on the turn.

This task keeps that boundary by persisting only conversation selector input and
turn snapshot fields, leaving candidate expansion, fallback, and entitlement
resolution to later Milestone 3 work.
