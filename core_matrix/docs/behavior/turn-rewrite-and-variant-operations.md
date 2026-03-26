# Turn Rewrite And Variant Operations

## Purpose

Task 07.3 adds append-only rewrite and variant-selection behavior on top of the
turn and message foundation from Task 07.2. These operations preserve timeline
history while giving the kernel explicit legality checks for edit, retry, rerun,
rollback, and output-variant selection.

## Rewrite Behavior

- `Conversations::RollbackToTurn` only supersedes later turns after a shared
  suffix-supersession contract proves the later suffix is already quiescent.
- rollback rejects later queued turns, later active turns, active workflow
  runs, queued or running agent tasks, open human interaction, running
  processes or subagents, and active execution leases in the superseded suffix.
- Rollback does not delete later turns or mutate their historical rows in
  place.
- rollback is not a second interrupt or close orchestration path; callers must
  quiesce live later runtime first.
- `Turns::EditTailInput` is tail-only in the active timeline.
- Tail input edit creates a new input variant row on the same turn, moves the
  selected-input pointer, and clears the selected output pointer.
- Historical input editing is not an in-place mutation path; the user must
  first rollback or branch.
- Tail input edit is also blocked when the selected input message is already a
  fork point for a child conversation.

## Output Variant Behavior

- `Turns::RetryOutput` targets a failed or canceled selected output and creates
  a new output variant in the same turn.
- `Turns::RerunOutput` targets a completed output.
- If the completed output is still the selected output on the selected tail
  turn, rerun happens in place by creating a new output variant in the same
  turn.
- If the completed output is historical or otherwise no longer the selected
  tail output, rerun auto-branches first and then replays inside the branch.
- output variants persist `source_input_message` provenance so each output row
  records the input variant that produced it.
- `Turns::SelectOutputVariant` restores both the selected output pointer and
  the matching selected input pointer for that output lineage.
- branch rerun replays the target output's stored source-input content, not the
  turn's current selected input pointer.
- retry, in-place rerun, and branch rerun all fail closed when the target
  output is missing persisted source-input provenance.
- Retry, in-place rerun, and output-variant selection all reject fork-point
  outputs because those operations would rewrite the active path after a child
  conversation already anchored to it.

## Variant And Tail Rules

- Selected input and output pointers remain explicit turn-owned state.
- selected input and selected output must stay within one persisted provenance
  lineage whenever both pointers are present.
- Variant rows remain append-only; services only add new variants and move
  selected pointers.
- Selecting a different output variant is only legal on a completed tail turn
  in the current timeline.
- Selecting a non-tail output variant in the current timeline is rejected.

## Invariants

- transcript history remains append-only
- rewrite legality is evaluated against the current active timeline, not just
  raw sequence order
- non-selected historical output reruns branch instead of mutating the current
  tail in place
- fork-point messages remain stable once a child conversation depends on them
- source inputs required by output-anchored descendants are fork-point messages
  too
- rollback and edit preserve old variants as inspectable history
- old output variants stay durable history without being re-paired to a newer
  input variant

## Failure Modes

- editing a non-tail input without rollback or branch semantics is rejected
- retrying a non-selected or completed output is rejected
- rerunning a non-completed output is rejected
- retry and rerun reject outputs with missing source-input provenance
- selecting an output variant on a non-tail or non-completed turn is rejected

## Reference Sanity Check

The retained conclusion from the local mutation-invariants design is narrow:
rewrite legality must be explicit, tail-aware, and append-only.

This task keeps that contract by implementing rollback, edit, retry, rerun, and
variant selection as pointer moves plus new variant rows, never direct mutation
of historical transcript rows.
