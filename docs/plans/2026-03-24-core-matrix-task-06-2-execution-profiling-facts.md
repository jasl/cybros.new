# Core Matrix Task 06.2: Add Execution Profiling Facts

Part of `Core Matrix Kernel Milestone 2: Governance And Accounting`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-milestone-2-governance-and-accounting.md`

Load this file as the detailed execution unit for Task 06.2. Treat Task Group 06 and the milestone file as ordering indexes, not as the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the consulted slice and the retained conclusion, invariant, or intentional difference in this task document or another local document updated by the same execution unit
- when this task updates behavior docs, checklist docs, or other local docs, carry that conclusion into those docs instead of leaving only a bare reference path
- keep reference paths as index pointers only; restate the relevant behavior locally so this task remains understandable if the reference later drifts

---

**Files:**
- Create: `core_matrix/db/migrate/20260324090018_create_execution_profile_facts.rb`
- Create: `core_matrix/app/models/execution_profile_fact.rb`
- Create: `core_matrix/app/services/execution_profiling/record_fact.rb`
- Create: `core_matrix/test/models/execution_profile_fact_test.rb`
- Create: `core_matrix/test/services/execution_profiling/record_fact_test.rb`
- Create: `core_matrix/test/integration/execution_profiling_flow_test.rb`

**Step 1: Write failing model, service, and integration tests**

Cover at least:

- execution profile facts for generic operation kinds such as tool calls, subagent outcomes, approval wait time, and process failures
- profile facts remaining separated from provider billing facts
- generic fact dimensions and nullable references so later runtime resources such as `ProcessRun`, `SubagentRun`, or `HumanInteractionRequest` can attach without forcing schema redesign
- recording separate execution profile facts without polluting provider usage rows

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/execution_profile_fact_test.rb test/services/execution_profiling/record_fact_test.rb test/integration/execution_profiling_flow_test.rb
```

Expected:

- missing table and model failures

**Step 3: Write migration, model, and service**

Rules:

- profile facts must stay separated from provider billing facts
- generic fact dimensions and nullable references must not depend on later runtime-resource tables already existing
- keep profiling recording behind an explicit service boundary

**Step 4: Run migrations and targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/execution_profile_fact_test.rb test/services/execution_profiling/record_fact_test.rb test/integration/execution_profiling_flow_test.rb
```

Expected:

- targeted tests pass

**Step 5: Commit**

```bash
git -C .. add core_matrix/db/migrate core_matrix/app/models/execution_profile_fact.rb core_matrix/app/services/execution_profiling core_matrix/test/models core_matrix/test/services core_matrix/test/integration core_matrix/db/schema.rb
git -C .. commit -m "feat: add execution profiling facts"
```

## Stop Point

Stop after execution profiling facts pass their tests.

Do not implement these items in this task:

- provider usage rollups
- runtime read-side summary queries
- runtime-resource tables from Milestone 3
