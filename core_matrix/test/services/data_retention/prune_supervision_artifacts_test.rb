require "test_helper"

class DataRetention::PruneSupervisionArtifactsTest < ActiveSupport::TestCase
  include ConversationSupervisionFixtureBuilder

  test "deletes closed supervision artifacts older than the cutoff" do
    fixture = prepare_conversation_supervision_context!(control_enabled: true)
    stale_session = create_conversation_supervision_session!(fixture)
    fresh_session = create_conversation_supervision_session!(fixture)

    stale_snapshot = create_snapshot!(fixture:, session: stale_session, created_at: 10.days.ago)
    stale_message = create_message!(fixture:, session: stale_session, snapshot: stale_snapshot, created_at: 10.days.ago)
    stale_request = create_request!(fixture:, session: stale_session, completed_at: 10.days.ago)

    fresh_snapshot = create_snapshot!(fixture:, session: fresh_session, created_at: 1.day.ago)
    fresh_message = create_message!(fixture:, session: fresh_session, snapshot: fresh_snapshot, created_at: 1.day.ago)
    fresh_request = create_request!(fixture:, session: fresh_session, completed_at: 1.day.ago)

    close_session!(stale_session, at: 8.days.ago)
    close_session!(fresh_session, at: 2.hours.ago)

    result = DataRetention::PruneSupervisionArtifacts.call(
      cutoff: 7.days.ago,
      batch_size: 10
    )

    assert_equal 1, result.fetch(:sessions_deleted)
    assert_equal 1, result.fetch(:snapshots_deleted)
    assert_equal 1, result.fetch(:messages_deleted)
    assert_equal 1, result.fetch(:control_requests_deleted)

    assert_not ConversationSupervisionSession.exists?(stale_session.id)
    assert_not ConversationSupervisionSnapshot.exists?(stale_snapshot.id)
    assert_not ConversationSupervisionMessage.exists?(stale_message.id)
    assert_not ConversationControlRequest.exists?(stale_request.id)

    assert ConversationSupervisionSession.exists?(fresh_session.id)
    assert ConversationSupervisionSnapshot.exists?(fresh_snapshot.id)
    assert ConversationSupervisionMessage.exists?(fresh_message.id)
    assert ConversationControlRequest.exists?(fresh_request.id)
  end

  test "does not delete open supervision sessions even when they are old" do
    fixture = prepare_conversation_supervision_context!(control_enabled: true)
    session = create_conversation_supervision_session!(fixture)
    snapshot = create_snapshot!(fixture:, session:, created_at: 14.days.ago)
    message = create_message!(fixture:, session:, snapshot:, created_at: 14.days.ago)
    request = create_request!(fixture:, session:, completed_at: 14.days.ago)

    result = DataRetention::PruneSupervisionArtifacts.call(
      cutoff: 7.days.ago,
      batch_size: 10
    )

    assert_equal 0, result.fetch(:sessions_deleted)
    assert_equal 0, result.fetch(:snapshots_deleted)
    assert_equal 0, result.fetch(:messages_deleted)
    assert_equal 0, result.fetch(:control_requests_deleted)

    assert ConversationSupervisionSession.exists?(session.id)
    assert ConversationSupervisionSnapshot.exists?(snapshot.id)
    assert ConversationSupervisionMessage.exists?(message.id)
    assert ConversationControlRequest.exists?(request.id)
  end

  private

  def close_session!(session, at:)
    travel_to(at) do
      session.update!(lifecycle_state: "closed")
    end
  end

  def create_snapshot!(fixture:, session:, created_at:)
    ConversationSupervisionSnapshot.create!(
      installation: fixture.fetch(:installation),
      target_conversation: fixture.fetch(:conversation),
      conversation_supervision_session: session,
      active_subagent_connection_public_ids: [],
      bundle_payload: {},
      machine_status_payload: {},
      created_at: created_at,
      updated_at: created_at
    )
  end

  def create_message!(fixture:, session:, snapshot:, created_at:)
    ConversationSupervisionMessage.create!(
      installation: fixture.fetch(:installation),
      target_conversation: fixture.fetch(:conversation),
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      role: "system",
      content: "Archived supervision message",
      created_at: created_at,
      updated_at: created_at
    )
  end

  def create_request!(fixture:, session:, completed_at:)
    ConversationControlRequest.create!(
      installation: fixture.fetch(:installation),
      conversation_supervision_session: session,
      target_conversation: fixture.fetch(:conversation),
      request_kind: "request_status_refresh",
      target_kind: "conversation",
      target_public_id: fixture.fetch(:conversation).public_id,
      lifecycle_state: "completed",
      request_payload: {},
      result_payload: {
        "response_payload" => {
          "control_outcome" => {
            "outcome_kind" => "status_refresh_acknowledged",
          },
        },
      },
      completed_at: completed_at,
      created_at: completed_at,
      updated_at: completed_at
    )
  end
end
