require "test_helper"

class ConversationDiagnostics::RecomputeConversationSnapshotTest < ActiveSupport::TestCase
  test "rolls up turn snapshots and exposes outlier turn references" do
    context = build_canonical_variable_context!
    conversation = context[:conversation]
    first_turn = context[:turn]

    ProviderUsage::RecordEvent.call(
      installation: context[:installation],
      user: context[:user],
      workspace: context[:workspace],
      conversation_id: conversation.id,
      turn_id: first_turn.id,
      workflow_node_key: "turn_step",
      agent_installation: context[:agent_installation],
      agent_deployment: context[:agent_deployment],
      provider_handle: "openrouter",
      model_ref: "openai-gpt-5.4",
      operation_kind: "text_generation",
      input_tokens: 90,
      output_tokens: 20,
      latency_ms: 900,
      estimated_cost: 0.008,
      success: true,
      occurred_at: Time.utc(2026, 4, 2, 9, 0, 0)
    )
    context[:workflow_run].update!(lifecycle_state: "completed")

    second_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Second question",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    second_workflow_run = create_workflow_run!(turn: second_turn, lifecycle_state: "active")
    create_workflow_node!(
      workflow_run: second_workflow_run,
      node_key: "turn_step",
      node_type: "turn_step",
      lifecycle_state: "completed",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago,
      presentation_policy: "internal_only",
      decision_source: "agent_program",
      metadata: {}
    )
    Turns::SteerCurrentInput.call(turn: second_turn, content: "Second question refined")
    ProviderUsage::RecordEvent.call(
      installation: context[:installation],
      user: context[:user],
      workspace: context[:workspace],
      conversation_id: conversation.id,
      turn_id: second_turn.id,
      workflow_node_key: "turn_step",
      agent_installation: context[:agent_installation],
      agent_deployment: context[:agent_deployment],
      provider_handle: "openrouter",
      model_ref: "openai-gpt-5.4",
      operation_kind: "text_generation",
      input_tokens: 180,
      output_tokens: 60,
      latency_ms: 1_800,
      estimated_cost: 0.020,
      success: true,
      occurred_at: Time.utc(2026, 4, 2, 9, 5, 0)
    )

    first_turn.update!(lifecycle_state: "completed")
    second_turn.update!(lifecycle_state: "failed")

    snapshot = ConversationDiagnostics::RecomputeConversationSnapshot.call(conversation: conversation)

    assert_equal conversation, snapshot.conversation
    assert_equal "active", snapshot.lifecycle_state
    assert_equal 2, snapshot.turn_count
    assert_equal 0, snapshot.active_turn_count
    assert_equal 1, snapshot.completed_turn_count
    assert_equal 1, snapshot.failed_turn_count
    assert_equal 0, snapshot.canceled_turn_count
    assert_equal 2, snapshot.usage_event_count
    assert_equal 270, snapshot.input_tokens_total
    assert_equal 80, snapshot.output_tokens_total
    assert_equal BigDecimal("0.028"), snapshot.estimated_cost_total
    assert_equal 2, snapshot.attributed_user_usage_event_count
    assert_equal 270, snapshot.attributed_user_input_tokens_total
    assert_equal 80, snapshot.attributed_user_output_tokens_total
    assert_equal BigDecimal("0.028"), snapshot.attributed_user_estimated_cost_total
    assert_equal 2, snapshot.provider_round_count
    assert_equal 3, snapshot.input_variant_count
    assert_equal second_turn.id, snapshot.most_expensive_turn_id
    assert_equal second_turn.id, snapshot.most_rounds_turn_id

    assert_equal "openrouter", snapshot.metadata.fetch("provider_usage_breakdown").first.fetch("provider_handle")
    assert_equal 2, snapshot.metadata.fetch("attributed_user_provider_usage_breakdown").first.fetch("event_count")
    assert_equal 2, snapshot.metadata.fetch("provider_usage_breakdown").first.fetch("estimated_cost_event_count")
    assert_equal 0, snapshot.metadata.fetch("provider_usage_breakdown").first.fetch("estimated_cost_missing_event_count")
    assert_equal true, snapshot.metadata.fetch("provider_usage_breakdown").first.fetch("cost_data_complete")
    assert_equal(
      {
        "estimated_cost_event_count" => 2,
        "estimated_cost_missing_event_count" => 0,
        "cost_data_available" => true,
        "cost_data_complete" => true,
      },
      snapshot.metadata.fetch("cost_summary")
    )
    assert_equal second_turn.public_id, snapshot.metadata.dig("outlier_refs", "most_expensive_turn_id")
    assert_equal second_turn.public_id, snapshot.metadata.dig("outlier_refs", "most_rounds_turn_id")
  end
end
