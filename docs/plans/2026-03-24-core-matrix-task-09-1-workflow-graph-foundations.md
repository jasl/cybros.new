# Core Matrix Task 09.1: Build Workflow Graph Foundations

Part of `Core Matrix Kernel Milestone 3: Conversation And Runtime`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-milestone-3-conversation-and-runtime.md`

Load this file as the detailed execution unit for Task 09.1. Treat Task Group 09 and the milestone file as ordering indexes, not as the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the consulted slice and the retained conclusion, invariant, or intentional difference in this task document or another local document updated by the same execution unit
- when this task updates behavior docs, checklist docs, or other local docs, carry that conclusion into those docs instead of leaving only a bare reference path
- keep reference paths as index pointers only; restate the relevant behavior locally so this task remains understandable if the reference later drifts

---

**Files:**
- Create: `core_matrix/db/migrate/20260324090028_create_workflow_runs.rb`
- Create: `core_matrix/db/migrate/20260324090029_create_workflow_nodes.rb`
- Create: `core_matrix/db/migrate/20260324090030_create_workflow_edges.rb`
- Create: `core_matrix/app/models/workflow_run.rb`
- Create: `core_matrix/app/models/workflow_node.rb`
- Create: `core_matrix/app/models/workflow_edge.rb`
- Create: `core_matrix/app/services/workflows/create_for_turn.rb`
- Create: `core_matrix/app/services/workflows/mutate.rb`
- Create: `core_matrix/test/models/workflow_run_test.rb`
- Create: `core_matrix/test/models/workflow_node_test.rb`
- Create: `core_matrix/test/models/workflow_edge_test.rb`
- Create: `core_matrix/test/services/workflows/create_for_turn_test.rb`
- Create: `core_matrix/test/services/workflows/mutate_test.rb`
- Create: `core_matrix/test/integration/workflow_graph_flow_test.rb`

**Step 1: Write failing model, service, and integration tests**

Cover at least:

- one active workflow per conversation in v1
- one workflow per turn
- workflow graph mutation appending nodes or edges at runtime while preserving acyclic shape
- workflow node ordinal uniqueness
- workflow node decision-source enum for `llm`, `agent_program`, `system`, and `user`
- workflow node metadata carrying explicit policy-sensitive markers when needed for audit decisions
- edge ordering and same-workflow integrity
- expanding the workflow graph after initial creation without replacing the run

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/workflow_run_test.rb test/models/workflow_node_test.rb test/models/workflow_edge_test.rb test/services/workflows/create_for_turn_test.rb test/services/workflows/mutate_test.rb test/integration/workflow_graph_flow_test.rb
```

Expected:

- missing table and model failures

**Step 3: Write migrations, models, and services**

Rules:

- workflow resources remain subordinate to the workflow
- `WorkflowRun` is one turn-scoped dynamic DAG, not a fixed template and not a conversation-wide graph
- workflow mutation may append nodes and edges at runtime but must reject any mutation that would introduce a cycle
- workflow nodes must persist explicit `decision_source` values and structured metadata needed by downstream execution, profiling, and audit services

**Step 4: Run migrations and targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/workflow_run_test.rb test/models/workflow_node_test.rb test/models/workflow_edge_test.rb test/services/workflows/create_for_turn_test.rb test/services/workflows/mutate_test.rb test/integration/workflow_graph_flow_test.rb
```

Expected:

- targeted tests pass

**Step 5: Commit**

```bash
git -C .. add core_matrix/db/migrate core_matrix/app/models/workflow_run.rb core_matrix/app/models/workflow_node.rb core_matrix/app/models/workflow_edge.rb core_matrix/app/services/workflows/create_for_turn.rb core_matrix/app/services/workflows/mutate.rb core_matrix/test/models core_matrix/test/services core_matrix/test/integration core_matrix/db/schema.rb
git -C .. commit -m "feat: add workflow graph foundations"
```

## Stop Point

Stop after workflow graph structure and mutation pass their tests.

Do not implement these items in this task:

- scheduler runnable-node selection
- model selector resolution
- context assembly
