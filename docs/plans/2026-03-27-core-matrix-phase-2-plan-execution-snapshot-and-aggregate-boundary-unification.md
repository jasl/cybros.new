# Core Matrix Phase 2 Execution Snapshot And Aggregate Boundary Unification Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Separate persistent aggregate ownership from runtime-facing execution snapshot ownership so `Conversation` and `Turn` stop acting as mixed aggregate-plus-projection facades.

**Architecture:** Split turn config and execution snapshot into separate persisted contracts, introduce one explicit execution-snapshot object/reader family, move transcript/context projection out of aggregate models into dedicated projection services, and migrate workflow/provider consumers onto the new snapshot contract without compatibility shims.

**Tech Stack:** Ruby on Rails (`core_matrix`), Active Record, JSONB snapshot persistence, Minitest model/service/integration coverage, Phase 2 behavior docs, schema reset workflow

---

## Execution Rules

- Treat this as a breaking architecture cleanup inside Milestone C acceptance,
  not as a compatibility-preserving refactor.
- Do not keep the current wrapped `resolved_config_snapshot` shape where
  `config` and `execution_context` live in the same payload.
- Do not keep `Conversation` or `Turn` as the long-term owners of transcript
  projection, attachment projection, or execution-snapshot field access.
- `Turn` should keep aggregate invariants and row identity only:
  - lifecycle
  - origin and selected-message pointers
  - deployment/environment consistency
  - persisted config snapshot row
  - persisted execution snapshot payload row
- Runtime-facing reads must go through one explicit execution-snapshot contract.
- Transcript/context projection must move to dedicated projection collaborators,
  not to a fatter `Conversation` model.
- Because compatibility is intentionally out of scope, it is acceptable to:
  - edit the original migration directly
  - rebuild `db/schema.rb`
  - reset the development and test databases
- Final verification is not complete until grep confirms:
  - no remaining `execution_context` nesting under `resolved_config_snapshot`
  - no remaining runtime-facing hash helper family on `Turn`
  - no remaining context-projection helper family on `Conversation`
- Commit after every task with the suggested message or a tighter equivalent.

## Target Shape

After this batch:

- `turns.resolved_config_snapshot` stores only the resolved config payload.
- `turns.execution_snapshot_payload` stores the frozen runtime-facing snapshot.
- `Turn#execution_snapshot` returns a dedicated snapshot object, not a raw hash.
- `WorkflowRun` delegates runtime-facing snapshot reads through that object.
- `Conversation` no longer defines:
  - `transcript_projection_messages`
  - `context_projection_messages`
  - `context_projection_attachments`
  - `historical_anchor_prefix_messages`
- Projection logic lives in a small projection family under
  `core_matrix/app/services/conversations/`.
- The snapshot builder owns field names and serialized shape for:
  - identity
  - turn origin
  - model context
  - provider execution
  - budget hints
  - context messages
  - context imports
  - attachment projections
- Provider execution callers consume snapshot fields through the explicit
  snapshot contract, not by reopening ad hoc turn JSON or aggregate helpers.

## Current Implementations That Must Be Adjusted

- `core_matrix/db/migrate/20260324090021_create_turns.rb`
  Reason: `resolved_config_snapshot` currently stores both config and execution
  snapshot content in one JSONB blob.
- `core_matrix/db/schema.rb`
  Reason: must be regenerated after the direct migration edit.
- `core_matrix/app/models/turn.rb`
  Reason: currently exposes the whole runtime-facing helper surface directly on
  the aggregate model.
- `core_matrix/app/models/workflow_run.rb`
  Reason: delegates snapshot reads from `Turn` helper methods that should no
  longer exist there.
- `core_matrix/app/models/conversation.rb`
  Reason: currently owns transcript/context projection helpers that belong on a
  read-side projection layer.
- `core_matrix/app/services/workflows/context_assembler.rb`
  Reason: currently builds the runtime snapshot but does not own an explicit
  persisted snapshot contract.
- `core_matrix/app/services/workflows/create_for_turn.rb`
  Reason: currently overwrites `resolved_config_snapshot` with a wrapped mixed
  payload.
- `core_matrix/app/services/workflows/execute_run.rb`
  Reason: currently reaches into `turn.context_messages`.
- `core_matrix/app/services/provider_execution/build_request_context.rb`
  Reason: currently re-derives provider request shape from the aggregate turn.
- `core_matrix/app/services/provider_execution/execute_turn_step.rb`
  Reason: currently builds request context from `Turn` instead of the explicit
  snapshot contract.
- `core_matrix/test/test_helper.rb`
  Reason: workflow execution fixtures and helper naming must match the new
  split snapshot model.
- `core_matrix/docs/behavior/workflow-context-assembly-and-execution-snapshot.md`
  Reason: currently documents the mixed `resolved_config_snapshot` layout and
  aggregate helper surface.
- `core_matrix/docs/behavior/turn-entry-and-selector-state.md`
  Reason: must describe the split between config snapshot and execution
  snapshot explicitly.
- `docs/reports/core-matrix-architecture-health-audit-register.md`
  Reason: should mark the relevant architecture finding and unification
  opportunity as implemented once the batch lands.
- `docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md`
  Reason: should be refreshable with a short implementation note after the
  batch lands.

## Anticipated File Set

### Create

- `core_matrix/app/models/turn_execution_snapshot.rb`
- `core_matrix/app/services/conversations/transcript_projection.rb`
- `core_matrix/app/services/conversations/context_projection.rb`
- `core_matrix/app/services/conversations/historical_anchor_projection.rb`
- `core_matrix/app/services/workflows/build_execution_snapshot.rb`
- `core_matrix/test/services/workflows/build_execution_snapshot_test.rb`
- `core_matrix/test/services/provider_execution/execute_turn_step_test.rb`

### Delete Or Rename

- `core_matrix/app/services/workflows/context_assembler.rb`
  - replace with `build_execution_snapshot.rb`
- `core_matrix/test/services/workflows/context_assembler_test.rb`
  - rename to `build_execution_snapshot_test.rb`

### Modify

- `core_matrix/db/migrate/20260324090021_create_turns.rb`
- `core_matrix/db/schema.rb`
- `core_matrix/app/models/conversation.rb`
- `core_matrix/app/models/turn.rb`
- `core_matrix/app/models/workflow_run.rb`
- `core_matrix/app/services/workflows/create_for_turn.rb`
- `core_matrix/app/services/workflows/execute_run.rb`
- `core_matrix/app/services/provider_execution/build_request_context.rb`
- `core_matrix/app/services/provider_execution/execute_turn_step.rb`
- `core_matrix/test/test_helper.rb`
- `core_matrix/test/models/conversation_test.rb`
- `core_matrix/test/models/turn_test.rb`
- `core_matrix/test/models/workflow_run_test.rb`
- `core_matrix/test/services/workflows/create_for_turn_test.rb`
- `core_matrix/test/services/workflows/execute_run_test.rb`
- `core_matrix/test/services/provider_execution/build_request_context_test.rb`
- `core_matrix/test/services/workflows/manual_retry_test.rb`
- `core_matrix/test/services/workflows/manual_resume_test.rb`
- `core_matrix/test/integration/workflow_context_flow_test.rb`
- `core_matrix/test/integration/provider_backed_turn_execution_test.rb`
- `core_matrix/docs/behavior/workflow-context-assembly-and-execution-snapshot.md`
- `core_matrix/docs/behavior/turn-entry-and-selector-state.md`
- `docs/reports/core-matrix-architecture-health-audit-register.md`
- `docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md`

## Task 1: Split Config Snapshot From Execution Snapshot At The Schema Boundary

**Files:**

- Modify: `core_matrix/db/migrate/20260324090021_create_turns.rb`
- Modify: `core_matrix/db/schema.rb`
- Modify: `core_matrix/app/models/turn.rb`
- Modify: `core_matrix/test/models/turn_test.rb`
- Modify: `core_matrix/test/services/workflows/create_for_turn_test.rb`

**Step 1: Write the failing tests**

Add or extend tests so they prove:

- `resolved_config_snapshot` stores only config keys after workflow creation
- the execution snapshot is persisted in a separate row attribute
- `Turn` rejects non-hash execution snapshot payloads
- no compatibility fallback accepts the old wrapped
  `{ "config" => ..., "execution_context" => ... }` layout

Example expectation:

```ruby
test "workflow creation stores config and execution snapshot in separate turn fields" do
  workflow_run = Workflows::CreateForTurn.call(...)
  turn = workflow_run.turn.reload

  assert_equal({ "temperature" => 0.2 }, turn.resolved_config_snapshot)
  assert_equal workflow_run.turn.public_id, turn.execution_snapshot.identity.fetch("turn_id")
  refute turn.resolved_config_snapshot.key?("execution_context")
end
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/models/turn_test.rb \
  test/services/workflows/create_for_turn_test.rb
```

Expected: FAIL because the new `execution_snapshot_payload` split does not yet
exist.

**Step 3: Write the minimal implementation**

Implement the breaking schema split:

- edit `20260324090021_create_turns.rb` to add
  `execution_snapshot_payload :jsonb, null: false, default: {}`
- keep `resolved_config_snapshot` as the config-only row
- regenerate `db/schema.rb`
- in `Turn`:
  - validate `execution_snapshot_payload` is a hash
  - add one explicit `execution_snapshot` reader that returns a value object
  - remove `effective_config_snapshot` compatibility fallback for wrapped
    payloads

**Step 4: Reset schema and databases**

Run:

```bash
cd core_matrix
bin/rails db:drop db:create db:schema:load
RAILS_ENV=test bin/rails db:drop db:create db:schema:load
```

**Step 5: Run tests to verify they pass**

Run the same targeted test command and confirm PASS.

**Step 6: Commit**

```bash
git add core_matrix/db/migrate/20260324090021_create_turns.rb \
  core_matrix/db/schema.rb \
  core_matrix/app/models/turn.rb \
  core_matrix/test/models/turn_test.rb \
  core_matrix/test/services/workflows/create_for_turn_test.rb
git commit -m "refactor: split turn execution snapshot persistence"
```

## Task 2: Introduce An Explicit Execution Snapshot Contract And Delete The Mixed Assembler Boundary

**Files:**

- Create: `core_matrix/app/models/turn_execution_snapshot.rb`
- Create: `core_matrix/app/services/workflows/build_execution_snapshot.rb`
- Create: `core_matrix/test/services/workflows/build_execution_snapshot_test.rb`
- Delete: `core_matrix/app/services/workflows/context_assembler.rb`
- Delete: `core_matrix/test/services/workflows/context_assembler_test.rb`
- Modify: `core_matrix/app/services/workflows/create_for_turn.rb`
- Modify: `core_matrix/test/services/workflows/create_for_turn_test.rb`
- Modify: `core_matrix/test/test_helper.rb`

**Step 1: Write the failing tests**

Add tests proving:

- the builder returns the new contract shape without nesting under
  `execution_context`
- the snapshot object exposes explicit readers for each frozen field
- `CreateForTurn` persists the built snapshot into
  `execution_snapshot_payload`
- the old `Workflows::ContextAssembler` constant is gone from the in-scope test
  surface

Example expectation:

```ruby
snapshot = Workflows::BuildExecutionSnapshot.call(turn: current_turn)

assert_equal "responses", snapshot.provider_execution.fetch("wire_api")
assert_equal current_turn.public_id, snapshot.identity.fetch("turn_id")
assert_equal snapshot.to_h, current_turn.reload.execution_snapshot.to_h
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/workflows/build_execution_snapshot_test.rb \
  test/services/workflows/create_for_turn_test.rb
```

Expected: FAIL because the new contract class and builder do not exist yet.

**Step 3: Write the minimal implementation**

Implement:

- `TurnExecutionSnapshot`
  - wraps the raw JSONB payload
  - owns `to_h`
  - exposes explicit readers for identity, origin, model context, provider
    execution, budget hints, context messages, imports, and attachment
    projections
- `Workflows::BuildExecutionSnapshot`
  - owns field names and serialized shape
  - returns a `TurnExecutionSnapshot`
- `CreateForTurn`
  - resolves model selection first
  - persists `resolved_config_snapshot` unchanged as config
  - persists `execution_snapshot_payload` from the builder
- remove the old `ContextAssembler` constant rather than keeping a wrapper

**Step 4: Run tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/models/turn_execution_snapshot.rb \
  core_matrix/app/services/workflows/build_execution_snapshot.rb \
  core_matrix/test/services/workflows/build_execution_snapshot_test.rb \
  core_matrix/app/services/workflows/create_for_turn.rb \
  core_matrix/test/services/workflows/create_for_turn_test.rb \
  core_matrix/test/test_helper.rb
git rm core_matrix/app/services/workflows/context_assembler.rb \
  core_matrix/test/services/workflows/context_assembler_test.rb
git commit -m "refactor: formalize execution snapshot contract"
```

## Task 3: Move Transcript And Historical-Anchor Projection Out Of Conversation

**Files:**

- Create: `core_matrix/app/services/conversations/transcript_projection.rb`
- Create: `core_matrix/app/services/conversations/context_projection.rb`
- Create: `core_matrix/app/services/conversations/historical_anchor_projection.rb`
- Modify: `core_matrix/app/models/conversation.rb`
- Modify: `core_matrix/app/services/workflows/build_execution_snapshot.rb`
- Modify: `core_matrix/test/models/conversation_test.rb`
- Modify: `core_matrix/test/integration/workflow_context_flow_test.rb`

**Step 1: Write the failing tests**

Add tests proving:

- `Conversation` no longer owns transcript/context projection helper methods
- the projection service family still preserves:
  - visibility overlays
  - context exclusion
  - historical-anchor prefix behavior
  - attachment eligibility tied to visible context messages
- workflow context assembly continues to use the projection layer rather than
  aggregate helper methods

Example expectation:

```ruby
projection = Conversations::ContextProjection.call(conversation: branch_conversation)

assert_equal expected_message_ids, projection.messages.map(&:public_id)
refute_respond_to branch_conversation, :context_projection_messages
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/models/conversation_test.rb \
  test/integration/workflow_context_flow_test.rb
```

Expected: FAIL because the projection family does not yet exist and
`Conversation` still owns the old helpers.

**Step 3: Write the minimal implementation**

Implement:

- `TranscriptProjection` for transcript-bearing selected message projection
- `HistoricalAnchorProjection` for parent-prefix resolution
- `ContextProjection` for context-visible message and attachment projection
- shrink `Conversation` to aggregate invariants plus minimal association and
  lifecycle helpers
- update `BuildExecutionSnapshot` to consume the new projection services

**Step 4: Run tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/conversations/transcript_projection.rb \
  core_matrix/app/services/conversations/context_projection.rb \
  core_matrix/app/services/conversations/historical_anchor_projection.rb \
  core_matrix/app/models/conversation.rb \
  core_matrix/app/services/workflows/build_execution_snapshot.rb \
  core_matrix/test/models/conversation_test.rb \
  core_matrix/test/integration/workflow_context_flow_test.rb
git commit -m "refactor: extract conversation projection services"
```

## Task 4: Move Workflow And Provider Execution Consumers Onto The Snapshot Contract

**Files:**

- Modify: `core_matrix/app/models/workflow_run.rb`
- Modify: `core_matrix/app/services/workflows/execute_run.rb`
- Modify: `core_matrix/app/services/provider_execution/build_request_context.rb`
- Modify: `core_matrix/app/services/provider_execution/execute_turn_step.rb`
- Modify: `core_matrix/test/models/workflow_run_test.rb`
- Modify: `core_matrix/test/services/workflows/execute_run_test.rb`
- Modify: `core_matrix/test/services/provider_execution/build_request_context_test.rb`
- Create: `core_matrix/test/services/provider_execution/execute_turn_step_test.rb`
- Modify: `core_matrix/test/integration/provider_backed_turn_execution_test.rb`
- Modify: `core_matrix/test/services/workflows/manual_retry_test.rb`
- Modify: `core_matrix/test/services/workflows/manual_resume_test.rb`

**Step 1: Write the failing tests**

Add tests proving:

- `WorkflowRun` delegates through `turn.execution_snapshot`
- `ExecuteRun` default messages come from the snapshot contract, not a turn
  aggregate helper
- provider request context reads model/provider/budget settings from the
  snapshot contract
- no direct caller in scope still expects the old
  `resolved_config_snapshot["execution_context"]` layout

Example expectation:

```ruby
assert_equal(
  workflow_run.turn.execution_snapshot.context_messages.map { |entry| entry.slice("role", "content") },
  Workflows::ExecuteRun.new(workflow_run: workflow_run).send(:default_messages)
)
```

**Step 2: Run tests to verify they fail**

Run:

```bash
cd core_matrix
bin/rails test \
  test/models/workflow_run_test.rb \
  test/services/workflows/execute_run_test.rb \
  test/services/provider_execution/build_request_context_test.rb \
  test/services/provider_execution/execute_turn_step_test.rb \
  test/integration/provider_backed_turn_execution_test.rb \
  test/services/workflows/manual_retry_test.rb \
  test/services/workflows/manual_resume_test.rb
```

Expected: FAIL because downstream consumers still depend on the old helper
surface.

**Step 3: Write the minimal implementation**

Implement:

- `WorkflowRun` delegation through `turn.execution_snapshot`
- `ExecuteRun` default message projection via the snapshot contract
- `BuildRequestContext` to accept the snapshot object as its primary source
- `ExecuteTurnStep` to request provider settings from the new contract
- add direct service coverage for `ExecuteTurnStep` so the snapshot-backed
  provider request path is not only exercised indirectly through integration
  flows
- remove in-scope direct reads of `execution_context` and aggregate helper
  methods

**Step 4: Run tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Grep audit**

Run:

```bash
cd core_matrix
rg -n "execution_context" app test docs
rg -n "def (execution_identity|model_context|provider_execution|budget_hints|turn_origin_context|context_messages|context_imports|attachment_manifest|runtime_attachment_manifest|model_input_attachments|attachment_diagnostics)" app/models/turn.rb
rg -n "def (transcript_projection_messages|context_projection_messages|context_projection_attachments|historical_anchor_prefix_messages)" app/models/conversation.rb
```

Expected:

- remaining `execution_context` hits should exist only in doc text being
  updated during the final doc task, not in runtime code
- the old helper families should no longer exist on the aggregate models

**Step 6: Commit**

```bash
git add core_matrix/app/models/workflow_run.rb \
  core_matrix/app/services/workflows/execute_run.rb \
  core_matrix/app/services/provider_execution/build_request_context.rb \
  core_matrix/app/services/provider_execution/execute_turn_step.rb \
  core_matrix/test/models/workflow_run_test.rb \
  core_matrix/test/services/workflows/execute_run_test.rb \
  core_matrix/test/services/provider_execution/build_request_context_test.rb \
  core_matrix/test/services/provider_execution/execute_turn_step_test.rb \
  core_matrix/test/integration/provider_backed_turn_execution_test.rb \
  core_matrix/test/services/workflows/manual_retry_test.rb \
  core_matrix/test/services/workflows/manual_resume_test.rb
git commit -m "refactor: route execution consumers through snapshot contract"
```

## Task 5: Update Behavior Docs, Audit Artifacts, And Verification Scripts

**Files:**

- Modify: `core_matrix/docs/behavior/workflow-context-assembly-and-execution-snapshot.md`
- Modify: `core_matrix/docs/behavior/turn-entry-and-selector-state.md`
- Modify: `docs/reports/core-matrix-architecture-health-audit-register.md`
- Modify: `docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md`

**Step 1: Update docs**

Document the landed target shape explicitly:

- config snapshot row and execution snapshot row are separate
- runtime-facing field names now belong to the explicit snapshot contract
- projection services own transcript/context assembly
- aggregate models keep invariants and row ownership only

**Step 2: Run focused verification**

Run:

```bash
cd core_matrix
bin/rails test \
  test/models/turn_test.rb \
  test/models/conversation_test.rb \
  test/models/workflow_run_test.rb \
  test/services/workflows/create_for_turn_test.rb \
  test/services/workflows/execute_run_test.rb \
  test/services/provider_execution/build_request_context_test.rb \
  test/services/provider_execution/execute_turn_step_test.rb \
  test/integration/workflow_context_flow_test.rb \
  test/integration/provider_backed_turn_execution_test.rb
```

Then run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git diff --check
```

**Step 3: Commit**

```bash
git add core_matrix/docs/behavior/workflow-context-assembly-and-execution-snapshot.md \
  core_matrix/docs/behavior/turn-entry-and-selector-state.md \
  docs/reports/core-matrix-architecture-health-audit-register.md \
  docs/reports/2026-03-27-core-matrix-architecture-health-audit-round-1.md
git commit -m "docs: record execution snapshot boundary unification"
```

## Task 6: Mandatory Three-Pass Completeness Review Before Declaring The Batch Ready

This task is required both while implementing and again before claiming the
batch is complete. Do not skip it.

### Pass 1: Scope And Files Review

Re-read this plan and the touched diff. Confirm:

- every file listed in `Anticipated File Set` was either changed or explicitly
  ruled out with a written reason in the implementation notes
- the migration edit, `db/schema.rb`, and database reset were actually done
- no leftover compatibility wrapper kept the old mixed snapshot layout alive

### Pass 2: Contract And Behavior Review

Confirm:

- the execution snapshot contract owns all runtime-facing field names
- `Conversation` and `Turn` no longer carry the deleted helper families
- projection services, snapshot builder, and provider/workflow consumers all
  use one coherent contract
- docs reflect the new row shape and the new owner boundaries

### Pass 3: Tests And Audit Review

Confirm:

- every test command in this plan was run
- failures were resolved without weakening the target shape
- grep audits came back clean
- the audit register and Round 1 report were updated consistently
- there is no missing use case, missing task, missing doc update, missing file,
  or missing verification command that was implied by this conversation

If any pass finds a gap, update code, docs, or this plan's execution notes and
repeat the affected pass until no issue remains. The batch is not ready until
all three passes are clean.

## Acceptance Criteria

- `Turn` persists config and execution snapshot in separate row attributes.
- `resolved_config_snapshot` no longer stores `execution_context`.
- `Turn` exposes one explicit execution-snapshot object instead of the old
  runtime-facing helper family.
- `Conversation` no longer owns transcript/context projection helpers.
- workflow and provider execution consumers read runtime-facing data through the
  snapshot contract.
- targeted tests, neighboring tests, schema reset, grep audits, and doc updates
  all pass.
