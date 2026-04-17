require "test_helper"

module RuntimeToolContracts
  class CommandAndProcessContractTest < ActiveSupport::TestCase
    test "exec_command payload provisions a public command run ref before runtime execution" do
      context = build_governed_tool_context!
      workflow_node = context.fetch(:workflow_node)
      round_bindings = ToolBindings::FreezeForWorkflowNode.call(
        workflow_node: workflow_node
      ).includes(:tool_definition, tool_implementation: :implementation_source).to_a
      requests = []
      execution_runtime_exchange = ProviderExecutionTestSupport::FakeExecutionRuntimeExchange.new do |payload:, **|
        requests << payload

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
      end

      ProviderExecution::RouteToolCall.call(
        workflow_node: workflow_node,
        tool_call: {
          "call_id" => "call-exec-command-contract-1",
          "tool_name" => "exec_command",
          "arguments" => {
            "command_line" => "printf 'hello\\n'",
            "pty" => true,
          },
          "provider_format" => "chat_completions",
        },
        round_bindings: round_bindings,
        execution_runtime_exchange: execution_runtime_exchange
      )

      command_ref = requests.first.dig("runtime_resource_refs", "command_run")
      command_run = CommandRun.find_by_public_id!(command_ref.fetch("command_run_id"))

      assert_equal %w[command_run_id runtime_owner_id], command_ref.keys.sort
      assert_equal command_run.public_id, command_ref.fetch("command_run_id")
      assert_equal workflow_node.public_id, command_ref.fetch("runtime_owner_id")
    end

    test "process_exec payload provisions a public process run ref before runtime execution" do
      process_exec_tool = {
        "tool_name" => "process_exec",
        "tool_kind" => "execution_runtime",
        "implementation_source" => "execution_runtime",
        "implementation_ref" => "env/process_exec",
        "input_schema" => { "type" => "object", "properties" => {} },
        "result_schema" => { "type" => "object", "properties" => {} },
        "streaming_support" => false,
        "idempotency_policy" => "best_effort",
      }
      context = build_governed_tool_context!(
        execution_runtime_tool_catalog: governed_execution_runtime_tool_catalog + [process_exec_tool],
        profile_policy: governed_profile_policy.deep_merge(
          "pragmatic" => {
            "allowed_tool_names" => %w[exec_command compact_context subagent_spawn process_exec],
          }
        )
      )
      workflow_node = context.fetch(:workflow_node)
      round_bindings = ToolBindings::FreezeForWorkflowNode.call(
        workflow_node: workflow_node
      ).includes(:tool_definition, tool_implementation: :implementation_source).to_a
      requests = []
      execution_runtime_exchange = ProviderExecutionTestSupport::FakeExecutionRuntimeExchange.new do |payload:, **|
        requests << payload

        {
          "status" => "ok",
          "result" => {
            "process_run_id" => payload.dig("runtime_resource_refs", "process_run", "process_run_id"),
            "lifecycle_state" => "running",
          },
          "output_chunks" => [],
          "summary_artifacts" => [],
        }
      end

      ProviderExecution::RouteToolCall.call(
        workflow_node: workflow_node,
        tool_call: {
          "call_id" => "call-process-contract-1",
          "tool_name" => "process_exec",
          "arguments" => {
            "command_line" => "printf ready",
            "proxy_port" => 4173,
          },
          "provider_format" => "chat_completions",
        },
        round_bindings: round_bindings,
        execution_runtime_exchange: execution_runtime_exchange
      )

      process_ref = requests.first.dig("runtime_resource_refs", "process_run")
      process_run = ProcessRun.find_by_public_id!(process_ref.fetch("process_run_id"))

      assert_equal %w[process_run_id runtime_owner_id], process_ref.keys.sort
      assert_equal process_run.public_id, process_ref.fetch("process_run_id")
      assert_equal workflow_node.public_id, process_ref.fetch("runtime_owner_id")
    end
  end
end
