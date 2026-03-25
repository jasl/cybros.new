require "test_helper"

class ProviderBackedTurnExecutionTest < ActionDispatch::IntegrationTest
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
          "x-request-id" => "openrouter-request-456",
        },
        body: JSON.generate(@response_body),
      }
    end
  end

  test "an explicit openrouter turn step executes through the shared provider path and projects usage rollups" do
    catalog_definition = test_provider_catalog_definition.deep_dup
    catalog_definition[:providers][:openrouter][:models]["openai-gpt-5.4"] = test_model_definition(
      display_name: "OpenAI GPT-5.4",
      api_model: "openai/gpt-5.4",
      tokenizer_hint: "o200k_base",
      context_window_tokens: 120,
      max_output_tokens: 24,
      context_soft_limit_ratio: 0.75,
      request_defaults: {
        temperature: 0.3,
        top_p: 0.8,
        top_k: 12,
        min_p: 0.05,
        presence_penalty: 0.1,
        repetition_penalty: 1.05,
      },
      multimodal_inputs: { image: false, audio: false, video: false, file: false }
    )
    catalog = build_test_provider_catalog_from(catalog_definition)
    adapter = FakeChatCompletionsAdapter.new(
      response_body: {
        id: "chatcmpl-openrouter-1",
        choices: [
          {
            message: { role: "assistant", content: "OpenRouter result" },
            finish_reason: "stop",
          },
        ],
        usage: {
          prompt_tokens: 18,
          completion_tokens: 7,
          total_tokens: 25,
        },
      }
    )
    workflow_run = nil

    with_stubbed_provider_catalog(catalog) do
      workflow_run = create_openrouter_turn_step_workflow_run!
    end

    with_stubbed_provider_catalog(catalog) do
      Workflows::ExecuteRun.call(
        workflow_run: workflow_run,
        messages: workflow_run.turn.context_messages.map { |entry| entry.slice("role", "content") },
        adapter: adapter
      )
    end

    request_body = JSON.parse(adapter.last_request.fetch(:body))
    usage_event = UsageEvent.last
    rollups = UsageRollup.where(
      installation: workflow_run.installation,
      provider_handle: "openrouter",
      model_ref: "openai-gpt-5.4"
    )

    assert_equal "openrouter", workflow_run.turn.execution_context.dig("model_context", "provider_handle")
    assert_equal "openai/gpt-5.4", workflow_run.turn.execution_context.dig("model_context", "api_model")
    assert_equal 90, workflow_run.turn.execution_context.dig("budget_hints", "advisory_hints", "recommended_compaction_threshold")
    assert_equal 0.3, workflow_run.turn.execution_context.dig("provider_execution", "execution_settings", "temperature")
    assert_equal "openai/gpt-5.4", request_body.fetch("model")
    assert_equal 24, request_body.fetch("max_tokens")
    assert_equal "OpenRouter result", workflow_run.turn.reload.selected_output_message.content
    assert workflow_run.reload.completed?
    assert workflow_run.turn.reload.completed?
    assert_equal "openrouter", usage_event.provider_handle
    assert_equal "openai-gpt-5.4", usage_event.model_ref
    assert_equal 3, rollups.count
  end

  private

  def create_openrouter_turn_step_workflow_run!
    context = create_workspace_context!
    capability_snapshot = create_capability_snapshot!(agent_deployment: context[:agent_deployment])
    context[:agent_deployment].update!(active_capability_snapshot: capability_snapshot)
    ProviderEntitlement.create!(
      installation: context[:installation],
      provider_handle: "openrouter",
      entitlement_key: "shared_window",
      window_kind: "rolling_five_hours",
      window_seconds: 5.hours.to_i,
      quota_limit: 200_000,
      active: true,
      metadata: {}
    )
    ProviderCredential.create!(
      installation: context[:installation],
      provider_handle: "openrouter",
      credential_kind: "api_key",
      secret: "sk-openrouter-test",
      last_rotated_at: Time.current,
      metadata: {}
    )

    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "OpenRouter input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    Workflows::CreateForTurn.call(
      turn: turn,
      root_node_key: "turn_step",
      root_node_type: "turn_step",
      decision_source: "system",
      metadata: {},
      selector_source: "slot",
      selector: "candidate:openrouter/openai-gpt-5.4"
    )
  end
end
