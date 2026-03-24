# Core Matrix Kernel Phase 1: Foundations

Use this phase document together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-ui-follow-up.md`
5. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

This phase owns Tasks 1-4:

- Rails shell and validation scaffolding
- installation, identity, invitation, session, and audit foundations
- agent registry and connectivity foundations
- user bindings, private workspaces, and bundled default-agent bootstrap

Apply the shared guardrails and phase-gate audits from the implementation-plan index.

---
### Task 1: Re-Baseline The Rails Shell And Validation Scaffolding

**Files:**
- Verify: `core_matrix/Gemfile`
- Verify: `core_matrix/db/schema.rb`
- Verify: `core_matrix/app/models/application_record.rb`
- Verify: `core_matrix/config/routes.rb`
- Create: `core_matrix/test/support/.keep`
- Create: `core_matrix/test/services/.keep`
- Create: `core_matrix/test/queries/.keep`
- Create: `core_matrix/test/integration/.keep`
- Create: `core_matrix/test/requests/.keep`
- Create: `core_matrix/script/manual/.keep`
- Modify: `core_matrix/README.md`

**Step 1: Document the backend phase boundary**

- Update `core_matrix/README.md` to point at the greenfield design doc, UI follow-up doc, and manual validation checklist.
- State explicitly that human-facing UI is out of scope for this phase.

**Step 2: Verify the shell baseline**

Run:

```bash
cd core_matrix
bin/rails db:version
bin/rails test
bin/rubocop app/models/application_record.rb
```

Expected:

- database version resolves without missing migration errors
- test suite is either empty or green
- RuboCop passes for the baseline file

**Step 3: Add empty directories for test and manual-validation work**

- Create `core_matrix/test/support/.keep`
- Create `core_matrix/test/services/.keep`
- Create `core_matrix/test/queries/.keep`
- Create `core_matrix/test/integration/.keep`
- Create `core_matrix/test/requests/.keep`
- Create `core_matrix/script/manual/.keep`

**Step 4: Commit**

```bash
git -C .. add core_matrix/README.md core_matrix/test/support/.keep core_matrix/test/services/.keep core_matrix/test/queries/.keep core_matrix/test/integration/.keep core_matrix/test/requests/.keep core_matrix/script/manual/.keep
git -C .. commit -m "chore: reset core matrix backend shell baseline"
```

### Task 2: Build Installation, Identity, User, Invitation, Session, And Audit Foundations

**Files:**
- Create: `core_matrix/db/migrate/20260324090000_create_installations.rb`
- Create: `core_matrix/db/migrate/20260324090001_create_identities.rb`
- Create: `core_matrix/db/migrate/20260324090002_create_users.rb`
- Create: `core_matrix/db/migrate/20260324090003_create_invitations.rb`
- Create: `core_matrix/db/migrate/20260324090004_create_sessions.rb`
- Create: `core_matrix/db/migrate/20260324090005_create_audit_logs.rb`
- Create: `core_matrix/app/models/installation.rb`
- Create: `core_matrix/app/models/identity.rb`
- Create: `core_matrix/app/models/user.rb`
- Create: `core_matrix/app/models/invitation.rb`
- Create: `core_matrix/app/models/session.rb`
- Create: `core_matrix/app/models/audit_log.rb`
- Create: `core_matrix/app/services/installations/bootstrap_first_admin.rb`
- Create: `core_matrix/app/services/invitations/consume.rb`
- Create: `core_matrix/app/services/users/grant_admin.rb`
- Create: `core_matrix/app/services/users/revoke_admin.rb`
- Create: `core_matrix/test/models/installation_test.rb`
- Create: `core_matrix/test/models/identity_test.rb`
- Create: `core_matrix/test/models/user_test.rb`
- Create: `core_matrix/test/models/invitation_test.rb`
- Create: `core_matrix/test/models/session_test.rb`
- Create: `core_matrix/test/models/audit_log_test.rb`
- Create: `core_matrix/test/services/installations/bootstrap_first_admin_test.rb`
- Create: `core_matrix/test/services/invitations/consume_test.rb`
- Create: `core_matrix/test/services/users/grant_admin_test.rb`
- Create: `core_matrix/test/services/users/revoke_admin_test.rb`
- Create: `core_matrix/test/integration/installation_bootstrap_flow_test.rb`
- Modify: `core_matrix/config/initializers/filter_parameter_logging.rb`
- Modify: `core_matrix/test/test_helper.rb`

**Step 1: Write failing unit tests for root aggregates**

Cover at least:

- single-row installation bootstrap assumptions
- `Identity` email normalization and uniqueness
- `Identity` password presence and authentication via `has_secure_password`
- `User` admin role semantics
- admin grant and revoke legality
- forbidding revocation of the last active admin
- invitation token uniqueness, expiration, and consumption
- session token uniqueness, expiration, and revocation
- audit log actor and subject shape

**Step 2: Write a failing integration flow test**

`installation_bootstrap_flow_test.rb` should cover:

- creating the first installation, identity, and admin user
- rejecting or safely no-oping a second bootstrap attempt
- creating an invitation and consuming it for a second user
- granting and revoking admin on a later user
- audit rows written for bootstrap, invite consumption, and admin role changes

**Step 3: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/installation_test.rb test/models/identity_test.rb test/models/user_test.rb test/models/invitation_test.rb test/models/session_test.rb test/models/audit_log_test.rb test/services/installations/bootstrap_first_admin_test.rb test/services/invitations/consume_test.rb test/services/users/grant_admin_test.rb test/services/users/revoke_admin_test.rb test/integration/installation_bootstrap_flow_test.rb
```

Expected:

- failures for missing tables, models, and validations

**Step 4: Write migrations and models**

Include:

- `installations` with name, bootstrap state, and global settings JSON
- `identities` with email, password digest, auth metadata, and disable state
- `users` with installation FK, identity FK, role state, display name, preferences JSON
- `invitations` with installation FK, inviter FK, token digest, email, expires_at, consumed_at
- `sessions` with identity FK, user FK, token digest, expires_at, revoked_at, metadata
- `audit_logs` with installation FK, actor polymorphism, action, subject polymorphism, metadata JSON

**Step 5: Implement minimal services**

- use transactions for bootstrap and invitation consumption
- implement explicit admin grant and revoke services with audit writes
- block revocation of the last active admin user
- keep orchestration in services, not callbacks
- filter auth secrets in logs

**Step 6: Run migrations and targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/installation_test.rb test/models/identity_test.rb test/models/user_test.rb test/models/invitation_test.rb test/models/session_test.rb test/models/audit_log_test.rb test/services/installations/bootstrap_first_admin_test.rb test/services/invitations/consume_test.rb test/services/users/grant_admin_test.rb test/services/users/revoke_admin_test.rb test/integration/installation_bootstrap_flow_test.rb
```

Expected:

- migrations apply cleanly
- targeted tests pass

**Step 7: Commit**

```bash
git -C .. add core_matrix/db/migrate core_matrix/app/models core_matrix/app/services/installations core_matrix/app/services/invitations core_matrix/app/services/users core_matrix/test/models core_matrix/test/services core_matrix/test/integration core_matrix/test/test_helper.rb core_matrix/config/initializers/filter_parameter_logging.rb core_matrix/db/schema.rb
git -C .. commit -m "feat: add installation identity foundations"
```

### Task 3: Build Agent Registry And Connectivity Foundations

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
- `capability_snapshots` with deployment FK, version, payload JSON, schema snapshots, and default config snapshot
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

### Task 4: Build User Bindings, Private Workspaces, And Bundled Default-Agent Bootstrap

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
