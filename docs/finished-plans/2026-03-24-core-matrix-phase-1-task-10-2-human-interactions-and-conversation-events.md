# Core Matrix Task 10.2: Add Human Interactions And Conversation Events

Part of `Core Matrix Kernel Milestone 3: Conversation And Runtime`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/finished-plans/2026-03-24-core-matrix-phase-1-kernel-greenfield-implementation-plan.md`
4. `docs/finished-plans/2026-03-24-core-matrix-phase-1-kernel-milestone-3-conversation-and-runtime.md`
5. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

Load this file as the detailed execution unit for Task 10.2. Treat Task Group 10 and the milestone file as ordering indexes, not as the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the consulted slice and the retained conclusion, invariant, or intentional difference in this task document or another local document updated by the same execution unit
- when this task updates behavior docs, checklist docs, or other local docs, carry that conclusion into those docs instead of leaving only a bare reference path
- keep reference paths as index pointers only; restate the relevant behavior locally so this task remains understandable if the reference later drifts

---

**Files:**
- Create: `core_matrix/db/migrate/20260324090035_create_human_interaction_requests.rb`
- Create: `core_matrix/db/migrate/20260324090037_create_conversation_events.rb`
- Create: `core_matrix/app/models/human_interaction_request.rb`
- Create: `core_matrix/app/models/approval_request.rb`
- Create: `core_matrix/app/models/human_form_request.rb`
- Create: `core_matrix/app/models/human_task_request.rb`
- Create: `core_matrix/app/models/conversation_event.rb`
- Create: `core_matrix/app/services/human_interactions/request.rb`
- Create: `core_matrix/app/services/human_interactions/resolve_approval.rb`
- Create: `core_matrix/app/services/human_interactions/submit_form.rb`
- Create: `core_matrix/app/services/human_interactions/complete_task.rb`
- Create: `core_matrix/app/services/conversation_events/project.rb`
- Create: `core_matrix/test/models/human_interaction_request_test.rb`
- Create: `core_matrix/test/models/approval_request_test.rb`
- Create: `core_matrix/test/models/human_form_request_test.rb`
- Create: `core_matrix/test/models/human_task_request_test.rb`
- Create: `core_matrix/test/models/conversation_event_test.rb`
- Create: `core_matrix/test/services/human_interactions/request_test.rb`
- Create: `core_matrix/test/services/human_interactions/resolve_approval_test.rb`
- Create: `core_matrix/test/services/human_interactions/submit_form_test.rb`
- Create: `core_matrix/test/services/human_interactions/complete_task_test.rb`
- Create: `core_matrix/test/services/conversation_events/project_test.rb`
- Create: `core_matrix/test/integration/human_interaction_flow_test.rb`
- Modify: `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

**Step 1: Write failing model, service, and integration tests**

Cover at least:

- `HumanInteractionRequest` STI legality and ownership by workflow node, turn, and conversation
- approval scope and transition rules
- form submission validation and timeout behavior
- task-request completion semantics and queryable open state
- blocking human-interaction resolution resuming the same workflow run on the same turn-scoped DAG by default
- `ConversationEvent` append-only projection rules and separation from transcript-bearing `Message` rows
- `ConversationEvent` stable per-conversation ordering and optional turn anchoring for live projection
- replaceable live-projection streams for streaming text, progress, or status surfaces while keeping append-only event history

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/human_interaction_request_test.rb test/models/approval_request_test.rb test/models/human_form_request_test.rb test/models/human_task_request_test.rb test/models/conversation_event_test.rb test/services/human_interactions/request_test.rb test/services/human_interactions/resolve_approval_test.rb test/services/human_interactions/submit_form_test.rb test/services/human_interactions/complete_task_test.rb test/services/conversation_events/project_test.rb test/integration/human_interaction_flow_test.rb
```

Expected:

- missing table and model failures

**Step 3: Write migrations, models, and services**

Rules:

- `HumanInteractionRequest` is the workflow-owned source of truth for approvals, forms, and human-task pauses
- `ConversationEvent` is append-only projection state and must not be reused as transcript-bearing `Message`
- `ConversationEvent` must persist deterministic projection-order metadata plus an optional turn anchor so live projection queries can merge events consistently
- `ConversationEvent` must support replaceable live-projection streams through append-only revisions
- `WorkflowNodeEvent` remains the workflow-local execution stream; project to `ConversationEvent` only when the runtime state is intentionally user-visible
- blocking human interactions must pause workflow progress until they resolve, cancel, or time out
- human-interaction outcomes must write structured results into workflow-local state before resumption
- blocking human-interaction resolution must resume the same `WorkflowRun` on the same turn-scoped DAG by default
- update the manual checklist for reproducible human-interaction validation

**Step 4: Run migrations and targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/human_interaction_request_test.rb test/models/approval_request_test.rb test/models/human_form_request_test.rb test/models/human_task_request_test.rb test/models/conversation_event_test.rb test/services/human_interactions/request_test.rb test/services/human_interactions/resolve_approval_test.rb test/services/human_interactions/submit_form_test.rb test/services/human_interactions/complete_task_test.rb test/services/conversation_events/project_test.rb test/integration/human_interaction_flow_test.rb
```

Expected:

- targeted tests pass

**Step 5: Commit**

```bash
git -C .. add core_matrix/db/migrate core_matrix/app/models/human_interaction_request.rb core_matrix/app/models/approval_request.rb core_matrix/app/models/human_form_request.rb core_matrix/app/models/human_task_request.rb core_matrix/app/models/conversation_event.rb core_matrix/app/services/human_interactions core_matrix/app/services/conversation_events core_matrix/test/models core_matrix/test/services core_matrix/test/integration docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md core_matrix/db/schema.rb
git -C .. commit -m "feat: add human interactions and conversation events"
```

## Stop Point

Stop after human-interaction resources and conversation-event projection pass their tests.

Do not implement these items in this task:

- canonical variable storage
- subagent runtime resources
- execution leases

## Completion Record

- status:
  completed on `2026-03-25`
- landing commit:
  - included in the accompanying
    `feat: add human interactions and conversation events` task commit
- actual landed scope:
  - added `HumanInteractionRequest` STI with `ApprovalRequest`,
    `HumanFormRequest`, and `HumanTaskRequest`
  - added `ConversationEvent` as the append-only conversation-local projection
    model with deterministic `projection_sequence`
  - added replaceable live-projection streams through `stream_key` and
    `stream_revision`
  - added `HumanInteractions::Request`, `ResolveApproval`, `SubmitForm`, and
    `CompleteTask` service boundaries on top of the existing workflow wait-state
    mechanism
  - added `ConversationEvents::Project` as the projection-sequence allocator
    and event appender
  - updated the manual checklist with a reproducible blocking-approval
    pause-and-resume flow
  - added
    `core_matrix/docs/behavior/human-interactions-and-conversation-events.md`
- plan alignment notes:
  - blocking human interactions now pause and resume the same `WorkflowRun`
    rather than creating a new turn or a new workflow run
  - request outcome data is persisted on the workflow-owned request row before
    wait-state clearance and scheduler resumption
  - `ConversationEvent` remains distinct from transcript-bearing `Message`
    rows and is used only as append-only projection state
  - replaceable live streams now collapse at read time through
    `ConversationEvent.live_projection` while the full append-only history stays
    durable
- verification evidence:
  - `cd core_matrix && bin/rails test test/models/human_interaction_request_test.rb test/models/approval_request_test.rb test/models/human_form_request_test.rb test/models/human_task_request_test.rb test/models/conversation_event_test.rb test/services/human_interactions/request_test.rb test/services/human_interactions/resolve_approval_test.rb test/services/human_interactions/submit_form_test.rb test/services/human_interactions/complete_task_test.rb test/services/conversation_events/project_test.rb test/integration/human_interaction_flow_test.rb`
    passed with `12 runs, 77 assertions, 0 failures, 0 errors`
  - `cd core_matrix && bin/rails test test/services/human_interactions test/services/conversation_events test/services/processes test/services/workflows test/integration/workflow_graph_flow_test.rb test/integration/workflow_scheduler_flow_test.rb test/integration/workflow_selector_flow_test.rb test/integration/workflow_context_flow_test.rb test/integration/runtime_process_flow_test.rb test/integration/human_interaction_flow_test.rb test/models/turn_test.rb test/models/workflow_run_test.rb test/models/workflow_node_test.rb test/models/workflow_artifact_test.rb test/models/workflow_node_event_test.rb test/models/process_run_test.rb test/models/human_interaction_request_test.rb test/models/approval_request_test.rb test/models/human_form_request_test.rb test/models/human_task_request_test.rb test/models/conversation_event_test.rb`
    passed with `47 runs, 265 assertions, 0 failures, 0 errors`
- checklist notes:
  - manual validation now includes a reproducible blocking-approval flow that
    proves same-workflow pause and resume plus append-only conversation-event
    history
- retained findings:
  - `ConversationEvent` should stay a projection-only model; it was not
    necessary to add transcript pointers or transcript mutation semantics for
    this task
  - request result persistence on `HumanInteractionRequest` was sufficient for
    the current “structured outcome before resume” requirement without
    pre-implementing canonical variables
  - a narrow Dify sanity check reinforced the same-workflow resume invariant,
    but Core Matrix keeps a simpler v1 shape by using the workflow-run wait
    state plus durable request outcome rows
- carry-forward notes:
  - Task 10.3 may read human-interaction outcomes when canonical-variable
    promotion is introduced, but it should not replace the request row as the
    runtime source of truth
  - later publication and read-model work should compose transcript messages and
    conversation events without collapsing the semantic distinction between the
    two record types
