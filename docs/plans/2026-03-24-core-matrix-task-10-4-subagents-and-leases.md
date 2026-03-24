# Core Matrix Task 10.4: Add Subagents And Leases

Part of `Core Matrix Kernel Milestone 3: Conversation And Runtime`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-milestone-3-conversation-and-runtime.md`

Load this file as the detailed execution unit for Task 10.4. Treat Task Group 10 and the milestone file as ordering indexes, not as the full task body.

---

**Files:**
- Create: `core_matrix/db/migrate/20260324090034_create_subagent_runs.rb`
- Create: `core_matrix/db/migrate/20260324090038_create_execution_leases.rb`
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
