# Core Matrix Phase 2 Task 03: Add AgentTaskRun And Execution Contract Safety

Part of `Core Matrix Phase 2 Milestone 1: Kernel Execution Foundations`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-25-core-matrix-agent-execution-delivery-contract-design.md`
3. `docs/plans/2026-03-25-core-matrix-phase-2-milestone-1-kernel-execution-foundations.md`
4. `docs/design/2026-03-25-core-matrix-workflow-yield-and-intent-batch-design.md`

Load this file as the detailed execution unit for Task 03. Treat the milestone
file as the ordering index, not as the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the
  consulted source section and the retained conclusion, invariant, or
  intentional difference in this task document or another local document
  updated by the same execution unit
- when this task updates behavior docs, checklist docs, or other local docs,
  carry that conclusion into those docs instead of leaving only a bare
  reference path
- keep reference paths as index pointers only; restate the relevant behavior
  locally so this task remains understandable if the reference later drifts

---

**Files:**
- Create: `core_matrix/app/models/agent_task_run.rb`
- Likely create: `core_matrix/app/controllers/agent_api/executions_controller.rb`
- Likely create: `core_matrix/app/services/agent_tasks/*`
- Likely create: `core_matrix/app/serializers/agent_api/execution_*`
- Modify: `core_matrix/app/models/execution_lease.rb`
- Modify: `core_matrix/app/models/workflow_run.rb`
- Modify: `core_matrix/app/models/workflow_node.rb`
- Modify: `core_matrix/app/models/agent_deployment.rb`
- Modify: `core_matrix/config/routes.rb`
- Create: `core_matrix/test/models/agent_task_run_test.rb`
- Create: `core_matrix/test/requests/agent_api/executions_claim_test.rb`
- Create: `core_matrix/test/requests/agent_api/executions_heartbeat_test.rb`
- Create: `core_matrix/test/requests/agent_api/executions_progress_test.rb`
- Create: `core_matrix/test/requests/agent_api/executions_complete_test.rb`
- Create: `core_matrix/test/requests/agent_api/executions_fail_test.rb`
- Likely create: `core_matrix/test/services/agent_tasks/*`
- Modify: `core_matrix/test/services/leases/*`
- Likely create: `core_matrix/test/integration/agent_execution_claim_flow_test.rb`
- Modify: `core_matrix/docs/behavior/agent-runtime-resource-apis.md`
- Modify: `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
- Modify: `core_matrix/docs/behavior/workflow-artifacts-node-events-and-process-runs.md`

**Step 1: Write failing model, request, service, and integration tests**

Cover at least:

- `AgentTaskRun` ownership and lifecycle
- `execution_claim` creating or acquiring a single-owner execution lease
- stale-lease rejection
- duplicate terminal delivery idempotency
- out-of-order progress handling
- bounded fast-terminal behavior with
  `execution_claim -> execution_complete`
- competing claim attempts for the same execution

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/agent_task_run_test.rb test/requests/agent_api/executions_claim_test.rb test/requests/agent_api/executions_heartbeat_test.rb test/requests/agent_api/executions_progress_test.rb test/requests/agent_api/executions_complete_test.rb test/requests/agent_api/executions_fail_test.rb test/services/agent_tasks test/services/leases test/integration/agent_execution_claim_flow_test.rb
```

Expected:

- missing model, controller, route, or lease-flow failures

**Step 3: Implement `AgentTaskRun` and the `execution_*` contract**

Rules:

- `WorkflowRun` must not become the claimable execution object
- `AgentTaskRun` stays workflow-owned and audit-friendly
- `execution_claim` may support bounded `wait_ms`, but there is no separate
  claimless API
- competing claims inherit `ExecutionLease` single-owner semantics
- breaking changes are allowed in Phase 2

**Step 4: Update local behavior docs**

Document exact retained behavior for:

- `AgentTaskRun` as a workflow-owned runtime resource
- `execution_*` request semantics
- fast-terminal handling
- duplicate, stale, and out-of-order delivery rules

**Step 5: Run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails test test/models/agent_task_run_test.rb test/requests/agent_api/executions_claim_test.rb test/requests/agent_api/executions_heartbeat_test.rb test/requests/agent_api/executions_progress_test.rb test/requests/agent_api/executions_complete_test.rb test/requests/agent_api/executions_fail_test.rb test/services/agent_tasks test/services/leases test/integration/agent_execution_claim_flow_test.rb
```

Expected:

- targeted execution-contract tests pass

**Step 6: Commit**

```bash
git -C .. add core_matrix/app/models/agent_task_run.rb core_matrix/app/controllers/agent_api/executions_controller.rb core_matrix/app/services/agent_tasks core_matrix/app/models/execution_lease.rb core_matrix/app/models/workflow_run.rb core_matrix/app/models/workflow_node.rb core_matrix/app/models/agent_deployment.rb core_matrix/config/routes.rb core_matrix/test/models/agent_task_run_test.rb core_matrix/test/requests/agent_api core_matrix/test/services/agent_tasks core_matrix/test/services/leases core_matrix/test/integration/agent_execution_claim_flow_test.rb core_matrix/docs/behavior/agent-runtime-resource-apis.md core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md core_matrix/docs/behavior/workflow-artifacts-node-events-and-process-runs.md
git -C .. commit -m "feat: add agent task execution contract"
```

## Stop Point

Stop after `AgentTaskRun` and the `execution_*` surface pass their targeted
tests.

Do not implement provider execution, feature policy, or MCP in this task.
