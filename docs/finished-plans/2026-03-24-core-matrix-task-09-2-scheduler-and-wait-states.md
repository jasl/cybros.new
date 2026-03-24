# Core Matrix Task 09.2: Add Scheduler And Wait States

Part of `Core Matrix Kernel Milestone 3: Conversation And Runtime`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/finished-plans/2026-03-24-core-matrix-kernel-milestone-3-conversation-and-runtime.md`

Load this file as the detailed execution unit for Task 09.2. Treat Task Group 09 and the milestone file as ordering indexes, not as the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the consulted slice and the retained conclusion, invariant, or intentional difference in this task document or another local document updated by the same execution unit
- when this task updates behavior docs, checklist docs, or other local docs, carry that conclusion into those docs instead of leaving only a bare reference path
- keep reference paths as index pointers only; restate the relevant behavior locally so this task remains understandable if the reference later drifts

---

**Files:**
- Create: `core_matrix/db/migrate/20260324090031_add_wait_state_to_workflow_runs.rb`
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
bin/rails db:test:prepare
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
bin/rails db:test:prepare
bin/rails test test/models/workflow_run_test.rb test/services/turns/steer_current_input_test.rb test/services/workflows/scheduler_test.rb test/integration/workflow_scheduler_flow_test.rb
```

Expected:

- targeted tests pass

**Step 5: Commit**

```bash
git -C .. add core_matrix/db/migrate core_matrix/app/models/workflow_run.rb core_matrix/app/services/workflows/scheduler.rb core_matrix/app/services/turns/steer_current_input.rb core_matrix/test/models core_matrix/test/services core_matrix/test/integration core_matrix/db/schema.rb
git -C .. commit -m "feat: add workflow scheduler semantics"
```

## Stop Point

Stop after scheduler semantics and wait-state behavior pass their tests.

Do not implement these items in this task:

- model selector resolution
- context assembly
- workflow-node side-effect execution

## Completion Record

- status:
  completed on `2026-03-25`
- landing commit:
  - included in the accompanying `feat: add workflow scheduler semantics` task
    commit
- actual landed scope:
  - added `workflow_runs` wait-state columns for current blocking reason,
    payload, timing, and blocking resource reference
  - extended `WorkflowRun` with `ready | waiting` wait-state validation and
    structured wait-reason validation
  - added `Workflows::Scheduler` with side-effect-free runnable-node selection,
    during-generation policy handling, and expected-tail guarding for queued
    follow-up work
  - extended `Turns::SteerCurrentInput` so post-side-effect steering delegates
    to queue or restart policy handling instead of rewriting already-sent work
  - added `core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
  - added targeted model, service, and integration coverage for barrier joins,
    wait-state rules, `reject | restart | queue`, queued-turn tail guards, and
    workflow-node boundary detection without stale association caches
- plan alignment notes:
  - runnable-node selection remains a pure scheduler decision and does not
    execute workflow side effects
  - wait-state data now describes only the current blocking condition, not the
    historical pause timeline
  - queued follow-up guards compare against the predecessor turn output rather
    than the conversation's last transcript row because queued-turn input
    already extends the visible tail
- verification evidence:
  - `cd core_matrix && bin/rails db:test:prepare && bin/rails test test/models/workflow_run_test.rb test/services/turns/steer_current_input_test.rb test/services/workflows/scheduler_test.rb test/integration/workflow_scheduler_flow_test.rb`
    passed with `10 runs, 51 assertions, 0 failures, 0 errors`
- checklist notes:
  - no manual-checklist delta was retained for this task because the landed
    behavior is workflow scheduler substrate and queue-guard infrastructure
- retained findings:
  - Task 09.2 needed a new additive migration for `workflow_runs`; the original
    task file was corrected because persisted wait-state fields cannot land
    without schema changes
  - `db:test:prepare` must run after the migration for reliable isolated reruns
    in this repo's Rails 8.2 test setup
  - predecessor-turn selected output is the correct expected-tail guard anchor
    for queued follow-up work; using the conversation's visible last transcript
    row would be wrong because the queued input itself already advances the tail
  - stale association caches can hide freshly persisted workflow-node
    side-effect markers, so boundary detection must query the current database
    scope directly
  - Dify pause entities were useful as a sanity check for separating current
    blocking state from historical pause history, but Core Matrix keeps that
    history for later event-stream tasks rather than adding a second pause
    aggregate now
- carry-forward notes:
  - Task 10 runtime-resource and event-stream work should project historical
    wait transitions from workflow activity instead of overloading
    `WorkflowRun.wait_reason_payload`
  - later scheduler or executor work should consume `expected_tail_message_id`
    and `during_generation_policy` as durable queued-turn guards instead of
    inventing parallel queue metadata
