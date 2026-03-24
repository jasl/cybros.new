# Core Matrix Task 04: Build User Bindings, Private Workspaces, And Bundled Default-Agent Bootstrap

Part of `Core Matrix Kernel Phase 1: Foundations`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-phase-1-foundations.md`
5. `docs/plans/2026-03-24-core-matrix-kernel-ui-follow-up.md`
6. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

Load this file as the detailed execution unit for Task 04. Treat the phase file as the ordering index, not the full task body.

---


**Files:**
- Create: `core_matrix/db/migrate/20260324090011_create_user_agent_bindings.rb`
- Create: `core_matrix/db/migrate/20260324090012_create_workspaces.rb`
- Create: `core_matrix/app/models/user_agent_binding.rb`
- Create: `core_matrix/app/models/workspace.rb`
- Create: `core_matrix/app/services/user_agent_bindings/enable.rb`
- Create: `core_matrix/app/services/workspaces/create_default.rb`
- Create: `core_matrix/app/services/installations/register_bundled_agent_runtime.rb`
- Create: `core_matrix/app/services/installations/bootstrap_bundled_agent_binding.rb`
- Create: `core_matrix/test/models/user_agent_binding_test.rb`
- Create: `core_matrix/test/models/workspace_test.rb`
- Create: `core_matrix/test/services/user_agent_bindings/enable_test.rb`
- Create: `core_matrix/test/services/workspaces/create_default_test.rb`
- Create: `core_matrix/test/services/installations/register_bundled_agent_runtime_test.rb`
- Create: `core_matrix/test/services/installations/bootstrap_bundled_agent_binding_test.rb`
- Create: `core_matrix/test/integration/user_binding_flow_test.rb`
- Modify: `core_matrix/app/services/installations/bootstrap_first_admin.rb`

**Step 1: Write failing unit tests**

Cover at least:

- one binding per user and agent installation pair
- default workspace requirement
- workspace privacy and ownership
- bundled runtime registration reconciles registry rows before binding
- bundled runtime registration is idempotent and must not duplicate logical or deployment rows
- bundled-agent bootstrap only when explicitly configured

**Step 2: Write a failing integration flow test**

`user_binding_flow_test.rb` should cover:

- enabling a global agent for a user
- creating a default workspace
- auto-registering the bundled default agent runtime into the registry when configuration is present
- auto-binding the bundled default agent to the first admin after registry reconciliation

**Step 3: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/user_agent_binding_test.rb test/models/workspace_test.rb test/services/user_agent_bindings/enable_test.rb test/services/workspaces/create_default_test.rb test/services/installations/register_bundled_agent_runtime_test.rb test/services/installations/bootstrap_bundled_agent_binding_test.rb test/integration/user_binding_flow_test.rb
```

Expected:

- failures for missing tables, models, or services

**Step 4: Write migrations, models, and services**

Include:

- `user_agent_bindings` with installation FK, user FK, agent installation FK, enabled state, user-local config JSON
- `workspaces` with installation FK, user FK, binding FK, name, public identifier, default flag, status
- bootstrap logic that first idempotently reconciles bundled `AgentInstallation`, `ExecutionEnvironment`, and `AgentDeployment` rows, then creates the first bundled binding plus default workspace when bundled `agents/fenix` is available and configured

**Step 5: Run migrations and targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/user_agent_binding_test.rb test/models/workspace_test.rb test/services/user_agent_bindings/enable_test.rb test/services/workspaces/create_default_test.rb test/services/installations/register_bundled_agent_runtime_test.rb test/services/installations/bootstrap_bundled_agent_binding_test.rb test/integration/user_binding_flow_test.rb
```

Expected:

- targeted tests pass

**Step 6: Commit**

```bash
git -C .. add core_matrix/db/migrate core_matrix/app/models core_matrix/app/services/user_agent_bindings core_matrix/app/services/workspaces core_matrix/app/services/installations core_matrix/test/models core_matrix/test/services core_matrix/test/integration core_matrix/db/schema.rb
git -C .. commit -m "feat: add user bindings and workspace ownership"
```
