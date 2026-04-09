require "test_helper"

class Fenix::Agent::Program::ExecuteConversationControlRequestTest < ActiveSupport::TestCase
  test "status refresh returns a structured acknowledgment for the target conversation" do
    response = Fenix::Agent::Program::ExecuteConversationControlRequest.call(
      payload: {
        "request_kind" => "supervision_status_refresh",
        "conversation_control" => {
          "conversation_control_request_id" => "control-request-1",
          "conversation_id" => "conversation-1",
          "request_kind" => "request_status_refresh",
          "target_kind" => "conversation",
          "target_public_id" => "conversation-1",
        },
      }
    )

    assert_equal "ok", response.fetch("status")
    assert_equal "supervision_status_refresh", response.fetch("handled_request_kind")
    assert_equal "status_refresh_acknowledged", response.dig("control_outcome", "outcome_kind")
    assert_equal "request_status_refresh", response.dig("control_outcome", "control_request_kind")
    assert_equal "conversation", response.dig("control_outcome", "target_kind")
    assert_equal "conversation-1", response.dig("control_outcome", "target_public_id")
  end

  test "active-agent guidance rejects a mismatched subagent target" do
    error = assert_raises(Fenix::Agent::Program::ExecuteConversationControlRequest::InvalidRequestError) do
      Fenix::Agent::Program::ExecuteConversationControlRequest.call(
        payload: {
          "request_kind" => "supervision_guidance",
          "content" => "Stop and summarize.",
          "subagent_session_id" => "subagent-session-1",
          "conversation_control" => {
            "conversation_control_request_id" => "control-request-1",
            "conversation_id" => "conversation-1",
            "request_kind" => "send_guidance_to_active_agent",
            "target_kind" => "conversation",
            "target_public_id" => "conversation-1",
          },
        }
      )
    end

    assert_includes error.message, "subagent_session_id"
  end
end
