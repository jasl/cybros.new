# Core Matrix Task 09.4: Add Context Assembly And Execution Snapshot

Part of `Core Matrix Kernel Phase 3: Conversation And Runtime`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-phase-3-conversation-and-runtime.md`
5. `docs/plans/2026-03-24-core-matrix-model-role-resolution-design.md`

Load this file as the detailed execution unit for Task 09.4. Treat Task 09 and the phase file as ordering indexes, not as the full task body.

---

**Files:**
- Create: `core_matrix/app/services/workflows/context_assembler.rb`
- Create: `core_matrix/test/services/workflows/context_assembler_test.rb`
- Create: `core_matrix/test/integration/workflow_context_flow_test.rb`
- Modify: `core_matrix/app/models/turn.rb`
- Modify: `core_matrix/app/models/workflow_run.rb`
- Modify: `core_matrix/app/services/workflows/create_for_turn.rb`
- Modify: `core_matrix/test/models/turn_test.rb`
- Modify: `core_matrix/test/services/workflows/create_for_turn_test.rb`

**Step 1: Write failing service and integration tests**

Cover at least:

- context assembly from base rules, active imports, transcript tail, selected workflow outputs, and eligible attachment manifests
- context assembly for automation-origin turns without a transcript-bearing user input
- execution-context identity fields for agent code, including `user_id`, `workspace_id`, `conversation_id`, and `turn_id`
- capability-gated attachment prompt projection based on the turn's pinned provider or model snapshot
- hidden, excluded, or branch-ineligible attachments never appearing in runtime manifests or model input blocks
- unsupported attachments remaining available to runtime preparation without being serialized as if the model received them
- non-transcript `ConversationEvent` rows never entering canonical transcript context assembly by default
- assembling context that includes imports and summary artifacts without walking a global conversation DAG

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/turn_test.rb test/services/workflows/create_for_turn_test.rb test/services/workflows/context_assembler_test.rb test/integration/workflow_context_flow_test.rb
```

Expected:

- missing service or context-assembly failures

**Step 3: Implement context assembly**

Rules:

- context assembly must not depend on a global conversation DAG
- context assembly must tolerate automation-origin turns that begin from trigger metadata or workflow bootstrap state instead of a transcript-bearing user message
- context assembly must freeze a canonical attachment manifest on the executing turn as the canonical execution snapshot and derive both runtime and model-facing projections from it, with optional denormalized references on `WorkflowRun`
- attachment prompt projection must be capability-gated by pinned catalog metadata rather than the latest mutable catalog state
- context assembly must record explicit diagnostic events when attachment preparation or prompt projection is skipped or degraded
- context assembly must draw from transcript-bearing messages and approved support rows, not from `ConversationEvent` projections by default
- context assembly must expose stable ownership identity fields so agent code can reason about the current user, workspace, conversation, and turn without scraping transcript text

**Step 4: Run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails test test/models/turn_test.rb test/services/workflows/create_for_turn_test.rb test/services/workflows/context_assembler_test.rb test/integration/workflow_context_flow_test.rb
```

Expected:

- targeted tests pass

**Step 5: Commit**

```bash
git -C .. add core_matrix/app/models/turn.rb core_matrix/app/models/workflow_run.rb core_matrix/app/services/workflows/context_assembler.rb core_matrix/app/services/workflows/create_for_turn.rb core_matrix/test/models core_matrix/test/services core_matrix/test/integration
git -C .. commit -m "feat: add workflow context assembly"
```

## Stop Point

Stop after context assembly and execution snapshot projection pass their tests.

Do not implement these items in this subtask:

- workflow-node side-effect execution
- machine-facing protocol controllers
- publication rendering
