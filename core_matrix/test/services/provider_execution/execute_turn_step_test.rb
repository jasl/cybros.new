require "test_helper"

class ProviderExecution::ExecuteTurnStepTest < ActiveSupport::TestCase
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

  test "uses the persisted execution snapshot contract for provider request context" do
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

    with_stubbed_provider_catalog(catalog) do
      ProviderExecution::ExecuteTurnStep.call(
        workflow_node: workflow_run.workflow_nodes.find_by!(node_key: "turn_step"),
        messages: workflow_run.execution_snapshot.context_messages.map { |entry| entry.slice("role", "content") },
        adapter: adapter
      )
    end

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
    assert_equal "Direct provider result", workflow_run.turn.reload.selected_output_message.content
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

    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Execute turn step input",
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
