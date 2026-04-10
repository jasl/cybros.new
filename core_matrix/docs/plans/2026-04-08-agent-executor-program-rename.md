# Agent / Executor Program Rename Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the `ExecutionRuntime`-centered model with a symmetric `AgentProgram` / `ExecutorProgram` domain, rename the machine-facing APIs to `agent_api` and `executor_api`, and remove the old execution-runtime naming from `core_matrix` without compatibility shims.

**Architecture:** Rename durable host entities and their sessions to `ExecutorProgram` and `ExecutorSession`, keep execution-behavior modules such as `ExecutionContract` and `provider_execution` unchanged, rewrite baseline migrations in place, then regenerate the local database and schema from scratch so Ruby, SQL, HTTP, tests, and docs all speak the same agent/executor vocabulary.

**Tech Stack:** Rails 8.2, PostgreSQL, Active Record, ActionDispatch, Minitest, Bun

---

## Destructive Assumptions

- This plan intentionally does **not** preserve compatibility with
  `ExecutionRuntime`, `ExecutionSession`, `/program_api`, or `/execution_api`.
- Edit the baseline migrations in place instead of adding compatibility
  migrations.
- Regenerate `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/schema.rb`
  from scratch.
- Reset the local database from
  `/Users/jasl/Workspaces/Ruby/cybros/core_matrix` with:

```bash
rails db:drop && rm db/schema.rb && rails db:create && rails db:migrate && rails db:reset
```

### Task 1: Rename the durable host schema to `ExecutorProgram` / `ExecutorSession`

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260324090007_create_execution_runtimes.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260324090021_create_turns.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260324090034_create_process_runs.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/20260326113000_add_agent_control_contract.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/agent_program.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/executor_program.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/executor_session.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/executor_program_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/executor_session_test.rb`

**Step 1: Write the failing model tests**

Add tests that assert:

- `ExecutorProgram` validates `executor_fingerprint`, `kind`,
  `connection_metadata`, `capability_payload`, and `tool_catalog`
- `AgentProgram` belongs to `default_executor_program`
- `ExecutorSession` belongs to `executor_program`
- only one active `ExecutorSession` exists per `ExecutorProgram`

**Step 2: Run the focused model tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/models/executor_program_test.rb test/models/executor_session_test.rb test/models/agent_program_test.rb
```

Expected: FAIL because the new models, associations, and schema names do not
exist yet.

**Step 3: Rewrite the baseline migrations**

Change the schema primitives so they create:

- `executor_programs`
- `executor_sessions`
- `agent_programs.default_executor_program_id`
- `turns.executor_program_id`
- `process_runs.executor_program_id`
- mailbox/report foreign keys using `executor_program` and `executor_session`

Rename the scalar columns at the same time:

- `runtime_fingerprint` -> `executor_fingerprint`
- `default_execution_runtime_id` -> `default_executor_program_id`

**Step 4: Implement the renamed models**

Create `ExecutorProgram` and `ExecutorSession`, move the validations and
associations from the old execution-runtime models, and update `AgentProgram`
to point at `default_executor_program`.

**Step 5: Rebuild the schema**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && rails db:drop && rm db/schema.rb && rails db:create && rails db:migrate && rails db:reset
```

Expected: the schema contains `executor_programs`, `executor_sessions`, and the
renamed foreign keys.

**Step 6: Re-run the focused model tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/models/executor_program_test.rb test/models/executor_session_test.rb test/models/agent_program_test.rb
```

Expected: PASS.

**Step 7: Commit**

```bash
git -C /Users/jasl/Workspaces/Ruby/cybros/core_matrix add db/migrate/20260324090007_create_execution_runtimes.rb db/migrate/20260324090021_create_turns.rb db/migrate/20260324090034_create_process_runs.rb db/migrate/20260326113000_add_agent_control_contract.rb app/models/agent_program.rb app/models/executor_program.rb app/models/executor_session.rb test/models/executor_program_test.rb test/models/executor_session_test.rb test/models/agent_program_test.rb db/schema.rb
git -C /Users/jasl/Workspaces/Ruby/cybros/core_matrix commit -m "refactor: rename execution host models to executor programs"
```

### Task 2: Rename executor lookup, bootstrap, and reconciliation services

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/installations/register_bundled_agent_runtime.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/turns/select_execution_runtime.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/workflows/build_execution_snapshot.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/executor_programs/reconcile.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/executor_programs/record_capabilities.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/executor_sessions/resolve_active_session.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/installations/register_bundled_agent_runtime_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/execution_runtimes/reconcile_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/execution_runtimes/record_capabilities_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/execution_sessions/resolve_active_session_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/workflows/build_execution_snapshot_test.rb`

**Step 1: Write the failing service tests**

Rename or rewrite the focused tests so they assert the new service/module names
and new `executor_*` associations and payload keys.

**Step 2: Run the focused service tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/execution_runtimes/reconcile_test.rb test/services/execution_runtimes/record_capabilities_test.rb test/services/execution_sessions/resolve_active_session_test.rb test/services/installations/register_bundled_agent_runtime_test.rb test/services/workflows/build_execution_snapshot_test.rb
```

Expected: FAIL because the old service namespaces and field names no longer
match the new design.

**Step 3: Rename the service layer**

- move `ExecutionRuntimes::*` to `ExecutorPrograms::*`
- move `ExecutionSessions::*` to `ExecutorSessions::*`
- update installation bootstrap and turn selection to use
  `default_executor_program`
- keep execution-behavior service names such as `BuildExecutionSnapshot`
  unchanged unless the file is specifically modeling the durable executor host

**Step 4: Re-run the focused service tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/execution_runtimes/reconcile_test.rb test/services/execution_runtimes/record_capabilities_test.rb test/services/execution_sessions/resolve_active_session_test.rb test/services/installations/register_bundled_agent_runtime_test.rb test/services/workflows/build_execution_snapshot_test.rb
```

Expected: PASS after the files and constants are renamed to the new executor
language.

**Step 5: Commit**

```bash
git -C /Users/jasl/Workspaces/Ruby/cybros/core_matrix add app/services/executor_programs app/services/executor_sessions app/services/installations/register_bundled_agent_runtime.rb app/services/turns/select_execution_runtime.rb app/services/workflows/build_execution_snapshot.rb test/services/execution_runtimes/reconcile_test.rb test/services/execution_runtimes/record_capabilities_test.rb test/services/execution_sessions/resolve_active_session_test.rb test/services/installations/register_bundled_agent_runtime_test.rb test/services/workflows/build_execution_snapshot_test.rb
git -C /Users/jasl/Workspaces/Ruby/cybros/core_matrix commit -m "refactor: rename executor host services"
```

### Task 3: Rename the machine-facing controllers and routes to `agent_api` / `executor_api`

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/config/routes.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/agent_api/base_controller.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/executor_api/base_controller.rb`
- Move: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/program_api/*`
- Move: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/execution_api/*`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/test_helper.rb`
- Move: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/program_api/*`
- Move: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/execution_api/*`

**Step 1: Write the failing request tests**

Rename the request tests so they assert:

- registration, heartbeat, health, capability, transcript, variable, and tool
  endpoints live under `/agent_api`
- command, process, attachment, and executor control endpoints live under
  `/executor_api`
- helper methods use `agent_api_headers` and `executor_api_headers`

**Step 2: Run the focused request tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/requests/program_api/registrations_test.rb test/requests/program_api/heartbeats_test.rb test/requests/program_api/capabilities_test.rb test/requests/execution_api/control_poll_test.rb test/requests/execution_api/attachments_controller_test.rb
```

Expected: FAIL because the routes and controller modules still use the old API
names.

**Step 3: Rename the routes, modules, and helpers**

- change `namespace :program_api` to `namespace :agent_api`
- change `namespace :execution_api` to `namespace :executor_api`
- rename `ProgramAPI` to `AgentAPI`
- rename `ExecutionAPI` to `ExecutorAPI`
- rename request helper methods in `test/test_helper.rb`

**Step 4: Re-run the focused request tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/requests/program_api/registrations_test.rb test/requests/program_api/heartbeats_test.rb test/requests/program_api/capabilities_test.rb test/requests/execution_api/control_poll_test.rb test/requests/execution_api/attachments_controller_test.rb
```

Expected: PASS after the files and paths are renamed.

**Step 5: Commit**

```bash
git -C /Users/jasl/Workspaces/Ruby/cybros/core_matrix add config/routes.rb app/controllers/agent_api app/controllers/executor_api test/test_helper.rb test/requests/program_api test/requests/execution_api
git -C /Users/jasl/Workspaces/Ruby/cybros/core_matrix commit -m "refactor: rename machine-facing APIs"
```

### Task 4: Rename control-plane routing and protocol payloads to executor terminology

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/agent_control_mailbox_item.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/serialize_mailbox_item.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/resolve_target_runtime.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/poll.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/report.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/create_execution_assignment.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/handle_execution_report.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/handle_runtime_resource_report.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/serialize_mailbox_item_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/resolve_target_runtime_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/poll_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/report_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/handle_execution_report_test.rb`

**Step 1: Write the failing contract tests**

Update tests to assert:

- durable routing uses `control_plane`, not `runtime_plane`
- the executor-side plane value is `"executor"`, not `"execution"`
- payloads emit `executor_program_id`, `executor_session_id`,
  `executor_fingerprint`, `executor_kind`, and `executor_connection_metadata`

**Step 2: Run the focused control-plane tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/agent_control/serialize_mailbox_item_test.rb test/services/agent_control/resolve_target_runtime_test.rb test/services/agent_control/poll_test.rb test/services/agent_control/report_test.rb test/services/agent_control/handle_execution_report_test.rb
```

Expected: FAIL because the mailbox contract still serializes the old
runtime/execution names.

**Step 3: Rewrite the mailbox and report vocabulary**

Replace the old field names consistently in models, serializers, routing
helpers, and report ingestion. Do not leave aliases or dual fields behind.

**Step 4: Re-run the focused control-plane tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/agent_control/serialize_mailbox_item_test.rb test/services/agent_control/resolve_target_runtime_test.rb test/services/agent_control/poll_test.rb test/services/agent_control/report_test.rb test/services/agent_control/handle_execution_report_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git -C /Users/jasl/Workspaces/Ruby/cybros/core_matrix add app/models/agent_control_mailbox_item.rb app/services/agent_control/serialize_mailbox_item.rb app/services/agent_control/resolve_target_runtime.rb app/services/agent_control/poll.rb app/services/agent_control/report.rb app/services/agent_control/create_execution_assignment.rb app/services/agent_control/handle_execution_report.rb app/services/agent_control/handle_runtime_resource_report.rb test/services/agent_control/serialize_mailbox_item_test.rb test/services/agent_control/resolve_target_runtime_test.rb test/services/agent_control/poll_test.rb test/services/agent_control/report_test.rb test/services/agent_control/handle_execution_report_test.rb
git -C /Users/jasl/Workspaces/Ruby/cybros/core_matrix commit -m "refactor: rename control-plane executor contract"
```

### Task 5: Rewrite test helpers, integration tests, and manual scripts around `executor_*`

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/test_helper.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/support/fake_agent_runtime_harness.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/integration/agent_registration_contract_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/integration/agent_runtime_resource_api_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/integration/dummy_agent_runtime_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/integration/bundled_default_agent_bootstrap_flow_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/manual_support.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/script/manual/dummy_agent_runtime.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/README.md`

**Step 1: Write the failing integration expectations**

Update the integration and helper expectations so they create and assert
`ExecutorProgram` / `ExecutorSession` records, `agent_api` / `executor_api`
routes, and `executor_*` JSON keys.

**Step 2: Run the focused integration tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/integration/agent_registration_contract_test.rb test/integration/agent_runtime_resource_api_test.rb test/integration/dummy_agent_runtime_test.rb test/integration/bundled_default_agent_bootstrap_flow_test.rb
```

Expected: FAIL because the helpers and scripts still use the old execution
runtime naming.

**Step 3: Rewrite the helpers and manual scripts**

Update factories, helper method names, dummy runtime payloads, and README
examples to use the executor vocabulary consistently.

**Step 4: Re-run the focused integration tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/integration/agent_registration_contract_test.rb test/integration/agent_runtime_resource_api_test.rb test/integration/dummy_agent_runtime_test.rb test/integration/bundled_default_agent_bootstrap_flow_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git -C /Users/jasl/Workspaces/Ruby/cybros add core_matrix/test/test_helper.rb core_matrix/test/support/fake_agent_runtime_harness.rb core_matrix/test/integration/agent_registration_contract_test.rb core_matrix/test/integration/agent_runtime_resource_api_test.rb core_matrix/test/integration/dummy_agent_runtime_test.rb core_matrix/test/integration/bundled_default_agent_bootstrap_flow_test.rb acceptance/lib/manual_support.rb core_matrix/script/manual/dummy_agent_runtime.rb core_matrix/README.md
git -C /Users/jasl/Workspaces/Ruby/cybros/core_matrix commit -m "refactor: rename executor integration surface"
```

### Task 6: Rewrite behavior docs to the new domain language

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/agent-registration-and-capability-handshake.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/agent-runtime-resource-apis.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/bundled-default-agent-bootstrap.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/agent-registry-and-connectivity-foundations.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/workflow-context-assembly-and-execution-snapshot.md`

**Step 1: Rewrite the source-of-truth docs**

Update the durable terminology, field names, route names, and control-plane
examples. Keep archived historical docs unchanged unless they are already
treated as live product behavior docs.

**Step 2: Run a residual naming scan**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && rg -n "ExecutionRuntime|ExecutionSession|program_api|execution_api|runtime_plane|default_execution_runtime|execution_runtime_id|execution_session_id" app config test script docs README.md
```

Expected: no hits in live code, tests, scripts, or behavior docs outside of
intentionally archived history.

**Step 3: Commit**

```bash
git -C /Users/jasl/Workspaces/Ruby/cybros/core_matrix add docs/behavior/agent-registration-and-capability-handshake.md docs/behavior/agent-runtime-resource-apis.md docs/behavior/bundled-default-agent-bootstrap.md docs/behavior/agent-registry-and-connectivity-foundations.md docs/behavior/workflow-context-assembly-and-execution-snapshot.md
git -C /Users/jasl/Workspaces/Ruby/cybros/core_matrix commit -m "docs: rewrite agent executor terminology"
```

### Task 7: Run full verification on the rebuilt database

**Files:**
- Inspect: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/schema.rb`

**Step 1: Rebuild the database one final time**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && rails db:drop && rm db/schema.rb && rails db:create && rails db:migrate && rails db:reset
```

Expected: clean rebuild with the renamed executor tables and foreign keys.

**Step 2: Run the full project verification**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/brakeman --no-pager
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/bundler-audit
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rubocop -f github
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bun run lint:js
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails db:test:prepare
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test:system
```

Expected: all commands pass on the rebuilt schema.

**Step 3: Commit**

```bash
git -C /Users/jasl/Workspaces/Ruby/cybros/core_matrix add db/schema.rb
git -C /Users/jasl/Workspaces/Ruby/cybros/core_matrix commit -m "chore: regenerate schema after executor rename"
```
