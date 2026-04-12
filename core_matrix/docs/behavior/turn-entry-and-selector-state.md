# Turn Entry And Selector State

## Purpose

Task 07.2 adds the first turn and transcript-bearing message foundation for
Core Matrix. It also persists conversation-level override and interactive
selector state without implementing selector resolution or fallback yet.

The later execution-snapshot unification batch keeps that selector
boundary intact while explicitly splitting config persistence from runtime
execution-snapshot persistence on the turn row.

## Conversation Selector And Override Behavior

- `Conversation` persists interactive selector state in two user-visible modes:
  - `auto`
  - `explicit_candidate`
- `auto` means the conversation stores no explicit provider or model pin
- `explicit_candidate` stores one exact `provider_handle/model_ref` pair and
  requires that pair to be present
- `Conversation` model validation only enforces selector-shape rules:
  - `auto` must leave provider and model fields blank
  - `explicit_candidate` must provide both fields together
- provider and model membership in the catalog is enforced at the application
  write boundary through `Conversations::UpdateOverride`, not by the model
  itself
- `Conversation` also persists:
  - `override_payload`
  - `override_last_schema_fingerprint`
  - `override_reconciliation_report`
  - `override_updated_at`
- override persistence is execution state, not unsent draft state
- `Conversations::UpdateOverride` updates override state and interactive
  selector state together
- `Conversations::UpdateOverride` is also the catalog-validation boundary for
  explicit candidate selector updates
- override updates now use the same live conversation mutation contract as turn
  entry:
  - `deletion_state = retained`
  - `lifecycle_state = active`
  - no unfinished close operation
- archived, pending-delete, and close-in-progress conversations therefore
  reject override and selector changes uniformly

## Turn Behavior

- `Turn` belongs to a conversation, installation, pinned
  `AgentDefinitionVersion`, required `ConversationExecutionEpoch`, optional
  `ExecutionRuntime`, and optional `ExecutionRuntimeVersion`
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
  - feature policy snapshot row
  - pinned agent-definition fingerprint
  - resolved config snapshot row
  - execution contract row
  - resolved model-selection snapshot row
- the frozen turn feature-policy snapshot contains:
  - `enabled_feature_ids`
  - `during_generation_input_policy`
- `resolved_config_snapshot` stores only the resolved config payload for the
  turn
- `execution_contract` stores the runtime-facing frozen execution contract and
  is read through `Turn#execution_snapshot`
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
- execution continuity is conversation-scoped through
  `Conversation.current_execution_epoch` plus the cached
  `Conversation.current_execution_runtime`
- root conversation creation seeds the current execution runtime from the
  workspace default, falling back to the agent default unless an explicit
  initial runtime override is supplied
- when a conversation still has no turn history, an explicit first-turn runtime
  override may retarget the current execution epoch before the first turn is
  frozen
- follow-up turns always freeze execution identity from the conversation current
  execution epoch rather than re-deriving continuity from previous-turn runtime
- ordinary end-user follow-up message APIs must not switch the execution
  runtime; conversation runtime handoff is deferred to a future dedicated flow
  instead of piggybacking on message creation
- agent discovery and agent-home visibility are separate from launchability;
  the launchability check happens when a conversation is started, not when an
  agent is merely listed or viewed
- manual-user turns persist `source_ref_type = "User"` with the owning user's
  `public_id` in `source_ref_id`
- ordinary user-turn entry rejects automation-purpose conversations
- `Turns::StartAutomationTurn` creates an active automation-origin turn without
  requiring a transcript-bearing `UserMessage`
- agent definition version bootstrap reuses `Turns::StartAutomationTurn` with
  `origin_kind = "system_internal"` so system-owned recovery and bootstrap work
  still uses the same durable turn substrate as other automation flows
- agent definition version bootstrap persists
  `source_ref_type = "AgentDefinitionVersion"` with the agent definition
  version `public_id` in `source_ref_id`
- `Turns::QueueFollowUp` creates a queued manual-user turn only when the
  conversation already has active or queued work
- queued follow-up turns freeze a fresh turn-level feature-policy snapshot at
  creation time, so later follow-up work is auditable against the policy that
  existed when the queued turn was appended
- `Turns::SteerCurrentInput` creates a new selected input variant on the same
  active turn and moves the turn's selected-input pointer
- steering is limited to pre-output state in this task; if an output pointer is
  already selected, the in-place steering path is rejected
- steer requests may include the expected active-turn `public_id`; when
  present, the kernel rejects the request unless it still matches the locked
  active turn
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
- once the turn has crossed a transcript side-effect boundary, steering uses
  the turn's frozen `during_generation_input_policy` rather than the current
  live conversation setting
- later conversation policy edits therefore affect newly created turns, but do
  not retroactively rewrite the active turn's during-generation behavior
- paused turns still accept steering because the turn remains active and
  resumable; that steering becomes the input carried into the next same-turn
  resume attempt and therefore bypasses the live during-generation queue or
  restart policy that applies only to still-running work

## Invariants

- conversation selector persistence remains separate from selector resolution
  and entitlement fallback
- override payload persistence remains separate from unsent client draft state
- turn-owned config persistence remains separate from runtime-facing execution
  snapshot persistence
- turn-owned feature-policy snapshots freeze execution meaning for in-flight
  work even if the conversation policy later changes
- automation-origin turns may exist without a transcript-bearing `UserMessage`
- queued follow-up only exists when there is already active work to follow
- selected transcript pointers remain explicit turn-owned state
- follow-up execution continuity is taken from the conversation current epoch,
  not from historical turn lookup
- execution-runtime identity may advance to newer versions for the same runtime
  id, but user-facing follow-up message APIs do not change the conversation to
  a different runtime id

## Failure Modes

- duplicate turn sequences inside one conversation are rejected
- invalid selector modes are rejected by `Conversation` shape validation
- explicit candidates outside the provider catalog are rejected by
  `Conversations::UpdateOverride`
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
