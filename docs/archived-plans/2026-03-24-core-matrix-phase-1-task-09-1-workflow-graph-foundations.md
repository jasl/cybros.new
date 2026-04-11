# Core Matrix Task 09.1: Build Workflow Graph Foundations

Part of `Core Matrix Kernel Milestone 3: Conversation And Runtime`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/finished-plans/2026-03-24-core-matrix-phase-1-kernel-greenfield-implementation-plan.md`
4. `docs/finished-plans/2026-03-24-core-matrix-phase-1-kernel-milestone-3-conversation-and-runtime.md`

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
- workflow node decision-source enum for `llm`, `agent`, `system`, and `user`
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
bin/rails db:test:prepare
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

## Completion Record

- status:
  completed on `2026-03-25`
- landing commit:
  - included in the accompanying `feat: add workflow graph foundations` task
    commit
- actual landed scope:
  - added `WorkflowRun`, `WorkflowNode`, and `WorkflowEdge` tables with foreign
    keys, append-order indexes, one-workflow-per-turn enforcement, and one
    active workflow per conversation enforcement
  - added `WorkflowRun`, `WorkflowNode`, and `WorkflowEdge` models with
    installation, conversation, turn, same-workflow, enum, metadata, and
    no-self-loop validations
  - added `Workflows::CreateForTurn` to create a turn-owned active workflow run
    with one root node
  - added `Workflows::Mutate` to append nodes and edges while rejecting cyclic
    mutations and unknown node-key references
  - updated `Conversation`, `Turn`, and shared test helpers with workflow-run
    associations and workflow factory helpers
  - added `core_matrix/docs/behavior/workflow-graph-foundations.md`
  - added targeted model, service, and integration coverage for run uniqueness,
    node decision sources and metadata, edge integrity, acyclic mutation, and
    repeated graph expansion
- plan alignment notes:
  - the workflow graph landed as a turn-scoped durable DAG substrate, not as a
    conversation-wide graph and not as a reusable template
  - policy-sensitive execution markers are carried by explicit node metadata
    rather than transcript inference
  - mutation now queries persisted workflow rows directly so repeated mutation
    against the same in-memory run object stays correct across calls
- verification evidence:
  - `cd core_matrix && bin/rails db:test:prepare && bin/rails test test/models/workflow_run_test.rb test/models/workflow_node_test.rb test/models/workflow_edge_test.rb test/services/workflows/create_for_turn_test.rb test/services/workflows/mutate_test.rb test/integration/workflow_graph_flow_test.rb`
    passed with `9 runs, 38 assertions, 0 failures, 0 errors`
- checklist notes:
  - no manual-checklist delta was retained for this task because the landed
    behavior is workflow substrate infrastructure covered by automated tests
- retained findings:
  - `t.references` creates indexes by default, so a separate unique index on the
    same foreign-key column must be expressed either through the reference
    itself or by disabling the default index first
  - repeated workflow mutation must not rely on a cached Active Record
    association from the caller's `workflow_run` instance; fresh database-scoped
    queries are required to see earlier appended nodes and edges
  - per-node edge ordinals need an explicit empty-collection rule so the first
    edge from a node starts at `0` instead of `1`
  - invalid edge endpoint references should be normalized into
    `ActiveRecord::RecordInvalid` at the workflow service boundary instead of
    leaking `KeyError`
  - Dify was useful as a sanity check for run-versus-execution separation, but
    it does not replace the local design requirement for durable turn-scoped DAG
    structure
- carry-forward notes:
  - Task 09.2 should layer runnable-state and wait-state semantics onto these
    durable graph rows instead of inventing a second workflow-structure store
  - later runtime-resource tasks should remain subordinate to `WorkflowRun` and
    reference workflow nodes by durable row identity rather than transient
    scheduler memory
