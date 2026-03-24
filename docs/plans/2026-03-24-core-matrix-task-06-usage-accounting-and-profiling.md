# Core Matrix Task 06: Build Usage Accounting, Rollups, And Execution Profiling Facts

Part of `Core Matrix Kernel Phase 2: Governance And Accounting`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-phase-2-governance-and-accounting.md`
5. `docs/plans/2026-03-24-core-matrix-kernel-ui-follow-up.md`
6. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

Load this file as the detailed execution unit for Task 06. Treat the phase file as the ordering index, not the full task body.

---


**Files:**
- Create: `core_matrix/db/migrate/20260324090016_create_usage_events.rb`
- Create: `core_matrix/db/migrate/20260324090017_create_usage_rollups.rb`
- Create: `core_matrix/db/migrate/20260324090018_create_execution_profile_facts.rb`
- Create: `core_matrix/app/models/usage_event.rb`
- Create: `core_matrix/app/models/usage_rollup.rb`
- Create: `core_matrix/app/models/execution_profile_fact.rb`
- Create: `core_matrix/app/services/provider_usage/record_event.rb`
- Create: `core_matrix/app/services/provider_usage/project_rollups.rb`
- Create: `core_matrix/app/services/execution_profiling/record_fact.rb`
- Create: `core_matrix/test/models/usage_event_test.rb`
- Create: `core_matrix/test/models/usage_rollup_test.rb`
- Create: `core_matrix/test/models/execution_profile_fact_test.rb`
- Create: `core_matrix/test/services/provider_usage/record_event_test.rb`
- Create: `core_matrix/test/services/provider_usage/project_rollups_test.rb`
- Create: `core_matrix/test/services/execution_profiling/record_fact_test.rb`
- Create: `core_matrix/test/integration/runtime_accounting_flow_test.rb`

**Step 1: Write failing unit tests**

Cover at least:

- usage events carrying user, workspace, conversation, turn, workflow node, provider, model, and operation dimensions
- rollup uniqueness by bucket and dimensions
- execution profile facts for generic operation kinds such as tool calls, subagent outcomes, approval wait time, and process failures without requiring later runtime-resource tables to exist yet
- support for token-based and media-unit usage

**Step 2: Write a failing integration flow test**

`runtime_accounting_flow_test.rb` should cover:

- recording a usage event
- projecting hourly and daily rollups
- recording separate execution profile facts without polluting provider usage rows

**Step 3: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/usage_event_test.rb test/models/usage_rollup_test.rb test/models/execution_profile_fact_test.rb test/services/provider_usage/record_event_test.rb test/services/provider_usage/project_rollups_test.rb test/services/execution_profiling/record_fact_test.rb test/integration/runtime_accounting_flow_test.rb
```

Expected:

- missing table and model failures

**Step 4: Write migrations, models, and services**

Include:

- rollup rows keyed by hour, day, and explicit rolling-window identifiers
- profile facts separated from provider billing facts
- generic fact dimensions and nullable references so later runtime resources such as `ProcessRun`, `SubagentRun`, or `HumanInteractionRequest` can attach without forcing schema redesign in this phase
- no hard dependency in this phase on runtime-resource tables that are introduced later in Phase 3
- global hard-limit support without per-user enforced quotas

**Step 5: Run migrations and targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/usage_event_test.rb test/models/usage_rollup_test.rb test/models/execution_profile_fact_test.rb test/services/provider_usage/record_event_test.rb test/services/provider_usage/project_rollups_test.rb test/services/execution_profiling/record_fact_test.rb test/integration/runtime_accounting_flow_test.rb
```

Expected:

- targeted tests pass

**Step 6: Commit**

```bash
git -C .. add core_matrix/db/migrate core_matrix/app/models core_matrix/app/services/provider_usage core_matrix/app/services/execution_profiling core_matrix/test/models core_matrix/test/services core_matrix/test/integration core_matrix/db/schema.rb
git -C .. commit -m "feat: add usage accounting and profiling facts"
```
