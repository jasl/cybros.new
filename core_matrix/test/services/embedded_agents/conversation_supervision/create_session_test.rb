require "test_helper"

class EmbeddedAgents::ConversationSupervision::CreateSessionTest < ActiveSupport::TestCase
  include ConversationSupervisionFixtureBuilder

  test "creates a supervision session for an authorized actor when side chat is enabled" do
    fixture = prepare_conversation_supervision_context!

    session = EmbeddedAgents::ConversationSupervision::CreateSession.call(
      actor: fixture.fetch(:user),
      conversation: fixture.fetch(:conversation)
    )

    assert_equal fixture.fetch(:conversation), session.target_conversation
    assert_equal fixture.fetch(:user), session.initiator
    assert_equal "open", session.lifecycle_state
    assert_equal "summary_model", session.responder_strategy
    assert_equal supervision_policy_snapshot_for(fixture.fetch(:policy)), session.capability_policy_snapshot
  end

  test "raises a typed error for an unauthorized actor" do
    fixture = prepare_conversation_supervision_context!
    outsider = create_user!(installation: fixture.fetch(:installation))

    error = assert_raises(EmbeddedAgents::Errors::UnauthorizedSupervision) do
      EmbeddedAgents::ConversationSupervision::CreateSession.call(
        actor: outsider,
        conversation: fixture.fetch(:conversation)
      )
    end

    assert_equal "not allowed to supervise conversation", error.message
  end

  test "rejects conversations where supervision side chat is not enabled" do
    fixture = prepare_conversation_supervision_context!(side_chat_enabled: false)

    error = assert_raises(EmbeddedAgents::Errors::UnauthorizedSupervision) do
      EmbeddedAgents::ConversationSupervision::CreateSession.call(
        actor: fixture.fetch(:user),
        conversation: fixture.fetch(:conversation)
      )
    end

    assert_equal "conversation supervision is not enabled", error.message
  end
end
