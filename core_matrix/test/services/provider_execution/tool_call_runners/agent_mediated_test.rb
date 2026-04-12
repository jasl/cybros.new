require "test_helper"

class ProviderExecution::ToolCallRunners::AgentMediatedTest < ActiveSupport::TestCase
  test "sends public agent and user scope ids in execute_tool payloads" do
    context = build_governed_tool_context!(
      agent_tool_catalog: governed_agent_tool_catalog + [calculator_tool_entry],
      profile_policy: governed_profile_policy.deep_merge(
        "main" => {
          "allowed_tool_names" => %w[exec_command compact_context subagent_spawn calculator],
        }
      )
    )
    workflow_node = context.fetch(:workflow_node)
    binding = ToolBindings::FreezeForWorkflowNode.call(
      workflow_node: workflow_node
    ).includes(:tool_definition, tool_implementation: :implementation_source).find do |candidate|
      candidate.tool_definition.tool_name == "calculator"
    end
    agent_request_exchange = ProviderExecutionTestSupport::FakeAgentRequestExchange.new(
      tool_results: {
        "call-calculator-1" => {
          "status" => "ok",
          "result" => { "value" => 4 },
          "output_chunks" => [],
          "summary_artifacts" => [],
        },
      }
    )

    result = ProviderExecution::ToolCallRunners::AgentMediated.call(
      workflow_node: workflow_node,
      tool_call: {
        "call_id" => "call-calculator-1",
        "tool_name" => "calculator",
        "arguments" => { "expression" => "2 + 2" },
        "provider_format" => "chat_completions",
      },
      binding: binding,
      agent_request_exchange: agent_request_exchange
    )

    request_payload = agent_request_exchange.execute_tool_requests.last

    assert_equal({ "value" => 4 }, result.result)
    assert_equal(
      {
        "agent_definition_version_id" => context.fetch(:agent_definition_version).public_id,
        "agent_id" => context.fetch(:agent).public_id,
        "user_id" => context.fetch(:user).public_id,
      },
      request_payload.fetch("runtime_context").slice("agent_definition_version_id", "agent_id", "user_id")
    )
  end

  test "preserves a running invocation across a deferred mailbox exchange and completes it on rerun" do
    context = build_governed_tool_context!(
      agent_tool_catalog: governed_agent_tool_catalog + [calculator_tool_entry],
      profile_policy: governed_profile_policy.deep_merge(
        "main" => {
          "allowed_tool_names" => %w[exec_command compact_context subagent_spawn calculator],
        }
      )
    )
    workflow_node = context.fetch(:workflow_node)
    binding = ToolBindings::FreezeForWorkflowNode.call(
      workflow_node: workflow_node
    ).includes(:tool_definition, tool_implementation: :implementation_source).find do |candidate|
      candidate.tool_definition.tool_name == "calculator"
    end

    pending_exchange = Class.new do
      def execute_tool(*)
        raise ProviderExecution::AgentRequestExchange::PendingResponse.new(
          mailbox_item_public_id: "mailbox-item-1",
          logical_work_id: "tool-call:pending",
          request_kind: "execute_tool"
        )
      end
    end.new

    assert_raises(ProviderExecution::AgentRequestExchange::PendingResponse) do
      ProviderExecution::ToolCallRunners::AgentMediated.call(
        workflow_node: workflow_node,
        tool_call: {
          "call_id" => "call-calculator-pending-1",
          "tool_name" => "calculator",
          "arguments" => { "expression" => "2 + 2" },
          "provider_format" => "chat_completions",
        },
        binding: binding,
        agent_request_exchange: pending_exchange
      )
    end

    invocation = binding.tool_invocations.find_by!(idempotency_key: "call-calculator-pending-1")
    assert_equal "running", invocation.reload.status

    completed_exchange = ProviderExecutionTestSupport::FakeAgentRequestExchange.new(
      tool_results: {
        "call-calculator-pending-1" => {
          "status" => "ok",
          "result" => { "value" => 4 },
          "output_chunks" => [],
          "summary_artifacts" => [],
        },
      }
    )

    result = ProviderExecution::ToolCallRunners::AgentMediated.call(
      workflow_node: workflow_node,
      tool_call: {
        "call_id" => "call-calculator-pending-1",
        "tool_name" => "calculator",
        "arguments" => { "expression" => "2 + 2" },
        "provider_format" => "chat_completions",
      },
      binding: binding,
      agent_request_exchange: completed_exchange
    )

    assert_equal invocation.public_id, result.tool_invocation.public_id
    assert_equal({ "value" => 4 }, result.result)
    assert_equal "succeeded", invocation.reload.status
  end

  private

  def calculator_tool_entry
    {
      "tool_name" => "calculator",
      "tool_kind" => "agent_observation",
      "implementation_source" => "agent",
      "implementation_ref" => "agent/calculator",
      "input_schema" => {
        "type" => "object",
        "properties" => {
          "expression" => { "type" => "string" },
        },
        "required" => ["expression"],
      },
      "result_schema" => {
        "type" => "object",
        "properties" => {
          "value" => {},
        },
      },
      "streaming_support" => false,
      "idempotency_policy" => "best_effort",
    }
  end
end
