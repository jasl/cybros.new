# Core Matrix Task 09.3: Add Model Selector Resolution

Part of `Core Matrix Kernel Milestone 3: Conversation And Runtime`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-milestone-3-conversation-and-runtime.md`
5. `docs/design/2026-03-24-core-matrix-model-role-resolution-design.md`

Load this file as the detailed execution unit for Task 09.3. Treat Task Group 09 and the milestone file as ordering indexes, not as the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the consulted slice and the retained conclusion, invariant, or intentional difference in this task document or another local document updated by the same execution unit
- when this task updates behavior docs, checklist docs, or other local docs, carry that conclusion into those docs instead of leaving only a bare reference path
- keep reference paths as index pointers only; restate the relevant behavior locally so this task remains understandable if the reference later drifts

---

**Files:**
- Create: `core_matrix/app/services/workflows/resolve_model_selector.rb`
- Create: `core_matrix/test/services/workflows/resolve_model_selector_test.rb`
- Create: `core_matrix/test/integration/workflow_selector_flow_test.rb`
- Modify: `core_matrix/app/models/turn.rb`
- Modify: `core_matrix/app/models/workflow_run.rb`
- Modify: `core_matrix/app/services/workflows/create_for_turn.rb`
- Modify: `core_matrix/test/models/turn_test.rb`
- Modify: `core_matrix/test/models/workflow_run_test.rb`
- Modify: `core_matrix/test/services/workflows/create_for_turn_test.rb`

**Step 1: Write failing service and integration tests**

Cover at least:

- selector normalization to `role:*` and `candidate:*`
- the reserved interactive path falling back to `role:main` when no more specific selector is present
- role-local fallback only within the current role's ordered candidate list
- explicit candidate selection rejecting fallback to unrelated models
- execution-time entitlement reservation causing fallback only to the next candidate in the same role list
- resolved model-selection snapshot fields frozen on the executing turn, with optional denormalized references on `WorkflowRun`

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/turn_test.rb test/models/workflow_run_test.rb test/services/workflows/create_for_turn_test.rb test/services/workflows/resolve_model_selector_test.rb test/integration/workflow_selector_flow_test.rb
```

Expected:

- missing service or selector-resolution failures

**Step 3: Implement selector resolution**

Rules:

- model selection must resolve through the explicit service boundary `workflows/resolve_model_selector`
- model selectors must normalize to `role:*` or `candidate:*`
- the reserved interactive path should fall back to `role:main`
- fallback is only allowed inside the ordered candidate list of the selected role
- execution-time entitlement reservation must happen before finalizing the selected candidate on the snapshot
- explicit candidate selection must fail immediately when unavailable instead of guessing another model
- resolved model snapshots should retain selector source, normalized selector, resolved provider, resolved model, resolution reason, and fallback count

**Step 4: Run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails test test/models/turn_test.rb test/models/workflow_run_test.rb test/services/workflows/create_for_turn_test.rb test/services/workflows/resolve_model_selector_test.rb test/integration/workflow_selector_flow_test.rb
```

Expected:

- targeted tests pass

**Step 5: Commit**

```bash
git -C .. add core_matrix/app/models/turn.rb core_matrix/app/models/workflow_run.rb core_matrix/app/services/workflows/resolve_model_selector.rb core_matrix/app/services/workflows/create_for_turn.rb core_matrix/test/models core_matrix/test/services core_matrix/test/integration
git -C .. commit -m "feat: add workflow model selector resolution"
```

## Stop Point

Stop after selector normalization, fallback, and snapshot freezing pass their tests.

Do not implement these items in this task:

- context assembly
- runtime attachment manifests
- transcript or publication APIs

## Completion Record

- status:
  completed on `2026-03-25`
- landing commit:
  - included in the accompanying `feat: add workflow model selector resolution`
    task commit
- actual landed scope:
  - added `Workflows::ResolveModelSelector` as the explicit service boundary for
    selector normalization, provider-catalog expansion, provider-policy checks,
    active-entitlement checks, and role-local fallback
  - updated `Workflows::CreateForTurn` so model selector resolution is frozen on
    the turn before the workflow run and root node are created
  - extended `Turn` with read-through selector helper methods and extended
    `WorkflowRun` with delegated selector helpers sourced from the owning turn
  - added targeted model, service, and integration coverage for normalization,
    role-local reservation fallback, explicit-candidate failure, specialized
    role exhaustion, frozen turn snapshots, workflow-run read-through helpers,
    and missing active capability snapshots
  - added `core_matrix/docs/behavior/workflow-model-selector-resolution.md`
- plan alignment notes:
  - canonical execution selector state is now frozen on `Turn`, with
    `WorkflowRun` exposing read-only denormalized helpers instead of a second
    persisted selector store
  - selector normalization remains bounded to `role:*` and `candidate:*`
  - fallback stays inside the currently selected role list and never guesses a
    different role or unrelated model
  - resolution now requires an active capability snapshot so historical
    executions keep a pinned runtime-capability reference
- verification evidence:
  - `cd core_matrix && bin/rails test test/models/turn_test.rb test/models/workflow_run_test.rb test/services/workflows/create_for_turn_test.rb test/services/workflows/resolve_model_selector_test.rb test/integration/workflow_selector_flow_test.rb`
    passed with `14 runs, 65 assertions, 0 failures, 0 errors`
- checklist notes:
  - no manual-checklist delta was retained for this task because the landed
    behavior is execution-selector normalization and snapshot infrastructure
    covered by automated tests
- retained findings:
  - selector-resolution failure should stop at the `Turn` service boundary with
    `ActiveRecord::RecordInvalid` instead of leaking catalog or lookup errors
  - workflow execution cannot freeze a historically meaningful selector
    snapshot without an active capability snapshot, so that requirement is now
    enforced explicitly
  - `WorkflowRun` did not need its own selector columns for this task; turn
    snapshot delegation was sufficient and kept schema scope aligned with the
    design's “optional denormalized references” language
  - Dify was useful as a sanity check for validating an exact provider-model
    choice separately from runtime credential state, but Core Matrix keeps the
    stronger local invariant that fallback is role-local only
- carry-forward notes:
  - Task 09.4 should consume the frozen turn selector snapshot as the canonical
    provider-model choice when building runtime attachment manifests
  - later runtime and audit tasks should continue recording selector-derived
    facts from the pinned turn snapshot instead of recomputing against mutable
    current catalog state
