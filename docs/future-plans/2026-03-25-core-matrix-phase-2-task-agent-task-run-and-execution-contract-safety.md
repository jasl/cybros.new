# Core Matrix Phase 2 Task: Add AgentTaskRun And Execution Contract Safety

Part of `Core Matrix Phase 2: Agent Loop Execution`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-25-core-matrix-agent-execution-delivery-contract-design.md`
3. `docs/future-plans/2026-03-25-core-matrix-phase-2-milestone-agent-loop-execution.md`
4. `docs/future-plans/2026-03-25-core-matrix-phase-2-agent-loop-execution-initial-plan.md`
5. `docs/future-plans/2026-03-25-core-matrix-phase-2-task-group-kernel-first-sequencing.md`
6. `docs/future-plans/2026-03-25-core-matrix-phase-2-activation-checklist.md`

Load this file as the detailed execution unit for the first kernel-owned Slice A
inside Phase 2. Treat the milestone file, the task-group file, and the initial
plan as ordering indexes, not as the full task body.

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

- `AgentTaskRun` ownership and lifecycle:
  - installation
  - workflow run
  - workflow node
  - useful redundant conversation or turn ownership
  - `queued`, `running`, `waiting`, `completed`, `failed`, `canceled`
- `execution_claim` creating or acquiring a single-owner execution lease
- stale-lease rejection
- duplicate terminal delivery idempotency
- out-of-order progress handling
- bounded fast-terminal behavior with
  `execution_claim -> execution_complete` and no intermediate heartbeat
- competing claim attempts for the same execution
- stable request or response shape for:
  - `execution_claim`
  - `execution_lease_heartbeat`
  - `execution_progress`
  - `execution_complete`
  - `execution_fail`

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/agent_task_run_test.rb test/requests/agent_api/executions_claim_test.rb test/requests/agent_api/executions_heartbeat_test.rb test/requests/agent_api/executions_progress_test.rb test/requests/agent_api/executions_complete_test.rb test/requests/agent_api/executions_fail_test.rb test/services/agent_tasks test/services/leases test/integration/agent_execution_claim_flow_test.rb
```

Expected:

- missing model, controller, route, or lease-flow failures

**Step 3: Implement `AgentTaskRun` as the claimable runtime resource**

Rules:

- `Core Matrix` must not expose `WorkflowRun` directly as the claimable
  execution object
- `AgentTaskRun` is the claimable runtime resource for Phase 2
- `AgentTaskRun` stays workflow-owned and audit-friendly
- lease ownership remains explicit through `ExecutionLease`
- the model should support durable attempt and result state without forcing
  every micro-stage into its own runtime resource

**Step 4: Implement the `execution_*` request surface**

Rules:

- canonical method family:
  - `execution_claim`
  - `execution_lease_heartbeat`
  - `execution_progress`
  - `execution_complete`
  - `execution_fail`
- keep the surface transport-neutral even if later accelerators exist
- `execution_claim` may support bounded `wait_ms`, but it does not become a
  claimless protocol
- fast terminal paths must still preserve durable claim semantics
- request handlers should stay thin and delegate lease, progress, and terminal
  rules into application services

**Step 5: Implement lease-safety and delivery-safety rules**

Rules:

- `execution_claim` must inherit `ExecutionLease` single-owner semantics
- a competing active claim must be rejected cleanly
- stale leases may only be replaced through the normal stale-lease path
- duplicate terminal delivery must be idempotent
- late terminal reports from stale or superseded leases must be rejected
- out-of-order progress must not corrupt durable execution history
- this task should prove durable control-surface safety before any broader
  provider or tool execution breadth is introduced

**Step 6: Update local behavior docs**

Document exact retained behavior for:

- `AgentTaskRun` as a workflow-owned runtime resource
- `execution_*` request semantics
- fast-terminal handling without a second claimless API
- single-owner lease behavior under competing claims
- duplicate, stale, and out-of-order delivery handling

Keep the durable execution story local in the behavior docs instead of relying
on the design note alone.

**Step 7: Run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails test test/models/agent_task_run_test.rb test/requests/agent_api/executions_claim_test.rb test/requests/agent_api/executions_heartbeat_test.rb test/requests/agent_api/executions_progress_test.rb test/requests/agent_api/executions_complete_test.rb test/requests/agent_api/executions_fail_test.rb test/services/agent_tasks test/services/leases test/integration/agent_execution_claim_flow_test.rb
```

Expected:

- targeted Slice A tests pass

**Step 8: Commit**

```bash
git -C .. add core_matrix/app/models/agent_task_run.rb core_matrix/app/controllers/agent_api/executions_controller.rb core_matrix/app/services/agent_tasks core_matrix/app/models/execution_lease.rb core_matrix/app/models/workflow_run.rb core_matrix/app/models/workflow_node.rb core_matrix/app/models/agent_deployment.rb core_matrix/config/routes.rb core_matrix/test/models/agent_task_run_test.rb core_matrix/test/requests/agent_api core_matrix/test/services/agent_tasks core_matrix/test/services/leases core_matrix/test/integration/agent_execution_claim_flow_test.rb core_matrix/docs/behavior/agent-runtime-resource-apis.md core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md core_matrix/docs/behavior/workflow-artifacts-node-events-and-process-runs.md
git -C .. commit -m "feat: add agent task execution contract"
```

## Stop Point

Stop after `AgentTaskRun`, the `execution_*` request surface, and lease-safety
rules pass their targeted tests.

Do not implement these items in this task:

- provider-backed turn execution
- MCP transport
- broad tool governance
- human-interaction wait handoff
- subagent orchestration
- workflow proof export
