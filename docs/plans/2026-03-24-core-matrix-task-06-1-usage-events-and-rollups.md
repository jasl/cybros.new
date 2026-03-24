# Core Matrix Task 06.1: Add Usage Events And Rollups

Part of `Core Matrix Kernel Phase 2: Governance And Accounting`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-phase-2-governance-and-accounting.md`

Load this file as the detailed execution unit for Task 06.1. Treat Task 06 and the phase file as ordering indexes, not as the full task body.

---

**Files:**
- Create: `core_matrix/db/migrate/20260324090016_create_usage_events.rb`
- Create: `core_matrix/db/migrate/20260324090017_create_usage_rollups.rb`
- Create: `core_matrix/app/models/usage_event.rb`
- Create: `core_matrix/app/models/usage_rollup.rb`
- Create: `core_matrix/app/services/provider_usage/record_event.rb`
- Create: `core_matrix/app/services/provider_usage/project_rollups.rb`
- Create: `core_matrix/test/models/usage_event_test.rb`
- Create: `core_matrix/test/models/usage_rollup_test.rb`
- Create: `core_matrix/test/services/provider_usage/record_event_test.rb`
- Create: `core_matrix/test/services/provider_usage/project_rollups_test.rb`
- Create: `core_matrix/test/integration/provider_usage_rollup_flow_test.rb`

**Step 1: Write failing model, service, and integration tests**

Cover at least:

- usage events carrying user, workspace, conversation, turn, workflow node, provider, model, and operation dimensions
- rollup uniqueness by bucket and dimensions
- support for token-based and media-unit usage
- recording a usage event and projecting hourly and daily rollups
- rollup rows keyed by hour, day, and explicit rolling-window identifiers

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/usage_event_test.rb test/models/usage_rollup_test.rb test/services/provider_usage/record_event_test.rb test/services/provider_usage/project_rollups_test.rb test/integration/provider_usage_rollup_flow_test.rb
```

Expected:

- missing table and model failures

**Step 3: Write migrations, models, and services**

Rules:

- no hard dependency in this subtask on runtime-resource tables that are introduced later in Phase 3
- preserve generic dimensions and nullable references so later runtime resources can attach without schema redesign
- global hard-limit support is allowed, but do not add per-user enforced quotas here

**Step 4: Run migrations and targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/usage_event_test.rb test/models/usage_rollup_test.rb test/services/provider_usage/record_event_test.rb test/services/provider_usage/project_rollups_test.rb test/integration/provider_usage_rollup_flow_test.rb
```

Expected:

- targeted tests pass

**Step 5: Commit**

```bash
git -C .. add core_matrix/db/migrate core_matrix/app/models/usage_event.rb core_matrix/app/models/usage_rollup.rb core_matrix/app/services/provider_usage core_matrix/test/models core_matrix/test/services core_matrix/test/integration core_matrix/db/schema.rb
git -C .. commit -m "feat: add provider usage events and rollups"
```

## Stop Point

Stop after usage events and rollups pass their tests.

Do not implement these items in this subtask:

- execution profiling facts
- read-side usage summary queries
- runtime-resource-specific foreign-key coupling
