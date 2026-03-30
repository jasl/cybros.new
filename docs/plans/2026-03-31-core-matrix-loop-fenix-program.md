# Core Matrix Loop With Fenix Agent Program Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move the provider-backed repeated agent loop into `core_matrix`, keep `agents/fenix` as the agent-program layer that prepares prompts and executes program-owned tools, and preserve the real 2048 browser capstone as the final acceptance gate.

**Architecture:** `Core Matrix` and `Fenix` are intentionally orthogonal and fully complementary. `Core Matrix` owns the outer round loop, provider transport, generic tool calling, Streamable HTTP MCP support, workflow DAG progression, and durable proof. `Fenix` exposes a small HTTP program contract: one endpoint prepares each round's messages and visible program tools, and one endpoint executes only Fenix-owned tools when `Core Matrix` routes them back. Dynamic per-round program tools must be materialized as workflow-node-scoped durable records so tool, command, and process proof no longer depends on `AgentTaskRun`.

**Tech Stack:** Ruby on Rails, Minitest, Active Job, `SimpleInference`, Streamable HTTP MCP, Net::HTTP/HTTPX, JSON contract fixtures, Dockerized `Fenix`, browser-based manual acceptance.

---

## Execution Assumptions

- This implementation may be destructive. Do not preserve compatibility with
  the rejected Fenix-first loop boundary.
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

### Task 1: Freeze The New Cross-App Program Contract

**Files:**
- Create: `shared/fixtures/contracts/core_matrix_fenix_prepare_round_v1.json`
- Create: `shared/fixtures/contracts/fenix_prepare_round_response_v1.json`
- Create: `shared/fixtures/contracts/core_matrix_fenix_execute_program_tool_v1.json`
- Create: `shared/fixtures/contracts/fenix_execute_program_tool_response_v1.json`
- Modify: `agents/fenix/app/services/fenix/runtime/pairing_manifest.rb`
- Test: `agents/fenix/test/integration/external_runtime_pairing_test.rb`
- Test: `core_matrix/test/integration/external_fenix_pairing_flow_test.rb`

**Step 1: Write the failing contract assertions**

Add fixture-backed expectations that the Fenix manifest advertises the new program endpoints and versioned contract metadata.

```ruby
manifest = Fenix::Runtime::PairingManifest.call(base_url: "https://fenix.example.test")

assert_equal "2026-03-31", manifest.fetch("protocol_version")
assert_equal "/runtime/rounds/prepare", manifest.dig("endpoint_metadata", "prepare_round_path")
assert_equal "/runtime/program_tools/execute", manifest.dig("endpoint_metadata", "execute_program_tool_path")
assert_equal ["prepare_round", "execute_program_tool"], manifest.fetch("program_contract").fetch("methods")
```

**Step 2: Run the focused tests and confirm they fail**

Run: `cd agents/fenix && bin/rails test test/integration/external_runtime_pairing_test.rb`

Expected: FAIL because the manifest does not yet expose `prepare_round_path`, `execute_program_tool_path`, or the bumped protocol version.

Run: `cd core_matrix && bin/rails test test/integration/external_fenix_pairing_flow_test.rb`

Expected: FAIL once the Core Matrix side starts asserting the richer manifest payload.

**Step 3: Add the shared fixtures and manifest fields**

Update the manifest to advertise the new program contract explicitly and keep the payload small and machine-readable.

```ruby
def endpoint_metadata
  {
    "transport" => "http",
    "base_url" => @base_url,
    "runtime_manifest_path" => "/runtime/manifest",
    "prepare_round_path" => "/runtime/rounds/prepare",
    "execute_program_tool_path" => "/runtime/program_tools/execute",
  }
end

def program_contract
  {
    "version" => "v1",
    "methods" => %w[prepare_round execute_program_tool],
  }
end
```

**Step 4: Re-run the contract tests**

Run: `cd agents/fenix && bin/rails test test/integration/external_runtime_pairing_test.rb`

Expected: PASS.

Run: `cd core_matrix && bin/rails test test/integration/external_fenix_pairing_flow_test.rb`

Expected: PASS with the new manifest metadata preserved through registration.

**Step 5: Commit**

```bash
git add shared/fixtures/contracts/core_matrix_fenix_prepare_round_v1.json shared/fixtures/contracts/fenix_prepare_round_response_v1.json shared/fixtures/contracts/core_matrix_fenix_execute_program_tool_v1.json shared/fixtures/contracts/fenix_execute_program_tool_response_v1.json agents/fenix/app/services/fenix/runtime/pairing_manifest.rb agents/fenix/test/integration/external_runtime_pairing_test.rb core_matrix/test/integration/external_fenix_pairing_flow_test.rb
git commit -m "docs: freeze core matrix fenix program contract"
```

### Task 2: Implement `Fenix.prepare_round`

**Files:**
- Create: `agents/fenix/app/controllers/runtime/rounds_controller.rb`
- Create: `agents/fenix/app/services/fenix/runtime/prepare_round.rb`
- Modify: `agents/fenix/config/routes.rb`
- Modify: `agents/fenix/app/services/fenix/runtime/pairing_manifest.rb`
- Test: `agents/fenix/test/integration/runtime_program_contract_test.rb`
- Test: `agents/fenix/test/services/fenix/runtime/prepare_round_test.rb`
- Test: `agents/fenix/test/integration/runtime_flow_test.rb`

**Step 1: Write the failing tests for the round-preparation API**

Assert that `POST /runtime/rounds/prepare` accepts the Core Matrix payload and returns prepared messages plus a round-local program tool catalog.

```ruby
post "/runtime/rounds/prepare", params: {
  conversation_id: "conversation-1",
  turn_id: "turn-1",
  workflow_run_id: "workflow-run-1",
  workflow_node_id: "workflow-node-1",
  transcript: [{ role: "user", content: "build 2048" }],
  context_imports: [],
  prior_tool_results: [],
  budget_hints: { advisory_hints: { recommended_compaction_threshold: 900_000 } },
  model_context: { model_ref: "gpt-5.4", api_model: "gpt-5.4" },
  agent_context: { profile: "main", is_subagent: false }
}

assert_response :success
assert response.parsed_body.fetch("messages").any?
assert response.parsed_body.fetch("program_tools").all? { |entry| entry.key?("tool_name") }
```

**Step 2: Run the Fenix tests and confirm the API is missing**

Run: `cd agents/fenix && bin/rails test test/integration/runtime_program_contract_test.rb test/services/fenix/runtime/prepare_round_test.rb`

Expected: FAIL because the route and service do not exist.

**Step 3: Implement the service with the existing Fenix hooks**

Keep the service thin: build round context, call the existing prompt/compaction hooks, let Fenix choose skills internally, and return only the final messages plus visible program tools.

```ruby
module Fenix
  module Runtime
    class PrepareRound
      def call
        prepared = Fenix::Hooks::PrepareTurn.call(context: round_context)
        compacted = Fenix::Hooks::CompactContext.call(
          messages: prepared.fetch("messages"),
          budget_hints: round_context.fetch("budget_hints"),
          likely_model: prepared.fetch("likely_model")
        )

        {
          "messages" => compacted.fetch("messages"),
          "program_tools" => visible_program_tools,
          "trace" => [prepared.fetch("trace"), compacted.fetch("trace")],
        }
      end
    end
  end
end
```

**Step 4: Run the Fenix round-preparation tests**

Run: `cd agents/fenix && bin/rails test test/integration/runtime_program_contract_test.rb test/services/fenix/runtime/prepare_round_test.rb test/integration/runtime_flow_test.rb`

Expected: PASS, and the existing runtime flow tests should still pass.

**Step 5: Commit**

```bash
git add agents/fenix/app/controllers/runtime/rounds_controller.rb agents/fenix/app/services/fenix/runtime/prepare_round.rb agents/fenix/config/routes.rb agents/fenix/app/services/fenix/runtime/pairing_manifest.rb agents/fenix/test/integration/runtime_program_contract_test.rb agents/fenix/test/services/fenix/runtime/prepare_round_test.rb agents/fenix/test/integration/runtime_flow_test.rb
git commit -m "feat: add fenix prepare round contract"
```

### Task 3: Implement `Fenix.execute_program_tool` By Extracting Shared Program Tool Logic

**Files:**
- Create: `agents/fenix/app/controllers/runtime/program_tools_controller.rb`
- Create: `agents/fenix/app/services/fenix/runtime/execute_program_tool.rb`
- Create: `agents/fenix/app/services/fenix/runtime/program_tool_executor.rb`
- Modify: `agents/fenix/app/services/fenix/runtime/execute_assignment.rb`
- Modify: `agents/fenix/config/routes.rb`
- Test: `agents/fenix/test/services/fenix/runtime/execute_assignment_test.rb`
- Test: `agents/fenix/test/integration/runtime_program_contract_test.rb`
- Test: `agents/fenix/test/services/fenix/runtime/program_tool_executor_test.rb`

**Step 1: Write the failing tests for HTTP program tool execution**

Cover a calculator-style tool, an `exec_command` tool that provisions command-run metadata, and a rejected tool name.

```ruby
post "/runtime/program_tools/execute", params: {
  tool_call_id: "call-1",
  tool_name: "calculator",
  arguments: { expression: "2 + 2" },
  workflow_node_id: "workflow-node-1",
  agent_context: { allowed_tool_names: ["calculator"] }
}

assert_response :success
assert_equal 4, response.parsed_body.dig("result", "value")
assert_equal "completed", response.parsed_body.fetch("status")
```

**Step 2: Run the Fenix tests and confirm the new endpoint is absent**

Run: `cd agents/fenix && bin/rails test test/integration/runtime_program_contract_test.rb test/services/fenix/runtime/execute_assignment_test.rb`

Expected: FAIL because `execute_program_tool` and the reusable executor are not present.

**Step 3: Extract the tool-execution core and reuse it**

Move the deterministic tool path out of `ExecuteAssignment` into a reusable service so both the legacy mailbox path and the new HTTP path share the same implementation.

```ruby
module Fenix
  module Runtime
    class ProgramToolExecutor
      def call(tool_call:, context:)
        reviewed_tool_call = Fenix::Hooks::ReviewToolCall.call(
          tool_call: tool_call,
          allowed_tool_names: context.dig("agent_context", "allowed_tool_names")
        )

        execute_tool(reviewed_tool_call, context:)
      end
    end
  end
end
```

Update `ExecuteAssignment` to delegate to `ProgramToolExecutor` instead of owning the deterministic flow inline.

**Step 4: Re-run the Fenix execution tests**

Run: `cd agents/fenix && bin/rails test test/services/fenix/runtime/program_tool_executor_test.rb test/services/fenix/runtime/execute_assignment_test.rb test/integration/runtime_program_contract_test.rb`

Expected: PASS, including existing `exec_command` and `write_stdin` behaviors.

**Step 5: Commit**

```bash
git add agents/fenix/app/controllers/runtime/program_tools_controller.rb agents/fenix/app/services/fenix/runtime/execute_program_tool.rb agents/fenix/app/services/fenix/runtime/program_tool_executor.rb agents/fenix/app/services/fenix/runtime/execute_assignment.rb agents/fenix/config/routes.rb agents/fenix/test/services/fenix/runtime/program_tool_executor_test.rb agents/fenix/test/services/fenix/runtime/execute_assignment_test.rb agents/fenix/test/integration/runtime_program_contract_test.rb
git commit -m "feat: add fenix program tool execution api"
```

### Task 4: Move Durable Tool Proof From `AgentTaskRun` To `WorkflowNode`

**Files:**
- Create: `core_matrix/db/migrate/20260331120000_add_workflow_node_projection_to_tool_runtime_records.rb`
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
- Test: `core_matrix/test/services/tool_bindings/freeze_for_task_test.rb`
- Test: `core_matrix/test/services/tool_invocations/lifecycle_test.rb`
- Test: `core_matrix/test/services/command_runs/terminalize_test.rb`

**Step 1: Write the failing persistence tests**

Add tests that provision a tool binding directly for a `turn_step` workflow node without an `AgentTaskRun`, then create a tool invocation and command run from that binding.

```ruby
binding = ToolBindings::FreezeForWorkflowNode.call(workflow_node: workflow_node, tool_catalog: round_tool_catalog).first

invocation = ToolInvocations::Start.call(
  tool_binding: binding,
  request_payload: { "arguments" => { "expression" => "2 + 2" } }
)

assert_equal workflow_node, binding.workflow_node
assert_nil binding.agent_task_run
assert_equal workflow_node, invocation.workflow_node
```

**Step 2: Run the focused Core Matrix tests and confirm the schema is missing**

Run: `cd core_matrix && bin/rails test test/models/tool_binding_test.rb test/models/tool_invocation_test.rb test/services/tool_invocations/lifecycle_test.rb`

Expected: FAIL because `workflow_node_id` does not exist on the durable tool records.

**Step 3: Add the migration and the new workflow-node projection**

Make `agent_task_run_id` optional for tool bindings, tool invocations, and command runs, add `workflow_node_id`, and keep compatibility for existing mailbox-driven paths.

```ruby
change_table :tool_bindings do |t|
  t.references :workflow_node, foreign_key: true
end

change_table :tool_invocations do |t|
  t.references :workflow_node, foreign_key: true
  change_column_null :agent_task_run_id, true
end

change_table :command_runs do |t|
  t.references :workflow_node, foreign_key: true
  change_column_null :agent_task_run_id, true
end
```

Generalize the services so they can derive installation, turn, and conversation from `workflow_node` when no `agent_task_run` is present.

**Step 4: Run migrations and the focused Core Matrix tests**

Run: `cd core_matrix && bin/rails db:migrate`

Expected: PASS.

Run: `cd core_matrix && bin/rails db:test:prepare test test/models/tool_binding_test.rb test/models/tool_invocation_test.rb test/services/tool_invocations/lifecycle_test.rb test/services/command_runs/terminalize_test.rb`

Expected: PASS.

**Step 5: Commit**

```bash
git add core_matrix/db/migrate/20260331120000_add_workflow_node_projection_to_tool_runtime_records.rb core_matrix/app/models/tool_binding.rb core_matrix/app/models/tool_invocation.rb core_matrix/app/models/command_run.rb core_matrix/app/models/agent_task_run.rb core_matrix/app/services/tool_bindings/freeze_for_workflow_node.rb core_matrix/app/services/tool_invocations/start.rb core_matrix/app/services/tool_invocations/provision.rb core_matrix/app/services/command_runs/provision.rb core_matrix/test/models/tool_binding_test.rb core_matrix/test/models/tool_invocation_test.rb core_matrix/test/services/tool_bindings/freeze_for_task_test.rb core_matrix/test/services/tool_invocations/lifecycle_test.rb core_matrix/test/services/command_runs/terminalize_test.rb
git commit -m "refactor: project tool proof onto workflow nodes"
```

### Task 5: Add The Core Matrix Fenix Program Client And Round-Scoped Tool Materialization

**Files:**
- Create: `core_matrix/app/services/provider_execution/fenix_program_client.rb`
- Create: `core_matrix/app/services/provider_execution/prepare_program_round.rb`
- Create: `core_matrix/app/services/provider_execution/materialize_round_tools.rb`
- Modify: `core_matrix/app/services/runtime_capabilities/compose_for_conversation.rb`
- Modify: `core_matrix/app/services/tool_bindings/freeze_for_workflow_node.rb`
- Test: `core_matrix/test/services/provider_execution/fenix_program_client_test.rb`
- Test: `core_matrix/test/services/provider_execution/prepare_program_round_test.rb`
- Test: `core_matrix/test/services/tool_bindings/freeze_for_workflow_node_test.rb`

**Step 1: Write the failing client and materialization tests**

Cover one successful `prepare_round` call, one HTTP failure, and one round-local tool catalog with a dynamic Fenix tool that is not present in the static capability snapshot.

```ruby
response = ProviderExecution::PrepareProgramRound.call(
  workflow_node: workflow_node,
  transcript: transcript,
  prior_tool_results: []
)

assert_equal "assistant", response.fetch("messages").last.fetch("role")
assert_equal "workspace_write_file", response.fetch("program_tools").first.fetch("tool_name")
```

**Step 2: Run the Core Matrix tests and confirm the new services do not exist**

Run: `cd core_matrix && bin/rails test test/services/provider_execution/fenix_program_client_test.rb test/services/provider_execution/prepare_program_round_test.rb test/services/tool_bindings/freeze_for_workflow_node_test.rb`

Expected: FAIL because the client and round-tool materialization services are not implemented.

**Step 3: Implement the HTTP client and round-tool freezing**

The Core Matrix client should read the Fenix endpoint metadata from the active deployment and POST JSON payloads directly.

```ruby
client.post_json(
  path: deployment.endpoint_metadata.fetch("prepare_round_path"),
  body: {
    conversation_id: workflow_run.conversation.public_id,
    turn_id: workflow_run.turn.public_id,
    workflow_run_id: workflow_run.public_id,
    workflow_node_id: workflow_node.public_id,
    transcript: transcript,
    context_imports: workflow_run.execution_snapshot.context_imports,
    prior_tool_results: prior_tool_results,
    budget_hints: workflow_run.execution_snapshot.budget_hints,
    model_context: workflow_run.execution_snapshot.model_context,
    agent_context: workflow_run.execution_snapshot.agent_context,
  }
)
```

`MaterializeRoundTools` should create or reuse workflow-node-scoped tool bindings for the exact tool set Fenix exposes for this round, even when the tool name is absent from the static capability snapshot.

**Step 4: Re-run the client and materialization tests**

Run: `cd core_matrix && bin/rails test test/services/provider_execution/fenix_program_client_test.rb test/services/provider_execution/prepare_program_round_test.rb test/services/tool_bindings/freeze_for_workflow_node_test.rb`

Expected: PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/provider_execution/fenix_program_client.rb core_matrix/app/services/provider_execution/prepare_program_round.rb core_matrix/app/services/provider_execution/materialize_round_tools.rb core_matrix/app/services/runtime_capabilities/compose_for_conversation.rb core_matrix/app/services/tool_bindings/freeze_for_workflow_node.rb core_matrix/test/services/provider_execution/fenix_program_client_test.rb core_matrix/test/services/provider_execution/prepare_program_round_test.rb core_matrix/test/services/tool_bindings/freeze_for_workflow_node_test.rb
git commit -m "feat: fetch and materialize fenix round tools"
```

### Task 6: Teach Provider Dispatch To Send Tools And Parse Tool Calls

**Files:**
- Modify: `core_matrix/app/services/provider_execution/dispatch_request.rb`
- Create: `core_matrix/app/services/provider_execution/normalize_provider_response.rb`
- Modify: `core_matrix/app/services/provider_execution/execute_turn_step.rb`
- Modify: `core_matrix/test/services/provider_execution/dispatch_request_test.rb`
- Test: `core_matrix/test/services/provider_execution/normalize_provider_response_test.rb`
- Test: `core_matrix/test/integration/provider_backed_turn_execution_test.rb`
- Modify: `core_matrix/vendor/simple_inference/lib/simple_inference/protocols/openai_compatible.rb`
- Modify: `core_matrix/vendor/simple_inference/lib/simple_inference/protocols/openai_responses.rb`
- Test: `core_matrix/vendor/simple_inference/test/test_protocol_contract.rb`
- Test: `core_matrix/vendor/simple_inference/test/test_openai_responses_protocol.rb`

**Step 1: Write the failing provider tests**

Add one chat-completions test that asserts `tools` and `tool_choice` are serialized, and one response-normalization test that converts a provider result with tool calls into a uniform structure.

```ruby
result = ProviderExecution::DispatchRequest.call(
  workflow_run: workflow_run,
  request_context: request_context,
  messages: turn_step_messages_for(workflow_run),
  tools: [{ "type" => "function", "function" => { "name" => "calculator", "parameters" => { "type" => "object" } } }],
  tool_choice: "auto",
  adapter: adapter
)

request_body = JSON.parse(adapter.last_request.fetch(:body))
assert_equal "auto", request_body.fetch("tool_choice")
assert_equal "calculator", request_body.fetch("tools").first.fetch("function").fetch("name")
```

**Step 2: Run the provider tests and confirm tools are not passed through**

Run: `cd core_matrix && bin/rails test test/services/provider_execution/dispatch_request_test.rb test/services/provider_execution/normalize_provider_response_test.rb`

Expected: FAIL because `DispatchRequest` ignores tool definitions and there is no normalized tool-call shape yet.

Run: `cd core_matrix/vendor/simple_inference && bundle exec rake`

Expected: FAIL once the new protocol expectations are added.

**Step 3: Wire tool definitions through `SimpleInference` and normalize the result**

Teach `DispatchRequest` to accept `tools:` and `tool_choice:`, pass them through to the client, and return a normalized structure that always includes either terminal text or tool calls.

```ruby
provider_result = build_client.chat(
  model: @request_context.api_model,
  messages: @messages,
  tools: @tools,
  tool_choice: @tool_choice,
  max_tokens: @request_context.hard_limits["max_output_tokens"],
  **@request_context.execution_settings.symbolize_keys
)

normalized = ProviderExecution::NormalizeProviderResponse.call(provider_result:)
```

**Step 4: Re-run the provider and vendored gem tests**

Run: `cd core_matrix && bin/rails test test/services/provider_execution/dispatch_request_test.rb test/services/provider_execution/normalize_provider_response_test.rb test/integration/provider_backed_turn_execution_test.rb`

Expected: PASS.

Run: `cd core_matrix/vendor/simple_inference && bundle exec rake`

Expected: PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/provider_execution/dispatch_request.rb core_matrix/app/services/provider_execution/normalize_provider_response.rb core_matrix/app/services/provider_execution/execute_turn_step.rb core_matrix/test/services/provider_execution/dispatch_request_test.rb core_matrix/test/services/provider_execution/normalize_provider_response_test.rb core_matrix/test/integration/provider_backed_turn_execution_test.rb core_matrix/vendor/simple_inference/lib/simple_inference/protocols/openai_compatible.rb core_matrix/vendor/simple_inference/lib/simple_inference/protocols/openai_responses.rb core_matrix/vendor/simple_inference/test/test_protocol_contract.rb core_matrix/vendor/simple_inference/test/test_openai_responses_protocol.rb
git commit -m "feat: add provider tool calling support"
```

### Task 7: Build The Core Matrix Repeated Round Loop And Tool Router

**Files:**
- Create: `core_matrix/app/services/provider_execution/execute_round_loop.rb`
- Create: `core_matrix/app/services/provider_execution/route_tool_call.rb`
- Create: `core_matrix/app/services/provider_execution/append_tool_result.rb`
- Modify: `core_matrix/app/services/provider_execution/execute_turn_step.rb`
- Modify: `core_matrix/app/services/workflows/execute_node.rb`
- Modify: `core_matrix/app/services/mcp/invoke_tool.rb`
- Test: `core_matrix/test/services/provider_execution/execute_round_loop_test.rb`
- Test: `core_matrix/test/services/provider_execution/route_tool_call_test.rb`
- Test: `core_matrix/test/integration/provider_backed_turn_execution_test.rb`
- Test: `core_matrix/test/integration/streamable_http_mcp_flow_test.rb`

**Step 1: Write the failing loop tests**

Cover these cases:
- terminal provider text on the first round
- provider tool call to a Core Matrix reserved tool
- provider tool call to an MCP tool
- provider tool call to a Fenix program tool that then feeds another provider round

```ruby
result = ProviderExecution::ExecuteRoundLoop.call(workflow_node: workflow_node, adapter: adapter)

assert_equal "completed", result.workflow_node.lifecycle_state
assert_equal ["prepare_round", "provider_request", "program_tool", "provider_request"], result.trace.map { |entry| entry.fetch("phase") }
assert_equal "Final answer", result.output_message.content
```

**Step 2: Run the loop tests and confirm only single-shot execution exists**

Run: `cd core_matrix && bin/rails test test/services/provider_execution/execute_round_loop_test.rb test/services/provider_execution/route_tool_call_test.rb`

Expected: FAIL because `ExecuteTurnStep` still assumes one provider request and immediate terminal persistence.

**Step 3: Implement the loop and router**

`ExecuteRoundLoop` should repeatedly call Fenix for round preparation, invoke the provider, route tool calls, append tool results, and stop only on terminal text or wait/interrupt conditions.

```ruby
loop do
  prepared = ProviderExecution::PrepareProgramRound.call(workflow_node: @workflow_node, transcript: transcript, prior_tool_results: tool_results)
  bindings = ProviderExecution::MaterializeRoundTools.call(workflow_node: @workflow_node, round_tools: prepared.fetch("program_tools"))
  provider_result = ProviderExecution::DispatchRequest.call(..., tools: provider_tools_for(bindings))
  normalized = ProviderExecution::NormalizeProviderResponse.call(provider_result: provider_result.provider_result)

  break persist_terminal!(normalized) if normalized.fetch("tool_calls").empty?

  tool_results = normalized.fetch("tool_calls").map do |tool_call|
    ProviderExecution::RouteToolCall.call(workflow_node: @workflow_node, tool_call: tool_call, round_bindings: bindings)
  end
end
```

**Step 4: Re-run the Core Matrix loop tests**

Run: `cd core_matrix && bin/rails test test/services/provider_execution/execute_round_loop_test.rb test/services/provider_execution/route_tool_call_test.rb test/integration/provider_backed_turn_execution_test.rb test/integration/streamable_http_mcp_flow_test.rb`

Expected: PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/provider_execution/execute_round_loop.rb core_matrix/app/services/provider_execution/route_tool_call.rb core_matrix/app/services/provider_execution/append_tool_result.rb core_matrix/app/services/provider_execution/execute_turn_step.rb core_matrix/app/services/workflows/execute_node.rb core_matrix/app/services/mcp/invoke_tool.rb core_matrix/test/services/provider_execution/execute_round_loop_test.rb core_matrix/test/services/provider_execution/route_tool_call_test.rb core_matrix/test/integration/provider_backed_turn_execution_test.rb core_matrix/test/integration/streamable_http_mcp_flow_test.rb
git commit -m "feat: run repeated agent rounds in core matrix"
```

### Task 8: Rewire Subagent And Resume Paths To Re-Enter The Same Core Matrix Loop

**Files:**
- Modify: `core_matrix/app/services/subagent_sessions/spawn.rb`
- Modify: `core_matrix/app/services/workflows/re_enter_agent.rb`
- Modify: `core_matrix/app/services/workflows/create_for_turn.rb`
- Modify: `core_matrix/test/services/subagent_sessions/spawn_test.rb`
- Create: `core_matrix/test/services/workflows/re_enter_agent_test.rb`
- Modify: `core_matrix/test/services/workflows/create_for_turn_test.rb`
- Modify: `core_matrix/test/services/workflows/step_retry_test.rb`

**Step 1: Write the failing workflow tests**

Assert that subagent child turns and post-wait re-entry schedule a normal runnable `turn_step` node instead of creating an `AgentTaskRun` mailbox assignment.

```ruby
result = SubagentSessions::Spawn.call(...)

workflow_run = WorkflowRun.find_by_public_id!(result.fetch("workflow_run_id"))
assert_equal "turn_step", workflow_run.workflow_nodes.first.node_type
assert_empty AgentTaskRun.where(workflow_run: workflow_run)
```

**Step 2: Run the workflow tests and confirm they still create mailbox work**

Run: `cd core_matrix && bin/rails test test/services/subagent_sessions/spawn_test.rb test/services/workflows/create_for_turn_test.rb test/services/workflows/step_retry_test.rb test/services/workflows/re_enter_agent_test.rb`

Expected: FAIL because subagent and re-entry paths still materialize `AgentTaskRun` work.

**Step 3: Switch those paths to the shared loop**

Make subagent child workflows and re-entry successor nodes use `turn_step` execution through the normal workflow scheduler.

```ruby
workflow_run = Workflows::CreateForTurn.call(
  turn: child_turn,
  root_node_key: "subagent_step_1",
  root_node_type: "turn_step",
  decision_source: "system",
  metadata: { "subagent_session_id" => session.public_id }
)

Workflows::DispatchRunnableNodes.call(workflow_run: workflow_run)
```

Keep `AgentTaskRun` only for truly mailbox-owned runtime work that still remains after this migration.

**Step 4: Re-run the workflow tests**

Run: `cd core_matrix && bin/rails test test/services/subagent_sessions/spawn_test.rb test/services/workflows/create_for_turn_test.rb test/services/workflows/step_retry_test.rb test/services/workflows/re_enter_agent_test.rb`

Expected: PASS.

**Step 5: Commit**

```bash
git add core_matrix/app/services/subagent_sessions/spawn.rb core_matrix/app/services/workflows/re_enter_agent.rb core_matrix/app/services/workflows/create_for_turn.rb core_matrix/test/services/subagent_sessions/spawn_test.rb core_matrix/test/services/workflows/re_enter_agent_test.rb core_matrix/test/services/workflows/create_for_turn_test.rb core_matrix/test/services/workflows/step_retry_test.rb
git commit -m "refactor: route subagent turns through core matrix loop"
```

### Task 9: Update The Capstone Checklist And Run The Real 2048 Acceptance

**Files:**
- Modify: `docs/checklists/2026-03-31-fenix-provider-backed-agent-capstone-acceptance.md`
- Create: `docs/checklists/artifacts/2026-03-31-core-matrix-loop-fenix-2048/turns.md`
- Create: `docs/checklists/artifacts/2026-03-31-core-matrix-loop-fenix-2048/conversation-transcript.md`
- Create: `docs/checklists/artifacts/2026-03-31-core-matrix-loop-fenix-2048/collaboration-notes.md`
- Create: `docs/checklists/artifacts/2026-03-31-core-matrix-loop-fenix-2048/runtime-and-deployment.md`
- Create: `docs/checklists/artifacts/2026-03-31-core-matrix-loop-fenix-2048/workspace-artifacts.md`
- Create: `docs/checklists/artifacts/2026-03-31-core-matrix-loop-fenix-2048/playability-verification.md`

**Step 1: Update the checklist language before the live run**

Rewrite only the architectural assertions that are now stale:
- `Core Matrix` owns the provider-backed loop
- `Fenix` must be reachable through the new program HTTP contract
- the acceptance workload remains the browser-based React `2048` game built through the real conversation path

```markdown
- `Core Matrix` must execute the repeated provider-backed loop
- `Fenix` must provide prompt preparation and program-owned tool execution through the published runtime endpoints
- the final application must still be a playable browser-based React `2048` game
```

**Step 2: Run the full automated verification before the capstone**

Run: `cd agents/fenix && bin/brakeman --no-pager && bin/bundler-audit && bin/rubocop -f github && bin/rails db:test:prepare test`

Expected: PASS.

Run: `cd core_matrix && bin/brakeman --no-pager && bin/bundler-audit && bin/rubocop -f github && bun run lint:js && bin/rails db:test:prepare test && bin/rails db:test:prepare test:system`

Expected: PASS.

Run: `cd core_matrix/vendor/simple_inference && bundle exec rake`

Expected: PASS.

**Step 3: Perform the real manual capstone**

Use the real stack, not a special debug path:
- start `Core Matrix`
- start Dockerized `Fenix`
- mount `/Users/jasl/Workspaces/Ruby/cybros/tmp/fenix`
- send a real conversation asking for a React `2048` game
- let the system complete the work through the new Core Matrix loop and Fenix tool callbacks
- play the finished game manually in a browser

Record every turn by `public_id` only and collect the proof package in the artifact directory above.

**Step 4: Verify the proof package and checklist**

Run: `git diff --check`

Expected: PASS.

Manually confirm:
- the generated app is playable
- the browser run proves movement, merges, score, game-over, and restart
- the proof package explains the observed DAG and tool activity

**Step 5: Commit**

```bash
git add docs/checklists/2026-03-31-fenix-provider-backed-agent-capstone-acceptance.md docs/checklists/artifacts/2026-03-31-core-matrix-loop-fenix-2048
git commit -m "docs: record core matrix fenix 2048 capstone acceptance"
```
