require "test_helper"

class ConversationControl::CreateRequestTest < ActiveSupport::TestCase
  include ConversationSupervisionFixtureBuilder

  test "request_status_refresh creates an auditable control request and a mailbox request" do
    fixture = prepare_conversation_supervision_context!(control_enabled: true)
    session = create_conversation_supervision_session!(fixture)

    assert_difference("ConversationControlRequest.count", 1) do
      assert_difference("AgentControlMailboxItem.where(item_type: 'agent_program_request').count", 1) do
        request = ConversationControl::CreateRequest.call(
          actor: fixture.fetch(:user),
          conversation_supervision_session: session,
          request_kind: "request_status_refresh",
          request_payload: {}
        )

        mailbox_item = AgentControlMailboxItem.order(:id).last

        assert_equal "dispatched", request.lifecycle_state
        assert_equal "conversation", request.target_kind
        assert_equal fixture.fetch(:conversation).public_id, request.target_public_id
        assert_equal "supervision_status_refresh", mailbox_item.payload.fetch("request_kind")
        assert_equal request.public_id, mailbox_item.payload.dig("conversation_control", "conversation_control_request_id")
      end
    end
  end

  test "send_guidance_to_subagent creates a durable request without mutating the target transcript at create time" do
    fixture = prepare_conversation_supervision_context!(control_enabled: true)
    session = create_conversation_supervision_session!(fixture)

    assert_difference("ConversationControlRequest.count", 1) do
      assert_no_difference(-> { fixture.fetch(:subagent_session).conversation.messages.count }) do
        request = ConversationControl::CreateRequest.call(
          actor: fixture.fetch(:user),
          conversation_supervision_session: session,
          request_kind: "send_guidance_to_subagent",
          request_payload: {
            "subagent_session_id" => fixture.fetch(:subagent_session).public_id,
            "content" => "Please stop and summarize your current status."
          }
        )

        assert_equal "dispatched", request.lifecycle_state
        assert_equal "subagent_session", request.target_kind
        assert_equal fixture.fetch(:subagent_session).public_id, request.target_public_id
      end
    end
  end

  test "disabled control capability blocks request creation before dispatch begins" do
    fixture = prepare_conversation_supervision_context!(control_enabled: false)
    session = create_conversation_supervision_session!(fixture)

    assert_no_difference("ConversationControlRequest.count") do
      assert_no_difference("AgentControlMailboxItem.count") do
        error = assert_raises(ActiveRecord::RecordInvalid) do
          ConversationControl::CreateRequest.call(
            actor: fixture.fetch(:user),
            conversation_supervision_session: session,
            request_kind: "request_status_refresh",
            request_payload: {}
          )
        end

        assert_includes error.record.errors[:base], "control is not enabled for this conversation"
      end
    end
  end
end
