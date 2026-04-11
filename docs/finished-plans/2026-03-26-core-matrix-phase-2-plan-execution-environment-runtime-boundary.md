# Execution Environment Runtime Boundary Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Repair the runtime model so `ExecutionEnvironment` becomes the stable owner of runtime resources, `AgentDeployment` becomes the rotatable Agent layer on top of that environment, and bundled runtimes expose distinct agent and environment planes without compatibility leftovers.

**Architecture:** Reshape the schema and model invariants first, then refactor pairing and routing so ownership is always environment-first while delivery can still reuse the current bundled runtime connection. After that, compose conversation capabilities and tool catalogs from environment plus agent layers, update Fenix to publish and serve both planes explicitly, and finally delete stale deployment-owned assumptions from docs, tests, and code.

**Tech Stack:** Ruby on Rails monorepo (`core_matrix`, `agents/fenix`), Active Record, Action Cable mailbox transport, Minitest integration/request/E2E coverage

---

## Execution Rules

- Treat this as a structural repair, not a compatibility exercise.
- Edit existing migrations in place when that yields a cleaner schema.
- Reset the database and regenerate `schema.rb` as needed.
- Do not keep transitional compatibility fields, adapters, or fallback routing.
- Extend the existing protocol E2E harness instead of introducing a second path.
- Commit after every task with the suggested message or a tighter equivalent.
- Treat this plan as `Task C5`, the `Milestone C` runtime-boundary follow-up.

### Task 1: Lift `ExecutionEnvironment` Into The Durable Owner Aggregate

**Files:**
- Modify: `core_matrix/db/migrate/20260324090007_create_execution_environments.rb`
- Modify: `core_matrix/db/migrate/20260324090009_create_agent_deployments.rb`
- Modify: `core_matrix/db/migrate/20260324090010_create_capability_snapshots.rb`
- Modify: `core_matrix/db/migrate/20260324090019_create_conversations.rb`
- Modify: `core_matrix/db/migrate/20260324090034_create_process_runs.rb`
- Modify: `core_matrix/db/migrate/20260324090039_create_execution_leases.rb`
- Modify: `core_matrix/db/schema.rb`
- Modify: `core_matrix/app/models/execution_environment.rb`
- Modify: `core_matrix/app/models/agent_deployment.rb`
- Modify: `core_matrix/app/models/capability_snapshot.rb`
- Modify: `core_matrix/app/models/conversation.rb`
- Modify: `core_matrix/app/models/process_run.rb`
- Modify: `core_matrix/app/models/execution_lease.rb`
- Create: `core_matrix/test/models/execution_environment_test.rb`
- Create: `core_matrix/test/models/conversation_test.rb`
- Modify: `core_matrix/test/models/process_run_test.rb`

**Step 1: Write the failing test**

```ruby
test "conversation binds to one execution environment and rejects a deployment from another environment" do
  first = create_execution_environment!
  second = create_execution_environment!
  deployment = create_agent_deployment!(execution_environment: second)

  conversation = Conversation.new(
    installation: first.installation,
    workspace: create_workspace!(installation: first.installation),
    execution_environment: first,
    agent_deployment: deployment,
    title: "Boundary"
  )

  assert_not conversation.valid?
  assert_includes conversation.errors[:agent_deployment], "must belong to the bound execution environment"
end
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd core_matrix
bin/rails test test/models/execution_environment_test.rb test/models/conversation_test.rb test/models/process_run_test.rb
```

Expected: FAIL because `Conversation` does not yet carry the new environment binding and the new ownership invariants are missing.

**Step 3: Write minimal implementation**

Implement the smallest schema and model changes that make the new aggregate real:

- add explicit environment ownership fields and capability payload fields to `execution_environments`
- add a stable `environment_fingerprint` field that is installation-local and
  distinct from deployment release fingerprinting
- make `conversations` bind to `execution_environment`
- keep `ProcessRun` environment-owned and remove any remaining deployment-owned interpretation
- demote `ExecutionLease.holder_key` to routing hint semantics only

**Step 4: Run test to verify it passes**

Run:

```bash
cd core_matrix
bin/rails db:drop db:create db:schema:load db:test:prepare
bin/rails test test/models/execution_environment_test.rb test/models/conversation_test.rb test/models/process_run_test.rb
```

Expected: PASS

**Step 5: Commit**

```bash
git add core_matrix/db/migrate/20260324090007_create_execution_environments.rb \
  core_matrix/db/migrate/20260324090009_create_agent_deployments.rb \
  core_matrix/db/migrate/20260324090010_create_capability_snapshots.rb \
  core_matrix/db/migrate/20260324090019_create_conversations.rb \
  core_matrix/db/migrate/20260324090034_create_process_runs.rb \
  core_matrix/db/migrate/20260324090039_create_execution_leases.rb \
  core_matrix/db/schema.rb \
  core_matrix/app/models/execution_environment.rb \
  core_matrix/app/models/agent_deployment.rb \
  core_matrix/app/models/capability_snapshot.rb \
  core_matrix/app/models/conversation.rb \
  core_matrix/app/models/process_run.rb \
  core_matrix/app/models/execution_lease.rb \
  core_matrix/test/models/execution_environment_test.rb \
  core_matrix/test/models/conversation_test.rb \
  core_matrix/test/models/process_run_test.rb
git commit -m "refactor: make execution environments durable runtime owners"
```

### Task 2: Refactor Pairing Into Environment Reconciliation Plus Deployment Rotation

**Files:**
- Create: `core_matrix/app/services/execution_environments/reconcile.rb`
- Create: `core_matrix/app/services/execution_environments/record_capabilities.rb`
- Create: `core_matrix/app/services/execution_environments/resolve_delivery_endpoint.rb`
- Modify: `core_matrix/app/services/agent_deployments/register.rb`
- Modify: `core_matrix/app/services/agent_deployments/handshake.rb`
- Modify: `core_matrix/app/services/agent_deployments/record_heartbeat.rb`
- Modify: `core_matrix/app/services/agent_deployments/mark_unavailable.rb`
- Modify: `core_matrix/app/services/agent_deployments/retire.rb`
- Modify: `core_matrix/app/services/installations/register_bundled_agent_runtime.rb`
- Modify: `core_matrix/app/services/installations/bootstrap_bundled_agent_binding.rb`
- Modify: `core_matrix/app/controllers/agent_api/registrations_controller.rb`
- Modify: `core_matrix/app/controllers/agent_api/capabilities_controller.rb`
- Modify: `core_matrix/app/controllers/agent_api/health_controller.rb`
- Modify: `core_matrix/app/channels/application_cable/connection.rb`
- Modify: `agents/fenix/app/services/runtime/pairing_manifest.rb`
- Modify: `agents/fenix/app/controllers/runtime_manifests_controller.rb`
- Create: `core_matrix/test/services/execution_environments/reconcile_test.rb`
- Create: `core_matrix/test/services/execution_environments/record_capabilities_test.rb`
- Modify: `core_matrix/test/requests/agent_api/registrations_test.rb`
- Modify: `core_matrix/test/requests/agent_api/capabilities_test.rb`
- Modify: `core_matrix/test/requests/agent_api/health_test.rb`
- Modify: `core_matrix/test/integration/agent_registration_contract_test.rb`
- Modify: `core_matrix/test/integration/bundled_default_agent_bootstrap_flow_test.rb`
- Modify: `core_matrix/test/integration/external_fenix_pairing_flow_test.rb`
- Modify: `agents/fenix/test/integration/external_runtime_pairing_test.rb`

**Step 1: Write the failing test**

```ruby
test "registration rotates the deployment while reusing the same execution environment" do
  first = register_agent_runtime!(
    environment_fingerprint: "fenix-host-a",
    fingerprint: "fenix-release-0.1.0",
    sdk_version: "fenix-0.1.0"
  )

  second = register_agent_runtime!(
    environment_fingerprint: "fenix-host-a",
    fingerprint: "fenix-release-0.2.0",
    sdk_version: "fenix-0.2.0",
    reuse_enrollment: true
  )

  assert_equal first[:deployment].execution_environment_id, second[:deployment].execution_environment_id
  refute_equal first[:deployment].public_id, second[:deployment].public_id
end
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/execution_environments/reconcile_test.rb \
  test/services/execution_environments/record_capabilities_test.rb \
  test/requests/agent_api/registrations_test.rb \
  test/requests/agent_api/capabilities_test.rb \
  test/requests/agent_api/health_test.rb \
  test/integration/agent_registration_contract_test.rb \
  test/integration/bundled_default_agent_bootstrap_flow_test.rb \
  test/integration/external_fenix_pairing_flow_test.rb

cd ../agents/fenix
bin/rails test test/integration/external_runtime_pairing_test.rb
```

Expected: FAIL because pairing still treats the deployment as the primary runtime identity.

**Step 3: Write minimal implementation**

Implement the pairing split:

- reconcile or create `ExecutionEnvironment` from stable `environment_fingerprint`
- create or rotate `AgentDeployment` on top of that environment
- reject pairing when the runtime does not provide `environment_fingerprint`
- record environment capabilities independently from deployment capability snapshot
- keep transport reuse, but persist environment identity independently from deployment identity
- expose environment identity in contract payloads where the runtime boundary now depends on it

**Step 4: Run test to verify it passes**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/execution_environments/reconcile.rb \
  core_matrix/app/services/execution_environments/record_capabilities.rb \
  core_matrix/app/services/execution_environments/resolve_delivery_endpoint.rb \
  core_matrix/app/services/agent_deployments/register.rb \
  core_matrix/app/services/agent_deployments/handshake.rb \
  core_matrix/app/services/agent_deployments/record_heartbeat.rb \
  core_matrix/app/services/agent_deployments/mark_unavailable.rb \
  core_matrix/app/services/agent_deployments/retire.rb \
  core_matrix/app/services/installations/register_bundled_agent_runtime.rb \
  core_matrix/app/services/installations/bootstrap_bundled_agent_binding.rb \
  core_matrix/app/controllers/agent_api/registrations_controller.rb \
  core_matrix/app/controllers/agent_api/capabilities_controller.rb \
  core_matrix/app/controllers/agent_api/health_controller.rb \
  core_matrix/app/channels/application_cable/connection.rb \
  agents/fenix/app/services/runtime/pairing_manifest.rb \
  agents/fenix/app/controllers/runtime_manifests_controller.rb \
  core_matrix/test/services/execution_environments/reconcile_test.rb \
  core_matrix/test/services/execution_environments/record_capabilities_test.rb \
  core_matrix/test/requests/agent_api/registrations_test.rb \
  core_matrix/test/requests/agent_api/capabilities_test.rb \
  core_matrix/test/requests/agent_api/health_test.rb \
  core_matrix/test/integration/agent_registration_contract_test.rb \
  core_matrix/test/integration/bundled_default_agent_bootstrap_flow_test.rb \
  core_matrix/test/integration/external_fenix_pairing_flow_test.rb \
  agents/fenix/test/integration/external_runtime_pairing_test.rb
git commit -m "refactor: split environment reconciliation from deployment rotation"
```

### Task 3: Bind Conversation Capability And Attachment Policy To Environment Plus Agent

**Files:**
- Create: `core_matrix/app/services/runtime_capabilities/compose_for_conversation.rb`
- Create: `core_matrix/app/services/conversations/refresh_runtime_contract.rb`
- Create: `core_matrix/app/services/conversations/switch_agent_deployment.rb`
- Modify: `core_matrix/app/services/conversations/create_root.rb`
- Modify: `core_matrix/app/services/conversations/create_thread.rb`
- Modify: `core_matrix/app/services/conversations/create_branch.rb`
- Modify: `core_matrix/app/services/workflows/create_for_turn.rb`
- Modify: `core_matrix/app/services/workflows/context_assembler.rb`
- Modify: `core_matrix/app/services/workflows/manual_resume.rb`
- Modify: `core_matrix/app/models/conversation.rb`
- Modify: `core_matrix/app/models/execution_environment.rb`
- Modify: `core_matrix/app/models/capability_snapshot.rb`
- Create: `core_matrix/test/services/runtime_capabilities/compose_for_conversation_test.rb`
- Create: `core_matrix/test/services/conversations/refresh_runtime_contract_test.rb`
- Create: `core_matrix/test/services/conversations/switch_agent_deployment_test.rb`
- Modify: `core_matrix/test/services/workflows/context_assembler_test.rb`
- Modify: `core_matrix/test/services/workflows/manual_resume_test.rb`

**Step 1: Write the failing test**

```ruby
test "conversation attachments stay disabled when the agent allows files but the environment does not" do
  environment = create_execution_environment!(capability_payload: { "conversation_attachment_upload" => false })
  deployment = create_agent_deployment!(execution_environment: environment)
  create_capability_snapshot!(
    agent_deployment: deployment,
    tool_catalog: default_tool_catalog("shell_exec", "file_upload")
  )

  contract = RuntimeCapabilities::ComposeForConversation.call(
    execution_environment: environment,
    agent_deployment: deployment
  )

  assert_equal false, contract.fetch("conversation_attachment_upload")
end
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd core_matrix
bin/rails test \
  test/services/runtime_capabilities/compose_for_conversation_test.rb \
  test/services/conversations/refresh_runtime_contract_test.rb \
  test/services/conversations/switch_agent_deployment_test.rb \
  test/services/workflows/context_assembler_test.rb \
  test/services/workflows/manual_resume_test.rb
```

Expected: FAIL because capability composition still reads as deployment-only.

**Step 3: Write minimal implementation**

Implement the conversation contract refresh path:

- compose effective capabilities from environment and agent
- refresh on conversation creation and agent switch
- refresh on environment capability change without requiring deployment rotation
- gate attachment visibility and workflow resume rules against the composed contract
- keep the environment fixed while allowing the active deployment to change

**Step 4: Run test to verify it passes**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/runtime_capabilities/compose_for_conversation.rb \
  core_matrix/app/services/conversations/refresh_runtime_contract.rb \
  core_matrix/app/services/conversations/switch_agent_deployment.rb \
  core_matrix/app/services/conversations/create_root.rb \
  core_matrix/app/services/conversations/create_thread.rb \
  core_matrix/app/services/conversations/create_branch.rb \
  core_matrix/app/services/workflows/create_for_turn.rb \
  core_matrix/app/services/workflows/context_assembler.rb \
  core_matrix/app/services/workflows/manual_resume.rb \
  core_matrix/app/models/conversation.rb \
  core_matrix/app/models/execution_environment.rb \
  core_matrix/app/models/capability_snapshot.rb \
  core_matrix/test/services/runtime_capabilities/compose_for_conversation_test.rb \
  core_matrix/test/services/conversations/refresh_runtime_contract_test.rb \
  core_matrix/test/services/conversations/switch_agent_deployment_test.rb \
  core_matrix/test/services/workflows/context_assembler_test.rb \
  core_matrix/test/services/workflows/manual_resume_test.rb
git commit -m "feat: compose conversation runtime contract from environment and agent"
```

### Task 4: Separate Environment Ownership From Delivery Routing In Mailbox Control

**Files:**
- Create: `core_matrix/app/services/agent_control/resolve_target_runtime.rb`
- Modify: `core_matrix/app/models/agent_control_mailbox_item.rb`
- Modify: `core_matrix/app/models/execution_lease.rb`
- Modify: `core_matrix/app/services/agent_control/create_execution_assignment.rb`
- Modify: `core_matrix/app/services/agent_control/create_resource_close_request.rb`
- Modify: `core_matrix/app/services/agent_control/poll.rb`
- Modify: `core_matrix/app/services/agent_control/report.rb`
- Modify: `core_matrix/app/services/agent_control/serialize_mailbox_item.rb`
- Modify: `core_matrix/app/services/conversations/request_turn_interrupt.rb`
- Modify: `core_matrix/app/services/conversations/request_close.rb`
- Modify: `core_matrix/app/queries/conversations/close_summary_query.rb`
- Modify: `core_matrix/test/models/agent_control_mailbox_item_test.rb`
- Modify: `core_matrix/test/requests/agent_api/control_poll_test.rb`
- Modify: `core_matrix/test/requests/agent_api/execution_delivery_test.rb`
- Modify: `core_matrix/test/requests/agent_api/resource_close_test.rb`
- Modify: `core_matrix/test/services/conversations/request_turn_interrupt_test.rb`
- Modify: `core_matrix/test/e2e/protocol/mailbox_delivery_e2e_test.rb`
- Modify: `core_matrix/test/e2e/protocol/turn_interrupt_e2e_test.rb`
- Modify: `core_matrix/test/e2e/protocol/process_close_escalation_e2e_test.rb`

**Step 1: Write the failing test**

```ruby
test "resource close routes by execution environment owner even after deployment rotation" do
  scenario = build_rotated_runtime_context!
  process_run = create_process_run!(
    workflow_node: scenario.fetch(:workflow_node),
    execution_environment: scenario.fetch(:execution_environment),
    kind: "turn_command"
  )

  mailbox_item = AgentControl::CreateResourceCloseRequest.call(
    resource: process_run,
    reason_kind: "turn_interrupted"
  )

  assert_equal scenario.fetch(:execution_environment).public_id, mailbox_item.payload.fetch("execution_environment_id")
  assert_equal scenario.fetch(:replacement_deployment).public_id, mailbox_item.target_agent_deployment.public_id
end
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd core_matrix
bin/rails test \
  test/models/agent_control_mailbox_item_test.rb \
  test/requests/agent_api/control_poll_test.rb \
  test/requests/agent_api/execution_delivery_test.rb \
  test/requests/agent_api/resource_close_test.rb \
  test/services/conversations/request_turn_interrupt_test.rb \
  test/e2e/protocol/mailbox_delivery_e2e_test.rb \
  test/e2e/protocol/turn_interrupt_e2e_test.rb \
  test/e2e/protocol/process_close_escalation_e2e_test.rb
```

Expected: FAIL because owner identity and delivery endpoint are still partially conflated.

**Step 3: Write minimal implementation**

Implement routing separation:

- tag mailbox work by logical runtime plane
- persist environment owner identity on environment-plane work
- resolve the live delivery endpoint from the environment at send time
- keep timeout-driven fences, but require environment-plane close for environment-owned resources

**Step 4: Run test to verify it passes**

Run the same command and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/agent_control/resolve_target_runtime.rb \
  core_matrix/app/models/agent_control_mailbox_item.rb \
  core_matrix/app/models/execution_lease.rb \
  core_matrix/app/services/agent_control/create_execution_assignment.rb \
  core_matrix/app/services/agent_control/create_resource_close_request.rb \
  core_matrix/app/services/agent_control/poll.rb \
  core_matrix/app/services/agent_control/report.rb \
  core_matrix/app/services/agent_control/serialize_mailbox_item.rb \
  core_matrix/app/services/conversations/request_turn_interrupt.rb \
  core_matrix/app/services/conversations/request_close.rb \
  core_matrix/app/queries/conversations/close_summary_query.rb \
  core_matrix/test/models/agent_control_mailbox_item_test.rb \
  core_matrix/test/requests/agent_api/control_poll_test.rb \
  core_matrix/test/requests/agent_api/execution_delivery_test.rb \
  core_matrix/test/requests/agent_api/resource_close_test.rb \
  core_matrix/test/services/conversations/request_turn_interrupt_test.rb \
  core_matrix/test/e2e/protocol/mailbox_delivery_e2e_test.rb \
  core_matrix/test/e2e/protocol/turn_interrupt_e2e_test.rb \
  core_matrix/test/e2e/protocol/process_close_escalation_e2e_test.rb
git commit -m "refactor: route mailbox control by environment owner and runtime plane"
```

### Task 5: Publish Tool Precedence And Dual-Plane Runtime Surfaces

**Files:**
- Create: `core_matrix/app/services/runtime_capabilities/compose_effective_tool_catalog.rb`
- Modify: `core_matrix/app/controllers/agent_api/capabilities_controller.rb`
- Modify: `core_matrix/app/models/execution_environment.rb`
- Modify: `core_matrix/app/models/capability_snapshot.rb`
- Modify: `core_matrix/test/requests/agent_api/capabilities_test.rb`
- Modify: `core_matrix/test/integration/agent_registration_contract_test.rb`
- Modify: `agents/fenix/app/services/runtime/pairing_manifest.rb`
- Modify: `agents/fenix/app/services/context/build_execution_context.rb`
- Modify: `agents/fenix/app/services/runtime/execute_assignment.rb`
- Modify: `agents/fenix/app/services/runtime_surface/report_collector.rb`
- Modify: `agents/fenix/app/controllers/runtime_manifests_controller.rb`
- Modify: `agents/fenix/test/integration/external_runtime_pairing_test.rb`
- Modify: `agents/fenix/test/integration/runtime_flow_test.rb`
- Modify: `agents/fenix/test/services/runtime/execute_assignment_test.rb`
- Modify: `agents/fenix/test/services/hooks/runtime_hooks_test.rb`

**Step 1: Write the failing test**

```ruby
test "environment tools shadow agent tools outside the reserved system namespace" do
  response_body = capabilities_refresh_for!(
    environment_tools: [{"tool_name" => "shell_exec", "tool_kind" => "environment_runtime"}],
    agent_tools: [{"tool_name" => "shell_exec", "tool_kind" => "agent_observation"}]
  )

  shell_entry = response_body.fetch("effective_tool_catalog").find { |entry| entry.fetch("tool_name") == "shell_exec" }

  assert_equal "environment_runtime", shell_entry.fetch("tool_kind")
end
```

**Step 2: Run test to verify it fails**

Run:

```bash
cd core_matrix
bin/rails test test/requests/agent_api/capabilities_test.rb test/integration/agent_registration_contract_test.rb

cd ../agents/fenix
bin/rails test \
  test/integration/external_runtime_pairing_test.rb \
  test/integration/runtime_flow_test.rb \
  test/services/runtime/execute_assignment_test.rb \
  test/services/hooks/runtime_hooks_test.rb
```

Expected: FAIL because the runtime manifest and capability refresh output do not yet publish environment-first precedence or explicit plane information.

**Step 3: Write minimal implementation**

Implement the effective tool surface:

- rename model-visible Core Matrix system tools into the reserved
  `core_matrix__*` namespace
- compose the final tool catalog with `ExecutionEnvironment > AgentDeployment > CoreMatrix` for all non-`core_matrix__*` tool names
- publish both agent-plane and environment-plane capabilities in pairing and refresh payloads
- update Fenix to advertise and execute the bundled dual-plane contract explicitly

**Step 4: Run test to verify it passes**

Run the same commands and confirm PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/runtime_capabilities/compose_effective_tool_catalog.rb \
  core_matrix/app/controllers/agent_api/capabilities_controller.rb \
  core_matrix/app/models/execution_environment.rb \
  core_matrix/app/models/capability_snapshot.rb \
  core_matrix/test/requests/agent_api/capabilities_test.rb \
  core_matrix/test/integration/agent_registration_contract_test.rb \
  agents/fenix/app/services/runtime/pairing_manifest.rb \
  agents/fenix/app/services/context/build_execution_context.rb \
  agents/fenix/app/services/runtime/execute_assignment.rb \
  agents/fenix/app/services/runtime_surface/report_collector.rb \
  agents/fenix/app/controllers/runtime_manifests_controller.rb \
  agents/fenix/test/integration/external_runtime_pairing_test.rb \
  agents/fenix/test/integration/runtime_flow_test.rb \
  agents/fenix/test/services/runtime/execute_assignment_test.rb \
  agents/fenix/test/services/hooks/runtime_hooks_test.rb
git commit -m "feat: publish environment-first tool precedence and dual-plane runtime manifests"
```

### Task 6: Delete Stale Ownership Semantics From Docs, Tests, And Leftovers

**Files:**
- Modify: `core_matrix/docs/behavior/agent-registry-and-connectivity-foundations.md`
- Modify: `core_matrix/docs/behavior/agent-registration-and-capability-handshake.md`
- Modify: `core_matrix/docs/behavior/bundled-default-agent-bootstrap.md`
- Modify: `core_matrix/docs/behavior/conversation-structure-and-lineage.md`
- Modify: `core_matrix/docs/behavior/transcript-visibility-and-attachments.md`
- Modify: `core_matrix/docs/behavior/workflow-context-assembly-and-execution-snapshot.md`
- Modify: `core_matrix/docs/behavior/workflow-artifacts-node-events-and-process-runs.md`
- Modify: `core_matrix/docs/behavior/agent-runtime-resource-apis.md`
- Modify: `core_matrix/docs/behavior/subagent-connections-and-execution-leases.md`
- Modify: `docs/design/2026-03-24-core-matrix-agent-protocol-and-tool-surface-design.md`
- Modify: `docs/plans/2026-03-26-core-matrix-phase-2-plan-agent-loop-execution.md`
- Modify: `docs/plans/2026-03-26-core-matrix-phase-2-milestone-c-runtime-pairing-and-control.md`
- Modify: `docs/plans/2026-03-26-core-matrix-phase-2-task-execution-environment-runtime-boundary-follow-up.md`
- Modify: `agents/fenix/README.md`
- Modify: `docs/plans/README.md`
- Modify: any stale tests or helper code that still assert deployment-owned runtime behavior

**Step 1: Write the failing test or assertion sweep**

Add or update at least one focused regression test that proves the stale model is gone, for example:

```ruby
test "process close contracts never treat agent deployment as the runtime owner" do
  process_run = create_process_run!(execution_environment: create_execution_environment!)

  assert_equal process_run.execution_environment.public_id, process_run.owner_public_id
end
```

Then grep for stale phrases before editing docs:

```bash
rg -n "deployment-owned|owner of ProcessRun|runtime owner.*AgentDeployment|holder_key.*owner" core_matrix docs agents/fenix
```

**Step 2: Run the focused test and the grep sweep**

Run:

```bash
cd core_matrix
bin/rails test test/models/process_run_test.rb test/e2e/protocol/mailbox_delivery_e2e_test.rb test/e2e/protocol/process_close_escalation_e2e_test.rb

cd ..
rg -n "deployment-owned|owner of ProcessRun|runtime owner.*AgentDeployment|holder_key.*owner" core_matrix docs agents/fenix
```

Expected: the tests or grep should reveal stale ownership language or stale helper assumptions before cleanup.

**Step 3: Write minimal implementation**

Remove or rewrite every leftover artifact that teaches the wrong model:

- stale behavior docs
- stale README guidance
- stale helper names or assertions
- dead code that only exists to preserve deployment-owned semantics

**Step 4: Run full verification**

Run:

```bash
cd core_matrix
bin/rails db:test:prepare
bin/rails test \
  test/models/execution_environment_test.rb \
  test/models/conversation_test.rb \
  test/models/process_run_test.rb \
  test/models/agent_control_mailbox_item_test.rb \
  test/services/execution_environments/reconcile_test.rb \
  test/services/execution_environments/record_capabilities_test.rb \
  test/services/runtime_capabilities/compose_for_conversation_test.rb \
  test/services/conversations/refresh_runtime_contract_test.rb \
  test/services/conversations/switch_agent_deployment_test.rb \
  test/services/conversations/request_turn_interrupt_test.rb \
  test/services/workflows/context_assembler_test.rb \
  test/services/workflows/manual_resume_test.rb \
  test/requests/agent_api/registrations_test.rb \
  test/requests/agent_api/capabilities_test.rb \
  test/requests/agent_api/health_test.rb \
  test/requests/agent_api/control_poll_test.rb \
  test/requests/agent_api/execution_delivery_test.rb \
  test/requests/agent_api/resource_close_test.rb \
  test/integration/agent_registration_contract_test.rb \
  test/integration/bundled_default_agent_bootstrap_flow_test.rb \
  test/integration/external_fenix_pairing_flow_test.rb \
  test/integration/agent_runtime_resource_api_test.rb \
  test/e2e/protocol/mailbox_delivery_e2e_test.rb \
  test/e2e/protocol/turn_interrupt_e2e_test.rb \
  test/e2e/protocol/process_close_escalation_e2e_test.rb
git diff --check

cd ../agents/fenix
bin/rails test \
  test/integration/external_runtime_pairing_test.rb \
  test/integration/runtime_flow_test.rb \
  test/services/runtime/execute_assignment_test.rb \
  test/services/hooks/runtime_hooks_test.rb
git diff --check
```

Expected: PASS and zero diff-check errors.

**Step 5: Commit**

```bash
git add core_matrix/docs/behavior/agent-registry-and-connectivity-foundations.md \
  core_matrix/docs/behavior/agent-registration-and-capability-handshake.md \
  core_matrix/docs/behavior/bundled-default-agent-bootstrap.md \
  core_matrix/docs/behavior/conversation-structure-and-lineage.md \
  core_matrix/docs/behavior/transcript-visibility-and-attachments.md \
  core_matrix/docs/behavior/workflow-context-assembly-and-execution-snapshot.md \
  core_matrix/docs/behavior/workflow-artifacts-node-events-and-process-runs.md \
  core_matrix/docs/behavior/agent-runtime-resource-apis.md \
  core_matrix/docs/behavior/subagent-connections-and-execution-leases.md \
  docs/design/2026-03-24-core-matrix-agent-protocol-and-tool-surface-design.md \
  docs/plans/2026-03-26-core-matrix-phase-2-plan-agent-loop-execution.md \
  docs/plans/2026-03-26-core-matrix-phase-2-milestone-c-runtime-pairing-and-control.md \
  docs/plans/2026-03-26-core-matrix-phase-2-task-execution-environment-runtime-boundary-follow-up.md \
  agents/fenix/README.md \
  docs/plans/README.md
git commit -m "docs: remove stale deployment-owned runtime semantics"
```

## Final Acceptance Sweep

After Task 6, run one final manual review pass before opening follow-up execution:

1. Confirm every runtime-owned resource resolves to one `ExecutionEnvironment`.
2. Confirm no conversation can switch environments after creation.
3. Confirm active agent switching works inside one bound environment and refreshes the conversation contract.
4. Confirm environment capability refresh works without deployment rotation.
5. Confirm deployment rotation preserves environment identity and resource ownership.
6. Confirm timeout-driven stop paths still route environment-owned resources through mailbox control.
7. Confirm effective tool catalogs honor `ExecutionEnvironment > AgentDeployment > CoreMatrix` for ordinary tools and reserve `core_matrix__*` for system tools.
8. Confirm Fenix and future bundled-agent assumptions are explicit in docs and manifests.
9. Confirm no stale behavior doc, test name, helper, or canonical design note still teaches deployment-owned runtime semantics.
