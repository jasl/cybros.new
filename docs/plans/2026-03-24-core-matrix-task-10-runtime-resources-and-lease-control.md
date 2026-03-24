# Core Matrix Task 10: Add Execution Resources, Conversation Events, Human Interactions, Canonical Variables, And Lease Control

Part of `Core Matrix Kernel Phase 3: Conversation And Runtime`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-phase-3-conversation-and-runtime.md`
5. `docs/plans/2026-03-24-core-matrix-kernel-ui-follow-up.md`
6. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

Load this file as the detailed execution unit for Task 10. Treat the phase file as the ordering index, not the full task body.

---


**Files:**
- Create: `core_matrix/db/migrate/20260324090031_create_workflow_artifacts.rb`
- Create: `core_matrix/db/migrate/20260324090032_create_workflow_node_events.rb`
- Create: `core_matrix/db/migrate/20260324090033_create_process_runs.rb`
- Create: `core_matrix/db/migrate/20260324090034_create_subagent_runs.rb`
- Create: `core_matrix/db/migrate/20260324090035_create_human_interaction_requests.rb`
- Create: `core_matrix/db/migrate/20260324090036_create_canonical_variables.rb`
- Create: `core_matrix/db/migrate/20260324090037_create_conversation_events.rb`
- Create: `core_matrix/db/migrate/20260324090038_create_execution_leases.rb`
- Create: `core_matrix/app/models/workflow_artifact.rb`
- Create: `core_matrix/app/models/workflow_node_event.rb`
- Create: `core_matrix/app/models/process_run.rb`
- Create: `core_matrix/app/models/subagent_run.rb`
- Create: `core_matrix/app/models/human_interaction_request.rb`
- Create: `core_matrix/app/models/approval_request.rb`
- Create: `core_matrix/app/models/human_form_request.rb`
- Create: `core_matrix/app/models/human_task_request.rb`
- Create: `core_matrix/app/models/canonical_variable.rb`
- Create: `core_matrix/app/models/conversation_event.rb`
- Create: `core_matrix/app/models/execution_lease.rb`
- Create: `core_matrix/app/services/processes/start.rb`
- Create: `core_matrix/app/services/processes/stop.rb`
- Create: `core_matrix/app/services/subagents/spawn.rb`
- Create: `core_matrix/app/services/human_interactions/request.rb`
- Create: `core_matrix/app/services/human_interactions/resolve_approval.rb`
- Create: `core_matrix/app/services/human_interactions/submit_form.rb`
- Create: `core_matrix/app/services/human_interactions/complete_task.rb`
- Create: `core_matrix/app/services/conversation_events/project.rb`
- Create: `core_matrix/app/services/variables/write.rb`
- Create: `core_matrix/app/services/variables/promote_to_workspace.rb`
- Create: `core_matrix/app/services/leases/acquire.rb`
- Create: `core_matrix/app/services/leases/heartbeat.rb`
- Create: `core_matrix/app/services/leases/release.rb`
- Create: `core_matrix/test/models/workflow_artifact_test.rb`
- Create: `core_matrix/test/models/workflow_node_event_test.rb`
- Create: `core_matrix/test/models/process_run_test.rb`
- Create: `core_matrix/test/models/subagent_run_test.rb`
- Create: `core_matrix/test/models/human_interaction_request_test.rb`
- Create: `core_matrix/test/models/approval_request_test.rb`
- Create: `core_matrix/test/models/human_form_request_test.rb`
- Create: `core_matrix/test/models/human_task_request_test.rb`
- Create: `core_matrix/test/models/canonical_variable_test.rb`
- Create: `core_matrix/test/models/conversation_event_test.rb`
- Create: `core_matrix/test/models/execution_lease_test.rb`
- Create: `core_matrix/test/services/processes/start_test.rb`
- Create: `core_matrix/test/services/processes/stop_test.rb`
- Create: `core_matrix/test/services/subagents/spawn_test.rb`
- Create: `core_matrix/test/services/human_interactions/request_test.rb`
- Create: `core_matrix/test/services/human_interactions/resolve_approval_test.rb`
- Create: `core_matrix/test/services/human_interactions/submit_form_test.rb`
- Create: `core_matrix/test/services/human_interactions/complete_task_test.rb`
- Create: `core_matrix/test/services/conversation_events/project_test.rb`
- Create: `core_matrix/test/services/variables/write_test.rb`
- Create: `core_matrix/test/services/variables/promote_to_workspace_test.rb`
- Create: `core_matrix/test/services/leases/acquire_test.rb`
- Create: `core_matrix/test/services/leases/heartbeat_test.rb`
- Create: `core_matrix/test/services/leases/release_test.rb`
- Create: `core_matrix/test/integration/runtime_resource_flow_test.rb`

**Step 1: Write failing unit tests**

Cover at least:

- artifact storage mode behavior
- workflow node events for live output and status replay
- `ProcessRun` kinds `turn_command` and `background_service`
- `ProcessRun` ownership by workflow node and execution environment
- redundant `conversation_id` and `turn_id` query fields on `ProcessRun`
- originating-message association for user-visible process runs
- timeout required for bounded turn commands
- timeout forbidden for background services
- `ConversationEvent` append-only projection rules and separation from transcript-bearing `Message` rows
- `ConversationEvent` stable per-conversation ordering and optional turn anchoring for live projection
- replaceable live-projection streams for streaming text, progress, or status surfaces while keeping append-only event history
- `HumanInteractionRequest` STI legality and ownership by workflow node, turn, and conversation
- approval scope and transition rules
- form submission validation and timeout behavior
- task-request completion semantics and queryable open state
- blocking human-interaction resolution resuming the same workflow run on the same turn-scoped DAG by default
- `SubagentRun` coordination metadata for parentage, depth, batch or coordination keys, requested role or slot, and final result artifact reference
- canonical variable scope rules for `workspace` and `conversation`
- canonical variable supersession history and explicit promotion from conversation to workspace
- lease uniqueness, heartbeat freshness, and release semantics
- audit rows for policy-sensitive process execution

**Step 2: Write a failing integration flow test**

`runtime_resource_flow_test.rb` should cover:

- starting a short-lived `turn_command` process under workflow ownership
- starting a long-lived `background_service` process under workflow ownership
- recording the execution environment, originating message, and denormalized turn or conversation references
- emitting stdout or stderr node events without mutating transcript rows
- writing audit rows when a process run is flagged as policy-sensitive by workflow metadata
- opening and resolving an approval gate
- opening a blocking form request, submitting structured input, and resuming the same workflow run with workflow-local output state
- opening a human task request and recording a completion payload
- projecting visible conversation events for blocking human interaction lifecycle changes without creating transcript `Message` rows, preserving stable projection order, and collapsing to the newest revision within one replaceable live-projection stream when requested
- writing a conversation-scope canonical variable and promoting it to workspace scope with preserved history
- spawning multiple coordinated subagent runs under one workflow and recording lightweight coordination metadata without introducing a second orchestration aggregate
- acquiring, heartbeating, and releasing an execution lease

**Step 3: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/workflow_artifact_test.rb test/models/workflow_node_event_test.rb test/models/process_run_test.rb test/models/subagent_run_test.rb test/models/human_interaction_request_test.rb test/models/approval_request_test.rb test/models/human_form_request_test.rb test/models/human_task_request_test.rb test/models/canonical_variable_test.rb test/models/conversation_event_test.rb test/models/execution_lease_test.rb test/services/processes/start_test.rb test/services/processes/stop_test.rb test/services/subagents/spawn_test.rb test/services/human_interactions/request_test.rb test/services/human_interactions/resolve_approval_test.rb test/services/human_interactions/submit_form_test.rb test/services/human_interactions/complete_task_test.rb test/services/conversation_events/project_test.rb test/services/variables/write_test.rb test/services/variables/promote_to_workspace_test.rb test/services/leases/acquire_test.rb test/services/leases/heartbeat_test.rb test/services/leases/release_test.rb test/integration/runtime_resource_flow_test.rb
```

Expected:

- missing table and model failures

**Step 4: Write migrations, models, and services**

Rules:

- kernel owns durable side effects
- live output is modeled as workflow node events, not transcript mutation
- `ProcessRun` must belong to both `WorkflowNode` and `ExecutionEnvironment`
- `ProcessRun` must redundantly persist `conversation_id` and `turn_id` for operational querying
- user-visible process runs must retain an originating message reference
- `turn_command` and `background_service` must remain explicit kind values for filtering and lifecycle rules
- background services are explicit first-class runtime resources
- policy-sensitive process execution must create audit rows when the workflow node or service input marks it as such
- `HumanInteractionRequest` is the workflow-owned source of truth for approvals, forms, and human-task pauses
- `ConversationEvent` is append-only projection state and must not be reused as transcript-bearing `Message`
- `ConversationEvent` must persist deterministic projection-order metadata plus an optional turn anchor so live projection queries can merge events consistently
- `ConversationEvent` must also support replaceable live-projection streams through append-only revisions so one visible streaming or status surface can update in place without dropping history
- blocking human interactions must pause workflow progress until they resolve, cancel, or time out
- human-interaction outcomes must write structured results into workflow-local state before resumption
- blocking human-interaction resolution must resume the same `WorkflowRun` on the same turn-scoped DAG by default and must not create a new `Turn` or `WorkflowRun` unless an explicit restart or retry path is chosen
- `SubagentRun` remains a workflow-node-backed runtime resource; swarm or multi-agent behavior is expressed through workflow DAG fan-out or fan-in rather than a separate `SwarmRun` aggregate
- `SubagentRun` must retain lightweight coordination metadata for parentage, depth, batching, coordination, requested role or slot, and terminal result artifact linkage
- canonical variables must support only `workspace` and `conversation` scope in v1
- canonical variable writes supersede prior current values without deleting history
- conversation-scope canonical values may be explicitly promoted to workspace scope

**Step 5: Run migrations and targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/workflow_artifact_test.rb test/models/workflow_node_event_test.rb test/models/process_run_test.rb test/models/subagent_run_test.rb test/models/human_interaction_request_test.rb test/models/approval_request_test.rb test/models/human_form_request_test.rb test/models/human_task_request_test.rb test/models/canonical_variable_test.rb test/models/conversation_event_test.rb test/models/execution_lease_test.rb test/services/processes/start_test.rb test/services/processes/stop_test.rb test/services/subagents/spawn_test.rb test/services/human_interactions/request_test.rb test/services/human_interactions/resolve_approval_test.rb test/services/human_interactions/submit_form_test.rb test/services/human_interactions/complete_task_test.rb test/services/conversation_events/project_test.rb test/services/variables/write_test.rb test/services/variables/promote_to_workspace_test.rb test/services/leases/acquire_test.rb test/services/leases/heartbeat_test.rb test/services/leases/release_test.rb test/integration/runtime_resource_flow_test.rb
```

Expected:

- targeted tests pass

**Step 6: Commit**

```bash
git -C .. add core_matrix/db/migrate core_matrix/app/models core_matrix/app/services/processes core_matrix/app/services/subagents core_matrix/app/services/human_interactions core_matrix/app/services/conversation_events core_matrix/app/services/variables core_matrix/app/services/leases core_matrix/test/models core_matrix/test/services core_matrix/test/integration core_matrix/db/schema.rb
git -C .. commit -m "feat: add runtime interaction and canonical variable resources"
```
