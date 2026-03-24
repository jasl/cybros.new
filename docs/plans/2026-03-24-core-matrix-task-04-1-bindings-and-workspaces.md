# Core Matrix Task 04.1: Build User Bindings And Private Workspaces

Part of `Core Matrix Kernel Phase 1: Foundations`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-phase-1-foundations.md`

Load this file as the detailed execution unit for Task 04.1. Treat Task 04 and the phase file as ordering indexes, not as the full task body.

---

**Files:**
- Create: `core_matrix/db/migrate/20260324090011_create_user_agent_bindings.rb`
- Create: `core_matrix/db/migrate/20260324090012_create_workspaces.rb`
- Create: `core_matrix/app/models/user_agent_binding.rb`
- Create: `core_matrix/app/models/workspace.rb`
- Create: `core_matrix/app/services/user_agent_bindings/enable.rb`
- Create: `core_matrix/app/services/workspaces/create_default.rb`
- Create: `core_matrix/test/models/user_agent_binding_test.rb`
- Create: `core_matrix/test/models/workspace_test.rb`
- Create: `core_matrix/test/services/user_agent_bindings/enable_test.rb`
- Create: `core_matrix/test/services/workspaces/create_default_test.rb`
- Create: `core_matrix/test/integration/user_binding_workspace_flow_test.rb`

**Step 1: Write failing model, service, and integration tests**

Cover at least:

- one binding per user and agent installation pair
- binding ownership constrained to one installation
- workspace privacy and ownership
- one default workspace per binding
- default workspace creation reusing the binding ownership boundary
- enabling a global agent for a user without creating duplicate bindings

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/user_agent_binding_test.rb test/models/workspace_test.rb test/services/user_agent_bindings/enable_test.rb test/services/workspaces/create_default_test.rb test/integration/user_binding_workspace_flow_test.rb
```

Expected:

- failures for missing tables, models, or services

**Step 3: Write migrations, models, and services**

Rules:

- `user_agent_bindings` must belong to `Installation`, `User`, and `AgentInstallation`
- `workspaces` must belong to `Installation`, `User`, and `UserAgentBinding`
- `Workspace` remains private and user-owned in v1
- default-workspace uniqueness is per binding, not per installation
- reuse services for ownership checks instead of ad hoc controller or model callbacks
- do not add bundled runtime registration or first-admin bootstrap behavior in this subtask

**Step 4: Run migrations and targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/user_agent_binding_test.rb test/models/workspace_test.rb test/services/user_agent_bindings/enable_test.rb test/services/workspaces/create_default_test.rb test/integration/user_binding_workspace_flow_test.rb
```

Expected:

- targeted tests pass

**Step 5: Commit**

```bash
git -C .. add core_matrix/db/migrate core_matrix/app/models core_matrix/app/services/user_agent_bindings core_matrix/app/services/workspaces core_matrix/test/models core_matrix/test/services core_matrix/test/integration core_matrix/db/schema.rb
git -C .. commit -m "feat: add user bindings and workspaces"
```

## Stop Point

Stop after bindings, workspaces, and default-workspace creation pass their tests.

Do not implement these items in this subtask:

- bundled runtime registration
- bundled first-admin auto-binding
- changes to `bootstrap_first_admin`
