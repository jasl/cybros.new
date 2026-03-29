require "test_helper"

class ProviderExecution::DispatchRequestTest < ActiveSupport::TestCase
  test "dispatches provider chat requests and returns normalized result data" do
    catalog = build_mock_chat_catalog
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: {
        "temperature" => 0.4,
        "presence_penalty" => 0.6,
        "sandbox" => "workspace-write",
      },
      catalog: catalog
    )
    request_context = build_request_context_for(workflow_run, catalog: catalog)
    adapter = ProviderExecutionTestSupport::FakeChatCompletionsAdapter.new(
      response_body: {
        id: "chatcmpl-direct-step-1",
        choices: [
          {
            message: { role: "assistant", content: "Direct provider result" },
            finish_reason: "stop",
          },
        ],
        usage: {
          prompt_tokens: 12,
          completion_tokens: 8,
          total_tokens: 20,
        },
      }
    )

    result = ProviderExecution::DispatchRequest.call(
      workflow_run: workflow_run,
      request_context: request_context,
      messages: turn_step_messages_for(workflow_run),
      adapter: adapter,
      catalog: catalog,
      provider_request_id: "provider-request-1"
    )

    request_body = JSON.parse(adapter.last_request.fetch(:body))

    assert_equal "mock-model", request_body.fetch("model")
    assert_equal 0.4, request_body.fetch("temperature")
    assert_equal 0.95, request_body.fetch("top_p")
    assert_equal 20, request_body.fetch("top_k")
    assert_equal 0.1, request_body.fetch("min_p")
    assert_equal 0.6, request_body.fetch("presence_penalty")
    assert_equal 1.1, request_body.fetch("repetition_penalty")
    assert_equal 40, request_body.fetch("max_tokens")
    refute request_body.key?("sandbox")

    assert_equal "Direct provider result", result.content
    assert_equal "execute-turn-step-request-1", result.provider_request_id
    assert_equal(
      {
        "input_tokens" => 12,
        "output_tokens" => 8,
        "total_tokens" => 20,
      },
      result.usage
    )
    assert_operator result.duration_ms, :>=, 0
  end

  test "streams provider chat requests and yields output deltas while returning the aggregated result" do
    catalog = build_mock_chat_catalog
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: {
        "temperature" => 0.4,
        "presence_penalty" => 0.6,
      },
      catalog: catalog
    )
    request_context = build_request_context_for(workflow_run, catalog: catalog)
    adapter = ProviderExecutionTestSupport::FakeStreamingChatCompletionsAdapter.new(
      chunks: ["Hel", "lo"]
    )
    deltas = []

    result = ProviderExecution::DispatchRequest.call(
      workflow_run: workflow_run,
      request_context: request_context,
      messages: turn_step_messages_for(workflow_run),
      adapter: adapter,
      catalog: catalog,
      provider_request_id: "provider-request-stream-1",
      on_delta: ->(delta) { deltas << delta }
    )

    request_body = JSON.parse(adapter.last_request.fetch(:body))

    assert_equal true, request_body.fetch("stream")
    assert_equal ["Hel", "lo"], deltas
    assert_equal "Hello", result.content
    assert_equal "execute-turn-step-request-1", result.provider_request_id
    assert_equal(
      {
        "input_tokens" => 12,
        "output_tokens" => 8,
        "total_tokens" => 20,
      },
      result.usage
    )
  end
end
