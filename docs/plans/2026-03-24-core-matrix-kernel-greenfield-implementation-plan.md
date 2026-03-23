# Core Matrix Kernel Greenfield Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rebuild `core_matrix` from a clean backend/domain baseline that matches the approved greenfield kernel design, starting from installation identity and ownership roots instead of from conversation runtime tables.

**Architecture:** Implement the kernel in layered order: installation and identity first, then agent registry and user bindings, then provider governance, then conversation runtime, and only after that runtime orchestration services. Treat the current Rails app as a clean shell with Active Storage already installed; do not reuse the old prototype schema or the superseded 2026-03-23 plan set. Keep this plan backend-first and model-first. Do not enter controllers, channels, views, or JavaScript UI work except where a minimal auth or setup service boundary is required for backend correctness.

**Tech Stack:** Rails 8.2, PostgreSQL, Active Storage, Minitest, bcrypt `has_secure_password`, RuboCop, Brakeman, Bundler Audit, Bun for existing frontend tooling only.

---

## Source Documents

Read these before each phase:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-design.md`

Do not use the deleted 2026-03-23 plan documents as implementation truth.

## Implementation Guardrails

- Build root aggregates before conversation/runtime tables.
- Keep only `personal` and `global` resource scopes.
- Keep `Identity` and `User` separate.
- Keep `AgentInstallation` and `AgentDeployment` separate.
- Require TDD for every new model and service.
- Commit after each finished task.
- Do not implement business-agent behavior in `core_matrix`.
- Do not implement collaborative conversations, group ACLs, or built-in memory systems in this plan.
- Do not implement controllers or UI in this plan unless a task explicitly says so.

## Phase Gates

At the end of each task, perform two audits before moving on:

1. Missing-fields audit: check for missing columns, indexes, associations, validations, enums, and test coverage against the greenfield design.
2. Boundary audit: check that the new code did not collapse domain boundaries such as `Identity` versus `User`, `AgentInstallation` versus `AgentDeployment`, or `Workspace` versus `Publication`.

If either audit fails, fix the issue inside the same task before continuing.

### Task 1: Re-Baseline The Rails Shell

**Files:**
- Verify: `core_matrix/Gemfile`
- Verify: `core_matrix/db/migrate/20260322213202_create_active_storage_tables.active_storage.rb`
- Verify: `core_matrix/db/schema.rb`
- Verify: `core_matrix/app/models/application_record.rb`
- Verify: `core_matrix/app/services/.keep`
- Verify: `core_matrix/app/queries/.keep`
- Create: `core_matrix/test/support/.keep`
- Create: `core_matrix/test/services/.keep`
- Create: `core_matrix/test/queries/.keep`
- Modify: `core_matrix/README.md`

**Step 1: Write a baseline checklist into the README**

- Add a short backend-foundation note to `core_matrix/README.md` that points engineers at the new greenfield design doc and states that old prototype schema work is intentionally discarded.

**Step 2: Verify the shell starts from the correct baseline**

Run:

```bash
cd core_matrix
bundle exec rails db:version
bundle exec rails test
bin/rubocop app/models/application_record.rb
```

Expected:

- database version resolves without missing migration errors
- test suite is either empty or green
- RuboCop passes for the baseline file

**Step 3: Add empty support directories for test-first work**

- Create `core_matrix/test/support/.keep`
- Create `core_matrix/test/services/.keep`
- Create `core_matrix/test/queries/.keep`

**Step 4: Commit the shell baseline**

```bash
git add core_matrix/README.md core_matrix/test/support/.keep core_matrix/test/services/.keep core_matrix/test/queries/.keep
git commit -m "chore: reset core matrix backend shell baseline"
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
- Create: `core_matrix/test/models/installation_test.rb`
- Create: `core_matrix/test/models/identity_test.rb`
- Create: `core_matrix/test/models/user_test.rb`
- Create: `core_matrix/test/models/invitation_test.rb`
- Create: `core_matrix/test/models/session_test.rb`
- Create: `core_matrix/test/models/audit_log_test.rb`
- Create: `core_matrix/test/services/installations/bootstrap_first_admin_test.rb`
- Create: `core_matrix/test/services/invitations/consume_test.rb`
- Modify: `core_matrix/config/initializers/filter_parameter_logging.rb`
- Modify: `core_matrix/test/test_helper.rb`

**Step 1: Write failing model tests for the root aggregates**

Cover at least:

- single-row installation bootstrap assumptions
- `Identity` email normalization and uniqueness
- `Identity` password presence via `has_secure_password`
- `User` admin role flag or enum
- `User` belongs to one installation and one identity
- invitation token uniqueness, expiration, consumption, and inviter audit metadata
- session token uniqueness and expiration semantics
- audit log shape for installation-level actors

**Step 2: Run the root model tests to verify failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/installation_test.rb test/models/identity_test.rb test/models/user_test.rb test/models/invitation_test.rb test/models/session_test.rb test/models/audit_log_test.rb
```

Expected:

- failures for missing tables, models, and validations

**Step 3: Write the migrations**

Include:

- `installations` with name, bootstrap state, and global settings JSON
- `identities` with email, password digest, auth metadata, and disable state
- `users` with installation FK, identity FK, role/admin state, display name, preferences JSON
- `invitations` with installation FK, inviter FK, token digest, email, expires_at, consumed_at
- `sessions` with identity FK, user FK, token digest, expires_at, revoked_at, metadata
- `audit_logs` with installation FK, actor polymorphism, action, subject polymorphism, metadata JSON

Add explicit indexes and foreign keys. Keep enums string-backed.

**Step 4: Write minimal model implementations**

Implement:

- associations
- enums
- validations
- token helpers
- password auth on `Identity`
- convenience scopes for active invitations and active sessions
- parameter filtering for password, session token, invitation token, and related auth secrets

**Step 5: Write failing service tests**

`Installations::BootstrapFirstAdmin` should:

- create the installation row if missing
- create the first identity and first admin user
- record audit logs
- be idempotent or explicitly reject a second bootstrap attempt

`Invitations::Consume` should:

- create `Identity + User` for a new email
- attach an existing identity when allowed
- mark the invitation consumed
- record audit logs

**Step 6: Implement minimal services**

- keep orchestration in services, not in models
- use transactions for bootstrap and invitation consumption

**Step 7: Run targeted tests and migrate schema**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/installation_test.rb test/models/identity_test.rb test/models/user_test.rb test/models/invitation_test.rb test/models/session_test.rb test/models/audit_log_test.rb test/services/installations/bootstrap_first_admin_test.rb test/services/invitations/consume_test.rb
```

Expected:

- migrations apply cleanly
- targeted tests pass

**Step 8: Commit**

```bash
git add core_matrix/db/migrate core_matrix/app/models core_matrix/app/services/installations core_matrix/app/services/invitations core_matrix/test/models core_matrix/test/services core_matrix/test/test_helper.rb core_matrix/db/schema.rb
git commit -m "feat: add installation identity foundations"
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

**Step 1: Write failing model tests**

Cover at least:

- `AgentInstallation` visibility `personal | global`
- optional owner user when personal
- `ExecutionEnvironment` kind and connectivity metadata
- one-time enrollment token lifecycle
- deployment uniqueness by installation plus fingerprint or active state
- health state enum and heartbeat timestamps
- capability snapshot immutability and versioning

**Step 2: Run the agent-registry model tests**

Run:

```bash
cd core_matrix
bin/rails test test/models/agent_installation_test.rb test/models/execution_environment_test.rb test/models/agent_enrollment_test.rb test/models/agent_deployment_test.rb test/models/capability_snapshot_test.rb
```

Expected:

- failures for missing tables, associations, and enums

**Step 3: Write migrations and models**

Include:

- `agent_installations` with installation FK, visibility, owner user FK, key, display name, lifecycle state
- `execution_environments` with installation FK, kind, connection metadata, lifecycle state
- `agent_enrollments` with installation FK, agent installation FK, token digest, expires_at, consumed_at
- `agent_deployments` with installation FK, agent installation FK, execution environment FK, machine credential digest, endpoint metadata, fingerprint, health fields, bootstrap state
- `capability_snapshots` with deployment FK, version, payload JSON, schema snapshots, defaults JSON

**Step 4: Write failing service tests**

`AgentEnrollments::Issue` should mint a one-time enrollment for a target agent installation.

`AgentDeployments::Register` should:

- consume an enrollment token
- create or activate a deployment
- mint a durable machine credential
- create an initial audit log

`AgentDeployments::RecordHeartbeat` should:

- refresh heartbeat timestamps
- update health state
- refuse retired or revoked deployments

**Step 5: Implement minimal services**

Keep RPC transport details out of the models. Services should only own persistence and state changes for now.

**Step 6: Run targeted tests and migrate**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/agent_installation_test.rb test/models/execution_environment_test.rb test/models/agent_enrollment_test.rb test/models/agent_deployment_test.rb test/models/capability_snapshot_test.rb test/services/agent_enrollments/issue_test.rb test/services/agent_deployments/register_test.rb test/services/agent_deployments/record_heartbeat_test.rb
```

Expected:

- migrations apply
- targeted tests pass

**Step 7: Commit**

```bash
git add core_matrix/db/migrate core_matrix/app/models core_matrix/app/services/agent_enrollments core_matrix/app/services/agent_deployments core_matrix/test/models core_matrix/test/services core_matrix/db/schema.rb
git commit -m "feat: add agent registry foundations"
```

### Task 4: Build User-Agent Bindings, Private Workspaces, And Publications

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

**Step 1: Write failing model tests**

Cover at least:

- one binding per user and agent installation pair
- default workspace requirement
- workspace privacy and ownership

**Step 2: Run the failing tests**

Run:

```bash
cd core_matrix
bin/rails test test/models/user_agent_binding_test.rb test/models/workspace_test.rb
```

Expected:

- failures for missing tables and models

**Step 3: Write migrations and models**

Include:

- `user_agent_bindings` with installation FK, user FK, agent installation FK, enabled state, user-local config JSON
- `workspaces` with installation FK, user FK, binding FK, name, slug or public id, default flag, status

Do not add shared workspace semantics or publication rows in this task.

**Step 4: Write failing service tests**

`UserAgentBindings::Enable` should:

- validate agent visibility rules
- create the binding
- create the default workspace
- audit the enable action

**Step 5: Implement minimal services and models**

Keep the task focused on bindings and private workspace creation.

**Step 6: Run targeted tests and migrate**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/user_agent_binding_test.rb test/models/workspace_test.rb test/services/user_agent_bindings/enable_test.rb test/services/workspaces/create_default_test.rb
```

Expected:

- targeted tests pass

**Step 7: Commit**

```bash
git add core_matrix/db/migrate core_matrix/app/models core_matrix/app/services/user_agent_bindings core_matrix/app/services/workspaces core_matrix/test/models core_matrix/test/services core_matrix/db/schema.rb
git commit -m "feat: add user agent bindings and private workspaces"
```

### Task 5: Build Provider Governance, Usage Events, And Rollups

**Files:**
- Create: `core_matrix/db/migrate/20260324090014_create_provider_credentials.rb`
- Create: `core_matrix/db/migrate/20260324090015_create_provider_entitlements.rb`
- Create: `core_matrix/db/migrate/20260324090016_create_provider_policies.rb`
- Create: `core_matrix/db/migrate/20260324090017_create_usage_events.rb`
- Create: `core_matrix/db/migrate/20260324090018_create_usage_rollups.rb`
- Create: `core_matrix/app/models/provider_credential.rb`
- Create: `core_matrix/app/models/provider_entitlement.rb`
- Create: `core_matrix/app/models/provider_policy.rb`
- Create: `core_matrix/app/models/usage_event.rb`
- Create: `core_matrix/app/models/usage_rollup.rb`
- Create: `core_matrix/app/services/provider_credentials/upsert_secret.rb`
- Create: `core_matrix/app/services/provider_usage/record_event.rb`
- Create: `core_matrix/app/services/provider_usage/project_rollups.rb`
- Create: `core_matrix/test/models/provider_credential_test.rb`
- Create: `core_matrix/test/models/provider_entitlement_test.rb`
- Create: `core_matrix/test/models/provider_policy_test.rb`
- Create: `core_matrix/test/models/usage_event_test.rb`
- Create: `core_matrix/test/models/usage_rollup_test.rb`
- Create: `core_matrix/test/services/provider_credentials/upsert_secret_test.rb`
- Create: `core_matrix/test/services/provider_usage/record_event_test.rb`
- Create: `core_matrix/test/services/provider_usage/project_rollups_test.rb`

**Step 1: Write failing model tests**

Cover at least:

- global ownership only
- encrypted or protected secret fields on credentials
- entitlement window kinds including rolling five-hour windows
- policy enablement and throttling fields
- usage event required dimensions
- rollup uniqueness by bucket key and dimensions

**Step 2: Run the failing tests**

Run:

```bash
cd core_matrix
bin/rails test test/models/provider_credential_test.rb test/models/provider_entitlement_test.rb test/models/provider_policy_test.rb test/models/usage_event_test.rb test/models/usage_rollup_test.rb
```

Expected:

- missing table and model failures

**Step 3: Write migrations and models**

Include:

- credential rows for provider connection facts, not for full model catalogs
- entitlement rows for subscriptions and quotas
- policy rows for concurrency, throttle, and default selection
- usage events that can store token-based and media-unit usage
- rollup rows keyed by hour, day, and explicit rolling-window identifiers

**Step 4: Write failing service tests**

`ProviderUsage::RecordEvent` should:

- persist the detailed event
- attach user, workspace, and runtime dimensions when present
- keep provider metadata snapshots on the event row

`ProviderUsage::ProjectRollups` should:

- aggregate events into deterministic hourly and daily buckets
- support explicit five-hour windows for entitlement views

**Step 5: Implement minimal services**

Keep the provider catalog config-backed. Do not build provider-model tables in SQL.

**Step 6: Run targeted tests and migrate**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/provider_credential_test.rb test/models/provider_entitlement_test.rb test/models/provider_policy_test.rb test/models/usage_event_test.rb test/models/usage_rollup_test.rb test/services/provider_credentials/upsert_secret_test.rb test/services/provider_usage/record_event_test.rb test/services/provider_usage/project_rollups_test.rb
```

Expected:

- targeted tests pass

**Step 7: Commit**

```bash
git add core_matrix/db/migrate core_matrix/app/models core_matrix/app/services/provider_credentials core_matrix/app/services/provider_usage core_matrix/test/models core_matrix/test/services core_matrix/db/schema.rb
git commit -m "feat: add provider governance and usage accounting"
```

### Task 6: Rebuild Conversation Tree And Transcript Under The New Ownership Chain

**Files:**
- Create: `core_matrix/db/migrate/20260324090019_create_conversations.rb`
- Create: `core_matrix/db/migrate/20260324090020_create_conversation_closures.rb`
- Create: `core_matrix/db/migrate/20260324090021_create_turns.rb`
- Create: `core_matrix/db/migrate/20260324090022_create_messages.rb`
- Create: `core_matrix/db/migrate/20260324090023_add_turn_message_foreign_keys.rb`
- Create: `core_matrix/app/models/conversation.rb`
- Create: `core_matrix/app/models/conversation_closure.rb`
- Create: `core_matrix/app/models/turn.rb`
- Create: `core_matrix/app/models/message.rb`
- Create: `core_matrix/app/services/conversations/create_root.rb`
- Create: `core_matrix/app/services/conversations/create_branch.rb`
- Create: `core_matrix/app/services/turns/start_user_turn.rb`
- Create: `core_matrix/test/models/conversation_test.rb`
- Create: `core_matrix/test/models/conversation_closure_test.rb`
- Create: `core_matrix/test/models/turn_test.rb`
- Create: `core_matrix/test/models/message_test.rb`
- Create: `core_matrix/test/services/conversations/create_root_test.rb`
- Create: `core_matrix/test/services/conversations/create_branch_test.rb`
- Create: `core_matrix/test/services/turns/start_user_turn_test.rb`

**Step 1: Write failing model tests**

Cover at least:

- conversation belongs to workspace, not directly to agent
- closure-table integrity
- turn sequence uniqueness within one conversation
- message role, slot, and variant semantics
- selected input and output pointers
- runtime pinning columns on turns for deployment and capability snapshots

**Step 2: Run the failing tests**

Run:

```bash
cd core_matrix
bin/rails test test/models/conversation_test.rb test/models/conversation_closure_test.rb test/models/turn_test.rb test/models/message_test.rb
```

Expected:

- missing table and model failures

**Step 3: Write migrations and models**

Include:

- workspace FK on conversations
- agent installation binding references only where logically needed
- no direct `conversation.agent_id` shortcut
- turn-level runtime snapshot fields such as deployment FK, deployment fingerprint, capability snapshot FK, resolved config snapshot JSON

**Step 4: Write failing service tests**

`Conversations::CreateRoot` should create a conversation in a workspace and write the closure self-row.

`Conversations::CreateBranch` should:

- branch from a prior message or turn
- preserve parent and root relationships
- keep ownership in the same workspace unless a later explicit cross-workspace rule is introduced

`Turns::StartUserTurn` should:

- append the next turn
- pin the active runtime identity snapshot
- reject work when the workspace binding or deployment state is invalid

**Step 5: Implement minimal services and models**

Keep transcript append-only. Do not port old prototype joins that assume conversations belong directly to agents.

**Step 6: Run targeted tests and migrate**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/conversation_test.rb test/models/conversation_closure_test.rb test/models/turn_test.rb test/models/message_test.rb test/services/conversations/create_root_test.rb test/services/conversations/create_branch_test.rb test/services/turns/start_user_turn_test.rb
```

Expected:

- targeted tests pass

**Step 7: Commit**

```bash
git add core_matrix/db/migrate core_matrix/app/models core_matrix/app/services/conversations core_matrix/app/services/turns core_matrix/test/models core_matrix/test/services core_matrix/db/schema.rb
git commit -m "feat: rebuild conversation tree and transcript foundations"
```

### Task 7: Rebuild Workflow Runtime And Execution Resource Models

**Files:**
- Create: `core_matrix/db/migrate/20260324090024_create_workflow_runs.rb`
- Create: `core_matrix/db/migrate/20260324090025_create_workflow_nodes.rb`
- Create: `core_matrix/db/migrate/20260324090026_create_workflow_edges.rb`
- Create: `core_matrix/db/migrate/20260324090027_create_workflow_artifacts.rb`
- Create: `core_matrix/db/migrate/20260324090028_create_process_runs.rb`
- Create: `core_matrix/db/migrate/20260324090029_create_subagent_runs.rb`
- Create: `core_matrix/db/migrate/20260324090030_create_approval_requests.rb`
- Create: `core_matrix/app/models/workflow_run.rb`
- Create: `core_matrix/app/models/workflow_node.rb`
- Create: `core_matrix/app/models/workflow_edge.rb`
- Create: `core_matrix/app/models/workflow_artifact.rb`
- Create: `core_matrix/app/models/process_run.rb`
- Create: `core_matrix/app/models/subagent_run.rb`
- Create: `core_matrix/app/models/approval_request.rb`
- Create: `core_matrix/app/services/workflows/create_for_turn.rb`
- Create: `core_matrix/app/services/workflows/mutate.rb`
- Create: `core_matrix/app/services/workflows/scheduler.rb`
- Create: `core_matrix/test/models/workflow_run_test.rb`
- Create: `core_matrix/test/models/workflow_node_test.rb`
- Create: `core_matrix/test/models/workflow_edge_test.rb`
- Create: `core_matrix/test/models/workflow_artifact_test.rb`
- Create: `core_matrix/test/models/process_run_test.rb`
- Create: `core_matrix/test/models/subagent_run_test.rb`
- Create: `core_matrix/test/models/approval_request_test.rb`
- Create: `core_matrix/test/services/workflows/create_for_turn_test.rb`
- Create: `core_matrix/test/services/workflows/mutate_test.rb`
- Create: `core_matrix/test/services/workflows/scheduler_test.rb`

**Step 1: Write failing model tests**

Cover at least:

- one workflow per turn
- workflow node ordinal uniqueness
- edge ordering and same-workflow integrity
- artifact storage mode behavior
- process run and subagent run state machines
- approval request scope and status transitions

**Step 2: Run the failing tests**

Run:

```bash
cd core_matrix
bin/rails test test/models/workflow_run_test.rb test/models/workflow_node_test.rb test/models/workflow_edge_test.rb test/models/workflow_artifact_test.rb test/models/process_run_test.rb test/models/subagent_run_test.rb test/models/approval_request_test.rb
```

Expected:

- missing table and model failures

**Step 3: Write migrations and models**

Add runtime ownership through turn and conversation foreign keys where needed, but keep workflow resources subordinate to the workflow.

**Step 4: Write failing service tests**

`Workflows::CreateForTurn` should initialize an empty workflow for a turn.

`Workflows::Mutate` should create nodes and edges while enforcing invariants.

`Workflows::Scheduler` should determine runnable nodes without executing side effects itself.

**Step 5: Implement minimal services**

Do not yet integrate external RPC or shell execution. This task is about workflow persistence and scheduling rules only.

**Step 6: Run targeted tests and migrate**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/workflow_run_test.rb test/models/workflow_node_test.rb test/models/workflow_edge_test.rb test/models/workflow_artifact_test.rb test/models/process_run_test.rb test/models/subagent_run_test.rb test/models/approval_request_test.rb test/services/workflows/create_for_turn_test.rb test/services/workflows/mutate_test.rb test/services/workflows/scheduler_test.rb
```

Expected:

- targeted tests pass

**Step 7: Commit**

```bash
git add core_matrix/db/migrate core_matrix/app/models core_matrix/app/services/workflows core_matrix/test/models core_matrix/test/services core_matrix/db/schema.rb
git commit -m "feat: rebuild workflow runtime foundations"
```

### Task 8: Implement Agent Handshake, Config Reconciliation, Bootstrap, And Health Recovery Services

**Files:**
- Create: `core_matrix/app/services/agent_deployments/handshake.rb`
- Create: `core_matrix/app/services/agent_deployments/reconcile_config.rb`
- Create: `core_matrix/app/services/agent_deployments/bootstrap.rb`
- Create: `core_matrix/app/services/agent_deployments/mark_unavailable.rb`
- Create: `core_matrix/app/services/agent_deployments/auto_resume_loops.rb`
- Create: `core_matrix/test/services/agent_deployments/handshake_test.rb`
- Create: `core_matrix/test/services/agent_deployments/reconcile_config_test.rb`
- Create: `core_matrix/test/services/agent_deployments/bootstrap_test.rb`
- Create: `core_matrix/test/services/agent_deployments/mark_unavailable_test.rb`
- Create: `core_matrix/test/services/agent_deployments/auto_resume_loops_test.rb`
- Modify: `core_matrix/app/models/agent_deployment.rb`
- Modify: `core_matrix/app/models/capability_snapshot.rb`
- Modify: `core_matrix/app/models/turn.rb`
- Modify: `core_matrix/app/models/workflow_run.rb`

**Step 1: Write failing service tests for handshake and config reconciliation**

Cover at least:

- parsing runtime identity and supported methods
- storing deployment config schema snapshots
- storing conversation override schema snapshots
- best-effort config compatibility behavior across schema changes
- never failing solely because an old field is no longer supported

**Step 2: Write failing service tests for bootstrap and outage recovery**

Cover at least:

- deployment bootstrap creates a system-owned workflow or run record
- bootstrap can enter `degraded` instead of hard failure for partial file materialization problems
- transient outage marks loops waiting
- prolonged outage pauses loops
- auto-resume only happens when deployment fingerprint and capabilities version did not drift

**Step 3: Implement minimal services**

Enforce the architectural law:

- agents return intent
- kernel materializes side effects
- drift blocks silent continuation

Store resolved deployment config and capability references on turn or workflow snapshots.

**Step 4: Run targeted tests**

Run:

```bash
cd core_matrix
bin/rails test test/services/agent_deployments/handshake_test.rb test/services/agent_deployments/reconcile_config_test.rb test/services/agent_deployments/bootstrap_test.rb test/services/agent_deployments/mark_unavailable_test.rb test/services/agent_deployments/auto_resume_loops_test.rb
```

Expected:

- targeted tests pass

**Step 5: Commit**

```bash
git add core_matrix/app/models core_matrix/app/services/agent_deployments core_matrix/test/services
git commit -m "feat: add agent handshake and bootstrap services"
```

### Task 9: Add Publications, Query Objects, Seed Baseline, And Full Verification

**Files:**
- Create: `core_matrix/db/migrate/20260324090031_create_publications.rb`
- Create: `core_matrix/app/models/publication.rb`
- Create: `core_matrix/app/services/publications/publish_live.rb`
- Create: `core_matrix/app/services/publications/revoke.rb`
- Create: `core_matrix/test/models/publication_test.rb`
- Create: `core_matrix/test/services/publications/publish_live_test.rb`
- Create: `core_matrix/test/services/publications/revoke_test.rb`
- Create: `core_matrix/app/queries/agent_installations/visible_to_user_query.rb`
- Create: `core_matrix/app/queries/workspaces/for_user_query.rb`
- Create: `core_matrix/app/queries/publications/live_projection_query.rb`
- Create: `core_matrix/app/queries/provider_usage/window_usage_query.rb`
- Create: `core_matrix/test/queries/agent_installations/visible_to_user_query_test.rb`
- Create: `core_matrix/test/queries/workspaces/for_user_query_test.rb`
- Create: `core_matrix/test/queries/publications/live_projection_query_test.rb`
- Create: `core_matrix/test/queries/provider_usage/window_usage_query_test.rb`
- Modify: `core_matrix/db/seeds.rb`
- Modify: `core_matrix/README.md`

**Step 1: Write failing query tests**

Cover at least:

- publication visibility modes and revocation semantics
- live projection assembly for the current canonical conversation state
- global versus personal agent visibility
- user-private workspace listing
- rolling-window provider usage summaries

**Step 2: Implement publication model and services**

`Publications::PublishLive` should:

- create or reactivate a publication for a conversation
- keep the mode read-only by definition
- record audit metadata

`Publications::Revoke` should:

- revoke the publication without touching workspace or conversation ownership

**Step 3: Implement minimal query objects**

Keep them read-only and domain-specific. Do not add controller formatting or serializers.

**Step 4: Update seeds**

Seed only a safe backend baseline:

- one installation placeholder for development
- optional demo admin identity and user in development only
- no business-agent assumptions beyond bundled Fenix bootstrap hooks if explicitly configured

**Step 5: Run the full backend verification set**

Run:

```bash
cd core_matrix
bin/rails db:test:prepare
bin/rails test
bin/rubocop -f github
bin/brakeman --no-pager
bin/bundler-audit
```

Expected:

- tests pass
- RuboCop passes
- Brakeman and Bundler Audit are clean or have reviewed, documented exceptions

**Step 6: Commit**

```bash
git add core_matrix/db/migrate core_matrix/app/models core_matrix/app/services/publications core_matrix/app/queries core_matrix/test/models core_matrix/test/services core_matrix/test/queries core_matrix/db/seeds.rb core_matrix/README.md core_matrix/db/schema.rb
git commit -m "feat: add publications and verification baseline"
```

## Stop Point

Stop after Task 9.

Do not implement:

- controllers
- setup wizard UI
- session UI
- admin dashboards
- conversation pages
- publication pages
- Action Cable
- JS runtime integration

Those should come from a later plan once the backend domain baseline is stable.
