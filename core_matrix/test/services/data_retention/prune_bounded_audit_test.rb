require "test_helper"

class DataRetention::PruneBoundedAuditTest < ActiveSupport::TestCase
  include ConversationSupervisionFixtureBuilder

  test "deletes old terminal control requests and usage events but keeps active requests" do
    fixture = prepare_conversation_supervision_context!(control_enabled: true)
    session = create_conversation_supervision_session!(fixture)

    stale_completed = ConversationControlRequest.create!(
      installation: fixture.fetch(:installation),
      conversation_supervision_session: session,
      target_conversation: fixture.fetch(:conversation),
      user: fixture.fetch(:conversation).user,
      workspace: fixture.fetch(:conversation).workspace,
      agent: fixture.fetch(:conversation).agent,
      request_kind: "request_status_refresh",
      target_kind: "conversation",
      target_public_id: fixture.fetch(:conversation).public_id,
      lifecycle_state: "completed",
      request_payload: {},
      result_payload: {},
      completed_at: 45.days.ago,
      created_at: 45.days.ago,
      updated_at: 45.days.ago
    )
    stale_failed = ConversationControlRequest.create!(
      installation: fixture.fetch(:installation),
      conversation_supervision_session: session,
      target_conversation: fixture.fetch(:conversation),
      user: fixture.fetch(:conversation).user,
      workspace: fixture.fetch(:conversation).workspace,
      agent: fixture.fetch(:conversation).agent,
      request_kind: "request_turn_interrupt",
      target_kind: "conversation",
      target_public_id: fixture.fetch(:conversation).public_id,
      lifecycle_state: "failed",
      request_payload: {},
      result_payload: { "error_payload" => { "code" => "failed" } },
      completed_at: 40.days.ago,
      created_at: 40.days.ago,
      updated_at: 40.days.ago
    )
    stale_queued = ConversationControlRequest.create!(
      installation: fixture.fetch(:installation),
      conversation_supervision_session: session,
      target_conversation: fixture.fetch(:conversation),
      user: fixture.fetch(:conversation).user,
      workspace: fixture.fetch(:conversation).workspace,
      agent: fixture.fetch(:conversation).agent,
      request_kind: "request_turn_interrupt",
      target_kind: "conversation",
      target_public_id: fixture.fetch(:conversation).public_id,
      lifecycle_state: "queued",
      request_payload: {},
      result_payload: {},
      created_at: 40.days.ago,
      updated_at: 40.days.ago
    )
    fresh_completed = ConversationControlRequest.create!(
      installation: fixture.fetch(:installation),
      conversation_supervision_session: session,
      target_conversation: fixture.fetch(:conversation),
      user: fixture.fetch(:conversation).user,
      workspace: fixture.fetch(:conversation).workspace,
      agent: fixture.fetch(:conversation).agent,
      request_kind: "request_status_refresh",
      target_kind: "conversation",
      target_public_id: fixture.fetch(:conversation).public_id,
      lifecycle_state: "completed",
      request_payload: {},
      result_payload: {},
      completed_at: 2.days.ago,
      created_at: 2.days.ago,
      updated_at: 2.days.ago
    )

    stale_usage = UsageEvent.create!(
      installation: fixture.fetch(:installation),
      provider_handle: "openai",
      model_ref: "gpt-5.4",
      operation_kind: "text_generation",
      input_tokens: 10,
      output_tokens: 5,
      success: true,
      occurred_at: 45.days.ago,
      created_at: 45.days.ago,
      updated_at: 45.days.ago
    )
    fresh_usage = UsageEvent.create!(
      installation: fixture.fetch(:installation),
      provider_handle: "openai",
      model_ref: "gpt-5.4",
      operation_kind: "text_generation",
      input_tokens: 10,
      output_tokens: 5,
      success: true,
      occurred_at: 2.days.ago,
      created_at: 2.days.ago,
      updated_at: 2.days.ago
    )

    result = DataRetention::PruneBoundedAudit.call(
      cutoff: 30.days.ago,
      batch_size: 10
    )

    assert_equal 2, result.fetch(:control_requests_deleted)
    assert_equal 1, result.fetch(:usage_events_deleted)

    assert_not ConversationControlRequest.exists?(stale_completed.id)
    assert_not ConversationControlRequest.exists?(stale_failed.id)
    assert ConversationControlRequest.exists?(stale_queued.id)
    assert ConversationControlRequest.exists?(fresh_completed.id)

    assert_not UsageEvent.exists?(stale_usage.id)
    assert UsageEvent.exists?(fresh_usage.id)
  end
end
