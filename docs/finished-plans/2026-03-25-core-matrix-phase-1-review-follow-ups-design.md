# Core Matrix Phase 1 Review Follow-Ups Design

## Status

- approved on `2026-03-25`
- scope owner: `core_matrix`
- source: Phase 1 review of the landed implementation against
  `docs/finished-plans` and the corresponding behavior docs

## Goal

Resolve every issue found during the Phase 1 review without quietly expanding
the meaning of already-finished plans.

The review findings split into two buckets:

1. implementation drift from the intent already captured in finished plans
2. newly discovered hardening work that was not explicitly designed in the
   original Phase 1 task set

The first bucket is corrected directly and documented back into the finished
records. The second bucket gets a new active execution plan before any code
changes are made.

## Reviewed Findings

### Batch 1: Direct corrections to finished-plan alignment

These issues are treated as implementation mistakes relative to the existing
finished plans and behavior docs, so they should be fixed directly:

1. descendant conversations can currently hide or exclude fork-point anchor
   messages through `ConversationMessageVisibility` overlays even though the
   finished Task 08.2 record says anchored history must not drift after
   branching
2. workflow context tests contain order-sensitive assertions that make review
   verification noisy without changing product behavior

### Batch 2: Review follow-up hardening

These issues are real and should be resolved, but they were not fully designed
as part of the finished Phase 1 scope. They require a new active plan:

1. attachment materialization buffers the entire source blob in memory before
   re-attaching it
2. transcript and context projections perform repeated per-message visibility
   lookups across lineage depth, creating avoidable query amplification
3. append-only ordinals and version counters are allocated with `MAX(...) + 1`
   and can fail under concurrent writers

## Batch 1: Finished-Plan Corrections

### Objectives

- enforce fork-point immutability across every descendant projection that
  depends on the anchored message, not only in the source message's native
  conversation
- make context-assembly verification deterministic by expressing set equality
  without accidental ordering assumptions
- revise the affected finished-plan completion records so they describe the
  corrected invariant instead of preserving a misleading review note

### Planned Code Scope

- tighten `Messages::UpdateVisibility` so descendant branch and checkpoint
  overlays cannot hide or exclude fork-point anchors
- add or update focused tests around descendant visibility attempts and
  fork-point protection
- fix order-insensitive assertions in the workflow context test coverage without
  changing runtime behavior

### Documentation Scope

- revise
  `docs/finished-plans/2026-03-24-core-matrix-phase-1-task-08-1-visibility-and-attachments.md`
- revise
  `docs/finished-plans/2026-03-24-core-matrix-phase-1-task-08-2-imports-and-summary-segments.md`
- revise
  `docs/finished-plans/2026-03-24-core-matrix-phase-1-task-09-4-context-assembly-and-execution-snapshot.md`
- revise behavior docs:
  - `core_matrix/docs/behavior/transcript-visibility-and-attachments.md`
  - `core_matrix/docs/behavior/transcript-imports-and-summary-segments.md`
  - `core_matrix/docs/behavior/workflow-context-assembly-and-execution-snapshot.md`

### Acceptance Criteria

- a message that acts as a fork-point anchor for a branch or checkpoint cannot
  be hidden or excluded from context inside any descendant conversation
  projection that depends on that anchor
- fork-point protection remains compatible with the existing append-only
  transcript and branch-prefix import model
- workflow context tests no longer depend on incidental record ordering where
  the behavior under test is set membership
- finished-plan records explicitly note that the review found and corrected a
  finished-scope implementation drift

## Batch 2: New Follow-Up Plan

### Purpose

Capture all remaining review findings in one active plan so nothing discovered
during review is lost, while still keeping the Phase 1 finished records
historical and bounded.

### Follow-Up Workstreams

#### 1. Attachment materialization streaming

- replace eager blob download and `StringIO` wrapping with a streaming copy path
- keep ancestry and attachment-row semantics unchanged
- make the acceptance rule behavioral: materialization must no longer require
  buffering the full blob payload in Ruby memory before attach

#### 2. Transcript and context projection batching

- keep the current local-projection architecture
- reduce repeated `ConversationMessageVisibility.exists?` checks across message
  lists and lineage depth
- define acceptance in terms of unchanged projection behavior plus a tighter
  query shape for branch, checkpoint, transcript-support, and context-assembly
  reads

#### 3. Append-only sequence and version allocation hardening

- replace `MAX(...) + 1` allocators in append-only event, process, turn,
  workflow mutation, and capability snapshot version paths with a
  concurrency-safe allocation strategy
- acceptance must cover concurrent writers and prove the system does not fail
  with random `RecordNotUnique` exceptions during normal append traffic

### Documentation Boundary

- Batch 2 is a new active execution plan in `docs/plans`
- Batch 2 does not get rewritten into the original Phase 1 task scope
- if later fixes need historical traceability, finished records may reference
  the follow-up plan as post-review hardening rather than pretending the work
  was already complete on first landing

## Verification And Execution Boundaries

### Batch 1 verification

- add or tighten focused tests for descendant fork-point visibility protection
- fix the flaky assertion patterns in the workflow context tests
- rerun targeted tests for the affected transcript and workflow surfaces
- rerun the standard `core_matrix` verification suite serially:
  - `bin/brakeman --no-pager`
  - `bin/bundler-audit`
  - `bin/rubocop -f github`
  - `bun run lint:js`
  - `bin/rails db:test:prepare test`
  - `bin/rails db:test:prepare test:system`
- keep `test` and `test:system` serial because both prepare the same test
  database

### Batch 2 verification requirements

- attachment streaming changes need targeted service tests that prove ancestry
  and attach behavior still match the current contract
- projection batching changes need targeted behavioral coverage for root,
  thread, branch, and checkpoint projections plus context assembly consumers
- concurrency hardening needs targeted tests around allocator behavior and
  failure semantics under competing writers, including deployment capability
  version allocation
- after Batch 2 implementation, rerun the normal `core_matrix` verification
  suite before closing the follow-up plan

## Delivery Shape

1. execute Batch 1 as direct fixes and revise the affected finished-plan and
   behavior documents in the same change set
2. create one active implementation plan for Batch 2 follow-up hardening
3. execute that follow-up plan separately so the historical Phase 1 records
   remain reviewable and the newly discovered hardening work stays explicit
