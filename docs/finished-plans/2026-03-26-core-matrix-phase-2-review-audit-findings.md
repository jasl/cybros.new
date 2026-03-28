# Core Matrix Review Audit Findings

## Scope

- Refresh date: `2026-03-27`
- Refresh baseline: post-fix state after `docs: describe lineage provenance hardening`
  (`b36e3ae`)
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
- The follow-up regressions found after that hardening pass were resolved by:
  - `7fba2a1 fix: align anchors with effective transcript history`
  - `1f9dd79 fix: protect output anchor source inputs`
  - `2d41c91 fix: fail closed on malformed output provenance`
  - `f809c23 docs: describe anchor lineage regression hardening`
- Post-fix contract state:
  - child-conversation anchors are validated against parent durable transcript
    history, including inherited visible rows and parent-local historical
    variants, and invalid durable anchors fail loudly at replay time
  - output variants carry `source_input_message` provenance, fork-point
    protection covers output-anchor source inputs, and selection/rerun paths
    stay within one lineage
  - rollback now rejects non-quiescent suffixes through
    `Conversations::ValidateTimelineSuffixSupersession` backed by the shared
    `Conversations::WorkBarrierQuery`
- Post-fix verification and grep rescans are recorded in the final execution
  pass for this follow-up batch

## Latest Post-Fix Audit Result

- Post-fix audit baseline:
  - `f809c23 docs: describe anchor lineage regression hardening`
- Full verification evidence:
  - `bin/brakeman --no-pager` -> `0 warnings`
  - `bin/bundler-audit` -> `No vulnerabilities found`
  - `bin/rubocop -f github` -> exit `0`
  - `bun run lint:js` -> exit `0`
  - `bin/rails db:test:prepare test` -> `535 runs, 2680 assertions, 0 failures, 0 errors, 0 skips`
  - `bin/rails db:test:prepare test:system` -> `0 runs, 0 failures, 0 errors`
- Reverse-pass grep confirmations:
  - child-conversation creators still route through
    `Conversations::ValidateHistoricalAnchor`
  - branch-prefix imports now validate against the same anchor family instead
    of a local direct-parent-only rule
  - no output rewrite path silently falls back from missing
    `source_input_message` to `selected_input_message`
  - the only production output writer remains `Turns::CreateOutputVariant`
- Additional regression surfaced during full verification:
  - `ExternalFenixPairingFlowTest` still encoded an obsolete expectation that
    manual retry could rebind paused work onto a rotated deployment created in
    a different execution environment, and that new workflow creation could
    still schedule on a superseded deployment
  - the test was updated to match the already-landed runtime-binding contract:
    paused work is created before rotation, and retry targets a rotated
    deployment in the same bound execution environment
- Outcome:
  - this post-fix audit pass did not confirm any new concrete production defect
    in the re-audited anchor, fork-point, provenance, or adjacent
    runtime-binding families
  - stop condition met for this review loop iteration

## Latest Refresh Findings

### Must Fix

1. `ValidateHistoricalAnchor` is now stricter than the actual transcript
   lineage model, so descendants can no longer anchor to inherited messages
   that are still valid in the parent transcript.
   - Why it matters: child conversations inherit transcript through
     `parent_conversation` recursion, not only through parent-owned rows.
     Tightening anchor validation to `anchor_message.conversation_id == parent.id`
     means a branch can display an inherited ancestor message in its transcript
     projection, but `CreateCheckpoint` or `CreateBranch` from that branch now
     rejects the same message as an anchor. This regresses legitimate
     checkpointing and descendant branch flows on inherited history.
   - Evidence:
     - `app/services/conversations/validate_historical_anchor.rb`
     - `app/models/conversation.rb`
     - `test/services/messages/update_visibility_test.rb`
     - `test/integration/transcript_visibility_attachment_flow_test.rb`
   - Reproduction:
     - `RAILS_ENV=test bin/rails db:drop db:create db:schema:load >/dev/null && bin/rails test test/services/messages/update_visibility_test.rb test/integration/transcript_visibility_attachment_flow_test.rb`
     - current result: `2 errors`, both failing inside
       `Conversations::CreateCheckpoint.call(... historical_anchor_message_id: message.id)`
       with `Historical anchor message must belong to the parent conversation history`
   - Reasoning basis: `Conversation#transcript_projection_includes?` and
     `Conversation#inherited_transcript_projection_messages` still model parent
     transcript lineage in terms of inherited messages, but the validator now
     only accepts parent-owned rows. The write contract and the projection
     contract have diverged.
   - Recommended action: validate anchors against the parent conversation's
     effective transcript lineage, not only `message.conversation_id == parent.id`,
     while still rejecting arbitrary foreign rows.

2. Output-anchored child lineage still does not protect the anchor's implicit
   `source_input_message` as a fork-point dependency.
   - Why it matters: output-anchor replay now reconstructs
     `[source_input_message, anchor_output]`, but fork-point protection still
     only recognizes the direct anchor row. That lets callers hide or rewrite
     the source-input half of an output-anchored pair, producing orphaned
     output-only transcript projections in the parent and descendants.
   - Evidence:
     - `app/models/conversation.rb`
     - `app/models/message.rb`
     - `app/services/messages/update_visibility.rb`
     - `app/services/turns/edit_tail_input.rb`
     - `test/services/messages/update_visibility_test.rb`
     - `test/services/turns/edit_tail_input_test.rb`
     - `test/integration/transcript_visibility_attachment_flow_test.rb`
   - Reproduction:
     - after resetting `core_matrix_test`, create a branch anchored to an output
       variant and call
       `Messages::UpdateVisibility.call(conversation: root, message: source_input, hidden: true)`
     - current observed result:
       `{overlay_id: 1, root_projection: ["Output"], branch_projection: ["Output"]}`
     - similarly, `Turns::EditTailInput.call(...)` still succeeds on the same
       source input after the child branch already anchors to the output
   - Reasoning basis: `Message#fork_point?` only checks whether
     `historical_anchor_message_id == message.id`. It does not treat
     `source_input_message` of an anchored output as protected lineage, even
     though descendant transcript replay now depends on it.
   - Recommended action: promote output-anchor source inputs into the same
     fork-point protection family used by direct anchor messages, and extend the
     visibility/edit tests to cover output-anchor lineage.

3. In-place `RerunOutput` and `RetryOutput` still silently repair malformed
   output provenance instead of failing closed.
   - Why it matters: the new provenance contract is explicit everywhere else,
     but these two paths still use
     `message.source_input_message || turn.selected_input_message`. A malformed
     or legacy output row with blank provenance therefore does not surface as a
     contract violation; the rewrite path silently re-pairs it to the current
     selected input and writes a fresh output variant.
   - Evidence:
     - `app/services/turns/rerun_output.rb`
     - `app/services/turns/retry_output.rb`
     - `test/services/turns/rerun_output_test.rb`
     - `test/services/turns/retry_output_test.rb`
     - `test/integration/turn_history_rewrite_flow_test.rb`
   - Reproduction:
     - after resetting `core_matrix_test`, corrupt the selected output with
       `output.update_columns(source_input_message_id: nil)` and bypass the turn
       backstop with `turn.update_columns(...)`
     - then call `Turns::RerunOutput.call(...)`
     - current observed result:
       `{old_output_source_input: nil, new_output: "Rerun", new_output_source_input: "Input"}`
   - Reasoning basis: branch rerun already fails closed on missing provenance,
     but in-place rerun and retry still keep a compatibility fallback. That is
     inconsistent with the explicit-lineage hardening just introduced.
   - Recommended action: remove the fallback and reject retry/rerun when the
     target output does not carry persisted source-input provenance.

## Latest Refresh Cross-check Summary

- Global signal notes:
  - the newest regressions concentrate in the lineage/provenance seams added by
    `937311d`, `dbce5f2`, and `b3cb2bf`
  - `ValidateHistoricalAnchor` is now the highest-yield hotspot because its
    write-time contract no longer matches transcript replay semantics
  - fork-point protection remains direct-anchor-only even though output-anchor
    replay now depends on a two-message pair
- Reverse-pass confirmations:
  - `RAILS_ENV=test bin/rails db:drop db:create db:schema:load >/dev/null && bin/rails test test/services/messages/update_visibility_test.rb test/integration/transcript_visibility_attachment_flow_test.rb`
    currently returns `2 errors`, confirming the inherited-anchor regression is
    already visible in existing test suites
  - the existing rewrite and visibility suites still do not cover output-anchor
    source-input protection or malformed-provenance fail-closed behavior

## Findings

### Must Fix

1. `Conversations::RollbackToTurn` still tears down later history by changing
   only `Turn.lifecycle_state`, without closing or canceling the later turns'
   active workflow/runtime graph.
   - Why it matters: rollback now passes the shared timeline-mutation fence, but
     once it is allowed to run it only does
     `later_turn.update!(lifecycle_state: "canceled")`. If any later turn owns
     an active `WorkflowRun`, `AgentTaskRun`, `HumanInteractionRequest`,
     `ProcessRun`, or `SubagentSession`, those resources remain live on a canceled
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
