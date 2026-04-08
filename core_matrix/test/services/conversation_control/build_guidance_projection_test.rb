require "test_helper"

class ConversationControl::BuildGuidanceProjectionTest < ActiveSupport::TestCase
  include ConversationSupervisionFixtureBuilder

  test "returns the latest and recent delivered conversation guidance for the target conversation" do
    fixture = prepare_conversation_supervision_context!(control_enabled: true)
    session = create_conversation_supervision_session!(fixture)

    older_request = create_guidance_request!(
      installation: fixture.fetch(:installation),
      session: session,
      target_conversation: fixture.fetch(:conversation),
      request_kind: "send_guidance_to_active_agent",
      target_kind: "conversation",
      target_public_id: fixture.fetch(:conversation).public_id,
      content: "Focus on the failing contract tests.",
      completed_at: 2.minutes.ago
    )
    newer_request = create_guidance_request!(
      installation: fixture.fetch(:installation),
      session: session,
      target_conversation: fixture.fetch(:conversation),
      request_kind: "send_guidance_to_active_agent",
      target_kind: "conversation",
      target_public_id: fixture.fetch(:conversation).public_id,
      content: "Stop and summarize the current repair loop.",
      completed_at: 1.minute.ago
    )

    projection = ConversationControl::BuildGuidanceProjection.call(
      conversation: fixture.fetch(:conversation)
    )

    assert_equal "conversation", projection.fetch("guidance_scope")
    assert_equal newer_request.public_id, projection.dig("latest_guidance", "conversation_control_request_id")
    assert_equal "Stop and summarize the current repair loop.", projection.dig("latest_guidance", "content")
    assert_equal [older_request.public_id, newer_request.public_id],
      projection.fetch("recent_guidance").map { |entry| entry.fetch("conversation_control_request_id") }
  end

  test "routes delivered subagent guidance from the owner conversation to the child conversation runtime" do
    fixture = prepare_conversation_supervision_context_with_turn_todo_plan!(control_enabled: true)
    session = create_conversation_supervision_session!(fixture)

    request = create_guidance_request!(
      installation: fixture.fetch(:installation),
      session: session,
      target_conversation: fixture.fetch(:conversation),
      request_kind: "send_guidance_to_subagent",
      target_kind: "subagent_session",
      target_public_id: fixture.fetch(:subagent_session).public_id,
      content: "Stop coding and report your current status.",
      completed_at: Time.current
    )

    projection = ConversationControl::BuildGuidanceProjection.call(
      conversation: fixture.fetch(:subagent_session).conversation
    )

    assert_equal "subagent", projection.fetch("guidance_scope")
    assert_equal request.public_id, projection.dig("latest_guidance", "conversation_control_request_id")
    assert_equal fixture.fetch(:subagent_session).public_id, projection.dig("latest_guidance", "target_public_id")
    assert_equal fixture.fetch(:conversation).public_id, projection.dig("latest_guidance", "source_conversation_id")
    assert_equal "Stop coding and report your current status.", projection.dig("latest_guidance", "content")
  end

  test "ignores failed guidance and non-guidance control requests" do
    fixture = prepare_conversation_supervision_context!(control_enabled: true)
    session = create_conversation_supervision_session!(fixture)

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
      completed_at: 2.minutes.ago
    )
    ConversationControlRequest.create!(
      installation: fixture.fetch(:installation),
      conversation_supervision_session: session,
      target_conversation: fixture.fetch(:conversation),
      request_kind: "send_guidance_to_active_agent",
      target_kind: "conversation",
      target_public_id: fixture.fetch(:conversation).public_id,
      lifecycle_state: "failed",
      request_payload: { "content" => "This failed and should not be shown." },
      result_payload: {
        "error_payload" => {
          "code" => "guidance_delivery_failed",
        },
      },
      completed_at: 1.minute.ago
    )

    projection = ConversationControl::BuildGuidanceProjection.call(
      conversation: fixture.fetch(:conversation)
    )

    assert_nil projection
  end

  test "still returns the latest acknowledged guidance when newer completed rows are malformed" do
    fixture = prepare_conversation_supervision_context!(control_enabled: true)
    session = create_conversation_supervision_session!(fixture)

    acknowledged_request = create_guidance_request!(
      installation: fixture.fetch(:installation),
      session: session,
      target_conversation: fixture.fetch(:conversation),
      request_kind: "send_guidance_to_active_agent",
      target_kind: "conversation",
      target_public_id: fixture.fetch(:conversation).public_id,
      content: "This is the latest acknowledged guidance.",
      completed_at: 10.minutes.ago
    )

    5.times do |index|
      ConversationControlRequest.create!(
        installation: fixture.fetch(:installation),
        conversation_supervision_session: session,
        target_conversation: fixture.fetch(:conversation),
        request_kind: "send_guidance_to_active_agent",
        target_kind: "conversation",
        target_public_id: fixture.fetch(:conversation).public_id,
        lifecycle_state: "completed",
        request_payload: { "content" => "Malformed guidance #{index}" },
        result_payload: {
          "response_payload" => {
            "control_outcome" => {
              "outcome_kind" => "status_refresh_acknowledged",
            },
          },
        },
        completed_at: (5 - index).minutes.ago
      )
    end

    projection = ConversationControl::BuildGuidanceProjection.call(
      conversation: fixture.fetch(:conversation)
    )

    assert_equal acknowledged_request.public_id, projection.dig("latest_guidance", "conversation_control_request_id")
    assert_equal "This is the latest acknowledged guidance.", projection.dig("latest_guidance", "content")
  end

  private

  def create_guidance_request!(installation:, session:, target_conversation:, request_kind:, target_kind:, target_public_id:, content:, completed_at:)
    ConversationControlRequest.create!(
      installation: installation,
      conversation_supervision_session: session,
      target_conversation: target_conversation,
      request_kind: request_kind,
      target_kind: target_kind,
      target_public_id: target_public_id,
      lifecycle_state: "completed",
      request_payload: { "content" => content },
      result_payload: {
        "response_payload" => {
          "control_outcome" => {
            "outcome_kind" => "guidance_acknowledged",
          },
        },
      },
      completed_at: completed_at
    )
  end
end
