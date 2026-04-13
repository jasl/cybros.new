require "test_helper"

class ConversationDiagnostics::RecomputeConversationSnapshotJobTest < ActiveSupport::TestCase
  test "recomputes missing turn and conversation snapshots" do
    context = build_canonical_variable_context!
    conversation = context[:conversation]

    record_usage_event(context, input_tokens: 120, output_tokens: 40, cached_input_tokens: 60)
    ConversationDiagnosticsSnapshot.where(conversation: conversation).delete_all
    TurnDiagnosticsSnapshot.where(conversation: conversation).delete_all

    assert_difference("ConversationDiagnosticsSnapshot.count", +1) do
      assert_difference("TurnDiagnosticsSnapshot.count", +1) do
        ConversationDiagnostics::RecomputeConversationSnapshotJob.perform_now(conversation.id)
      end
    end

    snapshot = ConversationDiagnosticsSnapshot.find_by!(conversation: conversation)
    turn_snapshot = TurnDiagnosticsSnapshot.find_by!(conversation: conversation, turn: context[:turn])

    assert_equal 1, snapshot.usage_event_count
    assert_equal 120, snapshot.input_tokens_total
    assert_equal 40, snapshot.output_tokens_total
    assert_equal 1, turn_snapshot.usage_event_count
    assert_equal 120, turn_snapshot.input_tokens_total
    assert_equal 40, turn_snapshot.output_tokens_total
  end

  test "rerunning the job updates existing snapshots instead of duplicating them" do
    context = build_canonical_variable_context!
    conversation = context[:conversation]

    record_usage_event(
      context,
      input_tokens: 120,
      output_tokens: 40,
      cached_input_tokens: 60,
      occurred_at: Time.utc(2026, 4, 2, 9, 0, 0)
    )
    ConversationDiagnostics::RecomputeConversationSnapshotJob.perform_now(conversation.id)

    conversation_snapshot = ConversationDiagnosticsSnapshot.find_by!(conversation: conversation)
    turn_snapshot = TurnDiagnosticsSnapshot.find_by!(conversation: conversation, turn: context[:turn])

    record_usage_event(
      context,
      input_tokens: 30,
      output_tokens: 10,
      cached_input_tokens: 0,
      prompt_cache_status: "unknown",
      occurred_at: Time.utc(2026, 4, 2, 9, 5, 0)
    )

    assert_no_difference("ConversationDiagnosticsSnapshot.count") do
      assert_no_difference("TurnDiagnosticsSnapshot.count") do
        ConversationDiagnostics::RecomputeConversationSnapshotJob.perform_now(conversation.id)
      end
    end

    assert_equal conversation_snapshot.id, ConversationDiagnosticsSnapshot.find_by!(conversation: conversation).id
    assert_equal turn_snapshot.id, TurnDiagnosticsSnapshot.find_by!(conversation: conversation, turn: context[:turn]).id
    assert_equal 2, conversation_snapshot.reload.usage_event_count
    assert_equal 150, conversation_snapshot.input_tokens_total
    assert_equal 50, conversation_snapshot.output_tokens_total
    assert_equal 2, turn_snapshot.reload.usage_event_count
    assert_equal 150, turn_snapshot.input_tokens_total
    assert_equal 50, turn_snapshot.output_tokens_total
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
