# Core Matrix Task 09.2: Add Scheduler And Wait States

Part of `Core Matrix Kernel Phase 3: Conversation And Runtime`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-phase-3-conversation-and-runtime.md`

Load this file as the detailed execution unit for Task 09.2. Treat Task 09 and the phase file as ordering indexes, not as the full task body.

---

**Files:**
- Create: `core_matrix/app/services/workflows/scheduler.rb`
- Create: `core_matrix/test/services/workflows/scheduler_test.rb`
- Create: `core_matrix/test/integration/workflow_scheduler_flow_test.rb`
- Modify: `core_matrix/app/models/workflow_run.rb`
- Modify: `core_matrix/app/services/turns/steer_current_input.rb`
- Modify: `core_matrix/test/models/workflow_run_test.rb`
- Modify: `core_matrix/test/services/turns/steer_current_input_test.rb`

**Step 1: Write failing service and integration tests**

Cover at least:

- scheduler fan-out and barrier-style fan-in join semantics inside one turn-scoped DAG
- structured `WorkflowRun` wait-state fields for current blocking reason, payload, and blocking resource reference
- during-generation policy semantics for `reject`, `restart`, and `queue`
- expected-tail guards that skip or cancel stale queued work before execution
- steering after the first side-effect boundary becoming queued follow-up or restart behavior instead of mutating already-sent work
- scheduler selecting runnable nodes without executing side effects

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/workflow_run_test.rb test/services/turns/steer_current_input_test.rb test/services/workflows/scheduler_test.rb test/integration/workflow_scheduler_flow_test.rb
```

Expected:

- missing service or wait-state failures

**Step 3: Implement scheduler semantics**

Rules:

- `WorkflowRun` must persist structured current wait-state fields for blocking reason, payload, blocking resource reference, and `waiting_since_at`
- scheduler must enforce `reject`, `restart`, and `queue` semantics deterministically
- scheduler must support fan-out, fan-in, and barrier-style joins within the same workflow run
- queued work must fail safe when its expected-tail guard no longer matches
- scheduler determines runnable work only; it does not execute side effects

**Step 4: Run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails test test/models/workflow_run_test.rb test/services/turns/steer_current_input_test.rb test/services/workflows/scheduler_test.rb test/integration/workflow_scheduler_flow_test.rb
```

Expected:

- targeted tests pass

**Step 5: Commit**

```bash
git -C .. add core_matrix/app/models/workflow_run.rb core_matrix/app/services/workflows/scheduler.rb core_matrix/app/services/turns/steer_current_input.rb core_matrix/test/models core_matrix/test/services core_matrix/test/integration
git -C .. commit -m "feat: add workflow scheduler semantics"
```

## Stop Point

Stop after scheduler semantics and wait-state behavior pass their tests.

Do not implement these items in this subtask:

- model selector resolution
- context assembly
- workflow-node side-effect execution
