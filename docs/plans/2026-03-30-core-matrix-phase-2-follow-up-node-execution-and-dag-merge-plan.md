# Core Matrix Phase 2 Follow-Up Node Execution And DAG Merge Plan

> **For Codex:** REQUIRED SUB-SKILL: Use [$executing-plans](/Users/jasl/.codex/skills/executing-plans/SKILL.md) to implement this plan task-by-task.

**Goal:** Replace the remaining sequential-execution assumptions with durable `WorkflowNode`-scoped async execution and DAG merge semantics so Phase 2 can be accepted.

**Architecture:** `WorkflowNode` becomes the one-shot async scheduling unit for one `WorkflowRun`. `WorkflowEdge` carries only `requirement = required | optional` in the first pass; the scheduler becomes DB-backed and dispatches one job per runnable node while preserving the existing wait-state and mailbox/subagent boundaries instead of wrapping a whole workflow run in one job.

**Tech Stack:** Ruby on Rails, Active Record, ActiveJob, PostgreSQL, Minitest, existing mailbox/runtime protocol between `core_matrix` and `agents/fenix`

---

## Required Inputs

- `AGENTS.md`
- `core_matrix/docs/behavior/workflow-graph-foundations.md`
- `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
- `docs/design/2026-03-25-core-matrix-workflow-yield-and-intent-batch-design.md`
- `docs/design/2026-03-30-core-matrix-phase-2-sequential-execution-design.md`
- `docs/plans/2026-03-26-core-matrix-phase-2-plan-agent-loop-execution.md`
- `docs/plans/2026-03-30-core-matrix-phase-2-milestone-d-sequential-execution-plan.md`
- `docs/plans/2026-03-30-core-matrix-phase-2-milestone-e-sequential-execution-plan.md`
- `docs/plans/2026-03-30-core-matrix-phase-2-milestone-f-sequential-execution-plan.md`

## Execution Contract

- Phase 2 is not accepted yet. Treat this follow-up as the new source of truth where it contradicts the earlier sequential-execution milestone plans.
- Backward compatibility is explicitly out of scope for this follow-up. Do not add compatibility branches, old-data rejection paths, or tests for obsolete schema or runtime payloads.
- It is allowed and expected to edit the existing workflow substrate migrations in place:
  - `core_matrix/db/migrate/20260324090029_create_workflow_nodes.rb`
  - `core_matrix/db/migrate/20260324090030_create_workflow_edges.rb`
  - `core_matrix/db/migrate/20260326100000_extend_workflow_substrate.rb`
- After migration edits, regenerate `core_matrix/db/schema.rb` and reset the local databases instead of trying to preserve old development or test state.
- `WorkflowNode` is one-shot per `WorkflowRun`. Retry is attempt-level behavior, not re-enablement of the same node by later predecessor arrivals.
- `WorkflowEdge.requirement` is limited to `required` and `optional` in the first pass. Do not add a separate trigger flag unless a concrete failing workflow shape proves it is necessary.
- Scheduler selection must stay pure and query-based. Job enqueueing and node-state transitions belong in separate mutating services.
- Do not collapse the DAG into one workflow-wide job. The only top-level async unit is one runnable `WorkflowNode`.
- Preserve the existing `public_id` boundary rules from `core_matrix/docs/behavior/identifier-policy.md`.

## Target Semantics

- A node becomes runnable only when:
  - it has not already been scheduled or terminalized
  - at least one predecessor is durably completed, unless it is the root node
  - every `required` predecessor is durably completed
- Late completion of an `optional` predecessor after a merge node has already been scheduled must not retrigger that merge node.
- Mailbox-owned agent work, subagent work, and local provider work must all project back into the same durable workflow-node lifecycle.

## Batch 1: Re-Baseline The Graph And Lock The Contract In Tests

### Task 1: Rewrite the scheduler tests around durable node state and edge requirements

**Files:**
- Modify: `core_matrix/test/services/workflows/scheduler_test.rb`
- Modify: `core_matrix/test/integration/workflow_scheduler_flow_test.rb`
- Modify: `core_matrix/test/services/workflows/execute_run_test.rb`
- Create: `core_matrix/test/services/workflows/dispatch_runnable_nodes_test.rb`
- Create: `core_matrix/test/jobs/workflows/execute_node_job_test.rb`

Run first:

```bash
cd core_matrix
bin/rails test test/services/workflows/scheduler_test.rb test/integration/workflow_scheduler_flow_test.rb test/services/workflows/execute_run_test.rb
```

Expected before implementation:

- failure because the current scheduler still depends on caller-supplied
  `satisfied_node_keys`
- failure because `WorkflowEdge` has no `required | optional` contract
- failure because there is no durable node job boundary yet

Lock the following behaviors in tests before changing implementation:

- `barrier_all` is represented by all incoming edges being `required`
- `any_of` is represented by all incoming edges being `optional`
- mixed fan-in requires all `required` predecessors and ignores late optional
  arrivals after the merge node has already been scheduled
- one runnable node maps to one enqueued node job, never one workflow-wide job

### Task 2: Rewrite the workflow substrate schema in place

**Files:**
- Modify: `core_matrix/db/migrate/20260324090029_create_workflow_nodes.rb`
- Modify: `core_matrix/db/migrate/20260324090030_create_workflow_edges.rb`
- Modify: `core_matrix/db/migrate/20260326100000_extend_workflow_substrate.rb`
- Modify: `core_matrix/db/schema.rb`
- Modify: `core_matrix/app/models/workflow_node.rb`
- Modify: `core_matrix/app/models/workflow_edge.rb`
- Modify: `core_matrix/app/models/workflow_run.rb`

Run:

```bash
cd core_matrix
bin/rails db:drop db:create db:migrate db:test:prepare
bin/rails test test/services/workflows/scheduler_test.rb
```

Implement only the durable graph-state pieces in this task:

- add edge-level `requirement`
- add durable node execution-state fields required for async scheduling
- keep node state one-shot and workflow-run-scoped
- keep the graph append-only and acyclic

Expected after implementation:

- the scheduler test can query readiness from durable workflow rows rather than
  an external `satisfied_node_keys` argument

## Batch 2: Introduce One Job Per Runnable Workflow Node

### Task 3: Add dispatcher and node-job boundaries

**Files:**
- Create: `core_matrix/app/jobs/workflows/execute_node_job.rb`
- Create: `core_matrix/app/services/workflows/dispatch_runnable_nodes.rb`
- Create: `core_matrix/app/services/workflows/execute_node.rb`
- Create or modify: `core_matrix/app/services/workflows/complete_node.rb`
- Create or modify: `core_matrix/app/services/workflows/fail_node.rb`
- Modify: `core_matrix/app/services/workflows/scheduler.rb`
- Modify: `core_matrix/app/services/workflows/execute_run.rb`
- Modify: `core_matrix/app/jobs/application_job.rb`
- Modify or create: `core_matrix/test/services/workflows/dispatch_runnable_nodes_test.rb`
- Modify or create: `core_matrix/test/jobs/workflows/execute_node_job_test.rb`

Run first:

```bash
cd core_matrix
bin/rails test test/services/workflows/dispatch_runnable_nodes_test.rb test/jobs/workflows/execute_node_job_test.rb test/services/workflows/scheduler_test.rb
```

Expected before implementation:

- failure because no service atomically claims runnable nodes and enqueues jobs
- failure because no workflow-node job exists

Implement only the dispatch boundary in this task:

- scheduler selects runnable pending nodes
- dispatcher locks the workflow run, claims runnable nodes once, marks them
  queued, and enqueues one job per node
- node job exits early if the node is no longer queued
- terminal node transitions trigger another dispatch pass for downstream nodes

Expected after implementation:

- one runnable node yields one enqueued job
- repeated dispatch calls do not duplicate work for already queued, running, or
  terminal nodes

### Task 4: Move local provider-backed turn-step execution behind node jobs

**Files:**
- Modify: `core_matrix/app/services/provider_execution/execute_turn_step.rb`
- Modify: `core_matrix/app/services/provider_execution/dispatch_request.rb`
- Modify: `core_matrix/app/services/workflows/execute_node.rb`
- Modify: `core_matrix/test/services/workflows/execute_run_test.rb`
- Modify: `core_matrix/test/integration/provider_backed_turn_execution_test.rb`

Run first:

```bash
cd core_matrix
bin/rails test test/services/workflows/execute_run_test.rb test/integration/provider_backed_turn_execution_test.rb
```

Expected before implementation:

- failure because provider-backed turn steps still execute synchronously through
  `Workflows::ExecuteRun.call`

Implement only the local provider execution boundary in this task:

- `turn_step` nodes that `core_matrix` owns are executed from the workflow-node
  job, not inline from a service call chain
- stale-work checks continue to happen under durable locks
- provider success and failure still append durable node events and usage facts

Expected after implementation:

- provider-backed turn-step tests pass with the new node-job boundary

## Batch 3: Bind Mailbox-Owned Agent Work Back Into Workflow Nodes

### Task 5: Make mailbox-owned agent completion advance the DAG exactly once

**Files:**
- Modify: `core_matrix/app/services/agent_control/create_execution_assignment.rb`
- Modify: `core_matrix/app/services/agent_control/handle_execution_report.rb`
- Modify: `core_matrix/app/models/agent_task_run.rb`
- Modify: `core_matrix/app/services/workflows/handle_wait_transition_request.rb`
- Modify: `core_matrix/app/services/workflows/re_enter_agent.rb`
- Modify: `core_matrix/app/services/workflows/resume_after_wait_resolution.rb`
- Modify: `core_matrix/test/services/agent_control/report_test.rb`
- Modify: `core_matrix/test/services/subagent_sessions/spawn_test.rb`
- Modify: `core_matrix/test/integration/human_interaction_and_subagent_flow_test.rb`
- Modify: `core_matrix/test/integration/workflow_scheduler_flow_test.rb`

Run first:

```bash
cd core_matrix
bin/rails test test/services/agent_control/report_test.rb test/services/subagent_sessions/spawn_test.rb test/integration/human_interaction_and_subagent_flow_test.rb test/integration/workflow_scheduler_flow_test.rb
```

Expected before implementation:

- failure because agent-owned node completion is not yet the durable source for
  downstream DAG advancement
- failure because merge nodes are not yet protected against late optional
  predecessor re-triggering

Implement only the mailbox-to-node lifecycle bridge in this task:

- agent-task completion or failure marks the owning workflow node terminal
- downstream dispatch happens once through the same dispatcher used for local
  nodes
- `wait_all` and `subagent_barrier` continue to use workflow wait state instead
  of ad hoc retrigger rules
- late optional predecessor completion records facts but does not reschedule a
  merge node that has already been consumed

Expected after implementation:

- agent-owned and subagent-owned execution integrates into the same one-shot
  DAG progression model

## Batch 4: Refresh The Docs And Re-Baseline Phase 2 Acceptance

### Task 6: Update behavior docs and supersede stale sequential assumptions

**Files:**
- Modify: `core_matrix/docs/behavior/workflow-graph-foundations.md`
- Modify: `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
- Modify: `core_matrix/docs/behavior/workflow-artifacts-node-events-and-process-runs.md`
- Modify: `docs/design/2026-03-30-core-matrix-phase-2-sequential-execution-design.md`
- Modify: `docs/plans/2026-03-30-core-matrix-phase-2-milestone-d-sequential-execution-plan.md`
- Modify: `docs/plans/2026-03-30-core-matrix-phase-2-milestone-e-sequential-execution-plan.md`
- Modify: `docs/plans/2026-03-30-core-matrix-phase-2-milestone-f-sequential-execution-plan.md`
- Modify: `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

Document explicitly:

- `WorkflowNode` is the async scheduling unit
- `WorkflowEdge.requirement` is the v1 merge contract
- merge nodes are one-shot
- old sequential assumptions are superseded and must not guide Phase 2
  acceptance anymore

### Task 7: Run the focused follow-up verification set

Run:

```bash
cd core_matrix
bin/rails db:drop db:create db:migrate db:test:prepare
bin/rails test test/services/workflows/scheduler_test.rb test/services/workflows/dispatch_runnable_nodes_test.rb test/jobs/workflows/execute_node_job_test.rb test/services/workflows/execute_run_test.rb test/services/agent_control/report_test.rb test/services/subagent_sessions/spawn_test.rb test/integration/workflow_scheduler_flow_test.rb test/integration/provider_backed_turn_execution_test.rb test/integration/human_interaction_and_subagent_flow_test.rb
```

Expected:

- the workflow graph, node job boundary, provider turn-step path, and mailbox
  completion path all pass under the new one-shot DAG contract

## Follow-Up Exit Criteria

- `WorkflowNode` is the only top-level async scheduling unit inside
  `core_matrix`
- `WorkflowEdge.requirement = required | optional` is the only merge contract in
  the first pass
- merge nodes are one-shot and do not retrigger on late optional arrivals
- provider-backed local work and mailbox-owned agent work both advance the DAG
  through the same durable node lifecycle
- stale sequential assumptions in the current Phase 2 milestone plans are
  either removed or explicitly marked superseded

## Must-Stop Conditions

- the first real merge case cannot be expressed with `required | optional`
  without inventing ambiguous ad hoc scheduler rules
- the node-job boundary proves insufficient and a separate durable node-attempt
  model is required
- provider-backed local execution and mailbox-owned agent execution require two
  incompatible scheduler models instead of one workflow-node lifecycle

