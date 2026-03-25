# Core Matrix Phase 2 Task 02: Extend Workflow Substrate For Yield And Projection

Part of `Core Matrix Phase 2 Milestone 1: Kernel Execution Foundations`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-25-core-matrix-workflow-yield-and-intent-batch-design.md`
3. `docs/design/2026-03-25-core-matrix-workflow-proof-and-mermaid-export-design.md`
4. `docs/plans/2026-03-25-core-matrix-phase-2-milestone-1-kernel-execution-foundations.md`

Load this file as the detailed execution unit for Task 02. Treat the milestone
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
- Modify: `core_matrix/app/models/workflow_run.rb`
- Modify: `core_matrix/app/models/workflow_node.rb`
- Modify: `core_matrix/app/models/workflow_node_event.rb`
- Modify: `core_matrix/app/models/workflow_artifact.rb`
- Modify: `core_matrix/app/models/workflow_edge.rb`
- Likely create or modify: `core_matrix/app/services/workflows/*`
- Likely create or modify: `core_matrix/app/services/workflow_nodes/*`
- Likely create or modify: `core_matrix/app/services/workflow_artifacts/*`
- Likely create or modify: `core_matrix/app/queries/workflows/*`
- Create: `core_matrix/test/models/workflow_node_test.rb`
- Create or modify: `core_matrix/test/models/workflow_node_event_test.rb`
- Create or modify: `core_matrix/test/models/workflow_artifact_test.rb`
- Likely create: `core_matrix/test/services/workflows/intent_batch_materialization_test.rb`
- Likely create: `core_matrix/test/integration/workflow_yield_materialization_flow_test.rb`
- Modify: `core_matrix/docs/behavior/workflow-graph-foundations.md`
- Modify: `core_matrix/docs/behavior/workflow-artifacts-node-events-and-process-runs.md`
- Modify: `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
- Modify: `core_matrix/docs/behavior/read-side-queries-and-seed-baseline.md`

**Step 1: Write failing model, service, and integration tests**

Cover at least:

- `WorkflowNode.presentation_policy` persisted and frozen at materialization
- workflow-owned storage for:
  - yield markers
  - intent-batch summaries
  - barrier or blocking summaries
  - successor-agent-step linkage or equivalent resume metadata
- stable workflow ordering metadata that later read paths can consume without
  graph-reconstruction SQL
- read-facing redundant ownership or projection fields needed by later
  dashboard or proof-export queries
- one workflow-yield materialization path that records:
  - the yielding node
  - one accepted durable intent
  - one batch or barrier summary
- one path where rejected intent remains visible through node-local audit or
  event state without creating a false durable mutation

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/workflow_node_test.rb test/models/workflow_node_event_test.rb test/models/workflow_artifact_test.rb test/services/workflows/intent_batch_materialization_test.rb test/integration/workflow_yield_materialization_flow_test.rb
```

Expected:

- missing model, field, or materialization failures

**Step 3: Extend the workflow substrate**

Rules:

- breaking changes are allowed in Phase 2
- accepted kernel-governed intent must have durable workflow representation
- rejected intent must remain auditable without pretending it became a durable
  mutation
- `presentation_policy` must not be inferred later from node kind
- read-facing redundant fields are allowed when they keep later read paths
  simple, stable, and non-N+1

**Step 4: Update local behavior docs**

Document exact retained behavior for:

- workflow-owned intent and barrier materialization
- durable versus audit-only intent outcomes
- frozen `presentation_policy`
- ordering and projection metadata expected by later read paths

**Step 5: Run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails test test/models/workflow_node_test.rb test/models/workflow_node_event_test.rb test/models/workflow_artifact_test.rb test/services/workflows/intent_batch_materialization_test.rb test/integration/workflow_yield_materialization_flow_test.rb
```

Expected:

- targeted workflow-substrate tests pass

**Step 6: Commit**

```bash
git -C .. add core_matrix/app/models/workflow_run.rb core_matrix/app/models/workflow_node.rb core_matrix/app/models/workflow_node_event.rb core_matrix/app/models/workflow_artifact.rb core_matrix/app/models/workflow_edge.rb core_matrix/app/services/workflows core_matrix/app/services/workflow_nodes core_matrix/app/services/workflow_artifacts core_matrix/app/queries/workflows core_matrix/test/models/workflow_node_test.rb core_matrix/test/models/workflow_node_event_test.rb core_matrix/test/models/workflow_artifact_test.rb core_matrix/test/services/workflows/intent_batch_materialization_test.rb core_matrix/test/integration/workflow_yield_materialization_flow_test.rb core_matrix/docs/behavior/workflow-graph-foundations.md core_matrix/docs/behavior/workflow-artifacts-node-events-and-process-runs.md core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md core_matrix/docs/behavior/read-side-queries-and-seed-baseline.md
git -C .. commit -m "feat: extend workflow substrate for yield materialization"
```

## Stop Point

Stop after the workflow substrate can durably represent yield, accepted intent,
audit-only rejected intent, barrier summaries, and projection metadata.

Do not implement provider execution, `AgentTaskRun`, or MCP in this task.
