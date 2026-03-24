# Core Matrix Task 10.3: Add Canonical Variables

Part of `Core Matrix Kernel Milestone 3: Conversation And Runtime`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-milestone-3-conversation-and-runtime.md`

Load this file as the detailed execution unit for Task 10.3. Treat Task Group 10 and the milestone file as ordering indexes, not as the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the consulted slice and the retained conclusion, invariant, or intentional difference in this task document or another local document updated by the same execution unit
- when this task updates behavior docs, checklist docs, or other local docs, carry that conclusion into those docs instead of leaving only a bare reference path
- keep reference paths as index pointers only; restate the relevant behavior locally so this task remains understandable if the reference later drifts

---

**Files:**
- Create: `core_matrix/db/migrate/20260324090036_create_canonical_variables.rb`
- Create: `core_matrix/app/models/canonical_variable.rb`
- Create: `core_matrix/app/services/variables/write.rb`
- Create: `core_matrix/app/services/variables/promote_to_workspace.rb`
- Create: `core_matrix/test/models/canonical_variable_test.rb`
- Create: `core_matrix/test/services/variables/write_test.rb`
- Create: `core_matrix/test/services/variables/promote_to_workspace_test.rb`
- Create: `core_matrix/test/integration/canonical_variable_flow_test.rb`

**Step 1: Write failing model, service, and integration tests**

Cover at least:

- canonical variable scope rules for `workspace` and `conversation`
- canonical variable supersession history
- explicit promotion from conversation to workspace
- preserved history when a current value is superseded

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/canonical_variable_test.rb test/services/variables/write_test.rb test/services/variables/promote_to_workspace_test.rb test/integration/canonical_variable_flow_test.rb
```

Expected:

- missing table and model failures

**Step 3: Write migration, model, and services**

Rules:

- canonical variables must support only `workspace` and `conversation` scope in v1
- canonical variable writes supersede prior current values without deleting history
- conversation-scope canonical values may be explicitly promoted to workspace scope
- keep write and promotion semantics in kernel-owned services rather than direct model mutation from callers

**Step 4: Run migrations and targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/canonical_variable_test.rb test/services/variables/write_test.rb test/services/variables/promote_to_workspace_test.rb test/integration/canonical_variable_flow_test.rb
```

Expected:

- targeted tests pass

**Step 5: Commit**

```bash
git -C .. add core_matrix/db/migrate core_matrix/app/models/canonical_variable.rb core_matrix/app/services/variables core_matrix/test/models core_matrix/test/services core_matrix/test/integration core_matrix/db/schema.rb
git -C .. commit -m "feat: add canonical variable history"
```

## Stop Point

Stop after canonical variable write and promotion semantics pass their tests.

Do not implement these items in this task:

- machine-facing variable APIs
- publication read models
- any additional scope beyond `workspace` and `conversation`

## Completion Record

- status:
  completed on `2026-03-25`
- landing commit:
  - included in the accompanying `feat: add canonical variable history` task
    commit
- actual landed scope:
  - added `CanonicalVariable` as a durable history row with explicit scope,
    typed payload, writer identity, source metadata, projection policy, and
    supersession linkage
  - added `Variables::Write` as the kernel-owned write boundary for current-row
    supersession without history deletion
  - added `Variables::PromoteToWorkspace` as the explicit conversation-to-
    workspace promotion boundary
  - added `CanonicalVariable.effective_for` for the v1
    `conversation > workspace` precedence rule used by tests and follow-up work
  - added targeted model, service, and integration coverage for scope legality,
    supersession history retention, explicit promotion, and effective lookup
  - added
    `core_matrix/docs/behavior/canonical-variable-history-and-promotion.md`
- plan alignment notes:
  - canonical values remain restricted to `workspace` and `conversation` scope
    in v1
  - new accepted values supersede earlier current values instead of mutating or
    deleting them in place
  - promotion is explicit and creates a new workspace-scoped durable row; it
    does not rewrite the conversation-scoped source row
  - projection policy is now persisted on canonical writes without pre-
    implementing the later read-model or projection API layer
- verification evidence:
  - `cd core_matrix && bin/rails test test/models/canonical_variable_test.rb test/services/variables/write_test.rb test/services/variables/promote_to_workspace_test.rb test/integration/canonical_variable_flow_test.rb`
    passed with `4 runs, 31 assertions, 0 failures, 0 errors`
  - `cd core_matrix && bin/rails test test/services/variables test/services/human_interactions test/services/conversation_events test/services/processes test/services/workflows test/integration/canonical_variable_flow_test.rb test/integration/human_interaction_flow_test.rb test/integration/workflow_graph_flow_test.rb test/integration/workflow_scheduler_flow_test.rb test/integration/workflow_selector_flow_test.rb test/integration/workflow_context_flow_test.rb test/integration/runtime_process_flow_test.rb test/models/canonical_variable_test.rb test/models/human_interaction_request_test.rb test/models/approval_request_test.rb test/models/human_form_request_test.rb test/models/human_task_request_test.rb test/models/conversation_event_test.rb test/models/process_run_test.rb test/models/workflow_artifact_test.rb test/models/workflow_node_event_test.rb test/models/workflow_run_test.rb test/models/turn_test.rb`
    passed with `50 runs, 291 assertions, 0 failures, 0 errors`
- checklist notes:
  - no manual-checklist delta was retained for this task because the landed
    behavior is canonical history and supersession semantics covered by
    automated tests
- retained findings:
  - supersession needed to be handled in the write service rather than through a
    direct insert-then-update pattern because the partial current-value unique
    indexes would otherwise reject concurrent current rows
  - a simple `effective_for` helper was enough to preserve the design's
    `conversation > workspace` precedence rule without prebuilding the later
    machine-facing variable API
  - Dify was useful only as a narrow sanity check for keeping conversation
    variables in a distinct scope space; Core Matrix intentionally keeps the
    stronger contract of explicit scope plus durable history
- carry-forward notes:
  - later variable APIs should resolve from the durable canonical store instead
    of bypassing it with raw process-local caches
  - future projection work may choose to emit `ConversationEvent` rows for
    user-significant canonical changes based on the persisted `projection_policy`
    rather than ad hoc caller behavior
