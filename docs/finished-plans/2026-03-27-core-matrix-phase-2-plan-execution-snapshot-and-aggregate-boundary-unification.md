# Core Matrix Phase 2 Execution Snapshot And Aggregate-Boundary Unification Closeout Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Finish the residual cleanup after the landed execution-snapshot / aggregate-boundary unification batch so the current codebase stops carrying stale transitional API, stale owner names, and stale documentation around the old mixed snapshot shape.

**Architecture:** The main unification work is already landed. `TurnExecutionSnapshot`, `Workflows::BuildExecutionSnapshot`, and the `Conversations::*Projection` services are now the active owners. The remaining work is a closeout pass: remove transitional helpers and legacy wrapper vocabulary that survived the rollout, then align active behavior docs and audit artifacts with the current owner boundaries.

**Tech Stack:** Ruby on Rails (`core_matrix`), Active Record, Minitest model/service/query coverage, behavior docs, audit artifacts, grep-based contract verification

---

## Current Baseline

This plan is intentionally re-baselined to the current workspace state as of
`2026-03-28`. The following work is already landed and must not be planned
again as if it were missing:

- `turns.resolved_config_snapshot` and `turns.execution_snapshot_payload` are
  already split persisted row contracts
- `Turn#execution_snapshot` already returns `TurnExecutionSnapshot`
- `Workflows::BuildExecutionSnapshot` already owns persisted execution-snapshot
  assembly
- `Conversation` no longer owns transcript/context projection helper methods
- `Conversations::TranscriptProjection`,
  `Conversations::ContextProjection`, and
  `Conversations::HistoricalAnchorProjection` already exist
- `WorkflowRun`, `Workflows::ExecuteRun`, and
  `ProviderExecution::BuildRequestContext` already consume the explicit
  snapshot contract
- the old `ContextAssembler` files are already gone

## Remaining Problems To Close

The main architecture shift is complete, but several residual issues remain:

- `Turn` still carries transitional legacy-wrapper vocabulary through
  `LEGACY_WRAPPED_EXECUTION_KEY` and `effective_config_snapshot`
- snapshot-related tests still depend on the helper
  `legacy_snapshot_context_key`, which keeps the deleted nested wrapper shape
  alive as test language
- active behavior docs still describe deleted aggregate helper owners:
  - `Conversation#transcript_projection_messages`
  - `Conversation#context_projection_messages`
  - `Conversation#context_projection_attachments`
- active audit artifacts still mention `ContextAssembler` and old helper names
  as if they were current runtime owners, even though the implementation
  update has already landed

## Execution Rules

- Treat this as a closeout and alignment batch, not as a schema migration or a
  second unification implementation.
- Do not recreate or rename `TurnExecutionSnapshot`,
  `Workflows::BuildExecutionSnapshot`, or the extracted projection services.
- Do not reintroduce the old wrapped execution payload shape.
- Finished plans and explicitly historical writeups may retain old names when
  they are describing the past. Active behavior docs and active audit artifacts
  must describe the current owner boundaries.
- Keep any remaining rejection of the legacy wrapped snapshot shape narrow and
  private. Do not keep a public helper surface or test DSL around that old
  shape.
- Final verification is not complete until:
  - no production code depends on `Turn#effective_config_snapshot`
  - no active behavior doc under `core_matrix/docs/behavior` describes
    `Conversation#transcript_projection_messages`,
    `Conversation#context_projection_messages`, or `ContextAssembler` as
    current owners
  - the Round 1 audit and audit register describe the landed owners using the
    current names
- Commit after every task with the suggested message or a tighter equivalent.

## Anticipated File Set

### Modify

- `core_matrix/app/models/turn.rb`
- `core_matrix/app/services/workflows/build_execution_snapshot.rb`
- `core_matrix/test/models/turn_test.rb`
- `core_matrix/test/services/workflows/build_execution_snapshot_test.rb`
- `core_matrix/test/services/workflows/create_for_turn_test.rb`
- `core_matrix/test/test_helper.rb`
- `core_matrix/docs/behavior/transcript-visibility-and-attachments.md`
- `core_matrix/docs/behavior/publication-and-live-projection.md`
- `core_matrix/docs/behavior/workflow-context-assembly-and-execution-snapshot.md`
  only if the closeout pass reveals stale owner wording
- `docs/reports/core-matrix-architecture-health-audit-register.md`
- `docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md`

## Task 1: Remove Residual Transitional Snapshot API And Legacy Wrapper Vocabulary

**Files:**

- Modify: `core_matrix/app/models/turn.rb`
- Modify: `core_matrix/app/services/workflows/build_execution_snapshot.rb`
- Modify: `core_matrix/test/models/turn_test.rb`
- Modify: `core_matrix/test/services/workflows/build_execution_snapshot_test.rb`
- Modify: `core_matrix/test/services/workflows/create_for_turn_test.rb`
- Modify: `core_matrix/test/test_helper.rb`

**Step 1: Write the failing tests**

Add or tighten tests so they prove:

- `Turn` no longer exposes `effective_config_snapshot` as a public transitional
  helper
- snapshot-building paths assert against the old wrapped key directly rather
  than through `legacy_snapshot_context_key`
- rejection of the old wrapped shape still works, but without a named legacy
  constant or test helper becoming part of the enduring surface

Example expectations:

```ruby
refute_respond_to turn, :effective_config_snapshot
refute turn.execution_snapshot.to_h.key?("execution_context")
assert_includes turn.errors[:resolved_config_snapshot], "must not use legacy wrapped execution context"
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/models/turn_test.rb \
  test/services/workflows/build_execution_snapshot_test.rb \
  test/services/workflows/create_for_turn_test.rb
```

Expected: FAIL because the current code still exposes the transitional helper
surface and helper naming.

**Step 3: Write the minimal implementation**

Implement:

- remove `Turn#effective_config_snapshot`
- make `Workflows::BuildExecutionSnapshot` read
  `turn.resolved_config_snapshot` directly
- remove `LEGACY_WRAPPED_EXECUTION_KEY`
- remove `legacy_snapshot_context_key` from `test/test_helper.rb`
- keep legacy wrapped-shape rejection only as a narrow private validation, with
  no public helper surface built around it

**Step 4: Run tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/models/turn.rb \
  core_matrix/app/services/workflows/build_execution_snapshot.rb \
  core_matrix/test/models/turn_test.rb \
  core_matrix/test/services/workflows/build_execution_snapshot_test.rb \
  core_matrix/test/services/workflows/create_for_turn_test.rb \
  core_matrix/test/test_helper.rb
git commit -m "refactor: remove residual snapshot transition helpers"
```

## Task 2: Align Active Behavior Docs And Audit Artifacts With The Landed Owners

**Files:**

- Modify: `core_matrix/docs/behavior/transcript-visibility-and-attachments.md`
- Modify: `core_matrix/docs/behavior/publication-and-live-projection.md`
- Modify: `core_matrix/docs/behavior/workflow-context-assembly-and-execution-snapshot.md`
  if any stale owner wording remains after the grep sweep
- Modify: `docs/reports/core-matrix-architecture-health-audit-register.md`
- Modify: `docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md`

**Step 1: Sweep active docs for stale owner names**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
rg -n "Conversation#transcript_projection_messages|Conversation#context_projection_messages|Conversation#context_projection_attachments|ContextAssembler|prepare_workflow_execution_context!" \
  core_matrix/docs/behavior \
  docs/reports
```

Use that output to drive the doc edits. Historical references in
`docs/finished-plans/` or other explicitly archival material are out of scope.

**Step 2: Update docs**

Make the active docs describe the current owners explicitly:

- transcript visibility and publication projection read through
  `Conversations::TranscriptProjection` and `Conversations::ContextProjection`
- execution-snapshot assembly is owned by
  `Workflows::BuildExecutionSnapshot`
- test/setup references in audit artifacts use the current helper names where
  they are describing present-day code rather than past-state diagnosis

**Step 3: Run doc-targeted verification**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
rg -n "Conversation#transcript_projection_messages|Conversation#context_projection_messages|Conversation#context_projection_attachments|ContextAssembler" \
  core_matrix/docs/behavior \
  docs/reports
```

Expected:

- no hits in active behavior docs except where the audit report is explicitly
  describing the old diagnosis as historical context
- the audit register and the Round 1 report implementation update should point
  at the current owners

**Step 4: Commit**

```bash
git add core_matrix/docs/behavior/transcript-visibility-and-attachments.md \
  core_matrix/docs/behavior/publication-and-live-projection.md \
  core_matrix/docs/behavior/workflow-context-assembly-and-execution-snapshot.md \
  docs/reports/core-matrix-architecture-health-audit-register.md \
  docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md
git commit -m "docs: align snapshot ownership references with landed code"
```

If `workflow-context-assembly-and-execution-snapshot.md` did not need changes,
omit it from the commit.

## Task 3: Final Verification And Closeout

**Step 1: Run focused verification**

Run:

```bash
cd core_matrix
bin/rails test \
  test/models/turn_test.rb \
  test/models/conversation_test.rb \
  test/services/workflows/build_execution_snapshot_test.rb \
  test/services/workflows/create_for_turn_test.rb \
  test/queries/publications/live_projection_query_test.rb \
  test/integration/workflow_context_flow_test.rb
```

Then run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
rg -n "LEGACY_WRAPPED_EXECUTION_KEY|legacy_snapshot_context_key" core_matrix/app core_matrix/test core_matrix/docs docs/reports
rg -n "effective_config_snapshot" core_matrix/app core_matrix/docs docs/reports
git diff --check
```

**Step 2: Acceptance review**

Confirm:

- the execution-snapshot unification batch is no longer described as ongoing
  implementation work in this repo
- the remaining app/test/doc surface uses current owner names
- no active code path depends on the deleted transitional helper surface

## Acceptance Criteria

- `Turn` no longer exposes `effective_config_snapshot`.
- no enduring helper constant or test DSL keeps the deleted wrapped snapshot
  shape alive.
- `Workflows::BuildExecutionSnapshot` reads the split config row directly.
- active behavior docs no longer describe deleted aggregate helper owners as
  current behavior.
- the audit register and Round 1 report describe the landed owners with current
  names.
- targeted tests, grep audits, and `git diff --check` all pass.

## Completion Record

- Status: completed
- Completion date: 2026-03-28
- Retirement note: moved out of `docs/plans` after the third-round
  completeness review confirmed this closeout had already landed in code and
  active docs.
- Landing commits:
  - `b3c3198` `refactor: split turn execution snapshot persistence`
  - `0090944` `refactor: formalize execution snapshot contract`
  - `679b15a` `refactor: wire turn to execution snapshot contract`
  - `bec23bb` `refactor: extract conversation projection services`
  - `be756eb` `refactor: route execution consumers through snapshot contract`
  - `d52d962` `docs: record execution snapshot boundary unification`
  - `e82a02b` `cleanup: close out execution snapshot boundaries`
- Landed scope:
  - `Turn` now exposes the explicit `execution_snapshot` contract and no longer
    carries the old public transition helper surface.
  - `Workflows::BuildExecutionSnapshot` owns persisted runtime snapshot
    assembly, and conversation projection logic lives in the extracted
    `Conversations::*Projection` services.
  - active behavior docs and audit artifacts describe the landed owners using
    the current names.
- Review corrections on 2026-03-28:
  - the final grep gate was narrowed so it no longer false-fails on the
    intentional negative assertion in `core_matrix/test/models/turn_test.rb`
    that proves `effective_config_snapshot` is gone.
  - the plan was retired from active execution tracking because the requested
    closeout work was already present at `HEAD`.
- Verification evidence:
  - `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/models/turn_test.rb test/models/conversation_test.rb test/services/workflows/build_execution_snapshot_test.rb test/services/workflows/create_for_turn_test.rb test/queries/publications/live_projection_query_test.rb test/integration/workflow_context_flow_test.rb`
  - `cd /Users/jasl/Workspaces/Ruby/cybros && rg -n "LEGACY_WRAPPED_EXECUTION_KEY|legacy_snapshot_context_key" core_matrix/app core_matrix/test core_matrix/docs docs/reports`
  - `cd /Users/jasl/Workspaces/Ruby/cybros && rg -n "effective_config_snapshot" core_matrix/app core_matrix/docs docs/reports`
  - `cd /Users/jasl/Workspaces/Ruby/cybros && git diff --check`
