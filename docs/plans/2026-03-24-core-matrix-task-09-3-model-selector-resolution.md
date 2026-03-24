# Core Matrix Task 09.3: Add Model Selector Resolution

Part of `Core Matrix Kernel Phase 3: Conversation And Runtime`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-phase-3-conversation-and-runtime.md`
5. `docs/design/2026-03-24-core-matrix-model-role-resolution-design.md`

Load this file as the detailed execution unit for Task 09.3. Treat Task 09 and the phase file as ordering indexes, not as the full task body.

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

Do not implement these items in this subtask:

- context assembly
- runtime attachment manifests
- transcript or publication APIs
