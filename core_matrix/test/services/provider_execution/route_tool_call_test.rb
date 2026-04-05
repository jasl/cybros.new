require "test_helper"

class ProviderExecution::RouteToolCallTest < ActiveSupport::TestCase
  setup do
    @mcp_server = FakeStreamableHttpMcpServer.new.start
  end

  teardown do
    @mcp_server.shutdown
  end

  test "routes agent-owned round tools back through the program mailbox exchange with workflow-node durable proof" do
    context = build_governed_tool_context!(
      agent_tool_catalog: governed_agent_tool_catalog + [calculator_tool_entry],
      profile_catalog: governed_profile_catalog.deep_merge(
        "main" => {
          "allowed_tool_names" => %w[exec_command compact_context subagent_spawn calculator],
        }
      )
    )
    workflow_node = context.fetch(:workflow_node)
    round_bindings = ProviderExecution::MaterializeRoundTools.call(
      workflow_node: workflow_node,
      tool_catalog: [calculator_tool_entry]
    ).includes(:tool_definition, tool_implementation: :implementation_source).to_a
    program_exchange = ProviderExecutionTestSupport::FakeProgramExchange.new(
      program_tool_results: {
        "call-calculator-1" => {
          "status" => "ok",
          "result" => { "value" => 4 },
          "output_chunks" => [],
          "summary_artifacts" => [{ "kind" => "tool_batch", "label" => "Calculator", "text" => "4", "metadata" => {} }],
        },
      }
    )

    result = ProviderExecution::RouteToolCall.call(
      workflow_node: workflow_node,
      tool_call: {
        "call_id" => "call-calculator-1",
        "tool_name" => "calculator",
        "arguments" => { "expression" => "2 + 2" },
        "provider_format" => "chat_completions",
      },
      round_bindings: round_bindings,
      program_exchange: program_exchange
    )

    invocation = result.tool_invocation.reload

    assert_equal({ "value" => 4 }, result.result)
    assert_equal "succeeded", invocation.status
    assert_equal workflow_node, invocation.workflow_node
    assert_nil invocation.agent_task_run
    assert_equal "chat_completions", invocation.provider_format
    assert_equal({ "expression" => "2 + 2" }, invocation.request_payload.fetch("arguments"))
    assert_equal({ "value" => 4 }, invocation.response_payload)
    assert_equal(
      {
        "summary_artifacts" => [{ "kind" => "tool_batch", "label" => "Calculator", "text" => "4", "metadata" => {} }],
        "output_chunks" => [],
      },
      invocation.trace_payload
    )
    assert_equal "call-calculator-1", program_exchange.execute_program_tool_requests.first.fetch("program_tool_call").fetch("call_id")
    assert_equal workflow_node.public_id, program_exchange.execute_program_tool_requests.first.fetch("task").fetch("workflow_node_id")
    assert_equal(
      { "agent_program_version_id" => context.fetch(:deployment).public_id },
      program_exchange.execute_program_tool_requests.first.fetch("runtime_context").slice("agent_program_version_id")
    )
  end

  test "routes execution-environment round tools back through the program mailbox exchange" do
    environment_tool = {
      "tool_name" => "memory_search",
      "tool_kind" => "execution_runtime",
      "implementation_source" => "execution_runtime",
      "implementation_ref" => "env/memory_search",
      "input_schema" => {
        "type" => "object",
        "properties" => {
          "query" => { "type" => "string" },
          "limit" => { "type" => "integer" },
        },
      },
      "result_schema" => {
        "type" => "object",
        "properties" => {
          "entries" => { "type" => "array" },
        },
      },
      "streaming_support" => false,
      "idempotency_policy" => "best_effort",
    }
    context = build_governed_tool_context!(
      execution_tool_catalog: [environment_tool],
      profile_catalog: {
        "main" => {
          "label" => "Main",
          "description" => "Primary interactive profile",
          "allowed_tool_names" => %w[memory_search compact_context subagent_spawn],
        },
      }
    )
    workflow_node = context.fetch(:workflow_node)
    round_bindings = ProviderExecution::MaterializeRoundTools.call(
      workflow_node: workflow_node,
      tool_catalog: [environment_tool]
    ).includes(:tool_definition, tool_implementation: :implementation_source).to_a
    program_exchange = ProviderExecutionTestSupport::FakeProgramExchange.new(
      program_tool_results: {
        "call-memory-search-1" => {
          "status" => "ok",
          "result" => {
            "entries" => [
              { "id" => "memory-1", "content" => "Using superpowers enables skill routing." },
            ],
          },
          "output_chunks" => [],
          "summary_artifacts" => [],
        },
      }
    )

    result = ProviderExecution::RouteToolCall.call(
      workflow_node: workflow_node,
      tool_call: {
        "call_id" => "call-memory-search-1",
        "tool_name" => "memory_search",
        "arguments" => { "query" => "using-superpowers skill", "limit" => 5 },
        "provider_format" => "chat_completions",
      },
      round_bindings: round_bindings,
      program_exchange: program_exchange
    )

    invocation = result.tool_invocation.reload

    assert_equal(
      { "entries" => [{ "id" => "memory-1", "content" => "Using superpowers enables skill routing." }] },
      result.result
    )
    assert_equal "succeeded", invocation.status
    assert_equal workflow_node, invocation.workflow_node
    assert_equal "memory_search", invocation.tool_definition.tool_name
    assert_equal "call-memory-search-1", program_exchange.execute_program_tool_requests.first.fetch("program_tool_call").fetch("call_id")
    assert_equal "memory_search", program_exchange.execute_program_tool_requests.first.fetch("program_tool_call").fetch("tool_name")
  end

  test "provisions durable command runs for exec_command program tools" do
    context = build_governed_tool_context!
    workflow_node = context.fetch(:workflow_node)
    round_bindings = ToolBindings::FreezeForWorkflowNode.call(
      workflow_node: workflow_node
    ).includes(:tool_definition, tool_implementation: :implementation_source).to_a
    program_exchange = ProviderExecutionTestSupport::FakeProgramExchange.new(
      program_tool_results: {
        "call-exec-command-1" => lambda { |payload:|
          {
            "status" => "ok",
            "result" => {
              "command_run_id" => payload.dig("runtime_resource_refs", "command_run", "command_run_id"),
              "session_closed" => false,
              "attached" => true,
            },
            "output_chunks" => [],
            "summary_artifacts" => [],
          }
        },
      }
    )

    result = ProviderExecution::RouteToolCall.call(
      workflow_node: workflow_node,
      tool_call: {
        "call_id" => "call-exec-command-1",
        "tool_name" => "exec_command",
        "arguments" => {
          "command_line" => "printf 'hello\\n'",
          "timeout_seconds" => 30,
          "pty" => true,
        },
        "provider_format" => "chat_completions",
      },
      round_bindings: round_bindings,
      program_exchange: program_exchange
    )

    invocation = result.tool_invocation.reload
    request_payload = program_exchange.execute_program_tool_requests.first
    command_run_id = request_payload.dig("runtime_resource_refs", "command_run", "command_run_id")
    command_run = CommandRun.find_by_public_id!(command_run_id)

    assert_equal command_run_id, result.result.fetch("command_run_id")
    assert_equal invocation, command_run.tool_invocation
    assert_equal workflow_node, command_run.workflow_node
    assert command_run.running?
  end

  test "terminalizes one-shot exec_command program tools as completed command runs" do
    context = build_governed_tool_context!
    workflow_node = context.fetch(:workflow_node)
    round_bindings = ToolBindings::FreezeForWorkflowNode.call(
      workflow_node: workflow_node
    ).includes(:tool_definition, tool_implementation: :implementation_source).to_a
    program_exchange = ProviderExecutionTestSupport::FakeProgramExchange.new(
      program_tool_results: {
        "call-exec-command-oneshot-1" => lambda { |payload:|
          {
            "status" => "ok",
            "result" => {
              "command_run_id" => payload.dig("runtime_resource_refs", "command_run", "command_run_id"),
              "exit_status" => 0,
              "stdout_bytes" => 6,
              "stderr_bytes" => 0,
              "output_streamed" => true,
            },
            "output_chunks" => [],
            "summary_artifacts" => [],
          }
        },
      }
    )

    result = ProviderExecution::RouteToolCall.call(
      workflow_node: workflow_node,
      tool_call: {
        "call_id" => "call-exec-command-oneshot-1",
        "tool_name" => "exec_command",
        "arguments" => {
          "command_line" => "printf 'hello\\n'",
          "timeout_seconds" => 30,
        },
        "provider_format" => "chat_completions",
      },
      round_bindings: round_bindings,
      program_exchange: program_exchange
    )

    request_payload = program_exchange.execute_program_tool_requests.first
    command_run_id = request_payload.dig("runtime_resource_refs", "command_run", "command_run_id")
    command_run = CommandRun.find_by_public_id!(command_run_id)

    assert_equal command_run_id, result.result.fetch("command_run_id")
    assert_equal "completed", command_run.lifecycle_state
    assert_equal 0, command_run.exit_status
    assert_equal 6, command_run.metadata.fetch("stdout_bytes")
  end

  test "terminalizes durable command runs when command_run_wait finishes an attached session" do
    command_run_wait_tool = {
      "tool_name" => "command_run_wait",
      "tool_kind" => "agent_observation",
      "implementation_source" => "agent",
      "implementation_ref" => "agent/command_run_wait",
      "input_schema" => { "type" => "object", "properties" => {} },
      "result_schema" => { "type" => "object", "properties" => {} },
      "streaming_support" => false,
      "idempotency_policy" => "best_effort",
    }
    context = build_governed_tool_context!(
      agent_tool_catalog: governed_agent_tool_catalog + [command_run_wait_tool],
      profile_catalog: governed_profile_catalog.deep_merge(
        "main" => {
          "allowed_tool_names" => %w[exec_command command_run_wait compact_context subagent_spawn],
        }
      )
    )
    workflow_node = context.fetch(:workflow_node)
    round_bindings = ToolBindings::FreezeForWorkflowNode.call(
      workflow_node: workflow_node
    ).includes(:tool_definition, tool_implementation: :implementation_source).to_a
    program_exchange = ProviderExecutionTestSupport::FakeProgramExchange.new(
      program_tool_results: {
        "call-exec-command-attached-1" => lambda { |payload:|
          {
            "status" => "ok",
            "result" => {
              "command_run_id" => payload.dig("runtime_resource_refs", "command_run", "command_run_id"),
              "session_closed" => false,
              "attached" => true,
            },
            "output_chunks" => [],
            "summary_artifacts" => [],
          }
        },
        "call-command-run-wait-1" => {
          "status" => "ok",
          "result" => {
            "command_run_id" => nil,
            "session_closed" => true,
            "exit_status" => 0,
            "stdout_bytes" => 12,
            "stderr_bytes" => 0,
            "output_streamed" => true,
          },
          "output_chunks" => [],
          "summary_artifacts" => [],
        },
      }
    )

    exec_result = ProviderExecution::RouteToolCall.call(
      workflow_node: workflow_node,
      tool_call: {
        "call_id" => "call-exec-command-attached-1",
        "tool_name" => "exec_command",
        "arguments" => {
          "command_line" => "printf 'hello\\n'",
          "timeout_seconds" => 30,
          "pty" => true,
        },
        "provider_format" => "chat_completions",
      },
      round_bindings: round_bindings,
      program_exchange: program_exchange
    )

    command_run_id = exec_result.result.fetch("command_run_id")
    program_exchange = ProviderExecutionTestSupport::FakeProgramExchange.new(
      program_tool_results: {
        "call-command-run-wait-1" => {
          "status" => "ok",
          "result" => {
            "command_run_id" => command_run_id,
            "session_closed" => true,
            "exit_status" => 0,
            "stdout_bytes" => 12,
            "stderr_bytes" => 0,
            "output_streamed" => true,
          },
          "output_chunks" => [],
          "summary_artifacts" => [],
        },
      }
    )

    ProviderExecution::RouteToolCall.call(
      workflow_node: workflow_node,
      tool_call: {
        "call_id" => "call-command-run-wait-1",
        "tool_name" => "command_run_wait",
        "arguments" => {
          "command_run_id" => command_run_id,
          "timeout_seconds" => 30,
        },
        "provider_format" => "chat_completions",
      },
      round_bindings: round_bindings,
      program_exchange: program_exchange
    )

    command_run = CommandRun.find_by_public_id!(command_run_id)
    assert_equal "completed", command_run.lifecycle_state
    assert_equal 0, command_run.exit_status
    assert_equal 12, command_run.metadata.fetch("stdout_bytes")
  end

  test "provisions durable process runs for process_exec program tools" do
    process_exec_tool = {
      "tool_name" => "process_exec",
      "tool_kind" => "agent_observation",
      "implementation_source" => "agent",
      "implementation_ref" => "agent/process_exec",
      "input_schema" => { "type" => "object", "properties" => {} },
      "result_schema" => { "type" => "object", "properties" => {} },
      "streaming_support" => false,
      "idempotency_policy" => "best_effort",
    }
    context = build_governed_tool_context!(
      agent_tool_catalog: governed_agent_tool_catalog + [process_exec_tool],
      profile_catalog: governed_profile_catalog.deep_merge(
        "main" => {
          "allowed_tool_names" => %w[exec_command compact_context subagent_spawn process_exec],
        }
      )
    )
    workflow_node = context.fetch(:workflow_node)
    round_bindings = ToolBindings::FreezeForWorkflowNode.call(
      workflow_node: workflow_node
    ).includes(:tool_definition, tool_implementation: :implementation_source).to_a
    program_exchange = ProviderExecutionTestSupport::FakeProgramExchange.new(
      program_tool_results: {
        "call-process-exec-1" => lambda { |payload:|
          {
            "status" => "ok",
            "result" => {
              "process_run_id" => payload.dig("runtime_resource_refs", "process_run", "process_run_id"),
              "lifecycle_state" => "running",
            },
            "output_chunks" => [],
            "summary_artifacts" => [],
          }
        },
      }
    )

    result = ProviderExecution::RouteToolCall.call(
      workflow_node: workflow_node,
      tool_call: {
        "call_id" => "call-process-exec-1",
        "tool_name" => "process_exec",
        "arguments" => {
          "kind" => "background_service",
          "command_line" => "npm run preview -- --host 0.0.0.0 --port 4173",
          "proxy_port" => 4173,
        },
        "provider_format" => "chat_completions",
      },
      round_bindings: round_bindings,
      program_exchange: program_exchange
    )

    request_payload = program_exchange.execute_program_tool_requests.first
    process_run_id = request_payload.dig("runtime_resource_refs", "process_run", "process_run_id")
    process_run = ProcessRun.find_by_public_id!(process_run_id)

    assert_equal process_run_id, result.result.fetch("process_run_id")
    assert_equal workflow_node, process_run.workflow_node
    assert_equal context.fetch(:conversation), process_run.conversation
    assert process_run.running?
    assert_equal workflow_node.turn.public_id, request_payload.dig("runtime_resource_refs", "process_run", "agent_task_run_id")
  end

  test "normalizes provider-facing process_exec kind aliases before provisioning process runs" do
    process_exec_tool = {
      "tool_name" => "process_exec",
      "tool_kind" => "agent_observation",
      "implementation_source" => "agent",
      "implementation_ref" => "agent/process_exec",
      "input_schema" => { "type" => "object", "properties" => {} },
      "result_schema" => { "type" => "object", "properties" => {} },
      "streaming_support" => false,
      "idempotency_policy" => "best_effort",
    }
    context = build_governed_tool_context!(
      agent_tool_catalog: governed_agent_tool_catalog + [process_exec_tool],
      profile_catalog: governed_profile_catalog.deep_merge(
        "main" => {
          "allowed_tool_names" => %w[exec_command compact_context subagent_spawn process_exec],
        }
      )
    )
    workflow_node = context.fetch(:workflow_node)
    round_bindings = ToolBindings::FreezeForWorkflowNode.call(
      workflow_node: workflow_node
    ).includes(:tool_definition, tool_implementation: :implementation_source).to_a
    program_exchange = ProviderExecutionTestSupport::FakeProgramExchange.new(
      program_tool_results: {
        "process_exec" => lambda { |payload:|
          {
            "status" => "ok",
            "result" => {
              "process_run_id" => payload.dig("runtime_resource_refs", "process_run", "process_run_id"),
              "lifecycle_state" => "running",
            },
            "output_chunks" => [],
            "summary_artifacts" => [],
          }
        },
      }
    )

    %w[background command process web web_server server default].each do |kind_alias|
      result = ProviderExecution::RouteToolCall.call(
        workflow_node: workflow_node,
        tool_call: {
          "call_id" => "call-process-exec-#{kind_alias}-alias-1",
          "tool_name" => "process_exec",
          "arguments" => {
            "kind" => kind_alias,
            "command_line" => "npm run preview -- --host 0.0.0.0 --port 4173",
            "proxy_port" => 4173,
          },
          "provider_format" => "chat_completions",
        },
        round_bindings: round_bindings,
        program_exchange: program_exchange
      )

      process_run = ProcessRun.find_by_public_id!(result.result.fetch("process_run_id"))
      assert_equal "background_service", process_run.kind
      assert process_run.running?
    end
  end

  test "fails the tool invocation when durable process run provisioning raises" do
    process_exec_tool = {
      "tool_name" => "process_exec",
      "tool_kind" => "agent_observation",
      "implementation_source" => "agent",
      "implementation_ref" => "agent/process_exec",
      "input_schema" => { "type" => "object", "properties" => {} },
      "result_schema" => { "type" => "object", "properties" => {} },
      "streaming_support" => false,
      "idempotency_policy" => "best_effort",
    }
    context = build_governed_tool_context!(
      agent_tool_catalog: governed_agent_tool_catalog + [process_exec_tool],
      profile_catalog: governed_profile_catalog.deep_merge(
        "main" => {
          "allowed_tool_names" => %w[exec_command compact_context subagent_spawn process_exec],
        }
      )
    )
    workflow_node = context.fetch(:workflow_node)
    round_bindings = ToolBindings::FreezeForWorkflowNode.call(
      workflow_node: workflow_node
    ).includes(:tool_definition, tool_implementation: :implementation_source).to_a

    error = assert_raises(ActiveRecord::RecordInvalid) do
      ProviderExecution::RouteToolCall.call(
        workflow_node: workflow_node,
        tool_call: {
          "call_id" => "call-process-exec-invalid-kind-1",
          "tool_name" => "process_exec",
          "arguments" => {
            "kind" => "not-a-real-kind",
            "command_line" => "npm run preview -- --host 0.0.0.0 --port 4173",
          },
          "provider_format" => "chat_completions",
        },
        round_bindings: round_bindings,
        program_exchange: ProviderExecutionTestSupport::FakeProgramExchange.new
      )
    end

    invocation = ToolInvocation.find_by!(idempotency_key: "call-process-exec-invalid-kind-1")
    assert_equal "failed", invocation.reload.status
    assert_equal "tool_execution_failed", invocation.error_payload.fetch("code")
    assert_match(/Kind is not included in the list/, error.message)
  end

  test "routes round-visible MCP tools through the generic MCP executor" do
    context = build_governed_mcp_context!(base_url: @mcp_server.base_url)
    workflow_node = context.fetch(:workflow_node)
    round_bindings = ProviderExecution::MaterializeRoundTools.call(
      workflow_node: workflow_node,
      tool_catalog: governed_mcp_tool_catalog(base_url: @mcp_server.base_url)
    ).includes(:tool_definition, tool_implementation: :implementation_source).to_a

    result = ProviderExecution::RouteToolCall.call(
      workflow_node: workflow_node,
      tool_call: {
        "call_id" => "call-mcp-1",
        "tool_name" => "remote_echo",
        "arguments" => { "message" => "hello from loop" },
        "provider_format" => "chat_completions",
      },
      round_bindings: round_bindings
    )

    invocation = result.tool_invocation.reload

    assert_equal "succeeded", invocation.status
    assert_equal workflow_node, invocation.workflow_node
    assert_equal "echo: hello from loop", result.result.dig("content", 0, "text")
    assert_match(/\Asession-\d+\z/, result.tool_binding.reload.runtime_state.dig("mcp", "session_id"))
  end

  test "routes core matrix tools without delegating back to the program mailbox exchange" do
    context = build_governed_tool_context!(
      profile_catalog: {
        "main" => {
          "label" => "Main",
          "description" => "Primary interactive profile",
          "allowed_tool_names" => %w[exec_command compact_context subagent_spawn subagent_list],
        },
      }
    )
    workflow_node = context.fetch(:workflow_node)
    round_bindings = ToolBindings::FreezeForWorkflowNode.call(
      workflow_node: workflow_node
    ).includes(:tool_definition, tool_implementation: :implementation_source).to_a
    program_exchange = ProviderExecutionTestSupport::FakeProgramExchange.new

    result = ProviderExecution::RouteToolCall.call(
      workflow_node: workflow_node,
      tool_call: {
        "call_id" => "call-subagent-list-1",
        "tool_name" => "subagent_list",
        "arguments" => {},
        "provider_format" => "chat_completions",
      },
      round_bindings: round_bindings,
      program_exchange: program_exchange
    )

    invocation = result.tool_invocation.reload

    assert_equal({ "entries" => [] }, result.result)
    assert_equal "succeeded", invocation.status
    assert_equal workflow_node, invocation.workflow_node
    assert_equal "subagent_list", invocation.tool_definition.tool_name
    assert_equal [], program_exchange.execute_program_tool_requests
  end

  private

  def calculator_tool_entry
    {
      "tool_name" => "calculator",
      "tool_kind" => "agent_observation",
      "implementation_source" => "agent",
      "implementation_ref" => "fenix/runtime/calculator",
      "input_schema" => {
        "type" => "object",
        "properties" => {
          "expression" => { "type" => "string" },
        },
      },
      "result_schema" => {
        "type" => "object",
        "properties" => {
          "value" => { "type" => "integer" },
        },
      },
      "streaming_support" => false,
      "idempotency_policy" => "best_effort",
    }
  end
end
