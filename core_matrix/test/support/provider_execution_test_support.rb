module ProviderExecutionTestSupport
  FakeHttpResponse = Struct.new(:code, :body, :headers, keyword_init: true)

  class FakeProgramExchange
    attr_reader :prepare_round_requests, :execute_program_tool_requests

    def initialize(prepared_rounds: nil, program_tool_results: nil)
      @prepared_rounds = Array(prepared_rounds).map { |entry| deep_copy(entry) }
      @program_tool_results = (program_tool_results || {}).deep_stringify_keys
      @prepare_round_requests = []
      @execute_program_tool_requests = []
    end

    def prepare_round(payload:)
      payload = payload.deep_stringify_keys
      @prepare_round_requests << payload

      round = @prepared_rounds.shift || {
        "status" => "ok",
        "messages" => payload.fetch("conversation_projection").fetch("messages"),
        "tool_surface" => payload.fetch("capability_projection").fetch("tool_surface", []).select do |entry|
          entry.fetch("implementation_source", nil) != "core_matrix"
        end,
        "summary_artifacts" => [],
        "trace" => [],
      }
      deep_copy(round)
    end

    def execute_program_tool(payload:)
      payload = payload.deep_stringify_keys
      @execute_program_tool_requests << payload

      responder =
        @program_tool_results.dig("program_tool_call", payload.dig("program_tool_call", "call_id")) ||
        @program_tool_results[payload.dig("program_tool_call", "call_id")] ||
        @program_tool_results[payload.dig("program_tool_call", "tool_name")] ||
        @program_tool_results[payload["tool_call_id"]] ||
        @program_tool_results[payload["tool_name"]]
      response = responder.respond_to?(:call) ? responder.call(payload: payload) : responder

      deep_copy(response || {
        "status" => "ok",
        "result" => {},
        "output_chunks" => [],
        "summary_artifacts" => [],
      })
    end

    private

    def deep_copy(value)
      JSON.parse(JSON.generate(value))
    end
  end

  class FakeJsonTransport
    attr_reader :last_uri, :last_method, :last_headers, :last_body

    def initialize(response: nil, &block)
      @response = response
      @block = block
    end

    def call(uri:, method:, headers:, body:)
      @last_uri = uri
      @last_method = method
      @last_headers = headers
      @last_body = body

      return @block.call(uri:, method:, headers:, body:) if @block

      @response || FakeHttpResponse.new(code: "200", body: "{}", headers: {})
    end
  end

  class FakeChatCompletionsAdapter < SimpleInference::HTTPAdapter
    attr_reader :last_request

    def initialize(response_body:)
      @response_body = response_body
    end

    def call(env)
      @last_request = env
      {
        status: 200,
        headers: {
          "content-type" => "application/json",
          "x-request-id" => "execute-turn-step-request-1",
        },
        body: JSON.generate(@response_body),
      }
    end
  end

  class FakeStreamingChatCompletionsAdapter < SimpleInference::HTTPAdapter
    attr_reader :last_request

    def initialize(chunks:, response_id: "chatcmpl-direct-step-1", request_id: "execute-turn-step-request-1", usage: { prompt_tokens: 12, completion_tokens: 8, total_tokens: 20 })
      @chunks = chunks
      @response_id = response_id
      @request_id = request_id
      @usage = usage
    end

    def call_stream(env)
      @last_request = env
      sse = +""
      sse << %(data: {"id":"#{@response_id}","choices":[{"delta":{"role":"assistant"},"finish_reason":null}]}\n\n)
      @chunks.each do |chunk|
        sse << %(data: {"id":"#{@response_id}","choices":[{"delta":{"content":"#{chunk}"},"finish_reason":null}]}\n\n)
      end
      sse << %(data: {"id":"#{@response_id}","choices":[{"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":#{@usage[:prompt_tokens]},"completion_tokens":#{@usage[:completion_tokens]},"total_tokens":#{@usage[:total_tokens]}}}\n\n)
      sse << "data: [DONE]\n\n"

      yield sse

      {
        status: 200,
        headers: {
          "content-type" => "text/event-stream",
          "x-request-id" => @request_id,
        },
        body: nil,
      }
    end
  end

  class FakeQueuedChatCompletionsAdapter < SimpleInference::HTTPAdapter
    attr_reader :requests

    def initialize(response_bodies:)
      @response_bodies = Array(response_bodies).map(&:deep_dup)
      @requests = []
    end

    def call(env)
      @requests << env
      response_body = @response_bodies.shift || raise("no queued chat completion response available")
      request_index = @requests.length

      {
        status: 200,
        headers: {
          "content-type" => "application/json",
          "x-request-id" => "queued-chat-request-#{request_index}",
        },
        body: JSON.generate(response_body),
      }
    end
  end

  class FakeResponsesAdapter < SimpleInference::HTTPAdapter
    attr_reader :last_request

    def initialize(response_body:)
      @response_body = response_body
    end

    def call(env)
      @last_request = env
      {
        status: 200,
        headers: {
          "content-type" => "application/json",
          "x-request-id" => "responses-request-1",
        },
        body: JSON.generate(@response_body),
      }
    end
  end

  def build_mock_chat_catalog
    catalog_definition = test_provider_catalog_definition.deep_dup
    catalog_definition[:providers][:dev][:models]["mock-model"] = test_model_definition(
      display_name: "Mock Model",
      api_model: "mock-model",
      tokenizer_hint: "o200k_base",
      context_window_tokens: 100,
      max_output_tokens: 40,
      context_soft_limit_ratio: 0.5,
      request_defaults: {
        temperature: 0.9,
        top_p: 0.95,
        top_k: 20,
        min_p: 0.1,
        presence_penalty: 0.2,
        repetition_penalty: 1.1,
      }
    )

    build_test_provider_catalog_from(catalog_definition)
  end

  def build_mock_responses_catalog
    catalog_definition = test_provider_catalog_definition.deep_dup
    catalog_definition[:providers][:dev][:adapter_key] = "mock_llm_responses"
    catalog_definition[:providers][:dev][:wire_api] = "responses"
    catalog_definition[:providers][:dev][:responses_path] = "/v1/responses"

    build_test_provider_catalog_from(catalog_definition)
  end

  def create_mock_turn_step_workflow_run!(resolved_config_snapshot:, catalog: build_mock_chat_catalog, tool_catalog: nil, profile_catalog: nil)
    workflow_run = nil

    with_stubbed_provider_catalog(catalog) do
      context = create_workspace_context!
      capability_snapshot = create_capability_snapshot!(
        agent_program_version: context[:agent_program_version],
        tool_catalog: tool_catalog || default_tool_catalog("exec_command") + [default_agent_observation_tool_entry("calculator")],
        profile_catalog: profile_catalog || {}
      )
      adopt_agent_program_version!(context, capability_snapshot, turn: nil)
      ProviderEntitlement.create!(
        installation: context[:installation],
        provider_handle: "dev",
        entitlement_key: "dev_window",
        window_kind: "rolling_five_hours",
        window_seconds: 5.hours.to_i,
        quota_limit: 200_000,
        active: true,
        metadata: {}
      )

      conversation = Conversations::CreateRoot.call(
        workspace: context[:workspace],
        agent_program: context[:agent_program]
      )
      turn = Turns::StartUserTurn.call(
        conversation: conversation,
        content: "Execute turn step input",
        execution_runtime: context[:execution_runtime],
        resolved_config_snapshot: resolved_config_snapshot,
        resolved_model_selection_snapshot: {}
      )

      workflow_run = Workflows::CreateForTurn.call(
        turn: turn,
        root_node_key: "turn_step",
        root_node_type: "turn_step",
        decision_source: "system",
        metadata: {},
        selector_source: "slot",
        selector: "role:mock"
      )
    end

    workflow_run
  end

  def build_request_context_for(workflow_run, catalog: build_mock_chat_catalog)
    with_stubbed_provider_catalog(catalog) do
      ProviderExecution::BuildRequestContext.call(
        turn: workflow_run.turn,
        execution_snapshot: workflow_run.execution_snapshot
      )
    end
  end

  def turn_step_messages_for(workflow_run)
    workflow_run.execution_snapshot.conversation_projection.fetch("messages", []).map { |entry| entry.slice("role", "content") }
  end

  def default_agent_observation_tool_entry(tool_name)
    {
      "tool_name" => tool_name,
      "tool_kind" => "agent_observation",
      "implementation_source" => "agent",
      "implementation_ref" => "fenix/runtime/#{tool_name}",
      "input_schema" => { "type" => "object", "properties" => {} },
      "result_schema" => { "type" => "object", "properties" => {} },
      "streaming_support" => false,
      "idempotency_policy" => "best_effort",
    }
  end

  def build_provider_chat_result(
    content: "Direct provider result",
    prompt_tokens: 12,
    completion_tokens: 8,
    total_tokens: 20,
    request_id: "execute-turn-step-request-1",
    response_id: "chatcmpl-direct-step-1"
  )
    response = SimpleInference::Response.new(
      status: 200,
      headers: {
        "content-type" => "application/json",
        "x-request-id" => request_id,
      },
      body: { "id" => response_id },
      raw_body: JSON.generate({ "id" => response_id })
    )

    SimpleInference::OpenAI::ChatResult.new(
      content: content,
      usage: {
        prompt_tokens: prompt_tokens,
        completion_tokens: completion_tokens,
        total_tokens: total_tokens,
      },
      finish_reason: "stop",
      response: response
    )
  end

  def build_provider_http_error(message: "provider request failed", request_id: "execute-turn-step-request-1")
    response = SimpleInference::Response.new(
      status: 500,
      headers: { "x-request-id" => request_id },
      body: { "error" => { "message" => message } },
      raw_body: JSON.generate({ "error" => { "message" => message } })
    )

    SimpleInference::HTTPError.new(message, response: response)
  end
end

ActiveSupport::TestCase.include(ProviderExecutionTestSupport)
