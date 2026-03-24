# Core Matrix Task 03: Build Agent Registry And Connectivity Foundations

Part of `Core Matrix Kernel Milestone 1: Foundations`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-milestone-1-foundations.md`

Load this file as the detailed execution unit for Task 03. Treat the milestone file as the ordering index, not the full task body.

---


**Files:**
- Create: `core_matrix/db/migrate/20260324090006_create_agent_installations.rb`
- Create: `core_matrix/db/migrate/20260324090007_create_execution_environments.rb`
- Create: `core_matrix/db/migrate/20260324090008_create_agent_enrollments.rb`
- Create: `core_matrix/db/migrate/20260324090009_create_agent_deployments.rb`
- Create: `core_matrix/db/migrate/20260324090010_create_capability_snapshots.rb`
- Create: `core_matrix/app/models/agent_installation.rb`
- Create: `core_matrix/app/models/execution_environment.rb`
- Create: `core_matrix/app/models/agent_enrollment.rb`
- Create: `core_matrix/app/models/agent_deployment.rb`
- Create: `core_matrix/app/models/capability_snapshot.rb`
- Create: `core_matrix/app/services/agent_enrollments/issue.rb`
- Create: `core_matrix/app/services/agent_deployments/register.rb`
- Create: `core_matrix/app/services/agent_deployments/record_heartbeat.rb`
- Create: `core_matrix/test/models/agent_installation_test.rb`
- Create: `core_matrix/test/models/execution_environment_test.rb`
- Create: `core_matrix/test/models/agent_enrollment_test.rb`
- Create: `core_matrix/test/models/agent_deployment_test.rb`
- Create: `core_matrix/test/models/capability_snapshot_test.rb`
- Create: `core_matrix/test/services/agent_enrollments/issue_test.rb`
- Create: `core_matrix/test/services/agent_deployments/register_test.rb`
- Create: `core_matrix/test/services/agent_deployments/record_heartbeat_test.rb`
- Create: `core_matrix/test/integration/agent_registry_flow_test.rb`

**Step 1: Write failing unit tests for agent registry models**

Cover at least:

- `AgentInstallation` visibility `personal | global`
- optional owner user when personal
- `ExecutionEnvironment` kind and connection metadata
- enrollment token lifecycle
- deployment uniqueness by `agent_installation` and active state
- health state enum and heartbeat timestamps
- capability snapshot immutability and versioning
- audit rows for enrollment issuance and deployment registration

**Step 2: Write a failing integration flow test**

`agent_registry_flow_test.rb` should cover:

- minting an enrollment token
- consuming it to create a deployment
- rotating deployment state from pending to active
- recording heartbeat and health metadata
- writing audit rows for enrollment issuance and successful registration

**Step 3: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/agent_installation_test.rb test/models/execution_environment_test.rb test/models/agent_enrollment_test.rb test/models/agent_deployment_test.rb test/models/capability_snapshot_test.rb test/services/agent_enrollments/issue_test.rb test/services/agent_deployments/register_test.rb test/services/agent_deployments/record_heartbeat_test.rb test/integration/agent_registry_flow_test.rb
```

Expected:

- failures for missing tables, models, associations, and enums

**Step 4: Write migrations, models, and services**

Include:

- `agent_installations` with installation FK, visibility, owner user FK, key, display name, lifecycle state
- `execution_environments` with installation FK, kind, connection metadata, lifecycle state
- `agent_enrollments` with installation FK, agent installation FK, token digest, expires_at, consumed_at
- `agent_deployments` with installation FK, agent installation FK, execution environment FK, machine credential digest, endpoint metadata, fingerprint, health fields, bootstrap state
- `capability_snapshots` with deployment FK, version, protocol-method metadata, tool-catalog metadata, config schema snapshots, conversation-override schema snapshot, and default config snapshot
- active deployment uniqueness scoped to `agent_installation_id`, not the top-level `Installation`
- enrollment issuance and successful registration must create audit rows

**Step 5: Run migrations and targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/agent_installation_test.rb test/models/execution_environment_test.rb test/models/agent_enrollment_test.rb test/models/agent_deployment_test.rb test/models/capability_snapshot_test.rb test/services/agent_enrollments/issue_test.rb test/services/agent_deployments/register_test.rb test/services/agent_deployments/record_heartbeat_test.rb test/integration/agent_registry_flow_test.rb
```

Expected:

- migrations apply
- targeted tests pass

**Step 6: Commit**

```bash
git -C .. add core_matrix/db/migrate core_matrix/app/models core_matrix/app/services/agent_enrollments core_matrix/app/services/agent_deployments core_matrix/test/models core_matrix/test/services core_matrix/test/integration core_matrix/db/schema.rb
git -C .. commit -m "feat: add agent registry foundations"
```

## Stop Point

Stop after agent installation, enrollment, deployment, heartbeat, and capability snapshot foundations pass their tests.

Do not implement these items in this task:

- user bindings or bundled bootstrap
- provider catalog or governance
- machine-facing controllers or recovery flows
