require "test_helper"

class ConversationDiagnostics::ResolveSnapshotStatusTest < ActiveSupport::TestCase
  test "returns pending when the conversation snapshot is missing" do
    context = build_canonical_variable_context!
    conversation = context[:conversation]

    result = ConversationDiagnostics::ResolveSnapshotStatus.call(conversation: conversation)

    assert_equal "pending", result.status
    assert_nil result.conversation_snapshot
    assert_equal 0, result.turn_snapshot_count
  end

  test "returns pending when the conversation has turns but turn snapshots are missing" do
    context = build_canonical_variable_context!
    conversation = context[:conversation]

    record_usage_event(context, input_tokens: 120, output_tokens: 40, cached_input_tokens: 60)
    ConversationDiagnostics::RecomputeConversationSnapshot.call(conversation: conversation)
    TurnDiagnosticsSnapshot.where(conversation: conversation).delete_all

    result = ConversationDiagnostics::ResolveSnapshotStatus.call(conversation: conversation)

    assert_equal "pending", result.status
    assert result.conversation_snapshot.present?
    assert_equal 0, result.turn_snapshot_count
  end

  test "returns stale when newer usage facts exist" do
    context = build_canonical_variable_context!
    conversation = context[:conversation]

    travel_to 5.minutes.ago do
      record_usage_event(
        context,
        input_tokens: 120,
        output_tokens: 40,
        cached_input_tokens: 60,
        occurred_at: Time.current
      )
      ConversationDiagnostics::RecomputeConversationSnapshot.call(conversation: conversation)
    end
    record_usage_event(
      context,
      input_tokens: 30,
      output_tokens: 10,
      cached_input_tokens: 0,
      prompt_cache_status: "unknown",
      occurred_at: Time.current
    )

    result = ConversationDiagnostics::ResolveSnapshotStatus.call(conversation: conversation)

    assert_equal "stale", result.status
    assert result.conversation_snapshot.present?
    assert_equal 1, result.turn_snapshot_count
  end

  test "returns stale when newer workflow facts exist" do
    context = build_canonical_variable_context!
    conversation = context[:conversation]

    record_usage_event(context, input_tokens: 120, output_tokens: 40, cached_input_tokens: 60)
    ConversationDiagnostics::RecomputeConversationSnapshot.call(conversation: conversation)
    context[:workflow_run].touch

    result = ConversationDiagnostics::ResolveSnapshotStatus.call(conversation: conversation)

    assert_equal "stale", result.status
    assert result.conversation_snapshot.present?
    assert_equal 1, result.turn_snapshot_count
  end

  test "returns stale with a lifecycle drift reason when persisted turn snapshot lifecycle drifts from the live turn" do
    context = build_canonical_variable_context!
    conversation = context[:conversation]

    record_usage_event(context, input_tokens: 120, output_tokens: 40, cached_input_tokens: 60)
    ConversationDiagnostics::RecomputeConversationSnapshot.call(conversation: conversation)
    context[:turn].update!(lifecycle_state: "completed")

    result = ConversationDiagnostics::ResolveSnapshotStatus.call(conversation: conversation)

    assert_equal "stale", result.status
    assert_equal true, result.turn_lifecycle_drift?
    assert result.conversation_snapshot.present?
    assert_equal 1, result.turn_snapshot_count
  end

  test "returns ready when no newer source facts exist" do
    context = build_canonical_variable_context!
    conversation = context[:conversation]

    record_usage_event(context, input_tokens: 120, output_tokens: 40, cached_input_tokens: 60)
    ConversationDiagnostics::RecomputeConversationSnapshot.call(conversation: conversation)

    result = ConversationDiagnostics::ResolveSnapshotStatus.call(conversation: conversation)

    assert_equal "ready", result.status
    assert result.conversation_snapshot.present?
    assert_equal 1, result.turn_snapshot_count
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
