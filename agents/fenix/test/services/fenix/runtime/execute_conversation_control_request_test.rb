require "test_helper"

class Fenix::Runtime::ExecuteConversationControlRequestTest < ActiveSupport::TestCase
  test "status refresh returns a structured acknowledgment for the target conversation" do
    response = Fenix::Runtime::ExecuteConversationControlRequest.call(
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

  test "active-agent guidance returns a structured acknowledgment for the conversation target" do
    response = Fenix::Runtime::ExecuteConversationControlRequest.call(
      payload: {
        "request_kind" => "supervision_guidance",
        "content" => "Stop and summarize.",
        "conversation_control" => {
          "conversation_control_request_id" => "control-request-1",
          "conversation_id" => "conversation-1",
          "request_kind" => "send_guidance_to_active_agent",
          "target_kind" => "conversation",
          "target_public_id" => "conversation-1",
        },
      }
    )

    assert_equal "ok", response.fetch("status")
    assert_equal "guidance_acknowledged", response.dig("control_outcome", "outcome_kind")
    assert_equal "send_guidance_to_active_agent", response.dig("control_outcome", "control_request_kind")
    assert_equal "Stop and summarize.", response.dig("control_outcome", "content")
  end

  test "subagent guidance requires a matching subagent target and subagent_session_id" do
    response = Fenix::Runtime::ExecuteConversationControlRequest.call(
      payload: {
        "request_kind" => "supervision_guidance",
        "content" => "Stop and summarize.",
        "subagent_session_id" => "subagent-session-1",
        "conversation_control" => {
          "conversation_control_request_id" => "control-request-1",
          "conversation_id" => "conversation-1",
          "request_kind" => "send_guidance_to_subagent",
          "target_kind" => "subagent_session",
          "target_public_id" => "subagent-session-1",
        },
      }
    )

    assert_equal "ok", response.fetch("status")
    assert_equal "guidance_acknowledged", response.dig("control_outcome", "outcome_kind")
    assert_equal "send_guidance_to_subagent", response.dig("control_outcome", "control_request_kind")
    assert_equal "subagent-session-1", response.dig("control_outcome", "subagent_session_id")
  end

  test "active-agent guidance rejects a mismatched subagent target" do
    error = assert_raises(Fenix::Runtime::ExecuteConversationControlRequest::InvalidRequestError) do
      Fenix::Runtime::ExecuteConversationControlRequest.call(
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
