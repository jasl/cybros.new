require "test_helper"

class ProviderBackedGraphLoopTest < ActionDispatch::IntegrationTest
  test "tool-driven provider re-entry advances through explicit workflow nodes" do
    catalog = build_mock_chat_catalog
    tool_call_adapter = ProviderExecutionTestSupport::FakeChatCompletionsAdapter.new(
      response_body: {
        id: "chatcmpl-round-1",
        choices: [
          {
            message: {
              role: "assistant",
              tool_calls: [
                {
                  id: "call-calculator-1",
                  type: "function",
                  function: {
                    name: "calculator",
                    arguments: JSON.generate(expression: "2 + 2"),
                  },
                },
              ],
            },
            finish_reason: "tool_calls",
          },
        ],
        usage: {
          prompt_tokens: 12,
          completion_tokens: 4,
          total_tokens: 16,
        },
      }
    )
    final_adapter = ProviderExecutionTestSupport::FakeChatCompletionsAdapter.new(
      response_body: {
        id: "chatcmpl-round-2",
        choices: [
          {
            message: { role: "assistant", content: "The answer is 4." },
            finish_reason: "stop",
          },
        ],
        usage: {
          prompt_tokens: 18,
          completion_tokens: 6,
          total_tokens: 24,
        },
      }
    )
    workflow_run = nil

    workflow_run = create_mock_turn_step_workflow_run!(resolved_config_snapshot: {}, catalog: catalog)
    provider_context = workflow_run.turn.execution_contract.provider_context.deep_dup
    provider_context["budget_hints"] = provider_context.fetch("budget_hints", {}).deep_dup.merge(
      "hard_limits" => provider_context.dig("budget_hints", "hard_limits").to_h.merge(
        "context_window_tokens" => 400,
        "hard_input_token_limit" => 360
      ),
      "advisory_hints" => provider_context.dig("budget_hints", "advisory_hints").to_h.merge(
        "recommended_input_tokens" => 360,
        "recommended_compaction_threshold" => 360
      )
    )
    workflow_run.turn.execution_contract.update!(provider_context: provider_context)

    transcript = turn_step_messages_for(workflow_run)
    agent_request_exchange = ProviderExecutionTestSupport::FakeAgentRequestExchange.new(
      prepared_rounds: [
        {
          "messages" => transcript,
          "visible_tool_names" => ["calculator"],
          "summary_artifacts" => [],
          "trace" => [],
        },
        {
          "messages" => transcript,
          "visible_tool_names" => [],
          "summary_artifacts" => [],
          "trace" => [],
        },
      ],
      tool_results: {
        "call-calculator-1" => {
          "status" => "ok",
          "result" => { "value" => 4 },
          "output_chunks" => [],
          "summary_artifacts" => [],
        },
      }
    )

    with_stubbed_provider_catalog(catalog) do
      Workflows::ExecuteNode.call(
        workflow_node: workflow_run.workflow_nodes.find_by!(node_key: "turn_step"),
        messages: transcript,
        adapter: tool_call_adapter,
        agent_request_exchange: agent_request_exchange
      )
    end

    tool_node = workflow_run.reload.workflow_nodes.find_by!(node_key: "provider_round_1_tool_1")
    join_node = workflow_run.workflow_nodes.find_by!(node_key: "provider_round_1_join_1")
    successor = workflow_run.workflow_nodes.find_by!(node_key: "provider_round_2")

    with_stubbed_provider_catalog(catalog) do
      Workflows::ExecuteNode.call(
        workflow_node: tool_node,
        agent_request_exchange: agent_request_exchange
      )
      Workflows::ExecuteNode.call(
        workflow_node: join_node
      )
      Workflows::ExecuteNode.call(
        workflow_node: successor,
        messages: transcript,
        adapter: final_adapter,
        agent_request_exchange: agent_request_exchange
      )
    end

    proof = Workflows::ProofExportQuery.call(workflow_run: workflow_run.reload)

    assert_equal "The answer is 4.", workflow_run.turn.reload.selected_output_message.content
    assert workflow_run.reload.completed?
    assert workflow_run.turn.reload.completed?
    assert_equal(
      %w[
        turn_step->provider_round_1_tool_1
        provider_round_1_tool_1->provider_round_1_join_1
        provider_round_1_join_1->provider_round_2
      ],
      proof.observed_dag_shape
    )
    final_request_body = JSON.parse(final_adapter.last_request.fetch(:body))
    tool_messages = final_request_body.fetch("messages").last(2)

    assert_equal "assistant", tool_messages.first.fetch("role")
    assert_equal "tool", tool_messages.second.fetch("role")
    assert_equal "calculator", tool_messages.second.fetch("name")
    assert_equal JSON.generate("value" => 4), tool_messages.second.fetch("content")
    assert_equal 1, agent_request_exchange.execute_tool_requests.length
  end

  private

  def calculator_tool_entry
    {
      "tool_name" => "calculator",
      "tool_kind" => "agent_observation",
      "implementation_source" => "agent",
      "implementation_ref" => "fenix/calculator",
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
