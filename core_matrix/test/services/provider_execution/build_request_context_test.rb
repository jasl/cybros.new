require "test_helper"

class ProviderExecution::BuildRequestContextTest < ActiveSupport::TestCase
  test "builds provider execution settings and separates hard limits from advisory hints" do
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

    request_context = nil

    with_stubbed_provider_catalog(catalog) do
      request_context = ProviderExecution::BuildRequestContext.call(
        turn: workflow_run.turn,
        execution_snapshot: workflow_run.execution_snapshot
      )
    end

    assert_instance_of ProviderRequestContext, request_context
    assert_equal "dev", request_context.provider_handle
    assert_equal "mock-model", request_context.model_ref
    assert_equal "mock-model", request_context.api_model
    assert_equal "chat_completions", request_context.wire_api
    assert_equal "o200k_base", request_context.tokenizer_hint
    assert_equal(
      {
        "temperature" => 0.4,
        "top_p" => 0.95,
        "top_k" => 20,
        "min_p" => 0.1,
        "presence_penalty" => 0.6,
        "repetition_penalty" => 1.1,
      },
      request_context.execution_settings
    )
    assert_equal(
      {
        "context_window_tokens" => 100,
        "max_output_tokens" => 40,
      },
      request_context.hard_limits
    )
    assert_equal(
      {
        "recommended_compaction_threshold" => 50,
      },
      request_context.advisory_hints
    )
    assert_same request_context, ProviderRequestContext.wrap(request_context)
  end

  private

  def create_mock_turn_step_workflow_run!(resolved_config_snapshot:)
    context = create_workspace_context!
    capability_snapshot = create_capability_snapshot!(agent_program_version: context[:agent_program_version])
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
      content: "Build request context",
      execution_runtime: context[:execution_runtime],
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
