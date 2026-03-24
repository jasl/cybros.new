# Core Matrix Task 11.4: Add Bootstrap And Recovery Flows

Part of `Core Matrix Kernel Milestone 4: Protocol, Publication, And Verification`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/finished-plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/finished-plans/2026-03-24-core-matrix-kernel-milestone-4-protocol-publication-and-verification.md`
5. `docs/design/2026-03-24-core-matrix-model-role-resolution-design.md`
6. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

Load this file as the detailed execution unit for Task 11.4. Treat Task Group 11 and the milestone file as ordering indexes, not as the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the consulted slice and the retained conclusion, invariant, or intentional difference in this task document or another local document updated by the same execution unit
- when this task updates behavior docs, checklist docs, or other local docs, carry that conclusion into those docs instead of leaving only a bare reference path
- keep reference paths as index pointers only; restate the relevant behavior locally so this task remains understandable if the reference later drifts

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

Do not implement these items in this task:

- publication read models
- schedule-trigger or webhook-ingress controllers
- changes that mutate durable selector config during manual recovery

## Completion Record

- status:
  completed on `2026-03-25`
- landing commit:
  - `0b11a4c` `feat: add deployment recovery and manual resume flows`
- actual landed scope:
  - added `AgentDeployments::Bootstrap`, `MarkUnavailable`, and
    `AutoResumeWorkflows`
  - added `Workflows::ManualResume` and `ManualRetry`
  - added the manual dummy runtime used to exercise enrollment, heartbeat,
    health, and recovery paths against a live server
  - extended deployment, turn, and workflow-run state so paused recovery,
    compatibility checks, and one-time selector overrides remain explicit
  - updated the manual checklist for bootstrap, outage, manual resume, and
    manual retry validation
  - added
    `core_matrix/docs/behavior/deployment-bootstrap-and-recovery-flows.md`
- plan alignment notes:
  - drift now blocks silent continuation and requires either explicit manual
    resume or explicit manual retry
  - one-time selector overrides apply only to the recovery action and do not
    mutate durable conversation selector config or deployment slot defaults
  - manual retry preserves the paused workflow run as historical state before
    starting a fresh execution path
- verification evidence:
  - `cd core_matrix && bin/rails test test/services/agent_deployments/bootstrap_test.rb test/services/agent_deployments/mark_unavailable_test.rb test/services/agent_deployments/auto_resume_workflows_test.rb test/services/workflows/manual_resume_test.rb test/services/workflows/manual_retry_test.rb test/integration/agent_recovery_flow_test.rb`
    passed with `11 runs, 93 assertions, 0 failures, 0 errors`
- checklist notes:
  - the final `2026-03-25` live rerun in Task 12.3 kept these recovery steps
    and tightened the dummy runtime register flow to require
    `CORE_MATRIX_EXECUTION_ENVIRONMENT_ID`
- retained findings:
  - auto-resume is only safe when the deployment fingerprint and capability
    version still match the paused workflow expectations
  - recovery override handling stays tractable when expressed as workflow-run
    recovery input rather than a persistent configuration mutation
- carry-forward notes:
  - future operator-facing recovery surfaces should call these services instead
    of embedding compatibility logic in controllers or UI code
  - later external runtime adapters should preserve the same pause, drift, and
    explicit-recovery semantics rather than inventing adapter-local state
