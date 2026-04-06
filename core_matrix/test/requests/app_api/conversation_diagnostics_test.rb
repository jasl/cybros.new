require "test_helper"

class AppApiConversationDiagnosticsTest < ActionDispatch::IntegrationTest
  test "shows conversation diagnostics and turn diagnostics through the app api" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)

    ProviderUsage::RecordEvent.call(
      installation: context[:installation],
      user: context[:user],
      workspace: context[:workspace],
      conversation_id: context[:conversation].id,
      turn_id: context[:turn].id,
      workflow_node_key: "turn_step",
      agent_program: context[:agent_program],
      agent_program_version: context[:agent_program_version],
      provider_handle: "openrouter",
      model_ref: "openai-gpt-5.4",
      operation_kind: "text_generation",
      input_tokens: 120,
      output_tokens: 40,
      prompt_cache_status: "available",
      cached_input_tokens: 60,
      latency_ms: 1_200,
      estimated_cost: 0.010,
      success: true,
      occurred_at: Time.utc(2026, 4, 2, 9, 0, 0)
    )

    ConversationDiagnosticsSnapshot.where(conversation: context[:conversation]).delete_all
    TurnDiagnosticsSnapshot.where(conversation: context[:conversation]).delete_all

    get "/app_api/conversation_diagnostics/show",
      params: {
        conversation_id: context[:conversation].public_id,
      },
      headers: app_api_headers(registration[:machine_credential])

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal "conversation_diagnostics_show", response_body["method_id"]
    assert_equal context[:conversation].public_id, response_body["conversation_id"]
    assert_equal context[:conversation].public_id, response_body.dig("snapshot", "conversation_id")
    assert_equal 1, response_body.dig("snapshot", "usage_event_count")
    assert_equal 120, response_body.dig("snapshot", "input_tokens_total")
    assert_equal 40, response_body.dig("snapshot", "output_tokens_total")
    assert_equal 160, response_body.dig("snapshot", "total_tokens_total")
    assert_equal 60, response_body.dig("snapshot", "cached_input_tokens_total")
    assert_equal 1, response_body.dig("snapshot", "prompt_cache_available_event_count")
    assert_equal 0, response_body.dig("snapshot", "prompt_cache_unknown_event_count")
    assert_equal 0, response_body.dig("snapshot", "prompt_cache_unsupported_event_count")
    assert_equal 0.5, response_body.dig("snapshot", "prompt_cache_hit_rate")
    assert_equal 1, response_body.dig("snapshot", "estimated_cost_event_count")
    assert_equal 0, response_body.dig("snapshot", "estimated_cost_missing_event_count")
    assert_equal true, response_body.dig("snapshot", "cost_data_available")
    assert_equal true, response_body.dig("snapshot", "cost_data_complete")
    assert_equal context[:user].public_id, response_body.dig("snapshot", "attributed_user_id")
    assert_equal 120, response_body.dig("snapshot", "attributed_user_input_tokens_total")
    assert_equal 40, response_body.dig("snapshot", "attributed_user_output_tokens_total")
    assert_equal 160, response_body.dig("snapshot", "attributed_user_total_tokens_total")
    assert_equal 0, response_body.dig("snapshot", "steer_count")
    assert_equal 1, response_body.dig("snapshot", "metadata", "attributed_user_provider_usage_breakdown").length
    assert_equal context[:turn].public_id, response_body.dig("snapshot", "most_expensive_turn_id")
    refute_includes response.body, %("#{context[:conversation].id}")
    refute_includes response.body, %("#{context[:turn].id}")

    get "/app_api/conversation_diagnostics/turns",
      params: {
        conversation_id: context[:conversation].public_id,
      },
      headers: app_api_headers(registration[:machine_credential])

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal "conversation_diagnostics_turns", response_body["method_id"]
    assert_equal context[:conversation].public_id, response_body["conversation_id"]
    assert_equal 1, response_body["items"].length
    assert_equal context[:turn].public_id, response_body["items"].first.fetch("turn_id")
    assert_equal context[:conversation].public_id, response_body["items"].first.fetch("conversation_id")
    assert_equal 120, response_body["items"].first.fetch("input_tokens_total")
    assert_equal 40, response_body["items"].first.fetch("output_tokens_total")
    assert_equal 160, response_body["items"].first.fetch("total_tokens_total")
    assert_equal 60, response_body["items"].first.fetch("cached_input_tokens_total")
    assert_equal 1, response_body["items"].first.fetch("prompt_cache_available_event_count")
    assert_equal 0.5, response_body["items"].first.fetch("prompt_cache_hit_rate")
    assert_equal 1200, response_body["items"].first.fetch("avg_latency_ms")
    assert_equal 1200, response_body["items"].first.fetch("max_latency_ms")
    assert_equal 1, response_body["items"].first.fetch("estimated_cost_event_count")
    assert_equal 0, response_body["items"].first.fetch("estimated_cost_missing_event_count")
    assert_equal context[:user].public_id, response_body["items"].first.fetch("attributed_user_id")
    assert_equal 120, response_body["items"].first.fetch("attributed_user_input_tokens_total")
    assert_equal 40, response_body["items"].first.fetch("attributed_user_output_tokens_total")
    assert_equal 160, response_body["items"].first.fetch("attributed_user_total_tokens_total")
    assert_equal 0, response_body["items"].first.fetch("steer_count")
    assert_equal 1, ConversationDiagnosticsSnapshot.where(conversation: context[:conversation]).count
    assert_equal 1, TurnDiagnosticsSnapshot.where(conversation: context[:conversation]).count
  end

  test "returns null prompt cache hit rate when no available usage events exist" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)

    ProviderUsage::RecordEvent.call(
      installation: context[:installation],
      user: context[:user],
      workspace: context[:workspace],
      conversation_id: context[:conversation].id,
      turn_id: context[:turn].id,
      workflow_node_key: "turn_step",
      agent_program: context[:agent_program],
      agent_program_version: context[:agent_program_version],
      provider_handle: "openrouter",
      model_ref: "openai-gpt-5.4",
      operation_kind: "text_generation",
      input_tokens: 120,
      output_tokens: 40,
      prompt_cache_status: "unsupported",
      latency_ms: 1_200,
      estimated_cost: 0.010,
      success: true,
      occurred_at: Time.utc(2026, 4, 2, 9, 0, 0)
    )

    get "/app_api/conversation_diagnostics/show",
      params: {
        conversation_id: context[:conversation].public_id,
      },
      headers: app_api_headers(registration[:machine_credential])

    assert_response :success
    assert_nil JSON.parse(response.body).dig("snapshot", "prompt_cache_hit_rate")
  end

  test "rejects raw bigint identifiers for conversation diagnostics lookups" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)

    get "/app_api/conversation_diagnostics/show",
      params: {
        conversation_id: context[:conversation].id,
      },
      headers: app_api_headers(registration[:machine_credential])

    assert_response :not_found

    get "/app_api/conversation_diagnostics/turns",
      params: {
        conversation_id: context[:conversation].id,
      },
      headers: app_api_headers(registration[:machine_credential])

    assert_response :not_found
  end
end
