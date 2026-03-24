# Core Matrix Task 10.2: Add Human Interactions And Conversation Events

Part of `Core Matrix Kernel Phase 3: Conversation And Runtime`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-phase-3-conversation-and-runtime.md`
5. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

Load this file as the detailed execution unit for Task 10.2. Treat Task 10 and the phase file as ordering indexes, not as the full task body.

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

Do not implement these items in this subtask:

- canonical variable storage
- subagent runtime resources
- execution leases
