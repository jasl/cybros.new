# Core Matrix Phase 2 Design: Anchor Lineage And Provenance Regression Hardening

Use this design document before starting the Milestone C follow-up batch that
repairs the latest lineage-contract regressions found after the provenance and
supersession hardening pass.

Read together with:

1. `AGENTS.md`
2. `docs/plans/README.md`
3. `docs/plans/2026-03-26-core-matrix-phase-2-plan-agent-loop-execution.md`
4. `docs/plans/2026-03-26-core-matrix-phase-2-milestone-c-runtime-pairing-and-control.md`
5. `docs/plans/2026-03-27-core-matrix-phase-2-lineage-provenance-and-supersession-hardening-design.md`
6. `docs/plans/2026-03-27-core-matrix-phase-2-plan-lineage-provenance-and-supersession-hardening.md`
7. `core_matrix/docs/plans/2026-03-26-core-matrix-review-audit-findings.md`

## Purpose

The previous follow-up correctly introduced stricter contracts for:

- child-conversation historical anchors
- output-to-input provenance on transcript rows
- rollback suffix quiescence

But the latest audit found that those contracts still drift at three edges:

- write-side historical-anchor validation is narrower than transcript replay
- fork-point protection still treats output-anchored lineage as a one-row anchor
- in-place output rewrite paths still silently repair broken provenance instead
  of failing closed

This batch is a regression-hardening follow-up, not a new architecture branch.
The goal is to finish the same lineage contract end to end so write-time
validation, replay, mutation guards, and fail-closed behavior all share one
semantic model.

## Problem Statement

The current codebase still allows three kinds of lineage drift:

1. anchor-membership drift
   - `ValidateHistoricalAnchor` only accepts rows owned directly by the parent
     conversation even though transcript replay still treats inherited ancestor
     messages as part of the effective parent history
2. fork-point dependency drift
   - output-anchor replay reconstructs
     `[source_input_message, anchor_output_message]`, but direct mutation guards
     still only protect the output anchor row itself
3. provenance fallback drift
   - branch rerun fails closed on missing provenance, but in-place rerun and
     retry still repair malformed output rows by falling back to the turn's
     current selected input

All three are the same class of bug: the lineage contract was made explicit in
one layer, but sibling layers still use older, narrower assumptions.

## Decisions

### 1. Historical Anchors Are Valid Against Effective Parent Transcript History

`Conversations::ValidateHistoricalAnchor` must validate against the parent
conversation's effective transcript lineage, not only rows whose
`conversation_id == parent.id`.

That means:

- inherited messages that are still visible in the parent's transcript remain
  valid anchors
- arbitrary foreign rows remain invalid
- output anchors remain valid only when replay can recover their
  `source_input_message`

The contract becomes:

- write-side validation and read-side transcript replay both operate on the same
  effective-history model
- thread, branch, and checkpoint do not invent separate anchor semantics

### 2. Output-Anchored Source Inputs Are Fork-Point Dependencies

An output-anchored child conversation depends on two rows:

- the anchor output
- the anchor output's `source_input_message`

Therefore fork-point protection must promote the source input into the same
protected family as the direct anchor row.

That protection should be shared rather than copied piecemeal. The simplest
path is to teach `Message#fork_point?` to answer true for either:

- a message directly referenced as `historical_anchor_message_id`
- an input message that is the `source_input_message` of a message referenced as
  a historical anchor

Once that contract is widened, existing callers such as:

- `Messages::UpdateVisibility`
- `Turns::EditTailInput`
- any future fork-point guard

inherit the stricter behavior automatically.

### 3. Missing Output Provenance Must Fail Closed Everywhere

The new explicit provenance contract is only coherent if every rewrite path uses
the same failure mode.

Therefore:

- `Turns::RetryOutput` must reject a target output whose
  `source_input_message` is missing
- in-place `Turns::RerunOutput` must reject the same condition
- no output rewrite path may fall back to `turn.selected_input_message`

This is a deliberate breaking change for malformed legacy or corrupted rows.
The application should surface the contract violation instead of fabricating a
new lineage.

### 4. Future Lineage Work Must Reuse Shared Helpers Instead Of Reinterpreting The Contract

After this follow-up, the shared lineage families should be:

- `Conversations::ValidateHistoricalAnchor` for anchor legitimacy
- `Message#fork_point?` for anchor and anchor-dependent mutation protection
- output provenance on `messages.source_input_message_id`
- fail-closed rewrite services for any output replay path

Any future code that:

- creates child conversations from existing transcript state
- protects transcript rows from rewrite/hide operations
- reruns or retries historical output variants

must reuse one of those shared families instead of adding a new local notion of
"valid anchor", "protected fork point", or "acceptable provenance fallback".

## Current Implementation Adjustments

### `Conversations::ValidateHistoricalAnchor`

Required adjustment:

- validate against `parent.transcript_projection_includes?(message)` or an
  equivalent effective-history check
- keep the existing same-installation requirement
- still reject output anchors whose `source_input_message` cannot be replayed

### `Conversation#inherited_transcript_projection_messages`

Required adjustment:

- keep failing loudly for invalid persisted anchors
- accept inherited anchors that are part of the parent's effective transcript
- stop requiring `anchor_message.conversation_id == parent_conversation_id`

### `Message#fork_point?`

Required adjustment:

- treat source inputs of output-anchored descendants as protected fork points
- keep existing direct-anchor protection intact

### `Messages::UpdateVisibility`

Required adjustment:

- no new local anchor logic
- continue delegating protection to `message.fork_point?`
- gain the stricter output-anchor behavior automatically through the shared
  helper

### `Turns::EditTailInput`

Required adjustment:

- no new local anchor logic
- continue delegating protection to `selected_input_message.fork_point?`
- reject edits to source inputs that are required by output-anchored descendants

### `Turns::RetryOutput` And `Turns::RerunOutput`

Required adjustment:

- remove the compatibility fallback to `turn.selected_input_message`
- raise validation errors when the target output lacks persisted source-input
  provenance
- keep branch rerun on the same strict contract as in-place rerun and retry

## Testing Strategy

This batch should be implemented with TDD and verified in four layers:

1. targeted regression tests for the three reported failures
2. neighboring service and integration tests for lineage, visibility, and
   rewrite flows
3. full `core_matrix` verification after the targeted suites are green, because
   the user explicitly wants this batch treated as a regression fix
4. one more review-audit pass after the code lands; continue looping only until:
   - no new concrete defect is found, or
   - the next issue is architectural enough to require discussion before code

## Acceptance Criteria

This follow-up is complete only when all of the following are true:

- branch, checkpoint, and thread can anchor to any message that is truly present
  in the parent's effective transcript history
- visibility and tail-input rewrite guards reject mutations to source inputs
  required by output-anchored descendants
- retry and both rerun modes all fail closed on missing output provenance
- existing lineage and replay docs are updated to reflect the stricter contract
- full `core_matrix` verification completes successfully after the targeted
  regression suites pass
- one fresh audit pass runs after the fix batch and either finds nothing new or
  identifies an architectural discussion point explicitly
