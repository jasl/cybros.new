# Core Matrix Review Audit Findings

## Scope

- Refresh date: `2026-03-27`
- Refresh baseline: post-fix state after `fix: harden runtime binding and wait blocker contracts`
  (`53253d5`)
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
    - turn mutation helpers that still update selected input or output state
    - rollback and timeline rewrite paths adjacent to the newly added rewrite
      guard
    - close and interrupt windows where a turn remains `active` but is already
      fenced
    - conversation-local selector or override writes that still update
      conversation state without a retained/active/close fence
    - conversation-local projection or support writes that still rely on the
      legacy retained-only helper instead of an explicit mutation contract

## Findings

### Must Fix

1. `Turns::SteerCurrentInput` still bypasses retention, close-operation, and
   interrupt fences on the no-side-effect rewrite path.
   - Why it matters: once `Conversations::RequestTurnInterrupt` lands, the turn
     can remain `active` while already fenced by
     `cancellation_reason_kind = "turn_interrupted"`. During that window,
     `SteerCurrentInput` can still append a new selected input variant because
     it only checks `turn.active?`. For delete requests, the conversation is
     already `pending_delete`; for archive/delete close requests, the
     conversation may also already have an unfinished close operation. This lets
     the user mutate a turn after the close fence that earlier rounds were
     explicitly trying to make durable.
   - Evidence:
     - `app/services/turns/steer_current_input.rb:13-39`
     - `app/services/workflows/scheduler.rb:71-109`
     - `app/services/conversations/request_turn_interrupt.rb:41-60`
     - `test/services/turns/steer_current_input_test.rb:4-92`
   - Reasoning basis: `SteerCurrentInput` has no retained/active-conversation or
     close-fence checks and no `turn_interrupted` check. The direct rewrite path
     at lines 23-38 only re-validates `turn.active?` under lock, so a fenced
     turn can still be edited until its lifecycle eventually flips to
     `canceled`. The side-effect-boundary path eventually goes through
     `QueueFollowUp`, which now blocks closing conversations, but the direct
     input rewrite path does not. The current tests only cover happy paths.
   - Recommended action: route `SteerCurrentInput` through the same shared
     rewrite/retention fence used for turn-history mutation, or add a dedicated
     shared guard for mutable current-turn input updates, and add negative tests
     for `pending_delete`, archived/closing, and `turn_interrupted` turns.

2. Remaining turn-history mutation helpers still bypass the shared rewrite
   safety contract.
   - Why it matters: the recent fix only hardened `RetryOutput` and
     `RerunOutput`, but adjacent helpers can still mutate the active timeline or
     prune transcript-support state without checking retained/active/closing or
     interrupt fences. That means archived or superseded conversations can still
     be rewritten through sibling APIs even after the output-specific path was
     secured.
   - Evidence:
     - `app/services/turns/edit_tail_input.rb:12-34`
     - `app/services/turns/select_output_variant.rb:11-22`
     - `app/services/conversations/rollback_to_turn.rb:12-25`
     - `test/services/turns/edit_tail_input_test.rb:4-58`
     - `test/services/turns/select_output_variant_test.rb:4-63`
     - `test/services/conversations/rollback_to_turn_test.rb:4-101`
   - Reasoning basis: `EditTailInput` only checks tail/fork-point shape before
     appending a new selected input and clearing `selected_output_message`.
     `SelectOutputVariant` only checks output-slot, completion, and tail shape
     before changing the selected output pointer. `RollbackToTurn` cancels later
     turns and prunes summary/import support state with no lifecycle or fence
     checks at all. The targeted test suites all pass, but they cover only
     happy-path timeline rules and contain no retained/archive/close/interrupt
     negatives.
   - Recommended action: extend the shared rewrite guard so all history-mutation
     helpers that alter timeline selection or prune transcript-support state
     must call it, then add negative tests for archived, pending-delete,
     closing, and `turn_interrupted` cases across these services.

3. `Conversations::UpdateOverride` can still rewrite selector and override
   state after archive or delete close fences because it bypasses the existing
   retained/active/closing checks entirely.
   - Why it matters: override payload and interactive-selector state are the
     same conversation-local execution inputs that later turn entry and selector
     resolution read. Right now `UpdateOverride` writes them directly on the
     conversation row with no `retained`, `active`, or `closing` check and no
     lock, so a user can still mutate those settings while the conversation is
     being archived or deleted. That recreates the same “late mutation after a
     close fence” class of bug that earlier rounds were already hardening away
     from turn and workflow state.
   - Evidence:
     - `app/services/conversations/update_override.rb:13-27`
     - `docs/behavior/turn-entry-and-selector-state.md:18-24`
     - `test/services/conversations/update_override_test.rb:3-48`
   - Reasoning basis: `UpdateOverride` does a direct `@conversation.update!`
     with no shared lifecycle contract around it. The current tests cover only
     happy-path persistence and do not challenge `pending_delete`, archived, or
     close-in-progress states.
   - Recommended action: treat override persistence as a live conversation
     mutation, fold it into the same shared conversation-mutation contract as
     turn entry and human-interaction writes, and add negative tests for
     `pending_delete`, archived, and closing conversations.

## Suggestions

1. Lineage-creation services may deserve the same archive/close-policy review
   as turn-entry and rewrite helpers.
   - Evidence:
     - `app/services/conversations/create_branch.rb:15-33`
     - `app/services/conversations/create_thread.rb:15-28`
     - `app/services/conversations/create_checkpoint.rb:15-28`
     - `docs/behavior/conversation-structure-and-lineage.md:88-90`
   - Why it matters: deletion is explicitly covered, but archive/close behavior
     for branch/thread/checkpoint creation is still not spelled out the same way
     the turn-entry contract is. I did not treat this as a confirmed defect
     because the current behavior docs stop at non-retained parents, but it is a
     likely future drift point.
   - Suggested action: decide whether archived or closing parents should reject
     lineage creation, then document and test that policy explicitly.

2. The legacy `Conversations::RetentionGuard` now mixes two different product
   contracts.
   - Evidence:
     - `app/services/conversations/retention_guard.rb:1-29`
     - `app/services/canonical_stores/set.rb:1-58`
     - `app/services/workflows/manual_resume.rb:1-103`
     - `app/services/publications/publish_live.rb:1-66`
   - Why it matters: some call sites need only `retained`, while others should
     really require `retained + active + not_closing`. Reusing the same helper
     across both semantics makes future drift likely even when no single call
     site is obviously broken today.
   - Suggested action: replace `RetentionGuard` with explicit shared contracts
     for `retained-only`, `live conversation mutation`, and `turn timeline
     mutation`, then migrate every remaining call site onto one of those
     explicit choices.

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
  - the recent runtime-binding, rewrite, and blocker-id fixes are present and
    the obvious sibling deployment paths (`AutoResumeWorkflows`,
    `StartAutomationTurn`) were already folded into that batch
  - the strongest remaining signal now comes from turn-mutation helpers that
    still write transcript or timeline state but were not folded into the new
    shared rewrite guard
  - `SteerCurrentInput` is the highest-risk entry because it can run while a
    fenced turn is still `active`
  - a broader follow-up scan across conversation-local selector, visibility,
    import, summary, lineage, and canonical-store services surfaced one more
    confirmed unfenced writer: `Conversations::UpdateOverride`
  - after that broader scan, no additional timeline/projection/lineage/settings
    mutation services were found outside the final hardening scope for this
    round
- Reverse-pass confirmations:
  - `bin/rails test test/services/turns/steer_current_input_test.rb test/services/turns/edit_tail_input_test.rb test/services/turns/select_output_variant_test.rb test/services/conversations/rollback_to_turn_test.rb`
    currently passes as
    `9 runs, 30 assertions, 0 failures, 0 errors, 0 skips`
  - those passing tests confirm timeline-shape behavior only; they do not
    challenge retained/archived/closing/`turn_interrupted` state
  - the newly added `ValidateRewriteTarget` guard is only referenced from
    `RetryOutput` and `RerunOutput`, which leaves adjacent history-mutation
    helpers outside the shared contract
  - `test/services/conversations/update_override_test.rb` currently covers only
    happy-path persistence and does not challenge retained/archive/close state

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
  - this refresh used targeted Rails test suites, not the full project test
    suite
  - no `bin/dev` or live-runtime manual validation was performed in this round
