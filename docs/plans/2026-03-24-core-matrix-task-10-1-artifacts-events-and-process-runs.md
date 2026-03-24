# Core Matrix Task 10.1: Add Workflow Artifacts, Node Events, And Process Runs

Part of `Core Matrix Kernel Phase 3: Conversation And Runtime`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-phase-3-conversation-and-runtime.md`

Load this file as the detailed execution unit for Task 10.1. Treat Task 10 and the phase file as ordering indexes, not as the full task body.

---

**Files:**
- Create: `core_matrix/db/migrate/20260324090031_create_workflow_artifacts.rb`
- Create: `core_matrix/db/migrate/20260324090032_create_workflow_node_events.rb`
- Create: `core_matrix/db/migrate/20260324090033_create_process_runs.rb`
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

Do not implement these items in this subtask:

- human interactions
- canonical variables
- subagent orchestration metadata
- execution leases
