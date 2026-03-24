# Core Matrix Task 04.2: Add Bundled Default-Agent Bootstrap

Part of `Core Matrix Kernel Phase 1: Foundations`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-phase-1-foundations.md`
5. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

Load this file as the detailed execution unit for Task 04.2. Treat Task 04 and the phase file as ordering indexes, not as the full task body.

---

**Files:**
- Create: `core_matrix/app/services/installations/register_bundled_agent_runtime.rb`
- Create: `core_matrix/app/services/installations/bootstrap_bundled_agent_binding.rb`
- Create: `core_matrix/test/services/installations/register_bundled_agent_runtime_test.rb`
- Create: `core_matrix/test/services/installations/bootstrap_bundled_agent_binding_test.rb`
- Create: `core_matrix/test/integration/bundled_default_agent_bootstrap_flow_test.rb`
- Modify: `core_matrix/app/services/installations/bootstrap_first_admin.rb`
- Modify: `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

**Step 1: Write failing service and integration tests**

Cover at least:

- bundled runtime registration reconciles registry rows before binding
- bundled runtime registration is idempotent and must not duplicate logical or deployment rows
- bundled-agent bootstrap only runs when explicitly configured
- first-admin bootstrap auto-binds the bundled agent only after registry reconciliation
- first-admin bootstrap creates the default workspace through existing workspace services

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/services/installations/register_bundled_agent_runtime_test.rb test/services/installations/bootstrap_bundled_agent_binding_test.rb test/integration/bundled_default_agent_bootstrap_flow_test.rb
```

Expected:

- failures for missing services or missing bootstrap behavior

**Step 3: Implement bundled bootstrap behavior**

Rules:

- bundled runtime registration must reconcile `AgentInstallation`, `ExecutionEnvironment`, and `AgentDeployment` before user binding
- bundled bootstrap must compose existing binding and workspace services rather than duplicating their rules
- first-admin bootstrap must stay opt-in through configuration
- keep bundled bootstrap scoped to the one packaged runtime and do not widen this into a generic connector or bridge layer
- update the manual checklist for the reproducible bundled-bootstrap flow

**Step 4: Run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails test test/services/installations/register_bundled_agent_runtime_test.rb test/services/installations/bootstrap_bundled_agent_binding_test.rb test/integration/bundled_default_agent_bootstrap_flow_test.rb
```

Expected:

- targeted tests pass

**Step 5: Commit**

```bash
git -C .. add core_matrix/app/services/installations core_matrix/test/services core_matrix/test/integration docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md
git -C .. commit -m "feat: add bundled default agent bootstrap"
```

## Stop Point

Stop after bundled runtime reconciliation and bundled first-admin bootstrap pass their tests.

Do not implement these items in this subtask:

- generic multi-agent bootstrap
- human-facing setup flows
- any schedule, webhook, or IM integration behavior
