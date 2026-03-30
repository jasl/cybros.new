# WebSocket-First Runtime Mailbox Control Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Productize external and bundled runtime execution around mailbox-first realtime control, kernel-created `ToolInvocation`/`CommandRun`/`ProcessRun` resources, attached command tools, and long-lived process control without relying on `/runtime/executions`.

**Architecture:** Keep `Core Matrix` as the only orchestration truth and move `Fenix` to a true mailbox worker model. Short-lived commands become `ToolInvocation + CommandRun` kernel-owned resources behind `exec_command` and `write_stdin`; long-lived services remain `ProcessRun`-owned environment resources with separate create/close/output handling. Remove `/runtime/executions` as a product path and update manual proof scripts to run only through the real mailbox control plane.

**Tech Stack:** Ruby on Rails, ActionCable, ActiveJob, Core Matrix mailbox control, Fenix runtime worker, integration tests, e2e protocol tests, operator-style manual scripts.

---

## Preconditions

- Re-read:
  - `/Users/jasl/Workspaces/Ruby/cybros/AGENTS.md`
  - `/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-03-30-websocket-first-runtime-mailbox-control-design.md`
  - `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/agent-runtime-resource-apis.md`
  - `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/workflow-artifacts-node-events-and-process-runs.md`
  - `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/docs/plans/2026-03-30-fenix-runtime-appliance-design.md`
  - `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/docs/plans/2026-03-30-fenix-runtime-appliance.md`
- Destructive changes are allowed. Remove obsolete paths instead of preserving compatibility.
- Do not expose `bigint` ids at external or agent-facing boundaries.

Implementation note:

- Tasks `1` through `5` describe the landed checkpoints already completed on
  the current branch.
- The remaining execution scope now starts at Task `6` and supersedes the older
  "manual validation immediately after manager work" assumption.

### Task 1: Remove `/runtime/executions` as a product dependency and pin the new contract

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/README.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/agent-runtime-resource-apis.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/agent-registry-and-connectivity-foundations.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/workflow-artifacts-node-events-and-process-runs.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/integration/external_runtime_pairing_test.rb`

**Step 1: Write the failing test**

Add or tighten an integration test asserting the manifest and pairing contract no
longer advertise `/runtime/executions` as the product execution path.

**Step 2: Run test to verify it fails**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix && bin/rails test test/integration/external_runtime_pairing_test.rb`
Expected: FAIL because the docs/contract still imply the old execution surface.

**Step 3: Write minimal implementation**

- Remove `/runtime/executions` from the documented product path.
- Keep `/runtime/manifest` as the registration surface.
- Update behavior docs to state that realtime/poll mailbox delivery is the only
  product execution/control path.

**Step 4: Run test to verify it passes**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix && bin/rails test test/integration/external_runtime_pairing_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add agents/fenix/README.md core_matrix/docs/behavior/agent-runtime-resource-apis.md core_matrix/docs/behavior/agent-registry-and-connectivity-foundations.md core_matrix/docs/behavior/workflow-artifacts-node-events-and-process-runs.md core_matrix/docs/behavior/workflow-scheduler-and-wait-states.md agents/fenix/test/integration/external_runtime_pairing_test.rb
git commit -m "feat: pin mailbox-first runtime execution contract"
```

### Task 2: Add a Fenix mailbox worker and runtime attempt registry

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/mailbox_worker.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/attempt_registry.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/pairing_manifest.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/jobs/runtime_execution_job.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/fenix/runtime/mailbox_worker_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/jobs/runtime_execution_job_test.rb`

**Step 1: Write the failing tests**

Cover:

- mailbox worker accepts `execution_assignment`
- mailbox worker creates one local task attempt
- reports are emitted incrementally through the worker path
- local attempt lookup is possible during close/cancel

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix && bin/rails test test/services/fenix/runtime/mailbox_worker_test.rb test/jobs/runtime_execution_job_test.rb`
Expected: FAIL because the runtime worker and attempt registry do not exist.

**Step 3: Write minimal implementation**

- Introduce a mailbox worker service as the runtime execution entrypoint.
- Add a local runtime attempt registry for active task attempts.
- Keep the current ActiveJob boundary, but make the worker the logical owner of
  execution and later close routing.

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix && bin/rails test test/services/fenix/runtime/mailbox_worker_test.rb test/jobs/runtime_execution_job_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add agents/fenix/app/services/fenix/runtime/mailbox_worker.rb agents/fenix/app/services/fenix/runtime/attempt_registry.rb agents/fenix/app/services/fenix/runtime/pairing_manifest.rb agents/fenix/app/jobs/runtime_execution_job.rb agents/fenix/test/services/fenix/runtime/mailbox_worker_test.rb agents/fenix/test/jobs/runtime_execution_job_test.rb
git commit -m "feat: add fenix mailbox worker and attempt registry"
```

### Task 3: Rename `shell_exec` into attached command tools

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/execute_assignment.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/pairing_manifest.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/hooks/review_tool_call.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/hooks/project_tool_result.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/fenix/runtime/execute_assignment_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/report_test.rb`

**Step 1: Write the failing tests**

Add failing coverage for:

- `exec_command`
- `write_stdin`
- PTY-backed session ids
- streamed stdout/stderr
- summary-only terminal payloads

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix && bin/rails test test/services/fenix/runtime/execute_assignment_test.rb`
Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/agent_control/report_test.rb`
Expected: FAIL because the attached command tool names and session model do not yet exist.

**Step 3: Write minimal implementation**

- Replace `shell_exec` with `exec_command`.
- Add `write_stdin` support for PTY sessions only.
- Keep raw output transport-only and durable payloads summary-only.

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix && bin/rails test test/services/fenix/runtime/execute_assignment_test.rb`
Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/agent_control/report_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add agents/fenix/app/services/fenix/runtime/execute_assignment.rb agents/fenix/app/services/fenix/runtime/pairing_manifest.rb agents/fenix/app/services/fenix/hooks/review_tool_call.rb agents/fenix/app/services/fenix/hooks/project_tool_result.rb agents/fenix/test/services/fenix/runtime/execute_assignment_test.rb core_matrix/test/services/agent_control/report_test.rb
git commit -m "feat: add attached command tools"
```

### Task 4: Propagate parent task close into attached command cancellation

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/mailbox_worker.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/attempt_registry.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/execute_assignment.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/handle_close_report.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/fenix/runtime/mailbox_worker_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/e2e/protocol/turn_interrupt_e2e_test.rb`

**Step 1: Write the failing tests**

Cover:

- a running `exec_command` receives parent `AgentTaskRun` close
- the attached subprocess is terminated
- runtime emits `execution_interrupted` or `execution_fail`
- parent resource close still settles through `resource_close_*`

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix && bin/rails test test/services/fenix/runtime/mailbox_worker_test.rb`
Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/e2e/protocol/turn_interrupt_e2e_test.rb`
Expected: FAIL because close currently does not reach a runtime-local attached command registry.

**Step 3: Write minimal implementation**

- Route `resource_close_request(resource_type = AgentTaskRun)` into the runtime
  attempt registry.
- Mark the local attempt as closing.
- Terminate any attached command sessions belonging to that attempt.
- Preserve the separation between `execution_*` and `resource_close_*`.

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix && bin/rails test test/services/fenix/runtime/mailbox_worker_test.rb`
Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/e2e/protocol/turn_interrupt_e2e_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add agents/fenix/app/services/fenix/runtime/mailbox_worker.rb agents/fenix/app/services/fenix/runtime/attempt_registry.rb agents/fenix/app/services/fenix/runtime/execute_assignment.rb core_matrix/app/services/agent_control/handle_close_report.rb agents/fenix/test/services/fenix/runtime/mailbox_worker_test.rb core_matrix/test/e2e/protocol/turn_interrupt_e2e_test.rb
git commit -m "feat: propagate task close into attached command cancellation"
```

### Task 5: Add a distinct long-lived process manager path

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/processes/manager.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/mailbox_worker.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/handle_runtime_resource_report.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/handle_close_report.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/fenix/processes/manager_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/agent_api/process_runtime_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/e2e/protocol/process_close_escalation_e2e_test.rb`

**Step 1: Write the failing tests**

Cover:

- long-lived process output remains on `runtime.process_run.output`
- long-lived process close goes through `resource_close_*`
- no `ToolInvocation` is created for long-lived process control

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix && bin/rails test test/services/fenix/processes/manager_test.rb`
Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/requests/agent_api/process_runtime_test.rb test/e2e/protocol/process_close_escalation_e2e_test.rb`
Expected: FAIL because there is no explicit runtime-side long-lived process manager yet.

**Step 3: Write minimal implementation**

- Add a distinct manager for `ProcessRun`-backed runtime handles.
- Keep process output and close reports on the environment-plane contract.
- Do not route long-lived process work through attached command tools.

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix && bin/rails test test/services/fenix/processes/manager_test.rb`
Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/requests/agent_api/process_runtime_test.rb test/e2e/protocol/process_close_escalation_e2e_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add agents/fenix/app/services/fenix/processes/manager.rb agents/fenix/app/services/fenix/runtime/mailbox_worker.rb core_matrix/app/services/agent_control/handle_runtime_resource_report.rb core_matrix/app/services/agent_control/handle_close_report.rb agents/fenix/test/services/fenix/processes/manager_test.rb core_matrix/test/requests/agent_api/process_runtime_test.rb core_matrix/test/e2e/protocol/process_close_escalation_e2e_test.rb
git commit -m "feat: separate long-lived process manager from attached commands"
```

### Task 6: Add machine-facing ToolInvocation and CommandRun create APIs

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/agent_api/tool_invocations_controller.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/agent_api/command_runs_controller.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/command_run.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/create_tool_invocation.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/create_command_run.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/config/routes.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/*command_runs*`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/schema.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/agent_api/tool_invocations_create_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/agent_api/command_runs_create_test.rb`

**Step 1: Write the failing tests**

Cover:

- `POST /agent_api/tool_invocations` creates one durable `ToolInvocation`
- `POST /agent_api/command_runs` creates one durable `CommandRun`
- both APIs accept only `public_id` references
- duplicate client request ids remain idempotent

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/requests/agent_api/tool_invocations_create_test.rb test/requests/agent_api/command_runs_create_test.rb`
Expected: FAIL because the machine-facing create APIs and `CommandRun` model do not yet exist.

**Step 3: Write minimal implementation**

- add a first-class `CommandRun` model for all `exec_command` invocations
- add machine-facing create endpoints for `ToolInvocation` and `CommandRun`
- keep the durable rows kernel-created before local runtime side effects begin

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/requests/agent_api/tool_invocations_create_test.rb test/requests/agent_api/command_runs_create_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add core_matrix/app/controllers/agent_api/tool_invocations_controller.rb core_matrix/app/controllers/agent_api/command_runs_controller.rb core_matrix/app/models/command_run.rb core_matrix/app/services/agent_control/create_tool_invocation.rb core_matrix/app/services/agent_control/create_command_run.rb core_matrix/config/routes.rb core_matrix/db/migrate core_matrix/db/schema.rb core_matrix/test/requests/agent_api/tool_invocations_create_test.rb core_matrix/test/requests/agent_api/command_runs_create_test.rb
git commit -m "feat: add tool invocation and command run create APIs"
```

### Task 7: Add machine-facing ProcessRun create API and route long-lived launch through it

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/agent_api/process_runs_controller.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/create_process_run.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/config/routes.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/processes/manager.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/mailbox_worker.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/agent_api/process_runs_create_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/fenix/processes/manager_test.rb`

**Step 1: Write the failing tests**

Cover:

- `POST /agent_api/process_runs` creates a durable `ProcessRun` in `starting`
  before local launch
- the runtime-side manager requests creation, reports `process_started`, then
  registers a local handle against the returned `public_id`
- natural process exit reports through `process_exited`
- close/output still route through `resource_close_*` and `process_output`

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/requests/agent_api/process_runs_create_test.rb`
Run: `cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix && bin/rails test test/services/fenix/processes/manager_test.rb`
Expected: FAIL because there is no process-run create API yet.

**Step 3: Write minimal implementation**

- add a machine-facing create endpoint for `ProcessRun`
- route runtime-side long-lived process launch through `process_exec`
- keep close/output on the existing environment-plane contract
- add runtime-side `process_started` / `process_exited` reports so kernel
  lifecycle stays accurate when the local process starts, fails, or exits on
  its own

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/requests/agent_api/process_runs_create_test.rb`
Run: `cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix && bin/rails test test/services/fenix/processes/manager_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add core_matrix/app/controllers/agent_api/process_runs_controller.rb core_matrix/app/services/agent_control/create_process_run.rb core_matrix/config/routes.rb agents/fenix/app/services/fenix/processes/manager.rb agents/fenix/app/services/fenix/runtime/mailbox_worker.rb core_matrix/test/requests/agent_api/process_runs_create_test.rb agents/fenix/test/services/fenix/processes/manager_test.rb
git commit -m "feat: add process run create API"
```

### Task 8: Rewire exec_command and write_stdin through ToolInvocation + CommandRun APIs

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/execute_assignment.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/attached_command_session_registry.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/hooks/project_tool_result.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/handle_execution_report.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/fenix/runtime/execute_assignment_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/report_test.rb`

**Step 1: Write the failing tests**

Cover:

- every `exec_command` requests `ToolInvocation` creation before local spawn
- every `exec_command` requests `CommandRun` creation before local spawn
- `write_stdin` addresses `CommandRun public_id`
- streamed output remains temporary while durable payloads remain summary-only

**Step 2: Run tests to verify they fail**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix && bin/rails test test/services/fenix/runtime/execute_assignment_test.rb`
Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/agent_control/report_test.rb`
Expected: FAIL because attached command execution still starts locally without kernel-created `ToolInvocation` / `CommandRun` records.

**Step 3: Write minimal implementation**

- route `exec_command` through the new create APIs
- keep the user-facing tool names unchanged
- remove remaining local-first attached-command creation paths

**Step 4: Run tests to verify they pass**

Run: `cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix && bin/rails test test/services/fenix/runtime/execute_assignment_test.rb`
Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test test/services/agent_control/report_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add agents/fenix/app/services/fenix/runtime/execute_assignment.rb agents/fenix/app/services/fenix/runtime/attached_command_session_registry.rb agents/fenix/app/services/fenix/hooks/project_tool_result.rb core_matrix/app/services/agent_control/handle_execution_report.rb agents/fenix/test/services/fenix/runtime/execute_assignment_test.rb core_matrix/test/services/agent_control/report_test.rb
git commit -m "feat: route attached commands through command run APIs"
```

### Task 9: Replace manual validation with mailbox-first proof scripts

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/script/manual/manual_acceptance_support.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/docs/reports/phase-2/README.md`
- Create/Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/script/manual/phase2/*`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/integration/agent_recovery_flow_test.rb`

**Step 1: Write the failing validation expectations**

Document and pin the minimum manual proof set:

1. bundled realtime execution
2. external realtime execution
3. poll fallback execution
4. provider-backed execution
5. attached command interrupt
6. long-lived process close

**Step 2: Run the current scripts to confirm the gap**

Run the relevant `phase2_*` scripts and record where they still depend on the
old execution surface or lack the new create APIs.

**Step 3: Write minimal implementation**

- Update manual support to use only realtime/poll/report and the new create APIs.
- Remove dependence on `/runtime/executions`.
- Keep proof artifacts keyed by `public_id`.

**Step 4: Run the scripts to verify they pass**

Run the updated manual scripts for the minimum proof set.
Expected: PASS with proof artifacts written under `/Users/jasl/Workspaces/Ruby/cybros/docs/reports/phase-2/`.

**Step 5: Commit**

```bash
git add core_matrix/script/manual core_matrix/docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md docs/reports/phase-2/README.md docs/reports/phase-2
git commit -m "feat: validate mailbox-first runtime control with proof scripts"
```

### Task 10: Full verification sweep

**Files:**
- Verify only

**Step 1: Run Fenix verification**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bin/rails db:test:prepare test
```

Expected: PASS

**Step 2: Run Core Matrix verification**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails db:test:prepare test
bin/rails db:test:prepare test:system
```

Expected: PASS

**Step 3: Run manual proof set**

Run the mailbox-first operator scripts for the six approved scenarios.

Expected: PASS with updated proof artifacts and no `bigint` ids in agent-facing
or proof-facing output.

**Step 4: Commit final verification metadata**

```bash
git add docs/reports/phase-2 core_matrix/docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md
git commit -m "chore: refresh mailbox-first runtime validation proofs"
```
