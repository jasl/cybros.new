require "test_helper"

class ProviderExecution::ExecuteRoundLoopTest < ActiveSupport::TestCase
  test "repeats provider rounds after an agent program tool call and forwards tool results into the next prepare_round" do
    catalog = build_mock_chat_catalog
    adapter = ProviderExecutionTestSupport::FakeQueuedChatCompletionsAdapter.new(
      response_bodies: [
        {
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
        },
        {
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
        },
      ]
    )
    workflow_run = nil

    with_stubbed_provider_catalog(catalog) do
      workflow_run = create_mock_turn_step_workflow_run!(resolved_config_snapshot: {}, catalog: catalog)
    end

    transcript = turn_step_messages_for(workflow_run)
    program_exchange = ProviderExecutionTestSupport::FakeProgramExchange.new(
      prepared_rounds: [
        {
          "messages" => transcript,
          "program_tools" => [calculator_tool_entry],
        },
        {
          "messages" => transcript,
          "program_tools" => [],
        },
      ],
      program_tool_results: {
        "call-calculator-1" => {
          "status" => "completed",
          "result" => { "value" => 4 },
          "summary" => "4",
        },
      }
    )

    result = nil

    with_stubbed_provider_catalog(catalog) do
      result = ProviderExecution::ExecuteRoundLoop.call(
        workflow_node: workflow_run.workflow_nodes.find_by!(node_key: "turn_step"),
        transcript: transcript,
        adapter: adapter,
        effective_catalog: ProviderCatalog::EffectiveCatalog.new(installation: workflow_run.installation, catalog: catalog),
        program_exchange: program_exchange
      )
    end

    assert_equal "The answer is 4.", result.normalized_response.fetch("output_text")
    assert_equal 2, adapter.requests.length
    assert_equal 2, program_exchange.prepare_round_requests.length
    assert_equal(
      { "value" => 4 },
      program_exchange.prepare_round_requests.second.fetch("prior_tool_results").first.fetch("result")
    )

    second_request_body = JSON.parse(adapter.requests.second.fetch(:body))
    assistant_tool_call_message = second_request_body.fetch("messages")[-2]
    tool_result_message = second_request_body.fetch("messages").last

    assert_equal "assistant", assistant_tool_call_message.fetch("role")
    assert_equal "call-calculator-1", assistant_tool_call_message.fetch("tool_calls").first.fetch("id")
    assert_equal "calculator", assistant_tool_call_message.fetch("tool_calls").first.dig("function", "name")
    assert_equal "{\"expression\":\"2 + 2\"}", assistant_tool_call_message.fetch("tool_calls").first.dig("function", "arguments")
    assert_equal "tool", tool_result_message.fetch("role")
    assert_equal "call-calculator-1", tool_result_message.fetch("tool_call_id")
    assert_equal "calculator", tool_result_message.fetch("name")
    assert_equal({ "value" => 4 }.to_json, tool_result_message.fetch("content"))

    invocation = workflow_run.workflow_nodes.find_by!(node_key: "turn_step").tool_invocations.order(:created_at).last

    assert_equal "calculator", invocation.tool_definition.tool_name
    assert_equal "succeeded", invocation.status
    assert_equal({ "value" => 4 }, invocation.response_payload)
  end

  test "raises a dedicated round limit error when the configured loop budget is exhausted" do
    catalog = build_mock_chat_catalog
    adapter = ProviderExecutionTestSupport::FakeQueuedChatCompletionsAdapter.new(
      response_bodies: [
        {
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
        },
      ]
    )
    workflow_run = nil

    with_stubbed_provider_catalog(catalog) do
      workflow_run = create_mock_turn_step_workflow_run!(
        resolved_config_snapshot: { "max_rounds" => 1 },
        catalog: catalog
      )
    end

    transcript = turn_step_messages_for(workflow_run)
    program_exchange = ProviderExecutionTestSupport::FakeProgramExchange.new(
      prepared_rounds: [
        {
          "messages" => transcript,
          "program_tools" => [calculator_tool_entry],
        },
      ],
      program_tool_results: {
        "call-calculator-1" => {
          "status" => "completed",
          "result" => { "value" => 4 },
          "summary" => "4",
        },
      }
    )

    error = assert_raises(ProviderExecution::ExecuteRoundLoop::RoundLimitExceeded) do
      with_stubbed_provider_catalog(catalog) do
        ProviderExecution::ExecuteRoundLoop.call(
          workflow_node: workflow_run.workflow_nodes.find_by!(node_key: "turn_step"),
          transcript: transcript,
          adapter: adapter,
          effective_catalog: ProviderCatalog::EffectiveCatalog.new(installation: workflow_run.installation, catalog: catalog),
          program_exchange: program_exchange
        )
      end
    end

    assert_equal 1, error.max_rounds
    assert_equal 2, error.attempted_rounds
    assert_equal transcript.length, error.messages_count
    assert_equal 1, adapter.requests.length
    assert_equal 1, program_exchange.prepare_round_requests.length
  end

  test "exposes visible core matrix tools even when fenix returns no program tools for the round" do
    catalog = build_mock_chat_catalog
    adapter = ProviderExecutionTestSupport::FakeChatCompletionsAdapter.new(
      response_body: {
        id: "chatcmpl-round-core-matrix",
        choices: [
          {
            message: { role: "assistant", content: "No tool call needed." },
            finish_reason: "stop",
          },
        ],
        usage: {
          prompt_tokens: 9,
          completion_tokens: 4,
          total_tokens: 13,
        },
      }
    )
    workflow_node = nil
    transcript = nil

    with_stubbed_provider_catalog(catalog) do
      context = build_governed_tool_context!(
        profile_catalog: {
          "main" => {
            "label" => "Main",
            "description" => "Primary interactive profile",
            "allowed_tool_names" => %w[exec_command compact_context subagent_spawn],
          },
        }
      )
      workflow_node = context.fetch(:workflow_node)
      transcript = turn_step_messages_for(context.fetch(:workflow_run))
    end

    with_stubbed_provider_catalog(catalog) do
      ProviderExecution::ExecuteRoundLoop.call(
        workflow_node: workflow_node,
        transcript: transcript,
        adapter: adapter,
        effective_catalog: ProviderCatalog::EffectiveCatalog.new(installation: workflow_node.installation, catalog: catalog),
        program_exchange: ProviderExecutionTestSupport::FakeProgramExchange.new(
          prepared_rounds: [
            {
              "messages" => transcript,
              "program_tools" => [],
            },
          ]
        )
      )
    end

    request_body = JSON.parse(adapter.last_request.fetch(:body))
    subagent_spawn = request_body.fetch("tools").find { |entry| entry.dig("function", "name") == "subagent_spawn" }

    assert subagent_spawn.present?
    assert_equal "string", subagent_spawn.dig("function", "parameters", "properties", "content", "type")
    assert_equal ["content"], subagent_spawn.dig("function", "parameters", "required")
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
