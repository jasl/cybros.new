require "test_helper"

class AppApiConversationDiagnosticsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "returns ready conversation diagnostics and turn diagnostics from persisted snapshots" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)

    record_usage_event(context, input_tokens: 120, output_tokens: 40, cached_input_tokens: 60)
    ConversationDiagnostics::RecomputeConversationSnapshot.call(conversation: context[:conversation])
    clear_enqueued_jobs

    assert_no_enqueued_jobs only: ConversationDiagnostics::RecomputeConversationSnapshotJob do
      get "/app_api/conversations/#{context[:conversation].public_id}/diagnostics",
        headers: app_api_headers(registration[:session_token])
    end

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal "conversation_diagnostics_show", response_body["method_id"]
    assert_equal context[:conversation].public_id, response_body["conversation_id"]
    assert_equal "ready", response_body["diagnostics_status"]
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

    assert_no_enqueued_jobs only: ConversationDiagnostics::RecomputeConversationSnapshotJob do
      get "/app_api/conversations/#{context[:conversation].public_id}/diagnostics/turns",
        headers: app_api_headers(registration[:session_token])
    end

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal "conversation_diagnostics_turns", response_body["method_id"]
    assert_equal context[:conversation].public_id, response_body["conversation_id"]
    assert_equal "ready", response_body["diagnostics_status"]
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

  test "returns pending conversation diagnostics and enqueues recompute when no snapshot exists" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)
    ConversationDiagnosticsSnapshot.where(conversation: context[:conversation]).delete_all
    TurnDiagnosticsSnapshot.where(conversation: context[:conversation]).delete_all
    clear_enqueued_jobs

    assert_enqueued_with(job: ConversationDiagnostics::RecomputeConversationSnapshotJob, args: [context[:conversation].id]) do
      get "/app_api/conversations/#{context[:conversation].public_id}/diagnostics",
        headers: app_api_headers(registration[:session_token])
    end

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal "conversation_diagnostics_show", response_body["method_id"]
    assert_equal context[:conversation].public_id, response_body["conversation_id"]
    assert_equal "pending", response_body["diagnostics_status"]
    assert_nil response_body["snapshot"]
    assert_equal 0, ConversationDiagnosticsSnapshot.where(conversation: context[:conversation]).count
    assert_equal 0, TurnDiagnosticsSnapshot.where(conversation: context[:conversation]).count
  end

  test "returns pending turn diagnostics and enqueues recompute when no snapshots exist" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)
    ConversationDiagnosticsSnapshot.where(conversation: context[:conversation]).delete_all
    TurnDiagnosticsSnapshot.where(conversation: context[:conversation]).delete_all
    clear_enqueued_jobs

    assert_enqueued_with(job: ConversationDiagnostics::RecomputeConversationSnapshotJob, args: [context[:conversation].id]) do
      get "/app_api/conversations/#{context[:conversation].public_id}/diagnostics/turns",
        headers: app_api_headers(registration[:session_token])
    end

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal "conversation_diagnostics_turns", response_body["method_id"]
    assert_equal context[:conversation].public_id, response_body["conversation_id"]
    assert_equal "pending", response_body["diagnostics_status"]
    assert_equal [], response_body["items"]
    assert_equal 0, ConversationDiagnosticsSnapshot.where(conversation: context[:conversation]).count
    assert_equal 0, TurnDiagnosticsSnapshot.where(conversation: context[:conversation]).count
  end

  test "returns stale conversation diagnostics and enqueues recompute when newer facts exist" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)

    travel_to 5.minutes.ago do
      record_usage_event(
        context,
        input_tokens: 120,
        output_tokens: 40,
        cached_input_tokens: 60,
        occurred_at: Time.current
      )
      ConversationDiagnostics::RecomputeConversationSnapshot.call(conversation: context[:conversation])
    end
    clear_enqueued_jobs
    record_usage_event(
      context,
      input_tokens: 30,
      output_tokens: 10,
      cached_input_tokens: 0,
      prompt_cache_status: "unknown",
      occurred_at: Time.current
    )

    assert_enqueued_with(job: ConversationDiagnostics::RecomputeConversationSnapshotJob, args: [context[:conversation].id]) do
      get "/app_api/conversations/#{context[:conversation].public_id}/diagnostics",
        headers: app_api_headers(registration[:session_token])
    end

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal "stale", response_body["diagnostics_status"]
    assert_equal 1, response_body.dig("snapshot", "usage_event_count")
    assert_equal 120, response_body.dig("snapshot", "input_tokens_total")
    assert_equal 40, response_body.dig("snapshot", "output_tokens_total")
    assert_equal 1, response_body.dig("snapshot", "prompt_cache_available_event_count")
    assert_equal 0, response_body.dig("snapshot", "prompt_cache_unknown_event_count")
  end

  test "returns stale turn diagnostics and enqueues recompute when newer facts exist" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)

    travel_to 5.minutes.ago do
      record_usage_event(
        context,
        input_tokens: 120,
        output_tokens: 40,
        cached_input_tokens: 60,
        occurred_at: Time.current
      )
      ConversationDiagnostics::RecomputeConversationSnapshot.call(conversation: context[:conversation])
    end
    clear_enqueued_jobs
    record_usage_event(
      context,
      input_tokens: 30,
      output_tokens: 10,
      cached_input_tokens: 0,
      prompt_cache_status: "unknown",
      occurred_at: Time.current
    )

    assert_enqueued_with(job: ConversationDiagnostics::RecomputeConversationSnapshotJob, args: [context[:conversation].id]) do
      get "/app_api/conversations/#{context[:conversation].public_id}/diagnostics/turns",
        headers: app_api_headers(registration[:session_token])
    end

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal "stale", response_body["diagnostics_status"]
    assert_equal 1, response_body["items"].length
    assert_equal 1, response_body.dig("items", 0, "usage_event_count")
    assert_equal 120, response_body.dig("items", 0, "input_tokens_total")
    assert_equal 40, response_body.dig("items", 0, "output_tokens_total")
    assert_equal 1, response_body.dig("items", 0, "prompt_cache_available_event_count")
    assert_equal 0, response_body.dig("items", 0, "prompt_cache_unknown_event_count")
  end

  test "returns null prompt cache hit rate when ready diagnostics have no available usage events" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)

    record_usage_event(
      context,
      input_tokens: 120,
      output_tokens: 40,
      cached_input_tokens: 0,
      prompt_cache_status: "unsupported"
    )
    ConversationDiagnostics::RecomputeConversationSnapshot.call(conversation: context[:conversation])

    get "/app_api/conversations/#{context[:conversation].public_id}/diagnostics",
      headers: app_api_headers(registration[:session_token])

    assert_response :success
    assert_equal "ready", JSON.parse(response.body)["diagnostics_status"]
    assert_nil JSON.parse(response.body).dig("snapshot", "prompt_cache_hit_rate")
  end

  test "rejects raw bigint identifiers for conversation diagnostics lookups" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)

    get "/app_api/conversations/#{context[:conversation].id}/diagnostics",
      headers: app_api_headers(registration[:session_token])

    assert_response :not_found

    get "/app_api/conversations/#{context[:conversation].id}/diagnostics/turns",
      headers: app_api_headers(registration[:session_token])

    assert_response :not_found
  end

  test "shows conversation diagnostics within twenty-four SQL queries" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)

    record_usage_event(context, input_tokens: 80, output_tokens: 20, cached_input_tokens: 40)
    ConversationDiagnostics::RecomputeConversationSnapshot.call(conversation: context[:conversation])

    assert_sql_query_count_at_most(24) do
      get "/app_api/conversations/#{context[:conversation].public_id}/diagnostics",
        headers: app_api_headers(registration[:session_token])
    end

    assert_response :success
    assert_equal "ready", response.parsed_body.fetch("diagnostics_status")
  end

  test "lists turn diagnostics within twenty-six SQL queries" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)

    record_usage_event(context, input_tokens: 80, output_tokens: 20, cached_input_tokens: 40)
    ConversationDiagnostics::RecomputeConversationSnapshot.call(conversation: context[:conversation])

    assert_sql_query_count_at_most(26) do
      get "/app_api/conversations/#{context[:conversation].public_id}/diagnostics/turns",
        headers: app_api_headers(registration[:session_token])
    end

    assert_response :success
    assert_equal "ready", response.parsed_body.fetch("diagnostics_status")
  end

  private

  def record_usage_event(context, input_tokens:, output_tokens:, cached_input_tokens:, prompt_cache_status: "available", occurred_at: Time.utc(2026, 4, 2, 9, 0, 0))
    ProviderUsage::RecordEvent.call(
      installation: context[:installation],
      user: context[:user],
      workspace: context[:workspace],
      conversation_id: context[:conversation].id,
      turn_id: context[:turn].id,
      workflow_node_key: "turn_step",
      agent: context[:agent],
      agent_definition_version: context[:agent_definition_version],
      provider_handle: "openrouter",
      model_ref: "openai-gpt-5.4",
      operation_kind: "text_generation",
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      prompt_cache_status: prompt_cache_status,
      cached_input_tokens: prompt_cache_status == "available" ? cached_input_tokens : nil,
      latency_ms: 1_200,
      estimated_cost: 0.010,
      success: true,
      occurred_at: occurred_at
    )
  end
end
