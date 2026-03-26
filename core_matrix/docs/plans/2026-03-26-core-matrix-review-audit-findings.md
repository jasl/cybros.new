# Core Matrix Review Audit Findings

## Scope

- Refresh date: `2026-03-27`
- Refresh baseline: post-fix state after `docs: describe conversation mutation contracts`
  (`2e56996`)
- In scope: Ruby code under `app/`, `lib/`, `config/`, `db/`, and `test/`
- Out of scope: frontend work, compiled assets, and non-Ruby code
- Review goals:
  - identify leftover or transitional development code
  - identify Ruby and Rails philosophy drift
  - identify potential risks in boundaries, lifecycle, callbacks, transactions,
    exception handling, and tests
- Review method:
  - primary pass: runtime and layering review
  - reverse pass: cross-cutting rules and tests
  - no category is considered complete until it has been checked from both
    directions
- Pre-screen targets from the refreshed global scan:
  - large production files:
    - `app/services/agent_control/report.rb`
    - `app/models/conversation.rb`
    - `app/services/workflows/scheduler.rb`
    - `app/services/turns/steer_current_input.rb`
    - `app/services/conversations/rollback_to_turn.rb`
  - high-yield namespaces by volume or signal density:
    - `app/services/conversations`
    - `app/services/workflows`
    - `app/services/turns`
    - `app/services/agent_control`
- targeted follow-up areas:
    - rollback and lineage paths after the shared mutation-contract cleanup
    - turn rewrite helpers that now share the timeline contract but still carry
      older append-only assumptions
    - provenance-bearing fields that still accept raw `bigint` references
      without transcript-membership validation
    - active-resource ownership paths adjacent to turn-history mutation
    - test suites that still encode permissive historical-anchor or rewrite
      behavior from earlier phases

## Resolution Update

- The three `Must Fix` findings from this refresh were resolved by:
  - `937311d fix: validate historical anchors against parent transcript`
  - `dbce5f2 fix: persist transcript output provenance`
  - `b3cb2bf fix: block rollback until later runtime is quiescent`
- Post-fix contract state:
  - child-conversation anchors are validated against parent conversation
    history and invalid durable anchors fail loudly at replay time
  - output variants carry `source_input_message` provenance and selection/rerun
    paths stay within one lineage
  - rollback now rejects non-quiescent suffixes through
    `Conversations::ValidateTimelineSuffixSupersession` backed by the shared
    `Conversations::WorkBarrierQuery`
- Post-fix verification and grep rescans are recorded in the final execution
  pass for this follow-up batch

## Findings

### Must Fix

1. `Conversations::RollbackToTurn` still tears down later history by changing
   only `Turn.lifecycle_state`, without closing or canceling the later turns'
   active workflow/runtime graph.
   - Why it matters: rollback now passes the shared timeline-mutation fence, but
     once it is allowed to run it only does
     `later_turn.update!(lifecycle_state: "canceled")`. If any later turn owns
     an active `WorkflowRun`, `AgentTaskRun`, `HumanInteractionRequest`,
     `ProcessRun`, or `SubagentRun`, those resources remain live on a canceled
     turn. That creates a split-brain runtime state where the visible timeline
     says the turn is gone but scheduler, close, and mailbox logic can still see
     active owned work.
   - Evidence:
     - `app/services/conversations/rollback_to_turn.rb:15-31`
     - `app/models/turn.rb:31-34`
     - `app/models/workflow_run.rb:35-42`
     - `app/services/conversations/request_turn_interrupt.rb:14-23`
     - `test/services/conversations/rollback_to_turn_test.rb:4-131`
   - Reasoning basis: rollback has no equivalent of `RequestTurnInterrupt` or
     any other quiesce path for later turns. It never looks at later turns'
     workflow runs or resources, and `WorkflowRun` has no validation that would
     reject an `active` workflow run whose turn was just marked `canceled`.
     Current tests only cover later turns with no owned runtime work.
   - Recommended action: either reject rollback while later turns still own
     active workflow/runtime resources, or route each later active turn through
     the same interrupt/quiesce contract used by archive/delete before the turn
     row is canceled.

2. Turn output variants still have no provenance link to the input variant that
   produced them, which lets later rewrite flows pair an old output with a new
   selected input.
   - Why it matters: after `Turns::EditTailInput` appends a new input variant,
     old output messages remain on the same turn. `Turns::SelectOutputVariant`
     can later point the turn back at one of those older output rows, and
     `Turns::RerunOutput` branch replay uses
     `turn.selected_input_message.content` rather than the input that actually
     produced the target output. That means transcript state and branch replay
     can silently drift away from the historical output being selected or
     rerun.
   - Evidence:
     - `app/models/message.rb:8-46`
     - `app/services/turns/edit_tail_input.rb:18-35`
     - `app/services/turns/select_output_variant.rb:17-29`
     - `app/services/turns/rerun_output.rb:60-82`
     - `test/integration/turn_history_rewrite_flow_test.rb:46-54`
   - Reasoning basis: `Message` belongs only to `turn`; there is no
     `source_input_message_id`, input-variant index, or similar provenance
     column. `EditTailInput` clears the selected output but keeps old outputs on
     the turn, `SelectOutputVariant` can point back to any output variant on the
     completed tail turn, and non-tail branch reruns copy the current selected
     input content instead of the target output's original input context. The
     existing integration test already performs edit-then-rerun on the same turn
     but never asserts the branch input, so the drift stays invisible.
   - Recommended action: persist output-to-input provenance on transcript rows
     or turn-local variant state, and make output selection and branch rerun
     validate or reconstruct against that provenance instead of the current turn
     pointer.

3. Child-conversation creation still accepts arbitrary
   `historical_anchor_message_id` values without validating that the anchor is a
   real parent transcript message.
   - Why it matters: branch and checkpoint transcript projection depend on the
     anchor to know how much parent history to inherit. Right now the model only
     checks that the field is present, not that it points at a real message row
     in the parent transcript. That allows durable lineage rows with bogus
     provenance and silently truncated inherited transcript state.
   - Evidence:
     - `app/models/conversation.rb:152-155`
     - `app/models/conversation.rb:243-251`
     - `app/services/conversations/create_branch.rb:21-39`
     - `app/services/conversations/create_checkpoint.rb:21-38`
     - `test/services/conversations/create_branch_test.rb:4-27`
     - `test/services/conversations/create_checkpoint_test.rb:4-27`
     - `test/integration/conversation_structure_flow_test.rb:13-21`
     - `docs/behavior/transcript-imports-and-summary-segments.md:18-28`
   - Reasoning basis: `Conversation#inherited_transcript_projection_messages`
     falls back to `[]` when the anchor cannot be found in the inherited
     transcript, and `CreateBranch` only materializes a `branch_prefix` import
     when `Message.find_by(id:, installation_id:)` succeeds. The model and
     services therefore allow `101/202/303`-style raw ids that may not exist or
     may not belong to the parent transcript. Existing service and integration
     tests explicitly expect those arbitrary anchors to succeed.
   - Recommended action: validate branch/checkpoint anchors, and optional thread
     anchors when present, against the parent conversation's transcript
     projection and reject invalid anchors instead of silently creating lineage
     with broken provenance.

## Suggestions

1. `Workflows::CreateForTurn` is currently behaving like an internal
   second-stage writer rather than a confirmed mutation-boundary defect, but its
   contract should stay explicit so future callers do not bypass the shared
   turn-entry and recovery fences.
   - Evidence:
     - `app/services/workflows/create_for_turn.rb:15-42`
     - `app/services/turns/start_user_turn.rb:13-50`
     - `app/services/workflows/manual_retry.rb:34-50`
   - Why it matters: the current app-level call paths enter through
     `StartUserTurn`, `StartAutomationTurn`, or `ManualRetry`, so mutable-state
     and runtime-binding checks happen before workflow creation. That makes
     `CreateForTurn` a trusted materialization primitive today, not the source of
     an active bug. The risk is architectural drift: a future caller may treat
     it like a public entry point and skip those higher-level contracts.
   - Suggested action: keep `CreateForTurn` documented and tested as an
     internal-only second-stage writer, and make app-level tests continue to
     assert that new workflow creation flows enter through fenced turn-entry or
     recovery services instead of calling it directly from unfenced mutation
     paths.

## Watch List

1. `AgentControl::Report` remains a large multi-role orchestrator.
   - `app/services/agent_control/report.rb` still owns mailbox validation,
     receipt idempotency, execution state transitions, retry-gate updates,
     resource-close transitions, lease handling, and close-operation
     reconciliation.

2. `Conversation` is still carrying multiple abstractions in one Active Record
   model.
   - `app/models/conversation.rb` still mixes projection assembly, lineage
     traversal, runtime-contract access, deletion-state validation, and
     interactive selector rules.

## Cross-check Summary

- Global signal scan notes:
  - the shared `retained-only`, `live-mutation`, and `timeline-mutation`
    contracts are now present and the old `RetentionGuard` and
    `ValidateRewriteTarget` helpers are gone
  - no new unfenced live-mutation or timeline-mutation entry point showed up in
    the latest pattern scan
  - the strongest remaining signals moved one layer deeper:
    - resource ownership gaps inside rollback
    - missing provenance between input and output variants
    - missing validation on historical-anchor identifiers
- Reverse-pass confirmations:
  - `bin/rails test test/services/conversations/create_branch_test.rb test/services/conversations/create_checkpoint_test.rb test/services/conversations/create_thread_test.rb test/services/conversations/rollback_to_turn_test.rb test/services/turns/rerun_output_test.rb test/services/turns/select_output_variant_test.rb test/integration/conversation_structure_flow_test.rb test/integration/turn_history_rewrite_flow_test.rb`
    currently passes as
    `23 runs, 91 assertions, 0 failures, 0 errors, 0 skips`
  - those passing tests confirm the current permissive behavior:
    - arbitrary historical anchor ids are still accepted
    - rollback only exercises later turns without active owned runtime work
    - edit-then-rerun flow does not assert the rerun branch's selected input
      against the historical output context
    - output-variant selection is only exercised inside one input lineage

## Completeness Check

- Goal coverage:
  - leftover-code review refreshed
  - Ruby and Rails philosophy review refreshed
  - potential-risk review refreshed
- Scope coverage:
  - re-reviewed the highest-yield mutation services under
    `app/services/turns`, `app/services/workflows`, and
    `app/services/conversations`
  - cross-checked the corresponding behavior docs and targeted test suites
- Double-check coverage:
  - findings were identified from code and contract drift first
  - findings were then checked against existing tests, sibling services, and
    contrasting guard paths
- Artifact completeness:
  - the current evidence-backed conclusions are written in this document
  - blocking defects are separated from suggestions and watch-list items
- Residual limitations:
  - this refresh used targeted Rails test suites and code inspection, not the
    full project test suite
  - no live-runtime manual validation was performed in this round
