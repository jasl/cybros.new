# Core Matrix Phase 2 Task: Prove External Fenix Pairing And Deployment Rotation

Part of `Core Matrix Phase 2: Agent Loop Execution`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/research-notes/2026-03-25-fenix-deployment-rotation-and-discourse-operations-research-note.md`
3. `docs/future-plans/2026-03-25-core-matrix-phase-2-milestone-agent-loop-execution.md`
4. `docs/future-plans/2026-03-25-core-matrix-phase-2-task-agent-task-run-and-execution-contract-safety.md`
5. `docs/future-plans/2026-03-25-core-matrix-phase-2-task-fenix-runtime-surface-and-execution-hooks.md`
6. `docs/future-plans/2026-03-25-core-matrix-phase-2-task-provider-backed-turn-execution.md`

Load this file as the detailed external-runtime validation unit for Phase 2.
Treat the milestone and preceding contract/runtime documents as ordering
indexes, not as the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the
  consulted slice and the retained conclusion, invariant, or intentional
  difference in this task document or another local document updated by the
  same execution unit
- when this task updates behavior docs, checklist docs, or other local docs,
  carry that conclusion into those docs instead of leaving only a bare
  reference path
- keep reference paths as index pointers only; restate the relevant behavior
  locally so this task remains understandable if the reference later drifts

---

**Files:**
- Modify: `core_matrix/app/services/agent_deployments/register.rb`
- Modify: `core_matrix/app/services/agent_deployments/record_heartbeat.rb`
- Modify: `core_matrix/app/services/agent_deployments/bootstrap.rb`
- Modify: `core_matrix/app/services/agent_deployments/mark_unavailable.rb`
- Modify: `core_matrix/app/services/agent_deployments/auto_resume_workflows.rb`
- Modify: `core_matrix/app/services/workflows/manual_resume.rb`
- Modify: `core_matrix/app/services/workflows/manual_retry.rb`
- Modify: `agents/fenix/README.md`
- Likely create or modify: `agents/fenix/app/services/fenix/runtime/*`
- Create or modify: `core_matrix/test/services/agent_deployments/*`
- Create or modify: `core_matrix/test/integration/external_fenix_pairing_flow_test.rb`
- Create or modify: `agents/fenix/test/integration/external_runtime_pairing_test.rb`
- Modify: `core_matrix/docs/behavior/deployment-bootstrap-and-recovery-flows.md`
- Modify: `core_matrix/docs/behavior/agent-registry-and-connectivity-foundations.md`

**Step 1: Write failing service and integration tests**

Cover at least:

- external `Fenix` enrollment and pairing
- heartbeat and health handling without kernel-initiated callbacks
- same-installation deployment cutover
- upgrade rotation
- downgrade rotation
- manual resume or retry behavior after rotation

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/services/agent_deployments test/integration/external_fenix_pairing_flow_test.rb
cd ../agents/fenix
bin/rails test test/integration/external_runtime_pairing_test.rb
```

Expected:

- missing pairing, heartbeat, or rotation failures

**Step 3: Implement external pairing and deployment rotation**

Rules:

- breaking changes are allowed in Phase 2
- Core Matrix must not need to dial private runtime addresses during normal
  execution delivery
- deployment rotation is the upgrade and downgrade model
- do not build an in-place updater
- if a new `Fenix` release cannot boot, treat that as an agent-program release
  failure, not a kernel recovery obligation

**Step 4: Update local behavior docs**

Document exact retained behavior for:

- pairing flow
- heartbeat and availability
- deployment rotation across upgrade or downgrade
- recovery expectations around release change

**Step 5: Run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails test test/services/agent_deployments test/integration/external_fenix_pairing_flow_test.rb
cd ../agents/fenix
bin/rails test test/integration/external_runtime_pairing_test.rb
```

Expected:

- targeted external-runtime tests pass

**Step 6: Run real pairing validation**

Validate with:

- bundled `Fenix`
- one independent external `Fenix`
- one same-installation second deployment for cutover

Expected:

- pairing succeeds
- rotation across upgrade and downgrade succeeds
- workflow recovery remains stable

**Step 7: Commit**

```bash
git -C .. add core_matrix/app/services/agent_deployments core_matrix/app/services/workflows/manual_resume.rb core_matrix/app/services/workflows/manual_retry.rb agents/fenix/README.md agents/fenix/app/services/fenix/runtime core_matrix/test/services/agent_deployments core_matrix/test/integration/external_fenix_pairing_flow_test.rb agents/fenix/test/integration/external_runtime_pairing_test.rb core_matrix/docs/behavior/deployment-bootstrap-and-recovery-flows.md core_matrix/docs/behavior/agent-registry-and-connectivity-foundations.md
git -C .. commit -m "feat: add fenix deployment rotation"
```

## Stop Point

Stop after external pairing and same-installation deployment rotation are real
and validated.

Do not implement these items in this task:

- skill installation
- plugin or extension systems
- Web UI productization
