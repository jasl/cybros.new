# Core Matrix Task 10.4: Add Subagents And Leases

Part of `Core Matrix Kernel Milestone 3: Conversation And Runtime`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/finished-plans/2026-03-24-core-matrix-phase-1-kernel-greenfield-implementation-plan.md`
4. `docs/finished-plans/2026-03-24-core-matrix-phase-1-kernel-milestone-3-conversation-and-runtime.md`

Load this file as the detailed execution unit for Task 10.4. Treat Task Group 10 and the milestone file as ordering indexes, not as the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the consulted slice and the retained conclusion, invariant, or intentional difference in this task document or another local document updated by the same execution unit
- when this task updates behavior docs, checklist docs, or other local docs, carry that conclusion into those docs instead of leaving only a bare reference path
- keep reference paths as index pointers only; restate the relevant behavior locally so this task remains understandable if the reference later drifts

---

**Files:**
- Create: `core_matrix/db/migrate/20260324090038_create_subagent_runs.rb`
- Create: `core_matrix/db/migrate/20260324090039_create_execution_leases.rb`
- Create: `core_matrix/app/models/subagent_run.rb`
- Create: `core_matrix/app/models/execution_lease.rb`
- Create: `core_matrix/app/services/subagents/spawn.rb`
- Create: `core_matrix/app/services/leases/acquire.rb`
- Create: `core_matrix/app/services/leases/heartbeat.rb`
- Create: `core_matrix/app/services/leases/release.rb`
- Create: `core_matrix/test/models/subagent_run_test.rb`
- Create: `core_matrix/test/models/execution_lease_test.rb`
- Create: `core_matrix/test/services/subagents/spawn_test.rb`
- Create: `core_matrix/test/services/leases/acquire_test.rb`
- Create: `core_matrix/test/services/leases/heartbeat_test.rb`
- Create: `core_matrix/test/services/leases/release_test.rb`
- Create: `core_matrix/test/integration/subagent_lease_flow_test.rb`

**Step 1: Write failing model, service, and integration tests**

Cover at least:

- `SubagentRun` coordination metadata for parentage, depth, batch or coordination keys, requested role or slot, and final result artifact reference
- lease uniqueness, heartbeat freshness, and release semantics
- spawning multiple coordinated subagent runs under one workflow without introducing a second orchestration aggregate
- acquiring, heartbeating, and releasing an execution lease

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/subagent_run_test.rb test/models/execution_lease_test.rb test/services/subagents/spawn_test.rb test/services/leases/acquire_test.rb test/services/leases/heartbeat_test.rb test/services/leases/release_test.rb test/integration/subagent_lease_flow_test.rb
```

Expected:

- missing table and model failures

**Step 3: Write migrations, models, and services**

Rules:

- `SubagentRun` remains a workflow-node-backed runtime resource
- swarm or multi-agent behavior must stay expressed through workflow DAG fan-out or fan-in rather than a separate `SwarmRun` aggregate
- `SubagentRun` must retain lightweight coordination metadata for parentage, depth, batching, coordination, requested role or slot, and terminal result artifact linkage
- execution leases must enforce uniqueness, heartbeat freshness, and explicit release semantics

**Step 4: Run migrations and targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/subagent_run_test.rb test/models/execution_lease_test.rb test/services/subagents/spawn_test.rb test/services/leases/acquire_test.rb test/services/leases/heartbeat_test.rb test/services/leases/release_test.rb test/integration/subagent_lease_flow_test.rb
```

Expected:

- targeted tests pass

**Step 5: Commit**

```bash
git -C .. add core_matrix/db/migrate core_matrix/app/models/subagent_run.rb core_matrix/app/models/execution_lease.rb core_matrix/app/services/subagents core_matrix/app/services/leases core_matrix/test/models core_matrix/test/services core_matrix/test/integration core_matrix/db/schema.rb
git -C .. commit -m "feat: add subagent coordination and leases"
```

## Stop Point

Stop after subagent coordination metadata and execution leases pass their tests.

Do not implement these items in this task:

- a separate `SwarmRun` aggregate
- generic agent-owned tool execution bridges
- schedule or webhook trigger orchestration

## Completion Record

- status:
  completed on `2026-03-25`
- landing commit:
  - included in the accompanying `feat: add subagent coordination and leases`
    task commit
- actual landed scope:
  - added `SubagentRun` as a workflow-owned coordination resource with
    lightweight parentage, depth, batch, coordination, requested-role, and
    terminal-summary linkage
  - added `ExecutionLease` as the explicit active-resource ownership row for
    workflow-bound `ProcessRun` and `SubagentRun` resources
  - added `Subagents::Spawn`, `Leases::Acquire`, `Leases::Heartbeat`, and
    `Leases::Release` as the kernel-owned application-service boundaries for
    subagent coordination and lease lifecycle
  - added targeted model, service, and integration coverage for coordination
    metadata, stale-lease replacement, heartbeat freshness, and explicit
    release semantics
  - added
    `core_matrix/docs/behavior/subagent-runs-and-execution-leases.md`
- plan alignment notes:
  - subagent fan-out remains expressed through workflow-owned runtime rows; no
    `SwarmRun` or parallel orchestration aggregate was introduced
  - lease ownership remains explicit and heartbeat-based, with stale leases
    timing out in-place before replacement acquisition is allowed
  - active-lease uniqueness is enforced in both the Rails model layer and the
    database through a partial unique index
- verification evidence:
  - `cd core_matrix && bin/rails test test/models/subagent_run_test.rb test/models/execution_lease_test.rb test/services/subagents/spawn_test.rb test/services/leases/acquire_test.rb test/services/leases/heartbeat_test.rb test/services/leases/release_test.rb test/integration/subagent_lease_flow_test.rb`
    passed with `7 runs, 42 assertions, 0 failures, 0 errors`
- checklist notes:
  - no manual-checklist delta was retained for this task because the landed
    contract is runtime-resource coordination and heartbeat ownership covered by
    automated model, service, and integration tests
- retained findings:
  - active-lease uniqueness could not safely rely on Rails validation alone;
    it needed a partial unique database index as well
  - stale-heartbeat handling needed to persist timeout release metadata before
    raising the stale-lease error, so the timeout write now commits before the
    service re-raises
- carry-forward notes:
  - later recovery work should treat `ExecutionLease` as the durable source of
    active-runtime ownership instead of inferring ownership from ephemeral
    process state alone
  - later machine-facing runtime APIs may expose or act on leased resources,
    but they should keep using these kernel-owned services rather than direct
    row mutation
