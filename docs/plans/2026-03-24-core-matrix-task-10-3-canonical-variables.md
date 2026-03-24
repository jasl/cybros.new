# Core Matrix Task 10.3: Add Canonical Variables

Part of `Core Matrix Kernel Phase 3: Conversation And Runtime`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-phase-3-conversation-and-runtime.md`

Load this file as the detailed execution unit for Task 10.3. Treat Task 10 and the phase file as ordering indexes, not as the full task body.

---

**Files:**
- Create: `core_matrix/db/migrate/20260324090036_create_canonical_variables.rb`
- Create: `core_matrix/app/models/canonical_variable.rb`
- Create: `core_matrix/app/services/variables/write.rb`
- Create: `core_matrix/app/services/variables/promote_to_workspace.rb`
- Create: `core_matrix/test/models/canonical_variable_test.rb`
- Create: `core_matrix/test/services/variables/write_test.rb`
- Create: `core_matrix/test/services/variables/promote_to_workspace_test.rb`
- Create: `core_matrix/test/integration/canonical_variable_flow_test.rb`

**Step 1: Write failing model, service, and integration tests**

Cover at least:

- canonical variable scope rules for `workspace` and `conversation`
- canonical variable supersession history
- explicit promotion from conversation to workspace
- preserved history when a current value is superseded

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/canonical_variable_test.rb test/services/variables/write_test.rb test/services/variables/promote_to_workspace_test.rb test/integration/canonical_variable_flow_test.rb
```

Expected:

- missing table and model failures

**Step 3: Write migration, model, and services**

Rules:

- canonical variables must support only `workspace` and `conversation` scope in v1
- canonical variable writes supersede prior current values without deleting history
- conversation-scope canonical values may be explicitly promoted to workspace scope
- keep write and promotion semantics in kernel-owned services rather than direct model mutation from callers

**Step 4: Run migrations and targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/canonical_variable_test.rb test/services/variables/write_test.rb test/services/variables/promote_to_workspace_test.rb test/integration/canonical_variable_flow_test.rb
```

Expected:

- targeted tests pass

**Step 5: Commit**

```bash
git -C .. add core_matrix/db/migrate core_matrix/app/models/canonical_variable.rb core_matrix/app/services/variables core_matrix/test/models core_matrix/test/services core_matrix/test/integration core_matrix/db/schema.rb
git -C .. commit -m "feat: add canonical variable history"
```

## Stop Point

Stop after canonical variable write and promotion semantics pass their tests.

Do not implement these items in this subtask:

- machine-facing variable APIs
- publication read models
- any additional scope beyond `workspace` and `conversation`
