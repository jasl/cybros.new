# Turn Entry And Selector State

## Purpose

Task 07.2 adds the first turn and transcript-bearing message foundation for
Core Matrix. It also persists conversation-level override and interactive
selector state without implementing selector resolution or fallback yet.

The later Phase 2 execution-snapshot unification batch keeps that selector
boundary intact while explicitly splitting config persistence from runtime
execution-snapshot persistence on the turn row.

## Conversation Selector And Override Behavior

- `Conversation` persists interactive selector state in two user-visible modes:
  - `auto`
  - `explicit_candidate`
- `auto` means the conversation stores no explicit provider or model pin
- `explicit_candidate` stores one exact `provider_handle/model_ref` pair and
  validates that pair against the provider catalog
- `Conversation` also persists:
  - `override_payload`
  - `override_last_schema_fingerprint`
  - `override_reconciliation_report`
  - `override_updated_at`
- override persistence is execution state, not unsent draft state
- `Conversations::UpdateOverride` updates override state and interactive
  selector state together
- override updates now use the same live conversation mutation contract as turn
  entry:
  - `deletion_state = retained`
  - `lifecycle_state = active`
  - no unfinished close operation
- archived, pending-delete, and close-in-progress conversations therefore
  reject override and selector changes uniformly

## Turn Behavior

- `Turn` belongs to a conversation, installation, and pinned agent deployment
- turn state is explicit and supports:
  - `queued`
  - `active`
  - terminal states such as `completed`, `failed`, and `canceled`
- turn origin is structured and persisted through:
  - `origin_kind`
  - `origin_payload`
  - `source_ref_type`
  - `source_ref_id`
  - `idempotency_key`
  - `external_event_key`
- supported v1 origin kinds are:
  - `manual_user`
  - `automation_schedule`
  - `automation_webhook`
  - `system_internal`
- turn rows freeze:
  - pinned deployment fingerprint
  - resolved config snapshot row
  - execution snapshot payload row
  - resolved model-selection snapshot row
- `resolved_config_snapshot` stores only the resolved config payload for the
  turn
- `execution_snapshot_payload` stores the runtime-facing frozen execution
  contract and is read through `Turn#execution_snapshot`
- turn sequence is unique within one conversation
- turn-sequence allocation is serialized at the conversation boundary so
  concurrent turn writers keep a monotonic append-only order without leaking
  duplicate-key races to callers

## Message Behavior

- `Message` is reserved for transcript-bearing records only
- v1 uses STI with two allowed persisted subclasses:
  - `UserMessage`
  - `AgentMessage`
- `UserMessage` is constrained to `role = user` and `slot = input`
- `AgentMessage` is constrained to `role = agent` and `slot = output`
- message variants are append-only within a turn and slot, keyed by
  `variant_index`
- variant-index allocation is serialized at the turn boundary so concurrent
  input or output rewrites keep unique append-only ordering within the slot
- turn rows store explicit selected input and output pointers rather than
  inferring the active transcript path from the newest message row

## Entry And Steering Behavior

- `Turns::StartUserTurn` creates an active manual-user turn plus an initial
  selected `UserMessage`
- manual-user turns persist `source_ref_type = "User"` with the owning user's
  `public_id` in `source_ref_id`
- ordinary user-turn entry rejects automation-purpose conversations
- `Turns::StartAutomationTurn` creates an active automation-origin turn without
  requiring a transcript-bearing `UserMessage`
- deployment bootstrap reuses `Turns::StartAutomationTurn` with
  `origin_kind = "system_internal"` so system-owned recovery and bootstrap work
  still uses the same durable turn substrate as other automation flows
- deployment bootstrap persists `source_ref_type = "AgentDeployment"` with the
  deployment `public_id` in `source_ref_id`
- `Turns::QueueFollowUp` creates a queued manual-user turn only when the
  conversation already has active or queued work
- `Turns::SteerCurrentInput` creates a new selected input variant on the same
  active turn and moves the turn's selected-input pointer
- steering is limited to pre-output state in this task; if an output pointer is
  already selected, the in-place steering path is rejected
- user-turn entry, automation-turn entry, queued follow-up, and override
  updates all re-check the live conversation mutation contract after acquiring
  the conversation row lock
- this prevents concurrent archive or deletion requests from opening new turn
  work against a conversation that became non-active mid-flight
- `Turns::SteerCurrentInput` now uses the shared timeline-mutation contract:
  - the owning conversation must still pass the live mutation contract
  - the target turn is reloaded under lock
  - `turn_interrupted` fences reject in-place steering and
    during-generation follow-up policy entry

## Invariants

- conversation selector persistence remains separate from selector resolution
  and entitlement fallback
- override payload persistence remains separate from unsent client draft state
- turn-owned config persistence remains separate from runtime-facing execution
  snapshot persistence
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
- archived conversations reject new user turns, automation turns, and queued
  follow-up turns even if the archive transition wins a race after caller-side
  prechecks
- close-in-progress or pending-delete conversations reject override updates and
  current-turn steering for the same reason

## Reference Sanity Check

The retained conclusion from the local design and model-role-resolution docs is
narrow: user-visible selector persistence must stay simple and explicit while
resolved model snapshots freeze on the turn.

This task keeps that boundary by persisting conversation selector input, turn
config snapshot state, and turn execution snapshot state separately, leaving
candidate expansion, fallback, and entitlement resolution to later Milestone 3
work.
