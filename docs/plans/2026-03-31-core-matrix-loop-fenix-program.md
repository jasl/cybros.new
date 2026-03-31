# Core Matrix Loop With Fenix Agent Program Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move the provider-backed repeated agent loop into `core_matrix`, keep
`agents/fenix` as the agent-program layer that prepares prompts and executes
program-owned tools, and preserve the real 2048 browser capstone as the final
acceptance gate.

**Architecture:** `Core Matrix` and `Fenix` are intentionally fully orthogonal
and fully complementary. `Core Matrix` owns the outer round loop, provider
transport, generic tool calling, Streamable HTTP MCP support, workflow DAG
progression, and durable proof. `Fenix` participates only through the
mailbox-first control plane: `Core Matrix` enqueues durable work, websocket
push and poll deliver it, and `Fenix` reports results back. Dynamic per-round
program tools must be materialized as workflow-node-scoped durable records so
tool, command, and process proof no longer depends on `AgentTaskRun`.

**Tech Stack:** Ruby on Rails, Minitest, Active Job, Action Cable,
`SimpleInference`, Streamable HTTP MCP, durable mailbox records, JSON contract
fixtures, Dockerized `Fenix`, browser-based manual acceptance.

## Current Status

Core implementation is now on the mailbox-first boundary described here.

Implemented on this branch:

- mailbox-first shared contract fixtures replaced the old direct HTTP request
  and response fixtures
- `Fenix` manifest advertises mailbox-first program participation
- direct `Fenix` runtime callback routes for `prepare_round` and
  `execute_program_tool` were removed
- `Fenix` mailbox execution now handles `agent_program_request` work for both
  `prepare_round` and `execute_program_tool`
- `Core Matrix` direct `FenixProgramClient` bridge was deleted
- `Core Matrix` now uses `ProviderExecution::ProgramMailboxExchange`
- `Core Matrix` now persists and routes `agent_program_request` mailbox items
  and terminal `agent_program_completed` / `agent_program_failed` reports
- provider round execution, tool routing, and workflow execution tests were
  updated to the new `program_exchange` collaboration surface
- `provider_execution.loop_policy` is now the canonical loop-control contract;
  only `max_rounds` is active today, while parallel-tool and loop-detection
  fields are reserved for follow-up work

Completed on this plan:

- broader verification beyond the focused suites already run
- final browser-based 2048 acceptance and proof package refresh

---

## Execution Assumptions

- This implementation may be destructive. Do not preserve compatibility with
  the rejected Fenix-first loop boundary.
- Treat destructive change as the default posture for this branch when it
  produces a cleaner final `Core Matrix` plus `Fenix` split.
- Do not preserve compatibility with the rejected synchronous HTTP program
  contract.
- Do not add transitional adapters or compatibility shims unless a real
  external dependency forces it.
- If the current Core Matrix capability surface is missing something needed for
  the new design, extend Core Matrix directly rather than routing around the
  gap.
- If a persistence shape is wrong, fix it at the source. Database work may
  rewrite existing migration files in place and regenerate `schema.rb` from a
  clean database.
- The allowed destructive database reset flow for this branch is:

```bash
cd core_matrix
bin/rails db:drop
rm db/schema.rb
bin/rails db:create
bin/rails db:migrate
bin/rails db:reset
```

- Stop for discussion only if an architectural or design conflict becomes a
  real blocker. Otherwise continue automatically through implementation,
  verification, and the 2048 acceptance run.

## Task 1: Freeze The Mailbox-First Program Protocol

**Files:**
- Create: `shared/fixtures/contracts/core_matrix_fenix_prepare_round_mailbox_item_v1.json`
- Create: `shared/fixtures/contracts/fenix_prepare_round_report_v1.json`
- Create: `shared/fixtures/contracts/core_matrix_fenix_execute_program_tool_mailbox_item_v1.json`
- Create: `shared/fixtures/contracts/fenix_execute_program_tool_report_v1.json`
- Modify: `agents/fenix/app/services/fenix/runtime/pairing_manifest.rb`
- Test: `agents/fenix/test/integration/external_runtime_pairing_test.rb`
- Test: `core_matrix/test/integration/external_fenix_pairing_flow_test.rb`

**Step 1: Write the failing contract assertions**

Add fixture-backed expectations that the Fenix manifest advertises mailbox-first
control-plane participation rather than direct execution endpoints.

```ruby
manifest = Fenix::Runtime::PairingManifest.call(base_url: "https://fenix.example.test")

assert_equal "2026-03-31", manifest.fetch("protocol_version")
assert_equal "mailbox-first", manifest.dig("program_contract", "transport")
assert_equal ["prepare_round", "execute_program_tool"], manifest.dig("program_contract", "methods")
assert_equal ["websocket_push", "poll"], manifest.dig("program_contract", "delivery")
assert_equal "/agent_api/control/report", manifest.dig("control_plane", "report_path")
```

**Step 2: Run the focused tests and confirm they fail**

Run: `cd agents/fenix && bin/rails test test/integration/external_runtime_pairing_test.rb`

Expected: FAIL because the manifest still describes the rejected direct program
HTTP contract.

Run: `cd core_matrix && bin/rails test test/integration/external_fenix_pairing_flow_test.rb`

Expected: FAIL once the Core Matrix side starts asserting the mailbox-first
manifest payload.

**Step 3: Add the shared fixtures and manifest fields**

Update the manifest to advertise the mailbox-first program contract explicitly
and keep the payload small and machine-readable.

**Step 4: Re-run the contract tests**

Run: `cd agents/fenix && bin/rails test test/integration/external_runtime_pairing_test.rb`

Expected: PASS.

Run: `cd core_matrix && bin/rails test test/integration/external_fenix_pairing_flow_test.rb`

Expected: PASS with the new manifest metadata preserved through registration.

**Step 5: Commit**

```bash
git add shared/fixtures/contracts/core_matrix_fenix_prepare_round_mailbox_item_v1.json shared/fixtures/contracts/fenix_prepare_round_report_v1.json shared/fixtures/contracts/core_matrix_fenix_execute_program_tool_mailbox_item_v1.json shared/fixtures/contracts/fenix_execute_program_tool_report_v1.json agents/fenix/app/services/fenix/runtime/pairing_manifest.rb agents/fenix/test/integration/external_runtime_pairing_test.rb core_matrix/test/integration/external_fenix_pairing_flow_test.rb
git commit -m "docs: freeze mailbox-first program contract"
```

## Task 2: Add Durable Core Matrix Request-Reply Coordination For Agent Program Work

**Files:**
- Create: `core_matrix/app/services/agent_programs/request_round_preparation.rb`
- Create: `core_matrix/app/services/agent_programs/request_program_tool_execution.rb`
- Create: `core_matrix/app/services/agent_programs/await_mailbox_report.rb`
- Create: `core_matrix/app/services/agent_programs/program_mailbox_payloads.rb`
- Modify: `core_matrix/app/services/agent_control/create_execution_assignment.rb`
- Modify: `core_matrix/app/services/agent_control/handle_execution_report.rb`
- Test: `core_matrix/test/services/agent_programs/request_round_preparation_test.rb`
- Test: `core_matrix/test/services/agent_programs/request_program_tool_execution_test.rb`
- Test: `core_matrix/test/services/agent_programs/await_mailbox_report_test.rb`

**Step 1: Write the failing coordinator tests**

Cover one successful round-preparation request, one successful program-tool
request, timeout behavior, and correlation by mailbox item plus logical work id.

**Step 2: Run the focused tests and confirm the coordination layer is missing**

Run: `cd core_matrix && bin/rails test test/services/agent_programs/request_round_preparation_test.rb test/services/agent_programs/request_program_tool_execution_test.rb test/services/agent_programs/await_mailbox_report_test.rb`

Expected: FAIL because there is no mailbox request-reply coordinator for
agent-program work.

**Step 3: Implement durable request-reply helpers**

The helpers should:

- create mailbox items for `prepare_round` and `execute_program_tool`
- record correlation identifiers in payload and metadata
- await terminal reports from the existing control-plane report stream
- surface structured success and structured failure back to provider execution

**Step 4: Re-run the focused coordination tests**

Run: `cd core_matrix && bin/rails test test/services/agent_programs/request_round_preparation_test.rb test/services/agent_programs/request_program_tool_execution_test.rb test/services/agent_programs/await_mailbox_report_test.rb`

Expected: PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/agent_programs/request_round_preparation.rb core_matrix/app/services/agent_programs/request_program_tool_execution.rb core_matrix/app/services/agent_programs/await_mailbox_report.rb core_matrix/app/services/agent_programs/program_mailbox_payloads.rb core_matrix/app/services/agent_control/create_execution_assignment.rb core_matrix/app/services/agent_control/handle_execution_report.rb core_matrix/test/services/agent_programs/request_round_preparation_test.rb core_matrix/test/services/agent_programs/request_program_tool_execution_test.rb core_matrix/test/services/agent_programs/await_mailbox_report_test.rb
git commit -m "feat: add mailbox program request reply coordination"
```

## Task 3: Teach Fenix To Execute `prepare_round` From Mailbox Work

**Files:**
- Create: `agents/fenix/app/services/fenix/runtime/prepare_round.rb`
- Create: `agents/fenix/app/services/fenix/runtime/execute_prepare_round_mailbox_item.rb`
- Modify: `agents/fenix/app/services/fenix/runtime/control_loop_once.rb`
- Modify: `agents/fenix/app/services/fenix/runtime/control_loop_forever.rb`
- Modify: `agents/fenix/app/services/fenix/context/build_execution_context.rb`
- Test: `agents/fenix/test/services/fenix/runtime/prepare_round_test.rb`
- Test: `agents/fenix/test/integration/runtime_program_contract_test.rb`
- Test: `agents/fenix/test/integration/runtime_flow_test.rb`

**Step 1: Write the failing tests for mailbox-driven round preparation**

Assert that a `prepare_round` mailbox item produces a structured control-plane
report containing prepared messages and a round-local program tool catalog.

**Step 2: Run the Fenix tests and confirm the mailbox handler is missing**

Run: `cd agents/fenix && bin/rails test test/integration/runtime_program_contract_test.rb test/services/fenix/runtime/prepare_round_test.rb`

Expected: FAIL because the mailbox executor does not yet understand
`prepare_round`.

**Step 3: Implement the handler with the existing Fenix hooks**

Keep the service thin: build round context, call the existing prompt and
compaction hooks, let Fenix choose skills internally, and report only the final
messages plus visible program tools.

**Step 4: Run the Fenix round-preparation tests**

Run: `cd agents/fenix && bin/rails test test/integration/runtime_program_contract_test.rb test/services/fenix/runtime/prepare_round_test.rb test/integration/runtime_flow_test.rb`

Expected: PASS, and the existing runtime flow tests should still pass.

**Step 5: Commit**

```bash
git add agents/fenix/app/services/fenix/runtime/prepare_round.rb agents/fenix/app/services/fenix/runtime/execute_prepare_round_mailbox_item.rb agents/fenix/app/services/fenix/runtime/control_loop_once.rb agents/fenix/app/services/fenix/runtime/control_loop_forever.rb agents/fenix/app/services/fenix/context/build_execution_context.rb agents/fenix/test/integration/runtime_program_contract_test.rb agents/fenix/test/services/fenix/runtime/prepare_round_test.rb agents/fenix/test/integration/runtime_flow_test.rb
git commit -m "feat: handle mailbox round preparation in fenix"
```

## Task 4: Extract Program Tool Execution And Route It Through Mailbox Work

**Files:**
- Create: `agents/fenix/app/services/fenix/runtime/program_tool_executor.rb`
- Create: `agents/fenix/app/services/fenix/runtime/execute_program_tool_mailbox_item.rb`
- Modify: `agents/fenix/app/services/fenix/runtime/execute_assignment.rb`
- Modify: `agents/fenix/app/services/fenix/runtime/control_loop_once.rb`
- Modify: `agents/fenix/app/services/fenix/runtime/control_loop_forever.rb`
- Test: `agents/fenix/test/services/fenix/runtime/execute_assignment_test.rb`
- Test: `agents/fenix/test/services/fenix/runtime/program_tool_executor_test.rb`
- Test: `agents/fenix/test/integration/runtime_program_contract_test.rb`

**Step 1: Write the failing tests for mailbox program-tool execution**

Cover a calculator-style tool, an `exec_command` tool that provisions
command-run metadata, and a rejected tool name, all through mailbox execution
and reports.

**Step 2: Run the Fenix tests and confirm the new mailbox path is absent**

Run: `cd agents/fenix && bin/rails test test/integration/runtime_program_contract_test.rb test/services/fenix/runtime/execute_assignment_test.rb`

Expected: FAIL because `execute_program_tool` mailbox handling and the reusable
executor are not present.

**Step 3: Extract the deterministic tool path and reuse it**

Move the deterministic tool path out of `ExecuteAssignment` into a reusable
service so both the legacy assignment path and the new mailbox path share the
same implementation.

**Step 4: Re-run the Fenix execution tests**

Run: `cd agents/fenix && bin/rails test test/services/fenix/runtime/program_tool_executor_test.rb test/services/fenix/runtime/execute_assignment_test.rb test/integration/runtime_program_contract_test.rb`

Expected: PASS, including existing `exec_command` and `write_stdin` behaviors.

**Step 5: Commit**

```bash
git add agents/fenix/app/services/fenix/runtime/program_tool_executor.rb agents/fenix/app/services/fenix/runtime/execute_program_tool_mailbox_item.rb agents/fenix/app/services/fenix/runtime/execute_assignment.rb agents/fenix/app/services/fenix/runtime/control_loop_once.rb agents/fenix/app/services/fenix/runtime/control_loop_forever.rb agents/fenix/test/services/fenix/runtime/program_tool_executor_test.rb agents/fenix/test/services/fenix/runtime/execute_assignment_test.rb agents/fenix/test/integration/runtime_program_contract_test.rb
git commit -m "feat: route program tools through mailbox execution"
```

## Task 5: Move Durable Tool Proof From `AgentTaskRun` To `WorkflowNode`

**Files:**
- Modify: `core_matrix/db/migrate/*tool_runtime_records*.rb`
- Modify: `core_matrix/app/models/tool_binding.rb`
- Modify: `core_matrix/app/models/tool_invocation.rb`
- Modify: `core_matrix/app/models/command_run.rb`
- Modify: `core_matrix/app/models/agent_task_run.rb`
- Create: `core_matrix/app/services/tool_bindings/freeze_for_workflow_node.rb`
- Modify: `core_matrix/app/services/tool_invocations/start.rb`
- Modify: `core_matrix/app/services/tool_invocations/provision.rb`
- Modify: `core_matrix/app/services/command_runs/provision.rb`
- Test: `core_matrix/test/models/tool_binding_test.rb`
- Test: `core_matrix/test/models/tool_invocation_test.rb`
- Test: `core_matrix/test/services/tool_bindings/freeze_for_workflow_node_test.rb`
- Test: `core_matrix/test/services/tool_invocations/lifecycle_test.rb`
- Test: `core_matrix/test/services/command_runs/terminalize_test.rb`

**Step 1: Write the failing persistence tests**

Add tests that provision a tool binding directly for a `workflow_node` without
an `AgentTaskRun`, then create a tool invocation and command run from that
binding.

**Step 2: Run the focused Core Matrix tests and confirm the schema is missing**

Run: `cd core_matrix && bin/rails test test/models/tool_binding_test.rb test/models/tool_invocation_test.rb test/services/tool_invocations/lifecycle_test.rb`

Expected: FAIL because `workflow_node_id` does not yet own the durable tool
records cleanly enough for the new outer-loop path.

**Step 3: Add the workflow-node projection**

Make `agent_task_run_id` optional where needed, add `workflow_node_id`, and
treat `workflow_node` as the durable execution owner for the new outer-loop
path.

**Step 4: Run migrations and the focused Core Matrix tests**

Run: `cd core_matrix && bin/rails db:migrate`

Expected: PASS.

Run: `cd core_matrix && bin/rails db:test:prepare test test/models/tool_binding_test.rb test/models/tool_invocation_test.rb test/services/tool_invocations/lifecycle_test.rb test/services/command_runs/terminalize_test.rb`

Expected: PASS.

**Step 5: Commit**

```bash
git add core_matrix/db/migrate core_matrix/app/models/tool_binding.rb core_matrix/app/models/tool_invocation.rb core_matrix/app/models/command_run.rb core_matrix/app/models/agent_task_run.rb core_matrix/app/services/tool_bindings/freeze_for_workflow_node.rb core_matrix/app/services/tool_invocations/start.rb core_matrix/app/services/tool_invocations/provision.rb core_matrix/app/services/command_runs/provision.rb core_matrix/test/models/tool_binding_test.rb core_matrix/test/models/tool_invocation_test.rb core_matrix/test/services/tool_bindings/freeze_for_workflow_node_test.rb core_matrix/test/services/tool_invocations/lifecycle_test.rb core_matrix/test/services/command_runs/terminalize_test.rb
git commit -m "refactor: project tool proof onto workflow nodes"
```

## Task 6: Materialize Round-Local Program Tools And Replace The HTTP Client Bridge

**Files:**
- Delete: `core_matrix/app/services/provider_execution/fenix_program_client.rb`
- Delete: `core_matrix/test/services/provider_execution/fenix_program_client_test.rb`
- Create: `core_matrix/app/services/provider_execution/prepare_program_round.rb`
- Create: `core_matrix/app/services/provider_execution/materialize_round_tools.rb`
- Modify: `core_matrix/app/services/provider_execution/route_tool_call.rb`
- Modify: `core_matrix/app/services/runtime_capabilities/compose_effective_tool_catalog.rb`
- Modify: `core_matrix/app/services/tool_bindings/freeze_for_workflow_node.rb`
- Test: `core_matrix/test/services/provider_execution/prepare_program_round_test.rb`
- Test: `core_matrix/test/services/provider_execution/route_tool_call_test.rb`
- Test: `core_matrix/test/services/tool_bindings/freeze_for_workflow_node_test.rb`

**Step 1: Write the failing tests for mailbox-backed round preparation**

Cover one successful `prepare_round` mailbox request, one structured failure,
and one round-local tool catalog with a dynamic Fenix tool that is not present
in the static capability snapshot.

**Step 2: Run the Core Matrix tests and confirm the HTTP bridge is wrong**

Run: `cd core_matrix && bin/rails test test/services/provider_execution/prepare_program_round_test.rb test/services/provider_execution/route_tool_call_test.rb test/services/tool_bindings/freeze_for_workflow_node_test.rb`

Expected: FAIL because the provider execution path still assumes direct HTTP
dispatch into `Fenix`.

**Step 3: Replace direct dispatch with mailbox coordination**

`PrepareProgramRound` should call the new mailbox request-reply coordinator.
`RouteToolCall` should enqueue program-tool execution when the selected binding
belongs to the agent-program side.

`MaterializeRoundTools` should create or reuse workflow-node-scoped tool
bindings for the exact tool set `Fenix` exposes for this round, even when the
tool name is absent from the static capability snapshot.

**Step 4: Re-run the mailbox-backed round tests**

Run: `cd core_matrix && bin/rails test test/services/provider_execution/prepare_program_round_test.rb test/services/provider_execution/route_tool_call_test.rb test/services/tool_bindings/freeze_for_workflow_node_test.rb`

Expected: PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/provider_execution/prepare_program_round.rb core_matrix/app/services/provider_execution/materialize_round_tools.rb core_matrix/app/services/provider_execution/route_tool_call.rb core_matrix/app/services/runtime_capabilities/compose_effective_tool_catalog.rb core_matrix/app/services/tool_bindings/freeze_for_workflow_node.rb core_matrix/test/services/provider_execution/prepare_program_round_test.rb core_matrix/test/services/provider_execution/route_tool_call_test.rb core_matrix/test/services/tool_bindings/freeze_for_workflow_node_test.rb
git rm core_matrix/app/services/provider_execution/fenix_program_client.rb core_matrix/test/services/provider_execution/fenix_program_client_test.rb
git commit -m "refactor: replace fenix http bridge with mailbox coordination"
```

## Task 7: Run The Provider Round Loop Through Mailbox-Backed Program Participation

**Files:**
- Modify: `core_matrix/app/services/provider_execution/execute_round_loop.rb`
- Modify: `core_matrix/app/services/provider_execution/append_tool_result.rb`
- Modify: `core_matrix/app/services/provider_execution/dispatch_request.rb`
- Modify: `core_matrix/app/services/provider_execution/execute_turn_step.rb`
- Modify: `core_matrix/app/services/workflows/execute_node.rb`
- Test: `core_matrix/test/services/provider_execution/execute_round_loop_test.rb`
- Test: `core_matrix/test/services/provider_execution/dispatch_request_test.rb`
- Test: `core_matrix/test/services/provider_execution/execute_turn_step_test.rb`
- Test: `core_matrix/test/integration/provider_backed_turn_execution_test.rb`

**Step 1: Write the failing end-to-end loop tests**

Cover one successful `prepare_round`, one program-owned tool execution, one
kernel-native tool execution, and one round-local tool catalog inside a full
provider-backed turn.

**Step 2: Run the focused Core Matrix tests and confirm the loop is still tied to the wrong bridge**

Run: `cd core_matrix && bin/rails test test/services/provider_execution/execute_round_loop_test.rb test/services/provider_execution/dispatch_request_test.rb test/services/provider_execution/execute_turn_step_test.rb test/integration/provider_backed_turn_execution_test.rb`

Expected: FAIL because the loop still assumes direct program callbacks or does
not yet await mailbox-backed replies cleanly.

**Step 3: Implement the mailbox-backed loop**

The round loop should:

- request round preparation through the mailbox coordinator
- merge program-owned tools with kernel-native and MCP tools
- call the provider
- route program-owned tool calls back through mailbox execution
- append reported tool results and continue the loop

**Step 4: Re-run the focused Core Matrix tests**

Run: `cd core_matrix && bin/rails test test/services/provider_execution/execute_round_loop_test.rb test/services/provider_execution/dispatch_request_test.rb test/services/provider_execution/execute_turn_step_test.rb test/integration/provider_backed_turn_execution_test.rb`

Expected: PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/provider_execution/execute_round_loop.rb core_matrix/app/services/provider_execution/append_tool_result.rb core_matrix/app/services/provider_execution/dispatch_request.rb core_matrix/app/services/provider_execution/execute_turn_step.rb core_matrix/app/services/workflows/execute_node.rb core_matrix/test/services/provider_execution/execute_round_loop_test.rb core_matrix/test/services/provider_execution/dispatch_request_test.rb core_matrix/test/services/provider_execution/execute_turn_step_test.rb core_matrix/test/integration/provider_backed_turn_execution_test.rb
git commit -m "feat: run provider loop through mailbox-backed program participation"
```

## Task 8: Remove Rejected HTTP Program-Contract Code Paths

**Files:**
- Delete any Fenix runtime controllers or routes added only for direct program
  HTTP callbacks
- Delete any Core Matrix tests that assert direct HTTP program dispatch
- Modify docs and READMEs that still describe the rejected callback model

**Step 1: Write the failing cleanup assertions**

Add tests or static assertions that the manifest no longer advertises direct
program execution endpoints and that no provider execution path references the
deleted HTTP bridge.

**Step 2: Run the focused cleanup tests**

Run: `cd agents/fenix && bin/rails test test/integration/external_runtime_pairing_test.rb test/integration/runtime_program_contract_test.rb`

Run: `cd core_matrix && bin/rails test test/integration/external_fenix_pairing_flow_test.rb test/services/provider_execution/prepare_program_round_test.rb`

Expected: FAIL until the rejected HTTP path is fully removed.

**Step 3: Remove the dead code and update docs**

Delete direct program callback controllers, routes, client code, and tests that
encode the wrong architecture.

**Step 4: Re-run the cleanup tests**

Expected: PASS.

**Step 5: Commit**

```bash
git add agents/fenix core_matrix docs
git commit -m "refactor: remove rejected http program contract"
```

## Task 9: Verify End-To-End And Perform The 2048 Acceptance Run

**Files:**
- Update or create proof artifacts under
  `docs/checklists/artifacts/2026-03-31-core-matrix-loop-fenix-2048`

**Step 1: Run focused verification for `agents/fenix`**

```bash
cd agents/fenix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bin/rails db:test:prepare test
```

Expected: PASS.

**Step 2: Run focused verification for `core_matrix`**

```bash
cd core_matrix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails db:test:prepare test
bin/rails db:test:prepare test:system
```

Expected: PASS.

**Step 3: Perform the manual browser acceptance**

Acceptance must prove:

- a real `Core Matrix` turn enters the provider-backed round loop
- `Fenix` participates only through mailbox-first control-plane work
- the browser workload is real and visible
- the agent manually operates the browser through the normal tool surface
- the browser-based `2048` game finishes successfully

**Step 4: Capture the proof package**

Record:

- mailbox items and reports for at least one `prepare_round`
- mailbox items and reports for at least one program-owned tool execution
- runtime transcripts and screenshots
- final acceptance notes showing the `2048` completion path

**Step 5: Commit**

```bash
git add docs/checklists/artifacts/2026-03-31-core-matrix-loop-fenix-2048
git commit -m "test: verify mailbox-first core matrix fenix acceptance"
```

## Expected Final State

At the end of this plan:

- `Core Matrix` owns provider transport and the repeated loop
- `Core Matrix` never directly dispatches application work into `Fenix`
  through synchronous RPC
- mailbox work is the only normal cross-app execution protocol
- websocket push and poll are interchangeable delivery mechanisms
- `Fenix` still owns prompt policy, skills, and program-owned tools
- round-local tool catalogs are durable at the workflow-node boundary
- the rejected direct HTTP bridge is gone
- the browser-based `2048` acceptance proof is complete
