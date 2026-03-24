# Core Matrix Task 11.4: Add Bootstrap And Recovery Flows

Part of `Core Matrix Kernel Phase 4: Protocol, Publication, And Verification`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-phase-4-protocol-publication-and-verification.md`
5. `docs/design/2026-03-24-core-matrix-model-role-resolution-design.md`
6. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

Load this file as the detailed execution unit for Task 11.4. Treat Task 11 and the phase file as ordering indexes, not as the full task body.

---

**Files:**
- Create: `core_matrix/app/services/agent_deployments/bootstrap.rb`
- Create: `core_matrix/app/services/agent_deployments/mark_unavailable.rb`
- Create: `core_matrix/app/services/agent_deployments/auto_resume_workflows.rb`
- Create: `core_matrix/app/services/workflows/manual_resume.rb`
- Create: `core_matrix/app/services/workflows/manual_retry.rb`
- Create: `core_matrix/script/manual/dummy_agent_runtime.rb`
- Create: `core_matrix/test/services/agent_deployments/bootstrap_test.rb`
- Create: `core_matrix/test/services/agent_deployments/mark_unavailable_test.rb`
- Create: `core_matrix/test/services/agent_deployments/auto_resume_workflows_test.rb`
- Create: `core_matrix/test/services/workflows/manual_resume_test.rb`
- Create: `core_matrix/test/services/workflows/manual_retry_test.rb`
- Create: `core_matrix/test/integration/agent_recovery_flow_test.rb`
- Modify: `core_matrix/app/models/agent_deployment.rb`
- Modify: `core_matrix/app/models/turn.rb`
- Modify: `core_matrix/app/models/workflow_run.rb`
- Modify: `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

**Step 1: Write failing service and integration tests**

Cover at least:

- bootstrap creating a system-owned run or workflow record
- transient outage marking work waiting
- prolonged outage pausing work
- auto-resume only when fingerprint and capabilities version did not drift
- drift requiring explicit manual resume or manual retry before work continues
- allowing one-time `role:*` or explicit-candidate overrides during manual recovery without mutating durable conversation or deployment config
- manual resume rejected when logical-agent, capability, or pinned-config compatibility checks fail
- manual retry preserving the paused run as history while starting a fresh workflow from the last stable selected input
- audit rows for bootstrap, degradation, paused-agent-unavailable transition, and explicit recovery decisions

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/services/agent_deployments/bootstrap_test.rb test/services/agent_deployments/mark_unavailable_test.rb test/services/agent_deployments/auto_resume_workflows_test.rb test/services/workflows/manual_resume_test.rb test/services/workflows/manual_retry_test.rb test/integration/agent_recovery_flow_test.rb
```

Expected:

- missing service or recovery-flow failures

**Step 3: Implement bootstrap and recovery flows**

Rules:

- drift blocks silent continuation
- explicit manual resume or manual retry is required after drift before paused work can continue
- manual resume is only allowed when the replacement deployment satisfies same-logical-agent and required-capability compatibility
- manual retry must preserve the paused workflow as historical state and create a fresh execution path
- manual recovery may accept a one-time selector override, but it must not mutate the persisted conversation selector or deployment slot config
- bootstrap, outage-state transitions, and manual recovery decisions must produce audit records
- update the manual checklist and dummy runtime so the documented flow can be reproduced end to end

**Step 4: Run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails test test/services/agent_deployments/bootstrap_test.rb test/services/agent_deployments/mark_unavailable_test.rb test/services/agent_deployments/auto_resume_workflows_test.rb test/services/workflows/manual_resume_test.rb test/services/workflows/manual_retry_test.rb test/integration/agent_recovery_flow_test.rb
```

Expected:

- targeted tests pass

**Step 5: Commit**

```bash
git -C .. add core_matrix/app/models/agent_deployment.rb core_matrix/app/models/turn.rb core_matrix/app/models/workflow_run.rb core_matrix/app/services/agent_deployments core_matrix/app/services/workflows core_matrix/script/manual/dummy_agent_runtime.rb core_matrix/test/services core_matrix/test/integration docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md
git -C .. commit -m "feat: add deployment recovery and manual resume flows"
```

## Stop Point

Stop after bootstrap, outage handling, auto-resume, manual resume, and manual retry pass their tests.

Do not implement these items in this subtask:

- publication read models
- schedule-trigger or webhook-ingress controllers
- changes that mutate durable selector config during manual recovery
