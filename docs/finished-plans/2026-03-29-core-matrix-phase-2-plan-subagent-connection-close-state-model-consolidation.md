# Core Matrix Phase 2 Subagent Session Close State Model Consolidation Implementation Plan

**Status:** Completed and archived on 2026-03-29.

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Collapse `SubagentConnection` close progression onto one canonical durable state model so close-control writes, quiescence guards, and machine-facing reads stop compensating across duplicated state owners.

**Architecture:** Make `close_state` the only durable owner of `SubagentConnection` close progression. Keep `last_known_status` as runtime-observed execution status only, and preserve machine-facing `lifecycle_state` output as a derived projection instead of a persisted second close-state machine. Under the phase 2 destructive-schema convention, land that ownership by rewriting the schema baseline so `subagent_connections.lifecycle_state` is no longer part of the durable model, then push reader-side behavior onto model predicates and scopes that encode the canonical semantics once.

**Tech Stack:** Ruby on Rails (`core_matrix`), Active Record migration and model predicates, Minitest model/service/query/request/e2e coverage, behavior docs, `rg`, `bin/rails test`

---

## Current Baseline

The current `SubagentConnection` model still persists three partially overlapping
signals:

- `close_state` from `ClosableRuntimeResource`
- `lifecycle_state` on `SubagentConnection` itself
- `last_known_status` for runtime-observed progress

That split leaks into both write-side and read-side code:

- `AgentControl::CreateResourceCloseRequest` writes both `close_state` and
  `lifecycle_state`
- `AgentControl::ApplyCloseOutcome` writes both `close_state` and
  `lifecycle_state`
- quiescence, barrier, wait, and serialization paths compensate by mixing
  `close_state`, `lifecycle_state`, and `last_known_status`
- tests and behavior docs still describe `lifecycle_state` as if it were a
  first-class durable owner rather than a projection of close progress

The mapping from the duplicated fields is already effectively deterministic:

- `close_state = open` maps to projected lifecycle `open`
- `close_state = requested|acknowledged` maps to projected lifecycle
  `close_requested`
- `close_state = closed|failed` maps to projected lifecycle `closed`

That makes this a good consolidation target: the duplicate column is not adding
information, only forcing callers to keep multiple state machines in sync.

## Locked Design Decisions

- `close_state` is the only durable close-progression owner for
  `SubagentConnection`.
- `last_known_status` remains persisted because runtimes still need to report
  execution progress and terminal runtime outcomes independently of close
  control.
- machine-facing serializers may continue to emit a `lifecycle_state` field,
  but it must be derived from `close_state`; it is no longer backed by a
  separate database column.
- no caller outside `SubagentConnection` should infer close semantics by hand from
  multiple columns once this batch lands.
- this batch follows the phase 2 destructive-schema policy: rewrite the schema
  baseline directly instead of adding a compatibility removal migration or a
  drift-checking bridge step.

## Execution Rules

- Treat this as one structural consolidation batch, not as a mixed bugfix and
  cleanup sweep.
- Keep external and machine-facing payload shape stable where cheap:
  `SubagentConnections::Wait` and `SubagentConnections::ListForConversation` may keep
  returning `"lifecycle_state"`, but only as a derived field.
- Do not introduce a second compatibility wrapper or a third state object.
  The canonical owner should live directly on `SubagentConnection`.
- Prefer model-level predicates and scopes over scattering `close_state`
  comparisons across services and queries.
- `last_known_status` may still drive runtime-observation behavior such as
  reporting `"failed"` or `"interrupted"` terminal status, but it must not
  become a second close owner.
- Remove direct writes to `SubagentConnection#lifecycle_state` before removing the
  column.
- Update behavior docs before final verification so the new owner model is
  documented as current behavior.
- Commit after each task with the suggested message or a tighter equivalent.

## Explicitly Out Of Scope

- runtime capability preservation and reuse unification
- deployment recovery contract cleanup
- broad renaming across non-subagent lifecycle models
- new user-facing or agent-facing subagent features
- schema cleanup for `AgentTaskRun` or `ProcessRun` close-state models

## Final Deliverables

This plan must finish with all of the following true:

- `core_matrix/app/models/subagent_connection.rb` owns the canonical close-state
  predicates, scopes, and lifecycle projection helpers
- `core_matrix/db/migrate/20260324090038_create_subagent_connections.rb` and
  `core_matrix/db/schema.rb` no longer define a persisted
  `subagent_connections.lifecycle_state` column
- `core_matrix/db/schema.rb` no longer lists `subagent_connections.lifecycle_state`
- `core_matrix/app/services/agent_control/create_resource_close_request.rb` and
  `core_matrix/app/services/agent_control/apply_close_outcome.rb` no longer
  write `SubagentConnection#lifecycle_state`
- reader-side guards and serializers consume model predicates or derived
  projection helpers instead of hand-encoding the split-state logic
- active behavior docs describe `close_state` as the durable close owner and
  `lifecycle_state` as a derived projection where it still appears externally

### Task 1: Lock The Canonical `SubagentConnection` State Contract At The Model Boundary

**Files:**
- Modify: `core_matrix/db/migrate/20260324090038_create_subagent_connections.rb`
- Modify: `core_matrix/app/models/subagent_connection.rb`
- Modify: `core_matrix/db/schema.rb`
- Test: `core_matrix/test/models/subagent_connection_test.rb`

**Step 1: Write the failing tests**

Add model tests that prove:

- `SubagentConnection` exposes one canonical mapping from `close_state` to
  projected lifecycle state
- the canonical projection maps:
  - `open -> open`
  - `requested|acknowledged -> close_requested`
  - `closed|failed -> closed`
- reader helpers such as `close_pending_or_open`, `running_for_barriers`, and
  any new predicate methods do not need a persisted `lifecycle_state` column
- the model still reports a machine-facing `lifecycle_state` projection after
  the column is removed

Example expectation:

```ruby
test "derives lifecycle projection from close_state" do
  session = build_subagent_connection(close_state: "acknowledged")

  assert_equal "close_requested", session.lifecycle_state
  assert session.close_pending?
  refute session.terminal_close?
end
```

Also add a test that proves terminal failed sessions still project lifecycle
`closed` while preserving `last_known_status = failed`.

**Step 2: Run the model tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/models/subagent_connection_test.rb
```

Expected: FAIL because the model still uses a persisted lifecycle enum and does
not expose the new canonical projection helpers.

**Step 3: Write the minimal implementation**

Implement:

- a destructive phase 2 schema-baseline update that removes
  `subagent_connections.lifecycle_state` from
  `20260324090038_create_subagent_connections.rb` and regenerates `db/schema.rb`
- `SubagentConnection` model changes:
  - remove the persisted lifecycle enum
  - add a derived `lifecycle_state` reader backed by `close_state`
  - add explicit predicate helpers for:
    - close pending
    - terminal close
    - runtime-running-for-barriers
  - keep `close_pending_or_open` and `running_for_barriers` as canonical
    scopes, but reimplement them in terms of the new owner model

Do not add a new value object unless the model methods become obviously
unreadable; the first target is one clear owner, not more abstraction.

**Step 4: Run migration and model tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/models/subagent_connection_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add core_matrix/db/migrate/20260324090038_create_subagent_connections.rb \
  core_matrix/app/models/subagent_connection.rb \
  core_matrix/db/schema.rb \
  core_matrix/test/models/subagent_connection_test.rb
git commit -m "refactor: consolidate subagent connection state ownership"
```

### Task 2: Move Close-Control Writes Onto `close_state` Only

**Files:**
- Modify: `core_matrix/app/services/agent_control/create_resource_close_request.rb`
- Modify: `core_matrix/app/services/agent_control/apply_close_outcome.rb`
- Modify: `core_matrix/app/services/subagent_connections/request_close.rb`
- Test: `core_matrix/test/services/subagent_connections/request_close_test.rb`
- Test: `core_matrix/test/services/agent_control/report_test.rb`
- Test: `core_matrix/test/e2e/protocol/turn_interrupt_e2e_test.rb`
- Test: `core_matrix/test/e2e/protocol/conversation_close_e2e_test.rb`

**Step 1: Write the failing tests**

Add or update tests that prove:

- requesting subagent close changes `close_state` and close metadata without
  persisting a second lifecycle owner
- terminal close reports for `SubagentConnection` only settle:
  - `close_state`
  - `close_acknowledged_at`
  - `close_outcome_kind`
  - `last_known_status`
- callers that still assert `lifecycle_state` observe the derived projection,
  not a duplicated durable write

Example expectation:

```ruby
test "resource_closed terminalizes a subagent connection through close_state" do
  result = AgentControl::Report.call(...)

  assert_equal "accepted", result.code
  assert_equal "closed", subagent_connection.reload.close_state
  assert_equal "interrupted", subagent_connection.last_known_status
  assert_equal "closed", subagent_connection.lifecycle_state
end
```

**Step 2: Run the targeted write-path tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test \
  test/services/subagent_connections/request_close_test.rb \
  test/services/agent_control/report_test.rb \
  test/e2e/protocol/turn_interrupt_e2e_test.rb \
  test/e2e/protocol/conversation_close_e2e_test.rb
```

Expected: FAIL because write-side paths still reference the removed
`lifecycle_state` column or the old expectations.

**Step 3: Write the minimal implementation**

Implement:

- `AgentControl::CreateResourceCloseRequest`
  - stop writing `SubagentConnection#lifecycle_state`
  - rely on `close_state = requested` plus close metadata only
- `AgentControl::ApplyCloseOutcome`
  - stop writing `SubagentConnection#lifecycle_state`
  - continue writing terminal `close_state`
  - continue writing terminal `last_known_status`
- `SubagentConnections::RequestClose`
  - keep the public service shape stable
  - rely on `close_open?` and the canonical close-state model only

Do not weaken close metadata validation while removing the duplicate column.

**Step 4: Run the targeted write-path tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/agent_control/create_resource_close_request.rb \
  core_matrix/app/services/agent_control/apply_close_outcome.rb \
  core_matrix/app/services/subagent_connections/request_close.rb \
  core_matrix/test/services/subagent_connections/request_close_test.rb \
  core_matrix/test/services/agent_control/report_test.rb \
  core_matrix/test/e2e/protocol/turn_interrupt_e2e_test.rb \
  core_matrix/test/e2e/protocol/conversation_close_e2e_test.rb
git commit -m "refactor: remove duplicate subagent lifecycle writes"
```

### Task 3: Collapse Reader-Side Guards And Machine-Facing Reads Onto Canonical Predicates

**Files:**
- Modify: `core_matrix/app/queries/conversations/blocker_snapshot_query.rb`
- Modify: `core_matrix/app/services/conversations/validate_quiescence.rb`
- Modify: `core_matrix/app/services/conversations/request_turn_interrupt.rb`
- Modify: `core_matrix/app/services/subagent_connections/wait.rb`
- Modify: `core_matrix/app/services/subagent_connections/list_for_conversation.rb`
- Test: `core_matrix/test/queries/conversations/blocker_snapshot_query_test.rb`
- Test: `core_matrix/test/services/conversations/validate_quiescence_test.rb`
- Test: `core_matrix/test/services/conversations/request_turn_interrupt_test.rb`
- Test: `core_matrix/test/services/subagent_connections/wait_test.rb`
- Test: `core_matrix/test/services/conversations/archive_test.rb`

**Step 1: Write the failing tests**

Add or update tests that prove:

- blocker counts use canonical subagent scopes instead of persisted lifecycle
  duplication
- quiescence rejects open or close-pending subagent connections using the model's
  canonical predicates
- turn interrupt barrier checks still distinguish:
  - reusable conversation-scoped subagent work
  - turn-scoped sessions pending close
- `SubagentConnections::Wait` and `SubagentConnections::ListForConversation` still
  emit `"lifecycle_state"` but that value is derived from `close_state`

Example expectation:

```ruby
assert_equal "close_requested", result.fetch("lifecycle_state")
assert_equal "acknowledged", session.reload.close_state
assert_equal "running", session.last_known_status
```

**Step 2: Run the targeted reader tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test \
  test/queries/conversations/blocker_snapshot_query_test.rb \
  test/services/conversations/validate_quiescence_test.rb \
  test/services/conversations/request_turn_interrupt_test.rb \
  test/services/subagent_connections/wait_test.rb \
  test/services/conversations/archive_test.rb
```

Expected: FAIL because reader and serializer paths still assume a persisted
`SubagentConnection.lifecycle_state`.

**Step 3: Write the minimal implementation**

Implement:

- `Conversations::BlockerSnapshotQuery`
  - consume canonical scopes only
- `Conversations::ValidateQuiescence`
  - continue rejecting open and close-pending owned sessions, but through
    canonical scopes and helpers
- `Conversations::RequestTurnInterrupt`
  - keep the current public behavior while removing any hidden dependency on a
    persisted lifecycle column
- `SubagentConnections::Wait`
  - terminate on canonical close semantics plus terminal runtime status
  - serialize derived lifecycle projection
- `SubagentConnections::ListForConversation`
  - serialize derived lifecycle projection

Keep `last_known_status` usage narrow: runtime-observation and terminal status
reporting only.

**Step 4: Run the targeted reader tests to verify they pass**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/queries/conversations/blocker_snapshot_query.rb \
  core_matrix/app/services/conversations/validate_quiescence.rb \
  core_matrix/app/services/conversations/request_turn_interrupt.rb \
  core_matrix/app/services/subagent_connections/wait.rb \
  core_matrix/app/services/subagent_connections/list_for_conversation.rb \
  core_matrix/test/queries/conversations/blocker_snapshot_query_test.rb \
  core_matrix/test/services/conversations/validate_quiescence_test.rb \
  core_matrix/test/services/conversations/request_turn_interrupt_test.rb \
  core_matrix/test/services/subagent_connections/wait_test.rb \
  core_matrix/test/services/conversations/archive_test.rb
git commit -m "refactor: unify subagent connection read-side close semantics"
```

### Task 4: Update Active Docs And Run Final Verification

**Files:**
- Modify: `core_matrix/docs/behavior/subagent-connections-and-execution-leases.md`
- Modify: `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
  only if the final sweep finds stale wording around subagent close barriers

**Step 1: Write the doc updates**

Update active docs so they state explicitly:

- `close_state` is the durable close owner for `SubagentConnection`
- `last_known_status` is runtime-observed progress only
- any machine-facing `lifecycle_state` surface is a derived projection
- barrier and wait semantics read the canonical model rather than a split state
  family

**Step 2: Run the doc and code sweep**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
rg -n "SubagentConnection.*lifecycle_state|lifecycle_close_requested\\?|lifecycle_closed\\?|lifecycle_open\\?" \
  core_matrix/app \
  core_matrix/test \
  core_matrix/docs/behavior
```

Interpretation:

- app-code hits should only remain where `lifecycle_state` is a derived
  serializer field or a historical doc mention that still needs updating
- direct writes and enum-style lifecycle predicates for `SubagentConnection`
  should be gone

**Step 3: Run final verification**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test \
  test/models/subagent_connection_test.rb \
  test/services/subagent_connections/request_close_test.rb \
  test/services/subagent_connections/wait_test.rb \
  test/services/agent_control/report_test.rb \
  test/services/conversations/request_turn_interrupt_test.rb \
  test/services/conversations/validate_quiescence_test.rb \
  test/services/conversations/archive_test.rb \
  test/queries/conversations/blocker_snapshot_query_test.rb \
  test/e2e/protocol/turn_interrupt_e2e_test.rb \
  test/e2e/protocol/conversation_close_e2e_test.rb

bin/rails test

cd /Users/jasl/Workspaces/Ruby/cybros
rake test
git diff --check
```

Expected: PASS.

**Step 4: Commit**

```bash
git add core_matrix/docs/behavior/subagent-connections-and-execution-leases.md \
  core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md
git commit -m "docs: describe unified subagent close state model"
```

If `workflow-scheduler-and-wait-states.md` did not change, omit it from the
commit.

## Acceptance Criteria

- under the phase 2 destructive-schema convention, the schema baseline and
  `db/schema.rb` no longer define a persisted
  `subagent_connections.lifecycle_state` column.
- `SubagentConnection` close progression writes are owned only by `close_state`
  plus close metadata.
- `SubagentConnection#last_known_status` remains persisted and is only used for
  runtime-observation behavior, not as a second close owner.
- machine-facing subagent payloads may still expose `"lifecycle_state"`, but
  that value is derived from `close_state`.
- quiescence, blocker, wait, interrupt, and close-report paths no longer rely
  on a separate persisted `SubagentConnection.lifecycle_state`.
- active behavior docs describe the canonical owner model correctly.
- targeted verification passes, full `core_matrix` test suite passes, root
  `rake test` passes, and `git diff --check` passes.

## Plan Self-Check

### Completeness

- This plan names the schema change, the model owner, the write paths, the
  read paths, the machine-facing serializers, the active docs, and the final
  verification commands.
- The plan includes both code refactor scope and acceptance criteria, so the
  implementation can be checked against the document instead of against memory.
- The plan explicitly preserves outward payload compatibility for
  `lifecycle_state`, which avoids leaving a hidden boundary decision unstated.

### Feasibility

- The refactor is mechanically feasible because the old `lifecycle_state`
  column does not encode extra information beyond `close_state`; the mapping is
  lossy in only one safe direction:
  `requested|acknowledged -> close_requested`, `closed|failed -> closed`.
- The schema change is feasible within phase 2 because this batch explicitly
  permits destructive baseline rewrites instead of compatibility migrations.
- The tasks are ordered so the canonical model lands first, then write paths,
  then readers, then docs and full-suite verification.
- No cross-project contract change is required for this batch; all touched
  boundaries live in `core_matrix`.

### Open Questions Closed By This Plan

- The canonical durable owner is `close_state`, not `lifecycle_state`.
- `last_known_status` stays because it models runtime observation, not close
  ownership.
- outward `lifecycle_state` payload compatibility is preserved as a derived
  projection instead of a persisted column.
