require "test_helper"

class ProviderExecution::DispatchRequestTest < ActiveSupport::TestCase
  class TrackingChatAdapter < SimpleInference::HTTPAdapter
    attr_reader :call_requests, :stream_requests

    def initialize(response_body:)
      @response_body = response_body
      @call_requests = []
      @stream_requests = []
    end

    def call(env)
      @call_requests << env
      {
        status: 200,
        headers: {
          "content-type" => "application/json",
          "x-request-id" => "tracking-chat-request-1",
        },
        body: JSON.generate(@response_body),
      }
    end

    def call_stream(env)
      @stream_requests << env
      super
    end
  end

  class FlakyStreamingAdapter < SimpleInference::HTTPAdapter
    attr_reader :stream_requests

    def initialize(chunks:, failures:)
      @delegate = ProviderExecutionTestSupport::FakeStreamingChatCompletionsAdapter.new(chunks: chunks)
      @failures_remaining = failures
      @stream_requests = []
    end

    def call_stream(env)
      @stream_requests << env

      if @failures_remaining.positive?
        @failures_remaining -= 1
        raise SimpleInference::TimeoutError, "Timed out while resolving openrouter.ai"
      end

      @delegate.call_stream(env) { |chunk| yield chunk }
    end
  end

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

  test "normalizes internal agent transcript roles to assistant before provider dispatch" do
    catalog = build_mock_chat_catalog
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: {
        "temperature" => 0.4,
      },
      catalog: catalog
    )
    request_context = build_request_context_for(workflow_run, catalog: catalog)
    adapter = ProviderExecutionTestSupport::FakeChatCompletionsAdapter.new(
      response_body: {
        id: "chatcmpl-direct-step-roles-1",
        choices: [
          {
            message: { role: "assistant", content: "ok" },
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

    ProviderExecution::DispatchRequest.call(
      workflow_run: workflow_run,
      request_context: request_context,
      messages: [
        { "role" => "user", "content" => "first input" },
        { "role" => "agent", "content" => "prior output" },
        { "role" => "user", "content" => "follow-up input" },
      ],
      adapter: adapter,
      catalog: catalog,
      provider_request_id: "provider-request-role-normalization-1"
    )

    request_body = JSON.parse(adapter.last_request.fetch(:body))

    assert_equal ["user", "assistant", "user"], request_body.fetch("messages").map { |entry| entry.fetch("role") }
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

  test "passes tools and tool_choice through chat-completions requests" do
    catalog = build_mock_chat_catalog
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: {
        "temperature" => 0.4,
      },
      catalog: catalog
    )
    request_context = build_request_context_for(workflow_run, catalog: catalog)
    adapter = ProviderExecutionTestSupport::FakeChatCompletionsAdapter.new(
      response_body: {
        id: "chatcmpl-tool-step-1",
        choices: [
          {
            message: {
              role: "assistant",
              tool_calls: [
                {
                  id: "call_1",
                  type: "function",
                  function: {
                    name: "calculator",
                    arguments: "{\"expression\":\"2 + 2\"}",
                  },
                },
              ],
            },
            finish_reason: "tool_calls",
          },
        ],
        usage: {
          prompt_tokens: 12,
          completion_tokens: 8,
          total_tokens: 20,
        },
      }
    )

    ProviderExecution::DispatchRequest.call(
      workflow_run: workflow_run,
      request_context: request_context,
      messages: turn_step_messages_for(workflow_run),
      tools: [
        {
          "type" => "function",
          "function" => {
            "name" => "calculator",
            "parameters" => { "type" => "object" },
          },
        },
      ],
      tool_choice: "auto",
      adapter: adapter,
      catalog: catalog,
      provider_request_id: "provider-request-tools-1"
    )

    request_body = JSON.parse(adapter.last_request.fetch(:body))

    assert_equal "auto", request_body.fetch("tool_choice")
    assert_equal "calculator", request_body.fetch("tools").first.fetch("function").fetch("name")
  end

  test "preserves tool result message metadata in chat-completions requests" do
    catalog = build_mock_chat_catalog
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: {
        "temperature" => 0.4,
      },
      catalog: catalog
    )
    request_context = build_request_context_for(workflow_run, catalog: catalog)
    adapter = ProviderExecutionTestSupport::FakeChatCompletionsAdapter.new(
      response_body: {
        id: "chatcmpl-tool-message-1",
        choices: [
          {
            message: { role: "assistant", content: "ok" },
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

    ProviderExecution::DispatchRequest.call(
      workflow_run: workflow_run,
      request_context: request_context,
      messages: [
        { "role" => "user", "content" => "calculate" },
        { "role" => "tool", "tool_call_id" => "call_1", "name" => "calculator", "content" => "{\"value\":4}" },
      ],
      adapter: adapter,
      catalog: catalog,
      provider_request_id: "provider-request-tool-message-1"
    )

    request_body = JSON.parse(adapter.last_request.fetch(:body))
    tool_message = request_body.fetch("messages").last

    assert_equal "tool", tool_message.fetch("role")
    assert_equal "call_1", tool_message.fetch("tool_call_id")
    assert_equal "call_1", tool_message.fetch("call_id")
    assert_equal "calculator", tool_message.fetch("name")
  end

  test "streams chat-completions even when tools are present so tool-enabled turns still emit deltas" do
    catalog = build_mock_chat_catalog
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: {
        "temperature" => 0.4,
      },
      catalog: catalog
    )
    request_context = build_request_context_for(workflow_run, catalog: catalog)
    adapter = ProviderExecutionTestSupport::FakeStreamingChatCompletionsAdapter.new(
      chunks: ["Tool-capable ", "turn"]
    )
    deltas = []

    result = ProviderExecution::DispatchRequest.call(
      workflow_run: workflow_run,
      request_context: request_context,
      messages: turn_step_messages_for(workflow_run),
      tools: [
        {
          "type" => "function",
          "function" => {
            "name" => "calculator",
            "parameters" => { "type" => "object" },
          },
        },
      ],
      tool_choice: "auto",
      adapter: adapter,
      catalog: catalog,
      provider_request_id: "provider-request-tools-stream-1",
      on_delta: ->(delta) { deltas << delta }
    )

    request_body = JSON.parse(adapter.last_request.fetch(:body))

    assert_equal true, request_body.fetch("stream")
    assert_equal "calculator", request_body.fetch("tools").first.fetch("function").fetch("name")
    assert_equal ["Tool-capable ", "turn"], deltas
    assert_equal "Tool-capable turn", result.content
  end

  test "retries a transient streaming provider timeout before any deltas are emitted" do
    catalog = build_mock_chat_catalog
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: {
        "temperature" => 0.4,
      },
      catalog: catalog
    )
    request_context = build_request_context_for(workflow_run, catalog: catalog)
    adapter = FlakyStreamingAdapter.new(chunks: ["Hel", "lo"], failures: 1)
    deltas = []

    result = ProviderExecution::DispatchRequest.call(
      workflow_run: workflow_run,
      request_context: request_context,
      messages: turn_step_messages_for(workflow_run),
      adapter: adapter,
      catalog: catalog,
      provider_request_id: "provider-request-stream-retry-1",
      on_delta: ->(delta) { deltas << delta }
    )

    assert_equal 2, adapter.stream_requests.length
    assert_equal ["Hel", "lo"], deltas
    assert_equal "Hello", result.content
  end

  test "normalizes provider tool schemas so array parameters always include items" do
    catalog = build_mock_chat_catalog
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: {
        "temperature" => 0.4,
      },
      catalog: catalog
    )
    request_context = build_request_context_for(workflow_run, catalog: catalog)
    adapter = ProviderExecutionTestSupport::FakeChatCompletionsAdapter.new(
      response_body: {
        id: "chatcmpl-tool-schema-1",
        choices: [
          {
            message: { role: "assistant", content: "ok" },
            finish_reason: "stop",
          },
        ],
        usage: {
          prompt_tokens: 4,
          completion_tokens: 1,
          total_tokens: 5,
        },
      }
    )

    ProviderExecution::DispatchRequest.call(
      workflow_run: workflow_run,
      request_context: request_context,
      messages: turn_step_messages_for(workflow_run),
      tools: [
        {
          "type" => "function",
          "function" => {
            "name" => "compact_context",
            "parameters" => {
              "type" => "object",
              "properties" => {
                "messages" => {
                  "type" => "array",
                },
              },
            },
          },
        },
      ],
      adapter: adapter,
      catalog: catalog,
      provider_request_id: "provider-request-tool-schema-1"
    )

    request_body = JSON.parse(adapter.last_request.fetch(:body))

    assert_equal({}, request_body.dig("tools", 0, "function", "parameters", "properties", "messages", "items"))
  end

  test "dispatches responses-api requests with input messages and tool metadata" do
    catalog = build_mock_responses_catalog
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: {
        "temperature" => 0.4,
      },
      catalog: catalog
    )
    request_context = build_request_context_for(workflow_run, catalog: catalog)
    adapter = ProviderExecutionTestSupport::FakeResponsesAdapter.new(
      response_body: {
        "output" => [
          {
            "type" => "function_call",
            "id" => "item_1",
            "call_id" => "call_1",
            "name" => "calculator",
            "arguments" => "{\"expression\":\"2 + 2\"}",
          },
        ],
        "usage" => {
          "input_tokens" => 5,
          "output_tokens" => 3,
          "total_tokens" => 8,
        },
      }
    )

    result = ProviderExecution::DispatchRequest.call(
      workflow_run: workflow_run,
      request_context: request_context,
      messages: turn_step_messages_for(workflow_run),
      tools: [
        {
          "type" => "function",
          "name" => "calculator",
          "parameters" => { "type" => "object" },
        },
      ],
      tool_choice: "auto",
      adapter: adapter,
      catalog: catalog,
      provider_request_id: "provider-request-responses-1"
    )

    request_body = JSON.parse(adapter.last_request.fetch(:body))

    assert_equal turn_step_messages_for(workflow_run), request_body.fetch("input")
    assert_equal "auto", request_body.fetch("tool_choice")
    assert_equal "calculator", request_body.fetch("tools").first.fetch("name")
    assert_equal 8, result.usage.fetch("total_tokens")
  end

  test "uses the provider adapter selected from the catalog when no adapter is injected" do
    catalog = build_mock_chat_catalog
    workflow_run = create_mock_turn_step_workflow_run!(
      resolved_config_snapshot: {
        "temperature" => 0.4,
      },
      catalog: catalog
    )
    request_context = build_request_context_for(workflow_run, catalog: catalog)
    adapter = ProviderExecutionTestSupport::FakeChatCompletionsAdapter.new(
      response_body: {
        id: "chatcmpl-adapter-selection-1",
        choices: [
          {
            message: { role: "assistant", content: "Selected adapter result" },
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

    adapter_class = ProviderExecution::BuildHttpAdapter.singleton_class
    original_call = ProviderExecution::BuildHttpAdapter.method(:call)

    adapter_class.define_method(:call) { |*_, **_| adapter }

    result = ProviderExecution::DispatchRequest.call(
      workflow_run: workflow_run,
      request_context: request_context,
      messages: turn_step_messages_for(workflow_run),
      catalog: catalog,
      provider_request_id: "provider-request-selected-adapter-1"
    )

    request_body = JSON.parse(adapter.last_request.fetch(:body))

    assert_equal "mock-model", request_body.fetch("model")
    assert_equal "Selected adapter result", result.content
  ensure
    adapter_class.define_method(:call, original_call)
  end
end
