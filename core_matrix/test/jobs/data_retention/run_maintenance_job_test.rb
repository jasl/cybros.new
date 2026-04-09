require "test_helper"

class DataRetention::RunMaintenanceJobTest < ActiveJob::TestCase
  include ConversationSupervisionFixtureBuilder

  test "runs bounded audit and supervision cleanup until the configured batch is drained" do
    fixture = prepare_conversation_supervision_context!(control_enabled: true)

    2.times do |index|
      session = create_conversation_supervision_session!(fixture)
      snapshot = ConversationSupervisionSnapshot.create!(
        installation: fixture.fetch(:installation),
        target_conversation: fixture.fetch(:conversation),
        conversation_supervision_session: session,
        active_subagent_session_public_ids: [],
        bundle_payload: {},
        machine_status_payload: {},
        created_at: 10.days.ago,
        updated_at: 10.days.ago
      )
      ConversationSupervisionMessage.create!(
        installation: fixture.fetch(:installation),
        target_conversation: fixture.fetch(:conversation),
        conversation_supervision_session: session,
        conversation_supervision_snapshot: snapshot,
        role: "system",
        content: "Archived message #{index}",
        created_at: 10.days.ago,
        updated_at: 10.days.ago
      )
      ConversationControlRequest.create!(
        installation: fixture.fetch(:installation),
        conversation_supervision_session: session,
        target_conversation: fixture.fetch(:conversation),
        request_kind: "request_status_refresh",
        target_kind: "conversation",
        target_public_id: fixture.fetch(:conversation).public_id,
        lifecycle_state: "completed",
        request_payload: {},
        result_payload: {},
        completed_at: 35.days.ago,
        created_at: 35.days.ago,
        updated_at: 35.days.ago
      )
      travel_to(8.days.ago) { session.update!(lifecycle_state: "closed") }
    end

    2.times do |index|
      UsageEvent.create!(
        installation: fixture.fetch(:installation),
        provider_handle: "openai",
        model_ref: "gpt-5.4",
        operation_kind: "text_generation",
        input_tokens: 10,
        output_tokens: 5,
        success: true,
        occurred_at: 35.days.ago - index.minutes,
        created_at: 35.days.ago - index.minutes,
        updated_at: 35.days.ago - index.minutes
      )
    end

    result = DataRetention::RunMaintenanceJob.perform_now(
      "batch_size" => 1,
      "bounded_audit_retention_days" => 30,
      "supervision_closed_retention_days" => 7
    )

    assert_equal 2, result.fetch(:bounded_audit).fetch(:control_requests_deleted)
    assert_equal 2, result.fetch(:bounded_audit).fetch(:usage_events_deleted)
    assert_equal 2, result.fetch(:supervision_artifacts).fetch(:sessions_deleted)
    assert_equal 2, result.fetch(:supervision_artifacts).fetch(:snapshots_deleted)
    assert_equal 2, result.fetch(:supervision_artifacts).fetch(:messages_deleted)
    assert_equal 0, ConversationSupervisionSession.where(lifecycle_state: "closed").count
    assert_equal 0, UsageEvent.where("occurred_at < ?", 30.days.ago).count
  end
end
