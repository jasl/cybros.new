# Core Matrix Phase 2 Design: Lineage Provenance And Supersession Hardening

Use this design document before starting the Milestone C follow-up batch that
repairs rollback supersession safety, transcript output provenance, and child
conversation historical-anchor validation.

Read together with:

1. `AGENTS.md`
2. `docs/plans/README.md`
3. `docs/plans/2026-03-26-core-matrix-phase-2-plan-agent-loop-execution.md`
4. `docs/plans/2026-03-26-core-matrix-phase-2-milestone-c-runtime-pairing-and-control.md`
5. `docs/plans/2026-03-27-core-matrix-phase-2-close-operation-reconciliation-design.md`
6. `docs/plans/2026-03-27-core-matrix-phase-2-plan-close-operation-reconciliation.md`
7. `docs/plans/2026-03-27-core-matrix-phase-2-runtime-binding-and-rewrite-safety-hardening-design.md`
8. `docs/plans/2026-03-27-core-matrix-phase-2-plan-runtime-binding-and-rewrite-safety-hardening.md`
9. `docs/plans/2026-03-27-core-matrix-phase-2-conversation-mutation-contract-unification-design.md`
10. `docs/plans/2026-03-27-core-matrix-phase-2-plan-conversation-mutation-contract-unification.md`

## Purpose

Milestone C now has explicit live-mutation and timeline-mutation contracts, but
three integrity gaps remain one layer deeper:

- `RollbackToTurn` can cancel later turns without proving their owned runtime
  work is already quiescent
- transcript output variants do not persist which input variant produced them
- child conversation creation still accepts raw historical-anchor ids without
  validating that they point at a real parent transcript message

These are not unrelated bugs. They are the same architectural problem repeated
at different boundaries: durable mutation targets are rewritten while subordinate
runtime state or provenance state remains implicit.

This follow-up hardens those boundaries with one coherent approach:

- shared service-level contracts for supersession and provenance validation
- model-level backstop invariants for durable rows
- no silent fallback when durable lineage is invalid

## Problem Statement

The current code still allows three forms of drift:

1. timeline supersession drift
   - rollback can make later turns disappear from the visible timeline while
     their workflow or agent-owned runtime resources remain live
2. transcript provenance drift
   - output variants can be selected or rerun against whatever input pointer the
     turn currently carries, not the input variant that actually produced the
     output
3. lineage anchor drift
   - branch, checkpoint, and optional thread anchors can persist arbitrary ids
     and rely on read-time fallback instead of validating durable provenance

All three violate the same Phase 2 expectation: once mutation contracts are
explicit, the durable rows they touch must also carry explicit ownership and
historical provenance.

## Decisions

### 1. Superseding Later Turns Requires A Shared Quiescence Contract

Any operation that supersedes a suffix of turns must first prove that the suffix
no longer owns live runtime work.

Phase 2 should add one explicit application service:

- `Conversations::ValidateTimelineSuffixSupersession`

That contract should:

- accept a conversation and target turn
- collect later turns that would be superseded
- reject when any later turn still owns live runtime work, including:
  - `WorkflowRun` in `active` or `waiting`
  - `AgentTaskRun` in `queued` or `running`
  - blocking `HumanInteractionRequest` in `open`
  - `ProcessRun` in `running`
  - `SubagentRun` in `running`

This follow-up intentionally chooses strict rejection instead of embedding a new
interrupt-or-close orchestration path inside rollback.

The architectural split becomes:

- interrupt and close services quiesce runtime work
- rollback rewrites timeline state only after the suffix is already quiescent

### 2. Output Variants Must Carry Input Provenance Explicitly

Phase 2 should stop inferring output lineage from the current turn pointer.

Add durable provenance to transcript rows through:

- `messages.source_input_message_id`

Contract:

- output messages must point to the input message that produced them
- input messages must not carry `source_input_message_id`
- output provenance must stay within one turn

This follow-up should also add one shared output writer:

- `Turns::CreateOutputVariant`

That writer should own:

- output `variant_index` allocation
- creation of the `AgentMessage`
- wiring `source_input_message`

Every output-producing path must use it:

- provider-backed turn execution
- retry output
- rerun output
- future output variant writers

### 3. Turn Selection Must Stay Within One Provenance Lineage

The selected input and selected output on a turn must represent the same
historical lineage.

Therefore:

- when a turn selects an output variant, it must also select that output's
  `source_input_message`
- branch rerun must use the target output's `source_input_message`, not the
  turn's current `selected_input_message`
- a turn with a selected output must reject persistence if
  `selected_output_message.source_input_message_id != selected_input_message_id`

This hardens output selection and replay without deleting old variants. The
variants remain durable history, but they can no longer be paired with the wrong
input lineage.

### 4. Historical Anchor Validation Must Be Shared And Explicit

Phase 2 should add one explicit application service:

- `Conversations::ValidateHistoricalAnchor`

That validator owns the contract for all child-conversation creation paths:

- `CreateBranch`
- `CreateCheckpoint`
- `CreateThread`

Rules:

- branch and checkpoint must provide an anchor
- thread may omit the anchor, but if one is provided it must be valid
- a valid anchor must be a real `Message`
- the anchor must be present in the parent conversation's transcript projection
- the validator should return the resolved anchor message row when one exists

This removes the current split where write paths accept arbitrary ids and
read-time transcript projection silently truncates when the id cannot be found.

### 5. Invalid Durable Lineage Must Fail Loudly

`Conversation#inherited_transcript_projection_messages` should no longer treat a
missing anchor as an empty inherited transcript.

If a persisted conversation carries an invalid historical anchor, read paths
should fail loudly rather than silently hiding parent history.

That is a deliberate breaking change. The codebase should not preserve silent
compatibility for invalid lineage rows created by the older permissive logic.

### 6. Existing Anchor Consistency Rules Should Be Reused, Not Duplicated

`ConversationImport` already enforces `branch_prefix` anchor consistency.
This follow-up should reuse the same mental model earlier in the write path.

`CreateBranch` should therefore stop doing a permissive
`Message.find_by(id:, installation_id:)` lookup. It should instead consume the
resolved anchor returned by the shared validator and create the `branch_prefix`
import from that authoritative message.

### 7. Future Mutation Paths Must Join One Of These Contract Families

After this follow-up, any future path that does one of the following must
explicitly join an existing shared family instead of inventing a new local rule:

- supersedes existing turns
- creates output variants
- selects or replays historical output variants
- creates child conversations from parent transcript lineage

The contract families become:

- `Conversations::WithMutableStateLock` for live conversation mutation
- `Turns::WithTimelineMutationLock` for turn timeline mutation
- `Conversations::ValidateTimelineSuffixSupersession` for suffix supersession
- `Turns::CreateOutputVariant` plus model provenance checks for output lineage
- `Conversations::ValidateHistoricalAnchor` for lineage anchor validation

## Current Implementation Adjustments

### `Conversations::RollbackToTurn`

Current issue:

- it only marks later turns as `canceled`
- it does not prove that later turns' owned runtime work is already quiescent

Required adjustment:

- call the shared suffix-supersession validator before canceling later turns
- keep summary and import pruning after the suffix is proven quiescent
- do not embed a second interrupt/close orchestration path inside rollback

### `Message`

Current issue:

- output rows do not record which input variant produced them

Required adjustment:

- add `source_input_message` association and validations
- enforce same-turn and slot compatibility

### `Turn`

Current issue:

- selected input and selected output can point at different provenances

Required adjustment:

- add a backstop validation that selected output lineage must match selected
  input lineage whenever both are present

### `Turns::SelectOutputVariant`

Current issue:

- it can point the turn at an old output variant without restoring the matching
  input lineage

Required adjustment:

- update both `selected_output_message` and `selected_input_message`
- reject output variants that do not carry valid provenance

### `Turns::RerunOutput`

Current issue:

- branch replay currently uses `turn.selected_input_message.content`

Required adjustment:

- use the target output's persisted source input
- create new output rows through the shared output writer

### `Turns::RetryOutput`

Current issue:

- it creates new output rows locally and does not reuse a shared provenance
  writer

Required adjustment:

- create retried output rows through `Turns::CreateOutputVariant`

### `ProviderExecution::ExecuteTurnStep`

Current issue:

- provider-backed output persistence allocates output variants inline and does
  not persist output-to-input provenance

Required adjustment:

- create output rows through `Turns::CreateOutputVariant`
- attach the turn's current selected input as the source input lineage

### `Conversations::CreateBranch`, `CreateCheckpoint`, And `CreateThread`

Current issue:

- they accept arbitrary historical-anchor ids and validate too little

Required adjustment:

- validate anchors through the shared historical-anchor contract
- branch should create `branch_prefix` import from the resolved anchor
- thread should reject invalid optional anchors instead of persisting them

### `Conversation`

Current issue:

- write-time validation checks only presence for branch and checkpoint anchors
- read-time projection silently falls back to `[]`

Required adjustment:

- add durable anchor-membership validation
- remove silent fallback from inherited transcript projection

## Testing And Verification Strategy

This follow-up must be driven test-first.

### Targeted Red/Green Coverage

Add or update focused tests for:

- rollback rejects later turns with active workflow or other live runtime work
- invalid branch/checkpoint/thread anchors are rejected
- branch/checkpoint/thread with valid parent transcript anchors still work
- output writers persist `source_input_message`
- selecting an old output variant restores the matching input variant
- rerun branch uses the target output's original input lineage
- turn/model validations reject inconsistent output lineage

### Neighboring Regression

Re-run adjacent suites that cover:

- transcript import and conversation structure flows
- provider-backed turn execution
- turn-history rewrite
- conversation close and turn interrupt
- agent recovery and workflow scheduler behavior

### Static Audit Pass

Before claiming completion, grep and confirm:

- every output writer uses `Turns::CreateOutputVariant`
- every child-conversation creator uses `Conversations::ValidateHistoricalAnchor`
- no rollback-like suffix supersession path still mutates later turns without the
  shared validator
- old permissive historical-anchor tests have been replaced by strict
  expectations

## Non-Goals

- redesigning the entire `Conversation` projection model
- introducing a generalized event-sourced transcript engine
- auto-quiescing rollback suffixes by reusing close-operation orchestration
- preserving compatibility for invalid historical anchors or lineage rows
