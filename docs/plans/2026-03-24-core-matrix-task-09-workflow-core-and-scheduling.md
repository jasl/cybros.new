# Core Matrix Task 09: Rebuild Workflow Core, Context Assembly, And Scheduling Rules

Part of `Core Matrix Kernel Phase 3: Conversation And Runtime`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-phase-3-conversation-and-runtime.md`
5. `docs/plans/2026-03-24-core-matrix-kernel-ui-follow-up.md`
6. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

Load this file as the detailed execution unit for Task 09. Treat the phase file as the ordering index, not the full task body.

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
- Create: `core_matrix/app/services/workflows/scheduler.rb`
- Create: `core_matrix/app/services/workflows/context_assembler.rb`
- Create: `core_matrix/app/services/workflows/resolve_model_selector.rb`
- Create: `core_matrix/test/models/workflow_run_test.rb`
- Create: `core_matrix/test/models/workflow_node_test.rb`
- Create: `core_matrix/test/models/workflow_edge_test.rb`
- Create: `core_matrix/test/services/workflows/create_for_turn_test.rb`
- Create: `core_matrix/test/services/workflows/mutate_test.rb`
- Create: `core_matrix/test/services/workflows/scheduler_test.rb`
- Create: `core_matrix/test/services/workflows/context_assembler_test.rb`
- Create: `core_matrix/test/services/workflows/resolve_model_selector_test.rb`
- Create: `core_matrix/test/integration/workflow_core_flow_test.rb`

**Step 1: Write failing unit tests**

Cover at least:

- one active workflow per conversation in v1
- one workflow per turn
- workflow graph mutation appending nodes or edges at runtime while preserving acyclic shape
- workflow node ordinal uniqueness
- workflow node decision-source enum for `llm`, `agent_program`, `system`, and `user`
- workflow node metadata carrying explicit policy-sensitive markers when needed for audit decisions
- edge ordering and same-workflow integrity
- scheduler fan-out and barrier-style fan-in join semantics inside one turn-scoped DAG
- structured `WorkflowRun` wait-state fields for current blocking reason, payload, and blocking resource reference
- selector normalization to `role:*` and `candidate:*`
- the reserved interactive path falling back to `role:main` when no more specific selector is present
- role-local fallback only within the current role's ordered candidate list
- explicit candidate selection rejecting fallback to unrelated models
- execution-time entitlement reservation causing fallback only to the next candidate in the same role list
- resolved model-selection snapshot fields frozen on the executing turn, with optional denormalized references on `WorkflowRun` if operational queries need them
- context assembly from base rules, active imports, transcript tail, selected workflow outputs, and eligible attachment manifests
- context assembly for automation-origin turns without a transcript-bearing user input
- execution-context identity fields for agent code, including `user_id`, `workspace_id`, `conversation_id`, and `turn_id`
- during-generation policy semantics for `reject`, `restart`, and `queue`
- expected-tail guards that skip or cancel stale queued work before execution
- steering after the first side-effect boundary becomes queued follow-up or restart behavior instead of mutating already-sent work
- capability-gated attachment prompt projection based on the turn's pinned provider or model snapshot
- hidden, excluded, or branch-ineligible attachments never appearing in runtime manifests or model input blocks
- unsupported attachments remaining available to runtime preparation without being serialized as if the model received them
- non-transcript `ConversationEvent` rows never entering canonical transcript context assembly by default
- scheduler selecting runnable nodes without executing side effects

**Step 2: Write a failing integration flow test**

`workflow_core_flow_test.rb` should cover:

- creating a workflow for a turn
- mutating nodes and edges
- expanding the workflow graph after initial creation without replacing the run
- ensuring only one active workflow exists for the conversation
- proving a barrier or join node does not become runnable until all required predecessor branches complete
- preserving workflow-node decision-source and policy metadata used later by execution and audit services
- resolving `auto` to `role:main`, choosing the first available role candidate, and freezing the resolved provider or model on the execution snapshot
- falling through to the next candidate when entitlement reservation fails for the first role-based choice
- rejecting implicit fallback when the selector is one explicit candidate
- assembling context that includes imports, summary artifacts, and capability-gated attachment prompt blocks without walking a global graph
- creating a workflow for an automation-origin turn whose trigger metadata seeds execution without a transcript-bearing user message
- exposing the current `user_id`, `workspace_id`, `conversation_id`, and `turn_id` in the assembled execution context
- proving unsupported attachments are omitted from model input projection while remaining available in the runtime attachment manifest
- proving queued stale work is skipped after the conversation tail changes

**Step 3: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/workflow_run_test.rb test/models/workflow_node_test.rb test/models/workflow_edge_test.rb test/services/workflows/create_for_turn_test.rb test/services/workflows/mutate_test.rb test/services/workflows/scheduler_test.rb test/services/workflows/context_assembler_test.rb test/services/workflows/resolve_model_selector_test.rb test/integration/workflow_core_flow_test.rb
```

Expected:

- missing table and model failures

**Step 4: Write migrations, models, and services**

Rules:

- workflow resources remain subordinate to the workflow
- `WorkflowRun` is one turn-scoped dynamic DAG, not a fixed template and not a conversation-wide graph
- workflow mutation may append nodes and edges at runtime but must reject any mutation that would introduce a cycle
- workflow nodes must persist explicit `decision_source` values and structured metadata needed by downstream execution, profiling, and audit services
- model selection must resolve through the explicit service boundary `workflows/resolve_model_selector`
- model selectors must normalize to `role:*` or `candidate:*`
- the reserved interactive path should fall back to `role:main`
- fallback is only allowed inside the ordered candidate list of the selected role
- execution-time entitlement reservation must happen before finalizing the selected candidate on the snapshot
- explicit candidate selection must fail immediately when unavailable instead of guessing another model
- resolved model snapshots should retain selector source, normalized selector, resolved provider, resolved model, resolution reason, and fallback count
- context assembly must not depend on a global conversation DAG
- context assembly must tolerate automation-origin turns that begin from trigger metadata or workflow bootstrap state instead of a transcript-bearing user message
- context assembly must freeze a canonical attachment manifest on the executing turn as the canonical execution snapshot and derive both runtime and model-facing projections from it, with optional denormalized references on `WorkflowRun`
- attachment prompt projection must be capability-gated by pinned catalog metadata rather than the latest mutable catalog state
- context assembly must record explicit diagnostic events when attachment preparation or prompt projection is skipped or degraded
- context assembly must draw from transcript-bearing messages and approved support rows, not from `ConversationEvent` projections by default
- context assembly must expose stable ownership identity fields so agent code can reason about the current user, workspace, conversation, and turn without scraping transcript text
- `WorkflowRun` must persist structured current wait-state fields for blocking reason, payload, blocking resource reference, and `waiting_since_at`
- scheduler must enforce `reject`, `restart`, and `queue` semantics deterministically
- scheduler must support fan-out, fan-in, and barrier-style joins within the same workflow run
- queued work must fail safe when its expected-tail guard no longer matches
- scheduler determines runnable work only; it does not execute side effects

**Step 5: Run migrations and targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/workflow_run_test.rb test/models/workflow_node_test.rb test/models/workflow_edge_test.rb test/services/workflows/create_for_turn_test.rb test/services/workflows/mutate_test.rb test/services/workflows/scheduler_test.rb test/services/workflows/context_assembler_test.rb test/services/workflows/resolve_model_selector_test.rb test/integration/workflow_core_flow_test.rb
```

Expected:

- targeted tests pass

**Step 6: Commit**

```bash
git -C .. add core_matrix/db/migrate core_matrix/app/models core_matrix/app/services/workflows core_matrix/test/models core_matrix/test/services core_matrix/test/integration core_matrix/db/schema.rb
git -C .. commit -m "feat: rebuild workflow core"
```

