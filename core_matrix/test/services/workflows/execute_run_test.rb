require "test_helper"

class Workflows::ExecuteRunTest < ActiveSupport::TestCase
  class FakeChatCompletionsAdapter < SimpleInference::HTTPAdapter
    attr_reader :last_request

    def initialize(response_body:, headers: {})
      @response_body = response_body
      @headers = {
        "content-type" => "application/json",
        "x-request-id" => "provider-request-123",
      }.merge(headers)
    end

    def call(env)
      @last_request = env
      {
        status: 200,
        headers: @headers,
        body: JSON.generate(@response_body),
      }
    end
  end

  test "executes a provider-backed turn step and persists durable usage and execution facts" do
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
    catalog = build_test_provider_catalog_from(catalog_definition)
    adapter = FakeChatCompletionsAdapter.new(
      response_body: {
        id: "chatcmpl-test-1",
        choices: [
          {
            message: { role: "assistant", content: "Provider result" },
            finish_reason: "stop",
          },
        ],
        usage: {
          prompt_tokens: 31,
          completion_tokens: 25,
          total_tokens: 56,
        },
      }
    )
    workflow_run = nil

    with_stubbed_provider_catalog(catalog) do
      workflow_run = create_mock_turn_step_workflow_run!(
        resolved_config_snapshot: {
          "temperature" => 0.4,
          "presence_penalty" => 0.6,
          "sandbox" => "workspace-write",
        }
      )
    end

    result = nil

    with_stubbed_provider_catalog(catalog) do
      result = Workflows::ExecuteRun.call(
        workflow_run: workflow_run,
        messages: workflow_run.turn.context_messages.map { |entry| entry.slice("role", "content") },
        adapter: adapter
      )
    end

    request_body = JSON.parse(adapter.last_request.fetch(:body))
    usage_event = UsageEvent.order(:id).last
    profiling_fact = ExecutionProfileFact.order(:id).last
    workflow_node_events = workflow_run.reload.workflow_node_events.order(:ordinal).to_a

    assert_equal "mock-model", request_body.fetch("model")
    assert_equal 0.4, request_body.fetch("temperature")
    assert_equal 0.95, request_body.fetch("top_p")
    assert_equal 20, request_body.fetch("top_k")
    assert_equal 0.1, request_body.fetch("min_p")
    assert_equal 0.6, request_body.fetch("presence_penalty")
    assert_equal 1.1, request_body.fetch("repetition_penalty")
    assert_equal 40, request_body.fetch("max_tokens")
    refute request_body.key?("sandbox")

    assert_equal "Provider result", result.output_message.content
    assert workflow_run.reload.completed?
    assert workflow_run.turn.reload.completed?
    assert_equal result.output_message, workflow_run.turn.selected_output_message
    assert_equal "dev", usage_event.provider_handle
    assert_equal "mock-model", usage_event.model_ref
    assert_equal "turn_step", usage_event.workflow_node_key
    assert_equal 31, usage_event.input_tokens
    assert_equal 25, usage_event.output_tokens
    assert usage_event.success
    assert profiling_fact.provider_request?
    assert_equal "turn_step", profiling_fact.fact_key
    assert profiling_fact.success
    assert_equal "provider-request-123", profiling_fact.metadata["provider_request_id"]
    assert_equal true, profiling_fact.metadata.dig("usage_evaluation", "threshold_crossed")
    assert_equal 50, profiling_fact.metadata.dig("usage_evaluation", "recommended_compaction_threshold")
    assert_equal %w[running completed], workflow_node_events.map { |event| event.payload.fetch("state") }
  end

  test "marks the turn and workflow failed when the provider request raises" do
    catalog_definition = test_provider_catalog_definition.deep_dup
    catalog = build_test_provider_catalog_from(catalog_definition)
    adapter = Class.new(SimpleInference::HTTPAdapter) do
      def call(_env)
        {
          status: 429,
          headers: { "content-type" => "application/json" },
          body: JSON.generate({ error: { message: "rate_limited" } }),
        }
      end
    end.new
    workflow_run = nil

    with_stubbed_provider_catalog(catalog) do
      workflow_run = create_mock_turn_step_workflow_run!(resolved_config_snapshot: {})
    end

    with_stubbed_provider_catalog(catalog) do
      error = assert_raises(SimpleInference::HTTPError) do
        Workflows::ExecuteRun.call(
          workflow_run: workflow_run,
          messages: workflow_run.turn.context_messages.map { |entry| entry.slice("role", "content") },
          adapter: adapter
        )
      end

      assert_includes error.message, "rate_limited"
    end

    profiling_fact = ExecutionProfileFact.last

    assert workflow_run.reload.failed?
    assert workflow_run.turn.reload.failed?
    assert profiling_fact.provider_request?
    refute profiling_fact.success
    assert_equal %w[running failed], workflow_run.workflow_node_events.order(:ordinal).map { |event| event.payload.fetch("state") }
    assert_equal 0, UsageEvent.count
  end

  private

  def create_mock_turn_step_workflow_run!(resolved_config_snapshot:)
    context = create_workspace_context!
    capability_snapshot = create_capability_snapshot!(agent_deployment: context[:agent_deployment])
    context[:agent_deployment].update!(active_capability_snapshot: capability_snapshot)
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

    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Execute run input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: resolved_config_snapshot,
      resolved_model_selection_snapshot: {}
    )

    Workflows::CreateForTurn.call(
      turn: turn,
      root_node_key: "turn_step",
      root_node_type: "turn_step",
      decision_source: "system",
      metadata: {},
      selector_source: "slot",
      selector: "role:mock"
    )
  end
end
