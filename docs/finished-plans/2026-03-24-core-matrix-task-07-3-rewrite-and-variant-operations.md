# Core Matrix Task 07.3: Build Rewrite And Variant Operations

Part of `Core Matrix Kernel Milestone 3: Conversation And Runtime`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/finished-plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/finished-plans/2026-03-24-core-matrix-kernel-milestone-3-conversation-and-runtime.md`

Load this file as the detailed execution unit for Task 07.3. Treat Task Group 07 and the milestone file as ordering indexes, not as the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the consulted slice and the retained conclusion, invariant, or intentional difference in this task document or another local document updated by the same execution unit
- when this task updates behavior docs, checklist docs, or other local docs, carry that conclusion into those docs instead of leaving only a bare reference path
- keep reference paths as index pointers only; restate the relevant behavior locally so this task remains understandable if the reference later drifts

---

**Files:**
- Create: `core_matrix/app/services/conversations/rollback_to_turn.rb`
- Create: `core_matrix/app/services/turns/edit_tail_input.rb`
- Create: `core_matrix/app/services/turns/retry_output.rb`
- Create: `core_matrix/app/services/turns/rerun_output.rb`
- Create: `core_matrix/app/services/turns/select_output_variant.rb`
- Create: `core_matrix/test/services/conversations/rollback_to_turn_test.rb`
- Create: `core_matrix/test/services/turns/edit_tail_input_test.rb`
- Create: `core_matrix/test/services/turns/retry_output_test.rb`
- Create: `core_matrix/test/services/turns/rerun_output_test.rb`
- Create: `core_matrix/test/services/turns/select_output_variant_test.rb`
- Create: `core_matrix/test/integration/turn_history_rewrite_flow_test.rb`
- Modify: `core_matrix/app/models/turn.rb`
- Modify: `core_matrix/app/models/message.rb`

**Step 1: Write failing service and integration tests**

Cover at least:

- tail input edit creating a new selected input variant without historical row mutation
- retry versus rerun semantics for assistant output variants
- variant selection legality for tail versus non-tail assistant output
- historical user-message editing resolving through rollback or fork semantics rather than in-place mutation
- rerunning a non-tail finished assistant output auto-branching before execution

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/services/conversations/rollback_to_turn_test.rb test/services/turns/edit_tail_input_test.rb test/services/turns/retry_output_test.rb test/services/turns/rerun_output_test.rb test/services/turns/select_output_variant_test.rb test/integration/turn_history_rewrite_flow_test.rb
```

Expected:

- missing service or model-behavior failures

**Step 3: Implement rewrite and variant behavior**

Rules:

- selected tail user input edits must create a new input variant and reset dependent output state
- historical user-message editing must resolve through rollback or fork semantics, never direct row mutation
- retry must target failed or unfinished assistant output and create a new output variant in the same turn
- rerun must target finished assistant output; non-tail rerun must auto-branch before execution
- selecting a different output variant is tail-only in the current timeline and must reject queued or in-flight variants
- keep transcript history append-only

**Step 4: Run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails test test/services/conversations/rollback_to_turn_test.rb test/services/turns/edit_tail_input_test.rb test/services/turns/retry_output_test.rb test/services/turns/rerun_output_test.rb test/services/turns/select_output_variant_test.rb test/integration/turn_history_rewrite_flow_test.rb
```

Expected:

- targeted tests pass

**Step 5: Commit**

```bash
git -C .. add core_matrix/app/models/turn.rb core_matrix/app/models/message.rb core_matrix/app/services/conversations/rollback_to_turn.rb core_matrix/app/services/turns core_matrix/test/services core_matrix/test/integration
git -C .. commit -m "feat: add turn rewrite and variant operations"
```

## Stop Point

Stop after rollback, tail edit, retry, rerun, and output-variant selection pass their tests.

Do not implement these items in this task:

- transcript support tables from Task 08
- workflow scheduling or context assembly from Task 09
- any human-facing history UI

## Completion Record

- status:
  completed on `2026-03-24`
- actual landed scope:
  - added `Conversations::RollbackToTurn`
  - added `Turns::EditTailInput`, `RetryOutput`, `RerunOutput`, and
    `SelectOutputVariant`
  - extended `Turn` with active-timeline tail detection used by rewrite
    legality checks
  - added `core_matrix/docs/behavior/turn-rewrite-and-variant-operations.md`
  - added targeted service and integration coverage for rollback, tail edit,
    retry, rerun, and output-variant legality
- plan alignment notes:
  - transcript rows remained append-only; services only added new variants or
    moved selected pointers
  - historical input editing required rollback semantics instead of in-place row
    mutation
  - non-current completed output reruns auto-branched before replaying work
- verification evidence:
  - `cd core_matrix && bin/rails test test/services/conversations/rollback_to_turn_test.rb test/services/turns/edit_tail_input_test.rb test/services/turns/retry_output_test.rb test/services/turns/rerun_output_test.rb test/services/turns/select_output_variant_test.rb test/integration/turn_history_rewrite_flow_test.rb`
    passed with `9 runs, 30 assertions, 0 failures, 0 errors`
- checklist notes:
  - no manual checklist delta was retained for this task because the landed
    behavior is legality and mutation-state infrastructure covered by automated
    tests
- retained findings:
  - active-timeline tail detection needs to ignore later canceled turns so
    rollback can legitimately restore an earlier turn as the editable tail
  - rerun legality depends on both timeline position and whether the target
    output is still the selected current variant
  - append-only history is easier to preserve when rewrite services only add new
    variant rows and move selected pointers
- carry-forward notes:
  - Task Group 08 transcript-support work should treat these variant rows as the
    immutable transcript substrate, adding overlays and attachments around them
    rather than changing rewrite semantics
  - later workflow and UI work should reuse the same legality boundaries instead
    of inventing separate history-mutation rules per surface
