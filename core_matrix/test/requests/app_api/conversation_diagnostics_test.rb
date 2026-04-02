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
      agent_installation: context[:agent_installation],
      agent_deployment: context[:agent_deployment],
      provider_handle: "openrouter",
      model_ref: "openai-gpt-5.4",
      operation_kind: "text_generation",
      input_tokens: 120,
      output_tokens: 40,
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

    response_body = JSON.parse(response.body)
    assert_equal "conversation_diagnostics_show", response_body["method_id"]
    assert_equal context[:conversation].public_id, response_body["conversation_id"]
    assert_equal context[:conversation].public_id, response_body.dig("snapshot", "conversation_id")
    assert_equal 1, response_body.dig("snapshot", "usage_event_count")
    assert_equal 120, response_body.dig("snapshot", "input_tokens_total")
    assert_equal 40, response_body.dig("snapshot", "output_tokens_total")
    assert_equal 160, response_body.dig("snapshot", "total_tokens_total")
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
    assert_equal context[:user].public_id, response_body["items"].first.fetch("attributed_user_id")
    assert_equal 120, response_body["items"].first.fetch("attributed_user_input_tokens_total")
    assert_equal 40, response_body["items"].first.fetch("attributed_user_output_tokens_total")
    assert_equal 160, response_body["items"].first.fetch("attributed_user_total_tokens_total")
    assert_equal 0, response_body["items"].first.fetch("steer_count")
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
