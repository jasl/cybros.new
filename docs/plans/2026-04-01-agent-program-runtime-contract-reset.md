# Agent Program Runtime Contract Reset Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reset the `core_matrix` <-> `agents/fenix` runtime contract to the new sectioned `agent program` envelope without preserving compatibility or historical fixture shapes.

**Architecture:** Treat this as a hard contract reset, not an incremental migration. Rewrite the shared fixtures first, then make `core_matrix` emit the new envelope, make `agents/fenix` consume and return it, and finally replace report payload parsing with typed `runtime_events` and `summary_artifacts`. Keep all agent-effect logic in `agents/fenix`; keep `core_matrix` focused on durable projection, capability visibility, mailbox delivery, and resource truth.

**Tech Stack:** Ruby on Rails, shared JSON contract fixtures, ActiveSupport tests, Core Matrix mailbox/runtime services, Fenix runtime services, versioned JSON payload envelopes.

---

## Preconditions

- This plan assumes the design in
  `docs/design/2026-04-01-agent-program-runtime-contract.md` is approved.
- This work is intentionally destructive:
  - do not preserve old payload shapes
  - do not add compatibility shims
  - do not keep `_v1` fixture naming
  - database reset is acceptable if schema corrections become simpler than
    migration
- Re-read before implementing:
  - `docs/design/2026-04-01-agent-program-runtime-contract.md`
  - `docs/design/2026-03-24-core-matrix-agent-protocol-and-tool-surface-design.md`
  - `core_matrix/app/services/workflows/build_execution_snapshot.rb`
  - `core_matrix/app/models/turn_execution_snapshot.rb`
  - `core_matrix/app/services/agent_control/create_execution_assignment.rb`
  - `core_matrix/app/services/provider_execution/prepare_program_round.rb`
  - `core_matrix/app/services/provider_execution/route_tool_call.rb`
  - `core_matrix/app/services/agent_control/handle_execution_report.rb`
  - `agents/fenix/app/services/fenix/context/build_execution_context.rb`
  - `agents/fenix/app/services/fenix/runtime/prepare_round.rb`
  - `agents/fenix/app/services/fenix/runtime/execute_program_tool.rb`
  - `agents/fenix/app/services/fenix/runtime/execute_agent_program_request.rb`
  - `agents/fenix/app/services/fenix/runtime/execute_assignment.rb`
  - `agents/fenix/app/services/fenix/runtime_surface/report_collector.rb`
- Shared fixtures currently live under `shared/fixtures/contracts/`.

## Target Contract

The implementation should converge on these section names:

- `protocol_version`
- `request_kind`
- `task`
- `conversation_projection`
- `capability_projection`
- `provider_context`
- `runtime_context`
- `task_payload`

The implementation should remove these public contract fields:

- `agent_context`
- `context_messages`
- `transcript`
- `program_tools`
- ad hoc `tool_invocation` / `tool_invocation_output` progress payload shapes

The implementation should add these durable cross-boundary fields:

- `tool_surface`
- `runtime_events`
- `summary_artifacts`
- `projection_fingerprint`

### Task 1: Rewrite the shared contract fixtures around the new sectioned envelope

**Files:**
- Create: `shared/fixtures/contracts/core_matrix_fenix_execution_assignment.json`
- Create: `shared/fixtures/contracts/core_matrix_fenix_prepare_round_mailbox_item.json`
- Create: `shared/fixtures/contracts/core_matrix_fenix_execute_program_tool_mailbox_item.json`
- Create: `shared/fixtures/contracts/fenix_prepare_round_report.json`
- Create: `shared/fixtures/contracts/fenix_execute_program_tool_report.json`
- Delete: `shared/fixtures/contracts/core_matrix_fenix_execution_assignment_v1.json`
- Delete: `shared/fixtures/contracts/core_matrix_fenix_prepare_round_mailbox_item_v1.json`
- Delete: `shared/fixtures/contracts/core_matrix_fenix_execute_program_tool_mailbox_item_v1.json`
- Delete: `shared/fixtures/contracts/fenix_prepare_round_report_v1.json`
- Delete: `shared/fixtures/contracts/fenix_execute_program_tool_report_v1.json`
- Modify: `agents/fenix/test/test_helper.rb`
- Test: `agents/fenix/test/integration/runtime_program_contract_test.rb`
- Test: `agents/fenix/test/services/fenix/runtime/prepare_round_test.rb`
- Test: `agents/fenix/test/services/fenix/runtime/execute_assignment_test.rb`
- Test: `core_matrix/test/services/agent_control/create_execution_assignment_test.rb`

**Step 1: Write the failing tests**

Update every fixture-backed test to look for the new top-level sections and new
fixture names. For example, the normalized prepare-round fixture should assert a
response like:

```json
{
  "response_payload": {
    "status": "ok",
    "messages": [{ "role": "system" }],
    "tool_surface": [{ "tool_name": "calculator" }],
    "summary_artifacts": [],
    "trace": [{ "hook": "prepare_turn" }]
  }
}
```

**Step 2: Run tests to verify they fail**

```bash
cd core_matrix
bin/rails test test/services/agent_control/create_execution_assignment_test.rb

cd ../agents/fenix
bin/rails test test/integration/runtime_program_contract_test.rb test/services/fenix/runtime/prepare_round_test.rb test/services/fenix/runtime/execute_assignment_test.rb
```

Expected: FAIL because the new fixtures and keys do not exist yet.

**Step 3: Write minimal implementation**

- Replace `_v1` fixture files with the new canonical names.
- Update `shared_contract_fixture` lookup code and fixture references.
- Make the new fixtures match the target envelope from the design document.
- Do not preserve the old fixture names as aliases.

**Step 4: Run tests to verify they pass**

```bash
cd core_matrix
bin/rails test test/services/agent_control/create_execution_assignment_test.rb

cd ../agents/fenix
bin/rails test test/integration/runtime_program_contract_test.rb test/services/fenix/runtime/prepare_round_test.rb test/services/fenix/runtime/execute_assignment_test.rb
```

Expected: PASS

**Step 5: Commit**

```bash
git add shared/fixtures/contracts agents/fenix/test/test_helper.rb agents/fenix/test/integration/runtime_program_contract_test.rb agents/fenix/test/services/fenix/runtime/prepare_round_test.rb agents/fenix/test/services/fenix/runtime/execute_assignment_test.rb core_matrix/test/services/agent_control/create_execution_assignment_test.rb
git commit -m "refactor: reset shared agent program contract fixtures"
```

### Task 2: Reset `TurnExecutionSnapshot` and execution snapshot builders to the new section layout

**Files:**
- Modify: `core_matrix/app/models/turn_execution_snapshot.rb`
- Modify: `core_matrix/app/services/workflows/build_execution_snapshot.rb`
- Test: `core_matrix/test/models/turn_execution_snapshot_test.rb`
- Test: `core_matrix/test/services/workflows/build_execution_snapshot_test.rb`
- Test: `core_matrix/test/services/provider_execution/execute_round_loop_test.rb`

**Step 1: Write the failing tests**

Update snapshot tests to assert the new read API:

- `conversation_projection`
- `capability_projection`
- `provider_context`
- `runtime_context`

Remove assertions for `agent_context` and `context_messages`.

**Step 2: Run tests to verify they fail**

```bash
cd core_matrix
bin/rails test test/models/turn_execution_snapshot_test.rb test/services/workflows/build_execution_snapshot_test.rb test/services/provider_execution/execute_round_loop_test.rb
```

Expected: FAIL because the snapshot object still exposes the old keys.

**Step 3: Write minimal implementation**

- Change `TurnExecutionSnapshot` to expose the new section readers.
- Change `Workflows::BuildExecutionSnapshot` to populate:
  - `conversation_projection.messages`
  - `conversation_projection.context_imports`
  - `capability_projection.tool_surface`
  - `capability_projection.profile_key`
  - `provider_context.budget_hints`
  - `runtime_context.deployment_public_id`
- Compute `projection_fingerprint` from the conversation projection payload.
- Remove `agent_context` and `context_messages` from the public snapshot shape.

**Step 4: Run tests to verify they pass**

```bash
cd core_matrix
bin/rails test test/models/turn_execution_snapshot_test.rb test/services/workflows/build_execution_snapshot_test.rb test/services/provider_execution/execute_round_loop_test.rb
```

Expected: PASS

**Step 5: Commit**

```bash
git add core_matrix/app/models/turn_execution_snapshot.rb core_matrix/app/services/workflows/build_execution_snapshot.rb core_matrix/test/models/turn_execution_snapshot_test.rb core_matrix/test/services/workflows/build_execution_snapshot_test.rb core_matrix/test/services/provider_execution/execute_round_loop_test.rb
git commit -m "refactor: section execution snapshots for agent programs"
```

### Task 3: Reset the kernel request builders for assignment and round preparation

**Files:**
- Modify: `core_matrix/app/services/agent_control/create_execution_assignment.rb`
- Modify: `core_matrix/app/services/provider_execution/prepare_program_round.rb`
- Modify: `core_matrix/app/services/provider_execution/program_mailbox_exchange.rb`
- Modify: `core_matrix/test/services/agent_control/create_execution_assignment_test.rb`
- Modify: `core_matrix/test/services/provider_execution/prepare_program_round_test.rb`
- Modify: `core_matrix/test/services/provider_execution/program_mailbox_exchange_test.rb`

**Step 1: Write the failing tests**

Update request-builder tests to assert:

- the assignment payload uses `task`, `conversation_projection`,
  `capability_projection`, `provider_context`, `runtime_context`
- prepare-round requests use `conversation_projection.messages` instead of
  `transcript`
- mailbox exchange validates `tool_surface` instead of `program_tools`

**Step 2: Run tests to verify they fail**

```bash
cd core_matrix
bin/rails test test/services/agent_control/create_execution_assignment_test.rb test/services/provider_execution/prepare_program_round_test.rb test/services/provider_execution/program_mailbox_exchange_test.rb
```

Expected: FAIL because the request payloads and validators still use legacy
field names.

**Step 3: Write minimal implementation**

- Rewrite `CreateExecutionAssignment` to emit the new sectioned envelope.
- Rewrite `PrepareProgramRound` to send the new request shape.
- Rewrite mailbox response validation to require:
  - `status`
  - `messages`
  - `tool_surface`
- Remove use of `program_tools` in the public contract.

**Step 4: Run tests to verify they pass**

```bash
cd core_matrix
bin/rails test test/services/agent_control/create_execution_assignment_test.rb test/services/provider_execution/prepare_program_round_test.rb test/services/provider_execution/program_mailbox_exchange_test.rb
```

Expected: PASS

**Step 5: Commit**

```bash
git add core_matrix/app/services/agent_control/create_execution_assignment.rb core_matrix/app/services/provider_execution/prepare_program_round.rb core_matrix/app/services/provider_execution/program_mailbox_exchange.rb core_matrix/test/services/agent_control/create_execution_assignment_test.rb core_matrix/test/services/provider_execution/prepare_program_round_test.rb core_matrix/test/services/provider_execution/program_mailbox_exchange_test.rb
git commit -m "refactor: reset kernel request envelopes for agent programs"
```

### Task 4: Reset the kernel tool-routing contract around `program_tool_call` and `runtime_resource_refs`

**Files:**
- Modify: `core_matrix/app/services/provider_execution/route_tool_call.rb`
- Modify: `core_matrix/app/services/provider_execution/execute_round_loop.rb`
- Modify: `core_matrix/test/services/provider_execution/route_tool_call_test.rb`
- Modify: `core_matrix/test/services/provider_execution/execute_round_loop_test.rb`
- Modify: `core_matrix/test/integration/provider_backed_graph_loop_test.rb`

**Step 1: Write the failing tests**

Update tool-routing tests to expect the execute-program-tool request shape:

```json
{
  "request_kind": "execute_program_tool",
  "task": { "workflow_node_id": "..." },
  "capability_projection": { "tool_surface": [] },
  "program_tool_call": {
    "call_id": "call-calculator-1",
    "tool_name": "calculator",
    "arguments": { "expression": "2 + 2" }
  },
  "runtime_resource_refs": {
    "tool_invocation": { "tool_invocation_id": "..." }
  }
}
```

Also update round-loop tests to expect prepare-round responses to expose
`tool_surface`.

**Step 2: Run tests to verify they fail**

```bash
cd core_matrix
bin/rails test test/services/provider_execution/route_tool_call_test.rb test/services/provider_execution/execute_round_loop_test.rb test/integration/provider_backed_graph_loop_test.rb
```

Expected: FAIL because the kernel still sends flat `tool_call` payloads and
expects `program_tools`.

**Step 3: Write minimal implementation**

- Replace the flat execute-program-tool payload with:
  - `task`
  - `capability_projection`
  - `provider_context`
  - `runtime_context`
  - `program_tool_call`
  - `runtime_resource_refs`
- Change `ExecuteRoundLoop` to consume `tool_surface`.
- Preserve the durable `ToolInvocation` and `ToolBinding` logic; only change
  the public envelope.

**Step 4: Run tests to verify they pass**

```bash
cd core_matrix
bin/rails test test/services/provider_execution/route_tool_call_test.rb test/services/provider_execution/execute_round_loop_test.rb test/integration/provider_backed_graph_loop_test.rb
```

Expected: PASS

**Step 5: Commit**

```bash
git add core_matrix/app/services/provider_execution/route_tool_call.rb core_matrix/app/services/provider_execution/execute_round_loop.rb core_matrix/test/services/provider_execution/route_tool_call_test.rb core_matrix/test/services/provider_execution/execute_round_loop_test.rb core_matrix/test/integration/provider_backed_graph_loop_test.rb
git commit -m "refactor: section execute-program-tool payloads"
```

### Task 5: Rewrite Fenix context readers and round preparation against the new envelope

**Files:**
- Modify: `agents/fenix/app/services/fenix/context/build_execution_context.rb`
- Modify: `agents/fenix/app/services/fenix/runtime/prepare_round.rb`
- Modify: `agents/fenix/app/services/fenix/hooks/prepare_turn.rb`
- Modify: `agents/fenix/app/services/fenix/runtime/build_round_prompt.rb`
- Modify: `agents/fenix/app/services/fenix/hooks/compact_context.rb`
- Modify: `agents/fenix/test/integration/runtime_flow_test.rb`
- Modify: `agents/fenix/test/services/fenix/runtime/prepare_round_test.rb`

**Step 1: Write the failing tests**

Update Fenix tests to assert:

- context comes from `conversation_projection.messages`
- visible tools come from `capability_projection.tool_surface`
- profile data comes from `capability_projection.profile_key`
- prepare-round returns `status: "ok"` and `tool_surface`

**Step 2: Run tests to verify they fail**

```bash
cd agents/fenix
bin/rails test test/integration/runtime_flow_test.rb test/services/fenix/runtime/prepare_round_test.rb
```

Expected: FAIL because `BuildExecutionContext` and `PrepareRound` still read the
old field names.

**Step 3: Write minimal implementation**

- Rewrite `BuildExecutionContext` to normalize the new envelope sections into a
  program-local context object.
- Rewrite `PrepareRound` and `PrepareTurn` to read:
  - `conversation_projection.messages`
  - `conversation_projection.context_imports`
  - `provider_context.budget_hints`
  - `capability_projection.tool_surface`
- Rename the return payload from `program_tools` to `tool_surface`.
- Keep prompt assembly and operator snapshot entirely local to Fenix.

**Step 4: Run tests to verify they pass**

```bash
cd agents/fenix
bin/rails test test/integration/runtime_flow_test.rb test/services/fenix/runtime/prepare_round_test.rb
```

Expected: PASS

**Step 5: Commit**

```bash
git add agents/fenix/app/services/fenix/context/build_execution_context.rb agents/fenix/app/services/fenix/runtime/prepare_round.rb agents/fenix/app/services/fenix/hooks/prepare_turn.rb agents/fenix/app/services/fenix/runtime/build_round_prompt.rb agents/fenix/app/services/fenix/hooks/compact_context.rb agents/fenix/test/integration/runtime_flow_test.rb agents/fenix/test/services/fenix/runtime/prepare_round_test.rb
git commit -m "refactor: teach fenix to consume sectioned runtime envelopes"
```

### Task 6: Rewrite Fenix tool execution and report emission around `runtime_events` and `summary_artifacts`

**Files:**
- Modify: `agents/fenix/app/services/fenix/runtime/execute_program_tool.rb`
- Modify: `agents/fenix/app/services/fenix/runtime/execute_agent_program_request.rb`
- Modify: `agents/fenix/app/services/fenix/runtime/execute_assignment.rb`
- Modify: `agents/fenix/app/services/fenix/runtime_surface/report_collector.rb`
- Modify: `agents/fenix/app/services/fenix/hooks/review_tool_call.rb`
- Modify: `agents/fenix/test/integration/runtime_program_contract_test.rb`
- Modify: `agents/fenix/test/services/fenix/runtime/execute_assignment_test.rb`
- Modify: `agents/fenix/test/jobs/runtime_execution_job_test.rb`

**Step 1: Write the failing tests**

Update Fenix execution tests to expect:

- tool visibility checks to use `tool_surface`
- program-tool responses to emit:
  - `status`
  - `result`
  - `summary_artifacts`
  - `output_chunks`
- execution reports to emit:
  - `runtime_events`
  - `summary_artifacts`
  - `output` or `failure`

**Step 2: Run tests to verify they fail**

```bash
cd agents/fenix
bin/rails test test/integration/runtime_program_contract_test.rb test/services/fenix/runtime/execute_assignment_test.rb test/jobs/runtime_execution_job_test.rb
```

Expected: FAIL because the runtime still emits legacy `progress_payload` and
`terminal_payload` internals.

**Step 3: Write minimal implementation**

- Replace `allowed_tool_names` checks with checks against the visible
  `tool_surface`.
- Make `ExecuteProgramTool` return `summary_artifacts` as a first-class field.
- Make `ExecuteAssignment` emit typed `runtime_events` for tool lifecycle and
  output instead of embedding tool event substructures directly.
- Make `ReportCollector` write the new report payload shape.

**Step 4: Run tests to verify they pass**

```bash
cd agents/fenix
bin/rails test test/integration/runtime_program_contract_test.rb test/services/fenix/runtime/execute_assignment_test.rb test/jobs/runtime_execution_job_test.rb
```

Expected: PASS

**Step 5: Commit**

```bash
git add agents/fenix/app/services/fenix/runtime/execute_program_tool.rb agents/fenix/app/services/fenix/runtime/execute_agent_program_request.rb agents/fenix/app/services/fenix/runtime/execute_assignment.rb agents/fenix/app/services/fenix/runtime_surface/report_collector.rb agents/fenix/app/services/fenix/hooks/review_tool_call.rb agents/fenix/test/integration/runtime_program_contract_test.rb agents/fenix/test/services/fenix/runtime/execute_assignment_test.rb agents/fenix/test/jobs/runtime_execution_job_test.rb
git commit -m "refactor: reset fenix runtime reports and tool execution contract"
```

### Task 7: Rewrite Core Matrix report reducers to consume typed runtime events and summary artifacts

**Files:**
- Modify: `core_matrix/app/services/agent_control/handle_execution_report.rb`
- Modify: `core_matrix/app/services/agent_control/handle_runtime_resource_report.rb`
- Modify: `core_matrix/app/services/agent_control/handle_close_report.rb`
- Modify: `core_matrix/test/services/agent_control/handle_execution_report_test.rb`
- Modify: `core_matrix/test/services/agent_control/report_test.rb`
- Modify: `core_matrix/test/services/agent_control/handle_agent_program_report_test.rb`

**Step 1: Write the failing tests**

Update reducer tests to expect:

- `execution_progress` to consume `runtime_events`
- `execution_complete` and `execution_fail` to consume:
  - `output`
  - `failure`
  - `runtime_events`
  - `summary_artifacts`
- tool invocation completion and failure to be derived from typed events instead
  of bespoke nested payloads

**Step 2: Run tests to verify they fail**

```bash
cd core_matrix
bin/rails test test/services/agent_control/handle_execution_report_test.rb test/services/agent_control/report_test.rb test/services/agent_control/handle_agent_program_report_test.rb
```

Expected: FAIL because the reducers still parse legacy terminal and progress
payload shapes.

**Step 3: Write minimal implementation**

- Replace the old progress and terminal parsing with event dispatch by
  `event_kind`.
- Map `summary_artifacts` into metadata or persisted summary surfaces where
  appropriate, but do not over-design persistence in this task.
- Keep `ToolInvocation`, `CommandRun`, and `ProcessRun` truth kernel-owned.
- Remove dead parsing branches for `tool_invocation_output`,
  `tool_invocations`, and other obsolete payload keys.

**Step 4: Run tests to verify they pass**

```bash
cd core_matrix
bin/rails test test/services/agent_control/handle_execution_report_test.rb test/services/agent_control/report_test.rb test/services/agent_control/handle_agent_program_report_test.rb
```

Expected: PASS

**Step 5: Commit**

```bash
git add core_matrix/app/services/agent_control/handle_execution_report.rb core_matrix/app/services/agent_control/handle_runtime_resource_report.rb core_matrix/app/services/agent_control/handle_close_report.rb core_matrix/test/services/agent_control/handle_execution_report_test.rb core_matrix/test/services/agent_control/report_test.rb core_matrix/test/services/agent_control/handle_agent_program_report_test.rb
git commit -m "refactor: consume typed runtime events in kernel report reducers"
```

### Task 8: Delete dead legacy fields and run end-to-end verification

**Files:**
- Modify: `core_matrix/test/services/provider_execution/prepare_program_round_test.rb`
- Modify: `core_matrix/test/services/provider_execution/route_tool_call_test.rb`
- Modify: `core_matrix/test/services/workflows/build_execution_snapshot_test.rb`
- Modify: `agents/fenix/test/services/fenix/runtime/mailbox_worker_test.rb`
- Modify: `agents/fenix/test/integration/external_runtime_pairing_test.rb`
- Modify: any remaining callers of:
  - `agent_context`
  - `context_messages`
  - `transcript`
  - `program_tools`
  - `allowed_tool_names`
- Delete: any orphaned fixture loaders or helpers that exist only for the old
  contract

**Step 1: Write the failing tests**

Add or update assertions that prove the old keys are gone. Example:

```ruby
refute payload.key?("agent_context")
refute payload.key?("context_messages")
refute response_payload.key?("program_tools")
assert response_payload.key?("tool_surface")
```

**Step 2: Run tests to verify they fail**

```bash
cd core_matrix
bin/rails test test/services/provider_execution/prepare_program_round_test.rb test/services/provider_execution/route_tool_call_test.rb test/services/workflows/build_execution_snapshot_test.rb

cd ../agents/fenix
bin/rails test test/services/fenix/runtime/mailbox_worker_test.rb test/integration/external_runtime_pairing_test.rb
```

Expected: FAIL until all legacy field usage is deleted.

**Step 3: Write minimal implementation**

- Remove the last legacy field references.
- Delete obsolete helper code instead of keeping aliases.
- Update pairing-manifest or contract-surface tests if the public method list or
  contract description changed.

**Step 4: Run focused verification**

```bash
cd core_matrix
bin/rails test test/models/turn_execution_snapshot_test.rb \
  test/services/workflows/build_execution_snapshot_test.rb \
  test/services/agent_control/create_execution_assignment_test.rb \
  test/services/provider_execution/prepare_program_round_test.rb \
  test/services/provider_execution/program_mailbox_exchange_test.rb \
  test/services/provider_execution/route_tool_call_test.rb \
  test/services/provider_execution/execute_round_loop_test.rb \
  test/services/agent_control/handle_execution_report_test.rb \
  test/services/agent_control/report_test.rb \
  test/services/agent_control/handle_agent_program_report_test.rb \
  test/integration/provider_backed_graph_loop_test.rb

cd ../agents/fenix
bin/rails test test/integration/runtime_program_contract_test.rb \
  test/integration/runtime_flow_test.rb \
  test/services/fenix/runtime/prepare_round_test.rb \
  test/services/fenix/runtime/execute_assignment_test.rb \
  test/jobs/runtime_execution_job_test.rb \
  test/services/fenix/runtime/mailbox_worker_test.rb \
  test/integration/external_runtime_pairing_test.rb
```

Expected: PASS

**Step 5: Optional destructive cleanup**

If schema or persisted test state still encodes the old contract and blocks
clarity:

```bash
cd core_matrix
bin/rails db:drop db:create db:schema:load

cd ../agents/fenix
bin/rails db:drop db:create db:schema:load
```

Only do this after preserving any local work you still need.

**Step 6: Commit**

```bash
git add core_matrix agents/fenix shared/fixtures/contracts
git commit -m "refactor: remove legacy agent program contract fields"
```

## Notes For Execution

- Keep the execution order. Fixture reset first, reducers last.
- Do not mix report-shape rewrites with unrelated prompt or memory improvements.
- If a test is asserting the old contract shape, rewrite or delete it. Do not
  add adapters.
- If a helper method exists only to support the old envelope, delete it.

## Final Verification Checklist

- `TurnExecutionSnapshot` no longer exposes `agent_context`
- kernel envelopes use `conversation_projection`, `capability_projection`,
  `provider_context`, and `runtime_context`
- Fenix validates visibility from `tool_surface`
- prepare-round returns `tool_surface`, not `program_tools`
- execution reports use `runtime_events` and `summary_artifacts`
- `_v1` shared contract fixtures are gone
- no compatibility code remains
