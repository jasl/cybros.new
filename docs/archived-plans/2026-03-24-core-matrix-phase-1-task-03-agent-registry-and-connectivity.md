# Core Matrix Task 03: Build Agent Registry And Connectivity Foundations

Part of `Core Matrix Kernel Milestone 1: Foundations`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/finished-plans/2026-03-24-core-matrix-phase-1-kernel-greenfield-implementation-plan.md`
4. `docs/finished-plans/2026-03-24-core-matrix-phase-1-kernel-milestone-1-foundations.md`

Load this file as the detailed execution unit for Task 03. Treat the milestone file as the ordering index, not the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the consulted slice and the retained conclusion, invariant, or intentional difference in this task document or another local document updated by the same execution unit
- when this task updates behavior docs, checklist docs, or other local docs, carry that conclusion into those docs instead of leaving only a bare reference path
- keep reference paths as index pointers only; restate the relevant behavior locally so this task remains understandable if the reference later drifts

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
- Modify: `core_matrix/app/models/installation.rb`
- Modify: `core_matrix/app/models/user.rb`
- Create: `core_matrix/app/services/agent_enrollments/issue.rb`
- Create: `core_matrix/app/services/agent_deployments/register.rb`
- Create: `core_matrix/app/services/agent_deployments/record_heartbeat.rb`
- Create: `core_matrix/docs/behavior/agent-registry-and-connectivity-foundations.md`
- Create: `core_matrix/test/models/agent_installation_test.rb`
- Create: `core_matrix/test/models/execution_environment_test.rb`
- Create: `core_matrix/test/models/agent_enrollment_test.rb`
- Create: `core_matrix/test/models/agent_deployment_test.rb`
- Create: `core_matrix/test/models/capability_snapshot_test.rb`
- Create: `core_matrix/test/services/agent_enrollments/issue_test.rb`
- Create: `core_matrix/test/services/agent_deployments/register_test.rb`
- Create: `core_matrix/test/services/agent_deployments/record_heartbeat_test.rb`
- Create: `core_matrix/test/integration/agent_registry_flow_test.rb`
- Modify: `core_matrix/test/test_helper.rb`
- Modify: `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

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
- `agent_deployments` with installation FK, agent installation FK, execution environment FK, connection credential digest, endpoint metadata, fingerprint, health fields, bootstrap state
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

**Step 6: Update behavior and manual validation docs**

- Add `core_matrix/docs/behavior/agent-registry-and-connectivity-foundations.md`
  describing registry aggregate boundaries, snapshot rules, and heartbeat
  lifecycle behavior.
- Update `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`
  with shell-reproducible steps for enrollment issuance, registration, and the
  first healthy heartbeat.

**Step 7: Commit**

```bash
git -C .. add core_matrix/db/migrate core_matrix/app/models core_matrix/app/services/agent_enrollments core_matrix/app/services/agent_deployments core_matrix/docs/behavior/agent-registry-and-connectivity-foundations.md core_matrix/test/models core_matrix/test/services core_matrix/test/integration core_matrix/test/test_helper.rb core_matrix/db/schema.rb docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md
git -C .. commit -m "feat: add agent registry foundations"
```

## Stop Point

Stop after agent installation, enrollment, deployment, heartbeat, and capability snapshot foundations pass their tests.

Do not implement these items in this task:

- user bindings or bundled bootstrap
- provider catalog or governance
- machine-facing controllers or recovery flows

## Completion Record

- status:
  completed on `2026-03-24` in commit `5c76965`
- actual landed scope:
  - added migrations `20260324090006` through `20260324090010`
  - added logical agent installations, execution environments, enrollments,
    deployments, capability snapshots, enrollment issuance, deployment
    registration, and heartbeat recording
  - updated parent associations on `Installation` and `User`, extended
    `core_matrix/test/test_helper.rb`, added manual checklist flow coverage,
    and added `core_matrix/docs/behavior/agent-registry-and-connectivity-foundations.md`
- plan alignment notes:
  - the file list above has been updated to match the real landed support-doc
    and helper changes that were required to keep the task self-contained
- verification evidence:
  - the original acceptance gate for this task was the targeted test command in
    Step 5
  - the `2026-03-24` doc-hardening rerun included
    `cd core_matrix && bin/rails test test/integration/agent_registry_flow_test.rb`
    inside the Milestone 1 integration spot-check, which passed
  - the same rerun also passed `cd core_matrix && bin/rails test` with
    `40 runs, 188 assertions, 0 failures, 0 errors`
- retained findings:
  - active deployment uniqueness is scoped to `agent_installation_id`, not the
    top-level installation
  - a deployment stays `pending` until the first healthy heartbeat promotes it
    to `active`
  - capability snapshots are append-only historical records with an explicit
    `active_capability_snapshot` pointer on the deployment
  - no product-behavior conclusion from non-authoritative reference projects
    was retained for this task
- carry-forward notes:
  - later protocol, recovery, and bootstrap work must continue to preserve
    `AgentInstallation` versus `AgentDeployment` separation
  - later capability changes should append or repoint snapshots instead of
    mutating historical snapshot rows in place
