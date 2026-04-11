# Core Matrix Task 10.1: Add Workflow Artifacts, Node Events, And Process Runs

Part of `Core Matrix Kernel Milestone 3: Conversation And Runtime`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/finished-plans/2026-03-24-core-matrix-phase-1-kernel-greenfield-implementation-plan.md`
4. `docs/finished-plans/2026-03-24-core-matrix-phase-1-kernel-milestone-3-conversation-and-runtime.md`

Load this file as the detailed execution unit for Task 10.1. Treat Task Group 10 and the milestone file as ordering indexes, not as the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the consulted slice and the retained conclusion, invariant, or intentional difference in this task document or another local document updated by the same execution unit
- when this task updates behavior docs, checklist docs, or other local docs, carry that conclusion into those docs instead of leaving only a bare reference path
- keep reference paths as index pointers only; restate the relevant behavior locally so this task remains understandable if the reference later drifts

---

**Files:**
- Create: `core_matrix/db/migrate/20260324090032_create_workflow_artifacts.rb`
- Create: `core_matrix/db/migrate/20260324090033_create_workflow_node_events.rb`
- Create: `core_matrix/db/migrate/20260324090034_create_process_runs.rb`
- Create: `core_matrix/app/models/workflow_artifact.rb`
- Create: `core_matrix/app/models/workflow_node_event.rb`
- Create: `core_matrix/app/models/process_run.rb`
- Create: `core_matrix/app/services/processes/start.rb`
- Create: `core_matrix/app/services/processes/stop.rb`
- Create: `core_matrix/test/models/workflow_artifact_test.rb`
- Create: `core_matrix/test/models/workflow_node_event_test.rb`
- Create: `core_matrix/test/models/process_run_test.rb`
- Create: `core_matrix/test/services/processes/start_test.rb`
- Create: `core_matrix/test/services/processes/stop_test.rb`
- Create: `core_matrix/test/integration/runtime_process_flow_test.rb`

**Step 1: Write failing model, service, and integration tests**

Cover at least:

- artifact storage mode behavior
- workflow node events for live output and status replay
- `ProcessRun` kinds `turn_command` and `background_service`
- `ProcessRun` ownership by workflow node and execution environment
- redundant `conversation_id` and `turn_id` query fields on `ProcessRun`
- originating-message association for user-visible process runs
- timeout required for bounded turn commands
- timeout forbidden for background services
- audit rows for policy-sensitive process execution

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/workflow_artifact_test.rb test/models/workflow_node_event_test.rb test/models/process_run_test.rb test/services/processes/start_test.rb test/services/processes/stop_test.rb test/integration/runtime_process_flow_test.rb
```

Expected:

- missing table and model failures

**Step 3: Write migrations, models, and services**

Rules:

- kernel owns durable side effects
- live output is modeled as workflow node events, not transcript mutation
- `ProcessRun` must belong to both `WorkflowNode` and `ExecutionEnvironment`
- `ProcessRun` must redundantly persist `conversation_id` and `turn_id` for operational querying
- user-visible process runs must retain an originating message reference
- `turn_command` and `background_service` must remain explicit kind values for filtering and lifecycle rules
- background services are first-class runtime resources
- policy-sensitive process execution must create audit rows when the workflow node or service input marks it as such

**Step 4: Run migrations and targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/workflow_artifact_test.rb test/models/workflow_node_event_test.rb test/models/process_run_test.rb test/services/processes/start_test.rb test/services/processes/stop_test.rb test/integration/runtime_process_flow_test.rb
```

Expected:

- targeted tests pass

**Step 5: Commit**

```bash
git -C .. add core_matrix/db/migrate core_matrix/app/models/workflow_artifact.rb core_matrix/app/models/workflow_node_event.rb core_matrix/app/models/process_run.rb core_matrix/app/services/processes core_matrix/test/models core_matrix/test/services core_matrix/test/integration core_matrix/db/schema.rb
git -C .. commit -m "feat: add workflow runtime process resources"
```

## Stop Point

Stop after workflow artifacts, node events, and process runs pass their tests.

Do not implement these items in this task:

- human interactions
- canonical variables
- subagent orchestration metadata
- execution leases

## Completion Record

- status:
  completed on `2026-03-25`
- landing commit:
  - included in the accompanying `feat: add workflow runtime process resources`
    task commit
- actual landed scope:
  - added workflow-owned `WorkflowArtifact`, `WorkflowNodeEvent`, and
    `ProcessRun` models with installation and ownership consistency checks
  - added file-backed and inline-json artifact storage modes through
    `WorkflowArtifact`
  - added append-only node-local event ordering for workflow execution replay
  - added `Processes::Start` and `Processes::Stop` service boundaries for
    process lifecycle materialization and termination
  - added targeted model, service, and integration coverage for artifact
    storage-mode validation, workflow-node event ordering, process kind and
    timeout rules, origin-message retention, policy-sensitive audit creation,
    and workflow-local status replay
  - added
    `core_matrix/docs/behavior/workflow-artifacts-node-events-and-process-runs.md`
- plan alignment notes:
  - process resources are now first-class workflow-owned rows rather than
    opaque tool side effects
  - `ProcessRun` redundantly persists `conversation_id` and `turn_id` exactly
    for operational filtering, while workflow-run ownership remains derived
    through the owning node instead of introducing another denormalized column
  - live process status is represented through append-only `WorkflowNodeEvent`
    rows, not mutable transcript records or mutable process output columns
  - policy-sensitive process execution now leaves an audit trace when the node
    or service input marks the process as sensitive
- verification evidence:
  - `cd core_matrix && bin/rails test test/models/workflow_artifact_test.rb test/models/workflow_node_event_test.rb test/models/process_run_test.rb test/services/processes/start_test.rb test/services/processes/stop_test.rb test/integration/runtime_process_flow_test.rb`
    passed with `7 runs, 43 assertions, 0 failures, 0 errors`
  - `cd core_matrix && bin/rails test test/services/processes test/services/workflows test/integration/workflow_graph_flow_test.rb test/integration/workflow_scheduler_flow_test.rb test/integration/workflow_selector_flow_test.rb test/integration/workflow_context_flow_test.rb test/integration/runtime_process_flow_test.rb test/models/turn_test.rb test/models/workflow_run_test.rb test/models/workflow_node_test.rb test/models/workflow_artifact_test.rb test/models/workflow_node_event_test.rb test/models/process_run_test.rb`
    passed with `35 runs, 188 assertions, 0 failures, 0 errors`
- checklist notes:
  - no manual-checklist delta was retained for this task because the landed
    runtime-resource behavior is covered by targeted automated tests
- retained findings:
  - `WorkflowNodeEvent` is sufficient as the workflow-local live replay surface
    for process lifecycle in this task; `ConversationEvent` projection should
    remain a later, explicit choice
  - `ProcessRun` needed explicit ownership validation back to the workflow run's
    turn and conversation so the redundant query columns cannot silently drift
  - `WorkflowArtifact` needed an explicit storage-mode boundary so inline JSON
    payloads and attached files do not blur into one loosely validated blob
- carry-forward notes:
  - Task 10.2 should project only intentionally user-visible runtime state from
    `WorkflowNodeEvent` into `ConversationEvent`
  - later runtime tasks should continue appending execution trace through
    workflow-local events and artifacts instead of mutating transcript-bearing
    `Message` rows
