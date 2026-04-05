require "test_helper"

class EmbeddedAgents::ConversationSupervision::AppendMessageTest < ActiveSupport::TestCase
  include ConversationSupervisionFixtureBuilder

  test "creates a snapshot-backed supervision exchange without mutating the target transcript" do
    fixture = prepare_conversation_supervision_context!
    session = create_conversation_supervision_session!(fixture)
    result = nil

    assert_difference("ConversationSupervisionSnapshot.count", 1) do
      assert_difference("ConversationSupervisionMessage.count", 2) do
        assert_no_difference(-> { fixture.fetch(:conversation).messages.count }) do
          result = EmbeddedAgents::ConversationSupervision::AppendMessage.call(
            actor: fixture.fetch(:user),
            conversation_supervision_session: session,
            content: "What are you waiting on right now?"
          )
        end
      end
    end

    snapshot = ConversationSupervisionSnapshot.order(:id).last
    exchange_messages = session.conversation_supervision_messages.order(:created_at).last(2)
    user_message, supervisor_message = exchange_messages

    assert_equal snapshot, user_message.conversation_supervision_snapshot
    assert_equal snapshot, supervisor_message.conversation_supervision_snapshot
    assert_equal "user", user_message.role
    assert_equal "supervisor_agent", supervisor_message.role
    assert_equal "What are you waiting on right now?", user_message.content
    assert_equal result.dig("human_sidechat", "content"), supervisor_message.content
    assert_equal snapshot.public_id, result.dig("machine_status", "supervision_snapshot_id")
    assert_equal snapshot.machine_status_payload, result.fetch("machine_status")
    refute_match(/\bprovider_round|tool_|runtime\.workflow_node|subagent_barrier\b/, result.dig("human_sidechat", "content"))
  end

  test "requires the session initiator and rejects closed supervision sessions" do
    fixture = prepare_conversation_supervision_context!
    session = create_conversation_supervision_session!(fixture)
    outsider = create_user!(installation: fixture.fetch(:installation))

    unauthorized_error = assert_raises(EmbeddedAgents::Errors::UnauthorizedSupervision) do
      EmbeddedAgents::ConversationSupervision::AppendMessage.call(
        actor: outsider,
        conversation_supervision_session: session,
        content: "What are you doing?"
      )
    end

    assert_equal "not allowed to supervise conversation", unauthorized_error.message

    session.update!(lifecycle_state: "closed")

    closed_error = assert_raises(EmbeddedAgents::Errors::ClosedSupervisionSession) do
      EmbeddedAgents::ConversationSupervision::AppendMessage.call(
        actor: fixture.fetch(:user),
        conversation_supervision_session: session,
        content: "What are you doing?"
      )
    end

    assert_equal "supervision session is closed", closed_error.message
  end

  test "raises record not found for a missing session row" do
    fixture = prepare_conversation_supervision_context!
    session = create_conversation_supervision_session!(fixture)
    session_id = session.id

    ConversationSupervisionSession.unscoped.where(id: session_id).delete_all

    error = assert_raises(ActiveRecord::RecordNotFound) do
      EmbeddedAgents::ConversationSupervision::AppendMessage.call(
        actor: fixture.fetch(:user),
        conversation_supervision_session: session,
        content: "What are you doing?"
      )
    end

    assert_match(/Couldn't find ConversationSupervisionSession/, error.message)
    assert_nil ConversationSupervisionSession.unscoped.find_by(id: session_id)
  end
end
